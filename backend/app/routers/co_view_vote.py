import json
import random
from typing import List, Literal

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from fastapi import WebSocket
from pydantic import TypeAdapter
from sqlalchemy.orm import Session

from app import models, realtime
from app.database import get_db
from app.deps import get_current_user, get_ws_user
from app import push
from app.routers.feed import get_discover_pool
from app.routers.partner import _coview_item, _member_ids, add_coview_entries, get_active_link
from app.schemas import (
    CoViewVoteCastRequest,
    CoViewVoteProposeRequest,
    CoViewVoteSessionOut,
    ExternalIds,
    LocalizedText,
    MediaItem,
)

router = APIRouter(prefix="/partner/co-viewing/vote", tags=["partner"])

PoolSource = Literal["personal", "coview", "both", "catalog"]


def _watchlist_item(entry: models.WatchlistEntry) -> MediaItem:
    """Rebuilds a MediaItem from a plan-to-watch snapshot — same reasoning
    as partner.py::_coview_item, just off WatchlistEntry instead of
    CoViewEntry."""
    return MediaItem(
        id=entry.media_id,
        media_type=entry.media_type.value,
        external_ids=ExternalIds(),
        title=LocalizedText(ru=entry.title_ru, en=entry.title_en),
        description=LocalizedText(),
        poster_url=entry.poster_url,
        year=entry.year,
        genres=entry.genres or [],
        rating=entry.rating,
        source=entry.source,
    )


async def _build_vote_pool(db: Session, link: models.PartnerLink, source: PoolSource) -> List[dict]:
    """Four different decks, picked by `source`:

    - "personal": both sides' own "plan to watch" shelves, minus
      anything already on the shared co-viewing list (any status) —
      deciding among what's still undecided.
    - "coview": the shared co-viewing planned list itself — deciding
      which of what you've already agreed on to watch tonight.
    - "both": the union of the two above — still just what's queued or
      agreed between the two of you, nothing outside that.
    - "catalog": the *actual* everything — every movie/series/anime,
      game, book, and manga in the app (same cached pool GET /feed
      serves — see feed.py::get_discover_pool), not just what's already
      on either of your shelves. This is the one that can surface a
      title neither of you has queued yet.

    "personal"/"coview"/"both" are deduped by (source, media_id) against
    each other; "catalog" is its own separate pool (already deduped
    within itself upstream) and isn't merged with the other three.
    Shuffled once here so both phones vote through the same order.
    """
    if source == "catalog":
        catalog_pool = list(await get_discover_pool(db))
        random.shuffle(catalog_pool)
        return [item.model_dump(mode="json") for item in catalog_pool]

    coview_rows = db.query(models.CoViewEntry).filter_by(link_id=link.id).all()
    coview_by_key = {(r.source, r.media_id): r for r in coview_rows}

    pool: List[dict] = []
    seen: set[tuple[str, str]] = set()

    if source in ("coview", "both"):
        for r in coview_rows:
            if r.status != models.CoViewStatus.planned:
                continue
            key = (r.source, r.media_id)
            if key in seen:
                continue
            seen.add(key)
            pool.append(_coview_item(r).model_dump(mode="json"))

    if source in ("personal", "both"):
        uids = _member_ids(link)
        entries = (
            db.query(models.WatchlistEntry)
            .filter(
                models.WatchlistEntry.user_id.in_(uids),
                models.WatchlistEntry.status == models.WatchStatus.watch_later,
            )
            .all()
        )
        for e in entries:
            key = (e.source, e.media_id)
            if key in seen or key in coview_by_key:
                continue
            seen.add(key)
            pool.append(_watchlist_item(e).model_dump(mode="json"))

    random.shuffle(pool)
    return pool


def _get_active_session(db: Session, link: models.PartnerLink) -> models.CoViewVoteSession | None:
    return (
        db.query(models.CoViewVoteSession)
        .filter_by(link_id=link.id, status=models.CoViewVoteStatus.active)
        .order_by(models.CoViewVoteSession.created_at.desc())
        .first()
    )


