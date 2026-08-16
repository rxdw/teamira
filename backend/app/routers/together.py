import json
import random
from datetime import datetime, timedelta
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from pydantic import TypeAdapter
from sqlalchemy.orm import Session

from app import cache, models
from app.database import get_db
from app.deps import get_current_user
from app.routers.feed import add_watchlist_status
from app.routers.partner import add_coview_entries, find_link_between
from app.adapters.tmdb import TmdbAdapter
from app.adapters.igdb import IgdbAdapter
from app.adapters.google_books import GoogleBooksAdapter
from app.adapters.shikimori import ShikimoriMangaAdapter
from app.schemas import (
    Collection,
    MediaItem,
    TogetherCreateRequest,
    TogetherJoinRequest,
    TogetherSessionOut,
    TogetherSwipeRequest,
)

router = APIRouter(prefix="/together", tags=["together"])

_tmdb = TmdbAdapter()
_games = IgdbAdapter()
_books = GoogleBooksAdapter()
_manga = ShikimoriMangaAdapter()

# No 0/O/1/I — codes get read aloud or typed on a cramped keyboard, so the
# alphabet drops anything that's easy to mis-key or mis-hear.
_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
_SESSION_TTL = timedelta(hours=12)  # an abandoned "waiting" code stops being joinable after this


def _gen_code(db: Session) -> str:
    while True:
        code = "".join(random.choices(_CODE_ALPHABET, k=6))
        if not db.query(models.TogetherSession).filter_by(code=code).first():
            return code


def _matches_type_filter(media_type: str, type_filter: str) -> bool:
    """The client's 'series' tab is labeled and behaves as "series &
    anime" (see TogetherScreen._filters) — a deliberate grouping for this
    one feature, distinct from Collections/Search where anime is its own
    tab. Keep that grouping here too so a network session's deck matches
    what the host who picked "series & anime" actually saw client-side."""
    if type_filter == "series":
        return media_type in ("series", "anime")
    return media_type == type_filter


def _matches_genre_filter(item_genres: List[str], genres_filter: List[str]) -> bool:
    """Empty genres_filter means no narrowing (same 'no filter' meaning
    type_filter's 'all' has). Otherwise a card only needs to share ONE
    genre with the picked set — requiring all of them would make picking
    two genres almost always empty the deck."""
    if not genres_filter:
        return True
    wanted = {g.lower() for g in genres_filter}
    return any(g.lower() in wanted for g in item_genres)


async def _build_deck(db: Session, type_filter: str, genres_filter: List[str] | None = None) -> List[dict]:
    """The same real-title pool the one-phone mode shuffles through (see
    TogetherScreen._startSession on the client) — built once here so both
    phones in a session swipe through an identical, already-shuffled deck.
    Reuses the Collections tab's 24h cache, so starting a session never
    costs an extra round-trip to TMDB/IGDB/Open Library on top of what the
    app already pays for elsewhere.
    """
    async def _fetch() -> List[Collection]:
        shelves = await _tmdb.named_collections()
        try:
            shelves += await _games.named_collections()
        except RuntimeError:
            pass
        shelves += await _books.named_collections()
        shelves += await _manga.named_collections()
        # named_collections() now returns (title_ru, title_en, items) —
        # see app/routers/feed.py::get_collections for why. This deck is
        # only ever flattened into cards below, shelf names aren't shown,
        # but the tuple shape has to match regardless.
        return [Collection(title=t_ru, title_en=t_en, items=i) for t_ru, t_en, i in shelves if i]

    payload_json = await cache.cached_dynamic(db, "feed:collections", _fetch)
    collections = TypeAdapter(List[Collection]).validate_json(payload_json)

    seen: set[str] = set()
    pool: List[dict] = []
    for c in collections:
        for item in c.items:
            if type_filter != "all" and not _matches_type_filter(item.media_type, type_filter):
                continue
            if not _matches_genre_filter(item.genres, genres_filter or []):
                continue
            key = f"{item.source}:{item.id}"
            if key in seen:
                continue
            seen.add(key)
            pool.append(item.model_dump(mode="json"))
    random.shuffle(pool)
    return pool