def _require_link(db: Session, user_id: str) -> models.PartnerLink:
    link = get_active_link(db, user_id)
    if link is None:
        raise HTTPException(status_code=409, detail="Link with a partner first")
    return link


def _lock_link(db: Session, link: models.PartnerLink) -> models.PartnerLink:
    """Re-fetches `link` with a row lock, held for the rest of this
    transaction. start_vote/propose_vote both do "is there already an
    active round? if not, create one" — without a lock, two requests
    for the same link (both partners tapping "vote" within the same
    instant, or a double-tap) can both pass that check before either
    commits, so both create a session — silently breaking the "at most
    one active round per link" invariant CoViewVoteSession's own
    docstring promises, with no unique constraint backing it up at the
    database level either. Locking the link row here serializes the
    two: the second call now blocks until the first commits, then sees
    the session the first one just created and hands that back instead
    of making a second one.
    """
    return db.get(models.PartnerLink, link.id, with_for_update=True)


def _deck_items(row: models.CoViewVoteSession) -> List[MediaItem]:
    return TypeAdapter(List[MediaItem]).validate_json(row.deck_json)


def _to_out(row: models.CoViewVoteSession, current_user_id: str) -> CoViewVoteSessionOut:
    my_decided = [
        f"{v.source}:{v.media_id}" for v in row.votes if v.user_id == current_user_id
    ]
    partner_decided_count = sum(1 for v in row.votes if v.user_id != current_user_id)

    winner = None
    if row.winner_source and row.winner_media_id:
        by_key = {(i.source, i.id): i for i in _deck_items(row)}
        winner = by_key.get((row.winner_source, row.winner_media_id))

    return CoViewVoteSessionOut(
        id=row.id,
        status=row.status.value,
        pool_source=row.pool_source,
        deck=_deck_items(row),
        my_decided=my_decided,
        partner_decided_count=partner_decided_count,
        member_count=len(_member_ids(row.link)),
        winner=winner,
        created_at=row.created_at,
    )


def _get_session_for_link(
    db: Session, session_id: str, link: models.PartnerLink, *, for_update: bool = False,
) -> models.CoViewVoteSession:
    """`for_update=True` takes a row lock (`SELECT ... FOR UPDATE`) on the
    session for the rest of this transaction — see cast_vote's own
    comment for why that matters there. Plain reads (get_vote, the `.tr`
    round display) stay unlocked; there's no correctness reason for a
    GET to block on a concurrent vote, only cast_vote's read-then-decide
    needs exclusivity.
    """
    row = db.get(models.CoViewVoteSession, session_id, with_for_update=for_update)
    if row is None or row.link_id != link.id:
        raise HTTPException(status_code=404, detail="Round not found")
    return row