def _get_session_for_participant(db: Session, session_id: str, user_id: str) -> models.TogetherSession:
    row = db.get(models.TogetherSession, session_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Session not found")
    if user_id not in (row.owner_id, row.guest_id):
        raise HTTPException(status_code=403, detail="Not a participant in this session")
    return row


def _deck_items(row: models.TogetherSession) -> List[MediaItem]:
    return TypeAdapter(List[MediaItem]).validate_json(row.deck_json)


def _matches(db: Session, row: models.TogetherSession) -> List[MediaItem]:
    if row.guest_id is None:
        return []
    owner_yes = {
        (s.source, s.media_id)
        for s in row.swipes
        if s.user_id == row.owner_id and s.decision
    }
    guest_yes = {
        (s.source, s.media_id)
        for s in row.swipes
        if s.user_id == row.guest_id and s.decision
    }
    matched_keys = owner_yes & guest_yes
    if not matched_keys:
        return []
    by_key = {(item.source, item.id): item for item in _deck_items(row)}
    return [by_key[k] for k in matched_keys if k in by_key]


def _to_out(db: Session, row: models.TogetherSession, current_user: models.User) -> TogetherSessionOut:
    my_role = "owner" if current_user.id == row.owner_id else "guest"
    partner_id = row.guest_id if my_role == "owner" else row.owner_id

    my_swiped = sum(1 for s in row.swipes if s.user_id == current_user.id)
    partner_swiped = sum(1 for s in row.swipes if partner_id and s.user_id == partner_id)

    return TogetherSessionOut(
        id=row.id,
        code=row.code,
        status=row.status.value,
        type_filter=row.type_filter,
        genres_filter=row.genres_filter or [],
        deck=_deck_items(row),
        owner_username=row.owner.username,
        guest_username=row.guest.username if row.guest else None,
        my_role=my_role,
        my_swiped=my_swiped,
        partner_swiped=partner_swiped,
        matches=_matches(db, row),
        created_at=row.created_at,
    )


def _add_match_to_both_lists(db: Session, row: models.TogetherSession, item: MediaItem) -> None:
    """A match should land on the *shared* co-viewing screen
    unconditionally when these two accounts are linked (see the
    add_coview_entries call below) — that's the whole point of a linked
    pair swiping together, on one phone or over the network.

    Whether it ALSO lands on each account's own "plan to watch" shelf
    (WatchlistEntry) and its named "watch together" list is a separate,
    per-account question, governed entirely by that account's own
    owner_sync_to_list/guest_sync_to_list toggle — mirrors the client's
    local pass-the-phone mode (see TogetherScreen._decide), where both
    of those writes are gated behind the same "add matches to my own
    list too" preference instead of the watchlist write firing
    unconditionally while only the named list respected the toggle.
    """
    for user_id, wants_it in (
        (row.owner_id, row.owner_sync_to_list),
        (row.guest_id, row.guest_sync_to_list),
    ):
        if not user_id or not wants_it:
            continue
        add_watchlist_status(db, user_id, item, models.WatchStatus.watch_later, "added to watch later")
        list_row = _ensure_together_list(db, user_id)
        existing = (
            db.query(models.UserListItem)
            .filter_by(list_id=list_row.id, source=item.source, media_id=item.id)
            .first()
        )
        if existing is None:
            db.add(models.UserListItem(
                list_id=list_row.id,
                media_id=item.id,
                media_type=item.media_type,
                source=item.source,
                title_ru=item.title.ru,
                title_en=item.title.en,
                poster_url=item.poster_url,
                year=item.year,
                genres=item.genres,
                rating=item.rating,
            ))

    # If these two accounts also have a standing partner link (not every
    # network session does — a code can be swapped with anyone), the match
    # additionally lands on their shared co-viewing screen, right alongside
    # matches from the suggest heart and from local pass-the-phone mode.
    # sync_own_watchlist=False: each side's own "plan to watch" shelf was
    # already written (or not) above, gated by that side's own
    # owner_sync_to_list/guest_sync_to_list — this call must only add the
    # shared CoViewEntry, not re-add it unconditionally on top of that.
    if row.guest_id:
        link = find_link_between(db, row.owner_id, row.guest_id)
        if link is not None:
            add_coview_entries(db, link, [item], sync_own_watchlist=False)


_TOGETHER_LIST_NAME = "watch together"


def _ensure_together_list(db: Session, user_id: str) -> models.UserList:
    row = (
        db.query(models.UserList)
        .filter_by(user_id=user_id, name=_TOGETHER_LIST_NAME)
        .first()
    )
    if row is not None:
        return row
    row = models.UserList(
        user_id=user_id,
        name=_TOGETHER_LIST_NAME,
        description="titles you both said yes to",
    )
    db.add(row)
    db.flush()
    return row


@router.post("", response_model=TogetherSessionOut, status_code=201)
async def create_session(
    payload: TogetherCreateRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    deck = await _build_deck(db, payload.type_filter, payload.genres)
    if not deck:
        raise HTTPException(status_code=422, detail="Nothing to shuffle right now")

    row = models.TogetherSession(
        code=_gen_code(db),
        owner_id=current_user.id,
        type_filter=payload.type_filter,
        genres_filter=payload.genres,
        owner_sync_to_list=payload.sync_to_own_list,
        deck_json=json.dumps(deck),
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return _to_out(db, row, current_user)


@router.post("/join", response_model=TogetherSessionOut)
def join_session(
    payload: TogetherJoinRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    code = payload.code.strip().upper()
    row = db.query(models.TogetherSession).filter_by(code=code).first()
    if row is None:
        raise HTTPException(status_code=404, detail="That code doesn't match a session")
    if row.owner_id == current_user.id:
        raise HTTPException(status_code=400, detail="That's your own code — send it to the other person")
    if row.status == models.TogetherSessionStatus.done:
        raise HTTPException(status_code=410, detail="This session has ended")
    if row.guest_id is not None and row.guest_id != current_user.id:
        raise HTTPException(status_code=409, detail="Someone already joined this session")
    if datetime.utcnow() - row.created_at > _SESSION_TTL:
        raise HTTPException(status_code=410, detail="This code has expired — ask for a new one")

    if row.guest_id is None:
        row.guest_id = current_user.id
        row.guest_sync_to_list = payload.sync_to_own_list
        row.status = models.TogetherSessionStatus.active
        db.commit()
        db.refresh(row)
    return _to_out(db, row, current_user)


@router.get("/{session_id}", response_model=TogetherSessionOut)
def get_session(
    session_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Polled every couple of seconds while a session is open — carries
    whether the partner has joined yet, how far along they are, and the
    running list of matches, without either phone needing a socket."""
    row = _get_session_for_participant(db, session_id, current_user.id)
    return _to_out(db, row, current_user)


@router.post("/{session_id}/swipe", response_model=TogetherSessionOut)
def swipe(
    session_id: str,
    payload: TogetherSwipeRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    row = _get_session_for_participant(db, session_id, current_user.id)
    if row.status != models.TogetherSessionStatus.active:
        raise HTTPException(status_code=409, detail="Session isn't active")

    existing = (
        db.query(models.TogetherSwipe)
        .filter_by(
            session_id=row.id,
            user_id=current_user.id,
            media_id=payload.media_id,
            source=payload.source,
        )
        .first()
    )
    if existing is None:
        db.add(models.TogetherSwipe(
            session_id=row.id,
            user_id=current_user.id,
            media_id=payload.media_id,
            source=payload.source,
            decision=1 if payload.decision else 0,
        ))
        db.flush()
    else:
        existing.decision = 1 if payload.decision else 0

    if payload.decision:
        partner_id = row.guest_id if current_user.id == row.owner_id else row.owner_id
        partner_said_yes = partner_id and any(
            s.user_id == partner_id and s.media_id == payload.media_id
            and s.source == payload.source and s.decision
            for s in row.swipes
        )
        if partner_said_yes:
            by_key = {(i.source, i.id): i for i in _deck_items(row)}
            matched_item = by_key.get((payload.source, payload.media_id))
            if matched_item:
                _add_match_to_both_lists(db, row, matched_item)

    db.commit()
    db.refresh(row)
    return _to_out(db, row, current_user)


@router.delete("/{session_id}", status_code=204)
def end_session(
    session_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    row = _get_session_for_participant(db, session_id, current_user.id)
    row.status = models.TogetherSessionStatus.done
    db.commit()