@router.get("/deck", response_model=List[MediaItem])
async def get_vote_deck(
    source: PoolSource = Query("personal"),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The raw pool, with no round attached — what the "pick for us" dice
    on the co-viewing screen draws its reroll from, without needing a
    synced round the way voting does."""
    link = _require_link(db, current_user.id)
    return TypeAdapter(List[MediaItem]).validate_python(await _build_vote_pool(db, link, source))


@router.post("", response_model=CoViewVoteSessionOut, status_code=201)
async def start_vote(
    source: PoolSource = Query("personal"),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Starts a round, or — if one's already active for this link — just
    hands that one back (whichever pool it was started with), so
    whichever of you taps "vote" first is the one both phones end up
    looking at."""
    link = _require_link(db, current_user.id)

    # Unlocked pre-check: skip building the pool entirely in the common
    # case where a round's already active. Not the actual race guard —
    # see the locked re-check right below, after the pool (which can hit
    # TMDB/IGDB on a cold cache — see _build_vote_pool's "catalog"
    # branch) is already built. Locking any earlier would hold the link
    # row locked across that network round trip, blocking the partner's
    # own request for no reason.
    precheck = _get_active_session(db, link)
    if precheck is not None:
        return _to_out(precheck, current_user.id)

    pool = await _build_vote_pool(db, link, source)
    if not pool:
        raise HTTPException(
            status_code=422,
            detail="Nothing there to vote on yet",
        )

    _lock_link(db, link)
    existing = _get_active_session(db, link)
    if existing is not None:
        return _to_out(existing, current_user.id)

    row = models.CoViewVoteSession(
        link_id=link.id,
        started_by_id=current_user.id,
        pool_source=source,
        deck_json=json.dumps(pool),
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return _to_out(row, current_user.id)


@router.post("/propose", response_model=CoViewVoteSessionOut, status_code=201)
def propose_vote(
    payload: CoViewVoteProposeRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Puts one specific pick — teamira's suggestion, a reel spin, a
    random draw — in front of the whole circle for a yes/no, instead of
    whoever tapped it adding it straight to the shared list on their
    own. Reuses the exact same round shape and "yes from everyone else"
    matching rule as a normal pool-sourced round (see cast_vote) — a
    one-item deck is just that rule's smallest case, nothing special-
    cased here. Same "hand back whatever's already active" behavior as
    start_vote too, so a stray double-tap (or a reroll racing a poll)
    can't fork the circle into two rounds it disagrees about.
    """
    link = _require_link(db, current_user.id)
    _lock_link(db, link)

    existing = _get_active_session(db, link)
    if existing is not None:
        return _to_out(existing, current_user.id)

    if not payload.items:
        raise HTTPException(status_code=422, detail="Nothing to propose")

    pool = [item.model_dump(mode="json") for item in payload.items]
    row = models.CoViewVoteSession(
        link_id=link.id,
        started_by_id=current_user.id,
        pool_source="proposed",
        deck_json=json.dumps(pool),
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return _to_out(row, current_user.id)


@router.get("/{session_id}", response_model=CoViewVoteSessionOut)
def get_vote(
    session_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Polled every couple of seconds while a round is open — same shape
    as Watch Together's own poll, minus the "has the guest joined yet"
    question, since a standing link already answers that."""
    link = _require_link(db, current_user.id)
    row = _get_session_for_link(db, session_id, link)
    return _to_out(row, current_user.id)


@router.post("/{session_id}/cast", response_model=CoViewVoteSessionOut)
def cast_vote(
    session_id: str,
    payload: CoViewVoteCastRequest,
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    link = _require_link(db, current_user.id)
    # Locked (see _get_session_for_link's own comment): two partners
    # tapping "yes" on the same title within milliseconds of each other
    # both used to read row.votes before the other's cast was committed,
    # so each independently saw only its own vote and neither ever
    # concluded "everyone said yes" — the match silently didn't fire
    # until someone acted again. Locking the row here serializes the
    # two requests: the second one now blocks until the first commits,
    # then reads row.votes fresh and actually sees the first vote. The
    # same lock also closes a second race one level up — both requests
    # racing past the `status != active` check below and both trying to
    # finish the round (and both calling add_coview_entries) — since the
    # second request's status read now happens only after the first has
    # already committed its status change.
    row = _get_session_for_link(db, session_id, link, for_update=True)
    if row.status != models.CoViewVoteStatus.active:
        raise HTTPException(status_code=409, detail="This round is already done")

    existing = (
        db.query(models.CoViewVoteCast)
        .filter_by(
            session_id=row.id,
            user_id=current_user.id,
            media_id=payload.media_id,
            source=payload.source,
        )
        .first()
    )
    if existing is None:
        db.add(models.CoViewVoteCast(
            session_id=row.id,
            user_id=current_user.id,
            media_id=payload.media_id,
            source=payload.source,
            decision=1 if payload.decision else 0,
        ))
        db.flush()
    else:
        existing.decision = 1 if payload.decision else 0

    matched_title_name = None
    matched_member_ids = None
    if payload.decision:
        # A match needs a yes from *everyone* else currently in the
        # circle, not just one specific other id — the couple case (one
        # other id) falls out of this as the size-1 special case, so
        # there's no separate branch needed for it.
        other_ids = [uid for uid in _member_ids(link) if uid != current_user.id]
        yes_ids = {
            v.user_id for v in row.votes
            if v.media_id == payload.media_id and v.source == payload.source and v.decision
        }
        yes_ids.add(current_user.id)
        everyone_said_yes = bool(other_ids) and all(uid in yes_ids for uid in other_ids)
        if everyone_said_yes:
            by_key = {(i.source, i.id): i for i in _deck_items(row)}
            winner = by_key.get((payload.source, payload.media_id))
            if winner is not None:
                row.status = models.CoViewVoteStatus.done
                row.winner_source = payload.source
                row.winner_media_id = payload.media_id
                # Already on both of your own plan-to-watch shelves — this
                # only needs to land on the shared list, not re-sync either
                # personal one.
                add_coview_entries(db, link, [winner], added_by_id=None, sync_own_watchlist=False)
                matched_title_name = winner.title.ru or winner.title.en or "что-то"
                matched_member_ids = list(yes_ids)
                matched_media_type = (
                    winner.media_type.value if hasattr(winner.media_type, "value") else winner.media_type
                )

    # Every successful cast changes something the *other* side's screen
    # shows — partner_decided_count at minimum, possibly a match — so
    # this always publishes, not just on the everyone_said_yes branch
    # above. Same transaction as the commit right below (see
    # app/realtime.py's own docstring for why that ordering matters).
    realtime.publish(db, realtime.topic_for("vote", row.id))
    db.commit()
    db.refresh(row)
    if matched_member_ids:
        # After commit, not before: a push describing a match that then
        # failed to save (row.status never actually reaching `done`)
        # would be worse than sending nothing — see app/push.py's own
        # docstring on this. Backgrounded so the person who just tapped
        # "yes" gets their response immediately regardless of how long
        # the actual FCM call takes.
        background_tasks.add_task(
            push.notify_match, matched_member_ids, matched_title_name,
            payload.media_id, payload.source, matched_media_type,
        )
    return _to_out(row, current_user.id)


@router.delete("/{session_id}", status_code=204)
def end_vote(
    session_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Either side can call it off — no match yet and you'd rather just
    pick randomly, or you want to reshuffle and start over."""
    link = _require_link(db, current_user.id)
    row = _get_session_for_link(db, session_id, link)
    topic = realtime.topic_for("vote", row.id)
    db.delete(row)
    # Still fires even though the row is gone by commit time — a
    # subscriber's own refetch just gets a 404 either way, which
    # run_ws_loop's `fetch` below already treats as "close, nothing
    # wrong". Publishing is what makes that happen right away instead
    # of only at the next heartbeat.
    realtime.publish(db, topic)
    db.commit()


@router.websocket("/{session_id}/ws")
async def watch_vote(
    websocket: WebSocket,
    session_id: str,
    token: str | None = None,
    db: Session = Depends(get_db),
):
    """Pushed updates for an open round — what replaces the mobile
    client's old `Timer.periodic(2s)` GET poll (see
    CoViewVoteService.poll and the `_pollTimer` in
    co_view_vote_screen.dart). See app/realtime.py for the actual pump;
    this just authenticates the connection and hands it a `fetch`
    closure that re-runs the same lookup+serialize get_vote above does.
    """
    await websocket.accept()
    user = await get_ws_user(token, db)
    if user is None:
        await websocket.close(code=4401)
        return

    def _fetch() -> str | None:
        try:
            link = _require_link(db, user.id)
            row = _get_session_for_link(db, session_id, link)
        except HTTPException:
            return None
        return _to_out(row, user.id).model_dump_json()

    await realtime.run_ws_loop(websocket, realtime.topic_for("vote", session_id), _fetch)
