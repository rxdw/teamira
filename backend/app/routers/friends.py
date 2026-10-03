import random
from datetime import datetime, timezone
from typing import List, Optional, Tuple

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Request
from sqlalchemy import and_, func, or_
from sqlalchemy.orm import Session

from app.config import settings
from app import models, push, similarity, sincerity
from app.invite_copy import build_share_text
from app.rate_limit import friend_search_limiter
from app.usernames import normalize_username
from app.database import get_db
from app.blocking import hidden_user_ids, is_blocked_between, visible_users_filter
from app.deps import get_active_user, get_current_user
from app.routers.partner import _member_ids, get_active_link
from app.routers.referrals import create_referral_for_signup
from app.routers.profile import (
    compute_level_for_user,
    compute_achievements_for_user,
    _pinned_ids_list,
)
from app.routers.activity import visible_to_friend, visible_to_everyone, item_from_event
from app.schemas import (
    FriendOut,
    FriendRequestCreate,
    FriendRequestOut,
    FriendSearchResultOut,
    FriendsOut,
    InviteOut,
    InviteClaimRequest,
    FriendProfileOut,
    FriendCollectionsOut,
    TopFavoritePick,
    SuggestedFriendOut,
    TasteMatchOut,
    SharedTasteTitleOut,
)

router = APIRouter(prefix="/friends", tags=["friends"])

# Bounded pool /suggested scores taste-match against before narrowing
# back down to the caller's requested `limit` — wide enough that taste
# ranking has real room to surface a good match instead of only ever
# reordering the newest dozen accounts, capped so this stays a fixed-
# cost query rather than a full-table scan as the user base grows.
_SUGGESTION_POOL_CAP = 300

# Same no-0/O/1/I alphabet as PartnerLink's own codes (see
# routers/partner.py) — easy to read aloud or type on a cramped keyboard.
# Longer than a partner code (8 vs 6) since this one is shared far more
# widely and reused by many people, not typed once by a single partner.
_INVITE_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
_INVITE_CODE_LENGTH = 8


def _gen_invite_code(db: Session) -> str:
    while True:
        code = "".join(random.choices(_INVITE_CODE_ALPHABET, k=_INVITE_CODE_LENGTH))
        if not db.query(models.User).filter_by(invite_code=code).first():
            return code


def _accepted_link(db: Session, user_a: str, user_b: str) -> models.FriendRequest | None:
    return (
        db.query(models.FriendRequest)
        .filter(
            models.FriendRequest.status == models.FriendRequestStatus.accepted,
            or_(
                (models.FriendRequest.from_user_id == user_a) & (models.FriendRequest.to_user_id == user_b),
                (models.FriendRequest.from_user_id == user_b) & (models.FriendRequest.to_user_id == user_a),
            ),
        )
        .first()
    )


def _any_link(db: Session, user_a: str, user_b: str) -> models.FriendRequest | None:
    """Any row between the two, answered or not — used to decide whether
    a new request is even allowed (see send_request)."""
    return (
        db.query(models.FriendRequest)
        .filter(
            or_(
                (models.FriendRequest.from_user_id == user_a) & (models.FriendRequest.to_user_id == user_b),
                (models.FriendRequest.from_user_id == user_b) & (models.FriendRequest.to_user_id == user_a),
            )
        )
        .first()
    )


def _friendship_status(db: Session, me_id: str, other_id: str) -> tuple[str, str | None]:
    """"none" | "friends" | "pending_outgoing" | "pending_incoming" plus
    the FriendRequest id behind a pending/accepted status — same
    vocabulary get_suggested_friends already tags search results with,
    reused here for the profile screen's own friend button (see
    FriendProfileOut.friendship_status)."""
    row = (
        db.query(models.FriendRequest)
        .filter(
            models.FriendRequest.status != models.FriendRequestStatus.declined,
            or_(
                and_(models.FriendRequest.from_user_id == me_id, models.FriendRequest.to_user_id == other_id),
                and_(models.FriendRequest.from_user_id == other_id, models.FriendRequest.to_user_id == me_id),
            ),
        )
        .first()
    )
    if row is None:
        return "none", None
    if row.status == models.FriendRequestStatus.accepted:
        return "friends", row.id
    return ("pending_outgoing" if row.from_user_id == me_id else "pending_incoming"), row.id


def _coview_status(db: Session, me_id: str, other_id: str) -> tuple[str, str | None]:
    """"none" | "same_circle" | "pending_outgoing" | "pending_incoming"
    for the profile screen's "invite to co-viewing" button — see
    FriendProfileOut.coview_status. Deliberately doesn't distinguish
    "you have no circle to invite through" from "none" here; the button
    itself starts one on first invite (see
    routers/partner.py::send_invite), so there's nothing extra for the
    profile screen to know or show ahead of time."""
    my_link = get_active_link(db, me_id)
    if my_link is not None and other_id in _member_ids(my_link):
        return "same_circle", None

    row = (
        db.query(models.PartnerLinkInvite)
        .filter(
            models.PartnerLinkInvite.status == models.PartnerLinkInviteStatus.pending,
            or_(
                and_(models.PartnerLinkInvite.from_user_id == me_id, models.PartnerLinkInvite.to_user_id == other_id),
                and_(models.PartnerLinkInvite.from_user_id == other_id, models.PartnerLinkInvite.to_user_id == me_id),
            ),
        )
        .first()
    )
    if row is None:
        return "none", None
    return ("pending_outgoing" if row.from_user_id == me_id else "pending_incoming"), row.id


def _recent_visible_event(db: Session, other: models.User) -> models.ActivityEvent | None:
    """The single most recent thing `other` logged that they've allowed a
    friend to see (see routers/activity.py::visible_to_friend) — powers
    the "last seen watching ___" line under a friend's name on the
    friends screen. Pulls a small page rather than just the newest row
    outright, since the newest row itself might be on a shelf this
    friend has hidden and the next one down might not be.
    """
    candidates = (
        db.query(models.ActivityEvent)
        .filter(models.ActivityEvent.user_id == other.id)
        .order_by(models.ActivityEvent.created_at.desc())
        .limit(10)
        .all()
    )
    for e in candidates:
        if visible_to_friend(other, e.verb):
            return e
    return None


def _taste_match_schema(match: Optional[similarity.TasteMatch]) -> Optional[TasteMatchOut]:
    """Pure conversion from app/similarity.py's dataclass to the wire
    schema — split out from _taste_match_out below so a caller that has
    already computed a TasteMatch (get_suggested_friends scores a whole
    pool at once and shouldn't recompute each pair) can reuse it instead
    of paying for a second lookup.
    """
    if match is None:
        return None
    return TasteMatchOut(
        overall=match.overall,
        headline=match.headline,
        basis=match.basis,
        confidence=match.confidence,
        shared_titles=[
            SharedTasteTitleOut(
                media_id=t.media_id, source=t.source, media_type=t.media_type,
                title_ru=t.title_ru, title_en=t.title_en, poster_url=t.poster_url,
            )
            for t in match.shared_titles
        ],
        shared_genres=match.shared_genres,
    )


def _taste_match_out(db: Session, viewer_id: str, other_id: str) -> Optional[TasteMatchOut]:
    """Computes and converts a single pair's taste match in one call —
    see _taste_match_schema for the conversion alone, used when the
    TasteMatch has already been computed elsewhere."""
    return _taste_match_schema(similarity.taste_match_between(db, viewer_id, other_id))


def _friend_out(db: Session, r: models.FriendRequest, other: models.User, viewer_id: str) -> FriendOut:
    recent = _recent_visible_event(db, other)
    return FriendOut(
        request_id=r.id,
        user_id=other.id,
        username=other.username,
        level=compute_level_for_user(db, other.id).level,
        friends_since=r.responded_at or r.created_at,
        display_name=other.display_name,
        avatar_preset=other.avatar_preset,
        avatar_url=other.avatar_url,
        status_text=other.status_text,
        recent_activity=item_from_event(recent, other.display_name or other.username) if recent else None,
        taste_match=_taste_match_out(db, viewer_id, other.id),
    )


_FRIENDS_PAGE_SIZE = 60


@router.get("", response_model=FriendsOut)
def list_friends(
    before: str | None = Query(
        default=None, description="a FriendOut.request_id to page before, for older friends"
    ),
    limit: int = Query(default=_FRIENDS_PAGE_SIZE, ge=1, le=200),
    full: bool = Query(
        default=False,
        description=(
            "bypass pagination on the accepted-friends list and return all of "
            "it — for pickers (co-view invites, etc) that need the complete "
            "set, not the friends screen's own scrolling view."
        ),
    ),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Everything the friends screen (and the profile's own friends block)
    needs in one call: the accepted list (with each friend's live level —
    see profile.py::compute_level_for_user), who's waiting on *you* to
    answer, and who *you're* still waiting on.

    The accepted list is cursor-paginated the same way GET /sincerity/me
    is (see routers/sincerity.py) — `total_friends` is a plain count
    that's accurate regardless of how much of the list has been paged
    in, so a badge/count display never needs the whole list loaded.
    Pending requests aren't paginated (see FriendsOut's own docstring).
    """
    pending_rows = (
        db.query(models.FriendRequest)
        .filter(
            or_(
                models.FriendRequest.from_user_id == current_user.id,
                models.FriendRequest.to_user_id == current_user.id,
            ),
            models.FriendRequest.status.notin_(
                [models.FriendRequestStatus.accepted, models.FriendRequestStatus.declined]
            ),
        )
        .order_by(models.FriendRequest.created_at.desc())
        .all()
    )
    incoming: List[FriendRequestOut] = []
    outgoing: List[FriendRequestOut] = []
    for r in pending_rows:
        other = r.to_user if r.from_user_id == current_user.id else r.from_user
        if other is None:
            continue
        out = FriendRequestOut(
            id=r.id, user_id=other.id, username=other.username, created_at=r.created_at,
            display_name=other.display_name, avatar_preset=other.avatar_preset, avatar_url=other.avatar_url,
        )
        (outgoing if r.from_user_id == current_user.id else incoming).append(out)

    accepted_q = db.query(models.FriendRequest).filter(
        or_(
            models.FriendRequest.from_user_id == current_user.id,
            models.FriendRequest.to_user_id == current_user.id,
        ),
        models.FriendRequest.status == models.FriendRequestStatus.accepted,
    )
    total_friends = accepted_q.count()

    order_key = func.coalesce(models.FriendRequest.responded_at, models.FriendRequest.created_at)

    if full:
        accepted_rows = accepted_q.order_by(order_key.desc(), models.FriendRequest.id.desc()).all()
        has_more = False
    else:
        if before:
            anchor = accepted_q.filter(models.FriendRequest.id == before).first()
            if anchor is not None:
                anchor_ts = anchor.responded_at or anchor.created_at
                accepted_q = accepted_q.filter(
                    or_(
                        order_key < anchor_ts,
                        and_(order_key == anchor_ts, models.FriendRequest.id < anchor.id),
                    )
                )
        accepted_rows = (
            accepted_q.order_by(order_key.desc(), models.FriendRequest.id.desc())
            .limit(limit + 1)
            .all()
        )
        has_more = len(accepted_rows) > limit
        accepted_rows = accepted_rows[:limit]

    friends: List[FriendOut] = []
    for r in accepted_rows:
        other = r.to_user if r.from_user_id == current_user.id else r.from_user
        if other is None:
            continue
        friends.append(_friend_out(db, r, other, current_user.id))

    return FriendsOut(
        friends=friends,
        has_more=has_more,
        total_friends=total_friends,
        incoming_requests=incoming,
        outgoing_requests=outgoing,
    )


# Three characters, not one. The old `min_length=1` paired with a
# `LIKE '%q%'` over every username turned this endpoint into a directory
# dump: twenty-six requests, one per letter of the alphabet, returned
# essentially the whole user table — ids, usernames, display names and
# avatar URLs — to any account that could sign up. Raising the floor
# doesn't fix that alone (three-letter prefixes are only ~17k
# combinations), which is why the query shape, the opt-out and the rate
# limit below all change together.
_MIN_SEARCH_LENGTH = 3
_MAX_SEARCH_RESULTS = 20


@router.get("/search", response_model=List[FriendSearchResultOut])
def search_users(
    q: str = Query(..., min_length=_MIN_SEARCH_LENGTH, max_length=64),
    current_user: models.User = Depends(get_active_user),
    db: Session = Depends(get_db),
):
    """Username search to start a friend request.

    Four things changed here, and they only work as a set:

    1. **Prefix, not substring.** `username LIKE 'ann%'` instead of
       `LIKE '%ann%'`. A substring match means every account whose name
       *contains* any two letters comes back, which is what made walking
       the namespace trivial. Prefix matching is also what people
       actually expect from a handle lookup — you type the start of a
       name you already know, you don't go fishing for fragments.
    2. **A floor on the query length** (see _MIN_SEARCH_LENGTH above).
    3. **An opt-out.** `users.discoverable` — "people can find me by my
       username" in Settings. Anyone who turns it off stops appearing
       here entirely, while existing friendships and a directly-shared
       invite code keep working exactly as before. There was no way to
       be un-findable at all before.
    4. **A rate limit**, keyed on the caller's account rather than their
       IP, since this endpoint is authenticated. See
       rate_limit.friend_search_limiter — enumeration is a volume attack,
       so the query shape alone was never going to be enough.

    Blocked accounts, deleted accounts and suspended accounts never
    appear, whatever the query — see app/blocking.py::hidden_user_ids.
    """
    friend_search_limiter.check(db, current_user.id)

    needle = normalize_username(q)
    if len(needle) < _MIN_SEARCH_LENGTH:
        return []

    # Escaped so a name containing % or _ is searched for literally
    # rather than acting as a wildcard — otherwise a single "%" query
    # would still return the whole table, which would undo everything
    # above in one character.
    escaped = needle.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")

    hidden = hidden_user_ids(db, current_user.id)

    matches = (
        db.query(models.User)
        .filter(
            *visible_users_filter(current_user.id),
            models.User.discoverable.is_(True),
            or_(
                models.User.username_lower.like(f"{escaped}%", escape="\\"),
                # Fallback for rows written before username_lower
                # existed and not yet backfilled. Costs an extra
                # sequential predicate on a small table; removable once
                # the backfill in the accompanying migration has run
                # everywhere.
                and_(
                    models.User.username_lower.is_(None),
                    func.lower(models.User.username).like(f"{escaped}%", escape="\\"),
                ),
            ),
        )
        .order_by(models.User.username)
        .limit(_MAX_SEARCH_RESULTS * 2)
        .all()
    )
    matches = [u for u in matches if u.id not in hidden][:_MAX_SEARCH_RESULTS]

    links = (
        db.query(models.FriendRequest)
        .filter(
            or_(
                models.FriendRequest.from_user_id == current_user.id,
                models.FriendRequest.to_user_id == current_user.id,
            ),
            models.FriendRequest.status != models.FriendRequestStatus.declined,
        )
        .all()
    )
    accepted_ids = set()
    outgoing_ids = set()
    incoming_ids = set()
    for r in links:
        other_id = r.to_user_id if r.from_user_id == current_user.id else r.from_user_id
        if r.status == models.FriendRequestStatus.accepted:
            accepted_ids.add(other_id)
        elif r.from_user_id == current_user.id:
            outgoing_ids.add(other_id)
        else:
            incoming_ids.add(other_id)

    results = []
    for u in matches:
        if u.id in accepted_ids:
            status = "friends"
        elif u.id in outgoing_ids:
            status = "pending_outgoing"
        elif u.id in incoming_ids:
            status = "pending_incoming"
        else:
            status = "none"
        results.append(FriendSearchResultOut(
            user_id=u.id, username=u.username, status=status,
            display_name=u.display_name, avatar_preset=u.avatar_preset, avatar_url=u.avatar_url,
        ))
    return results


@router.post("/request", response_model=FriendRequestOut, status_code=201)
def send_request(
    payload: FriendRequestCreate,
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    # Matched on the normalized column (see app/usernames.py) rather than
    # `func.lower(username)`, which is what this used before — the two
    # disagree on anything Unicode does interesting things to, and
    # registration checks the normalized form, so this has to as well or
    # a name that can be registered still can't be friended.
    needle = normalize_username(payload.username)
    target = (
        db.query(models.User)
        .filter(
            or_(
                models.User.username_lower == needle,
                func.lower(models.User.username) == needle,
            )
        )
        .first()
    )
    if not target or target.deleted_at is not None:
        raise HTTPException(status_code=404, detail="No one on tanè has that username")
    if target.id == current_user.id:
        raise HTTPException(status_code=400, detail="That's your own username")
    if is_blocked_between(db, current_user.id, target.id):
        # Deliberately the same 404 as "no such username". Telling the
        # sender "you're blocked" hands the blocked person a reliable way
        # to confirm the block, which is exactly what a block is supposed
        # not to do — and telling the *blocker's* side apart from a typo
        # gains nobody anything.
        raise HTTPException(status_code=404, detail="No one on tanè has that username")
    if target.suspended_at is not None:
        raise HTTPException(status_code=404, detail="No one on tanè has that username")

    existing = _any_link(db, current_user.id, target.id)
    if existing:
        if existing.status == models.FriendRequestStatus.accepted:
            raise HTTPException(status_code=400, detail="Already friends")
        if existing.status == models.FriendRequestStatus.pending:
            raise HTTPException(status_code=400, detail="A request is already pending between you two")
        # A previously declined request between this pair — clear it so a
        # fresh one can be sent without fighting the unique pair constraint.
        db.delete(existing)
        db.flush()

    request = models.FriendRequest(from_user_id=current_user.id, to_user_id=target.id)
    db.add(request)
    db.commit()
    db.refresh(request)
    background_tasks.add_task(
        push.notify_friend_request,
        user_id=target.id,
        from_display_name=current_user.display_name or current_user.username,
    )
    return FriendRequestOut(
        id=request.id, user_id=target.id, username=target.username, created_at=request.created_at,
        display_name=target.display_name, avatar_preset=target.avatar_preset, avatar_url=target.avatar_url,
    )


def _own_incoming_request(db: Session, current_user_id: str, request_id: str) -> models.FriendRequest:
    request = db.query(models.FriendRequest).filter_by(id=request_id).first()
    if not request or request.to_user_id != current_user_id:
        raise HTTPException(status_code=404, detail="Request not found")
    if request.status != models.FriendRequestStatus.pending:
        raise HTTPException(status_code=400, detail="That request was already answered")
    return request


@router.post("/requests/{request_id}/accept", response_model=FriendOut)
def accept_request(
    request_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    request = _own_incoming_request(db, current_user.id, request_id)
    request.status = models.FriendRequestStatus.accepted
    request.responded_at = datetime.now(timezone.utc)
    db.commit()
    other = request.from_user
    return _friend_out(db, request, other, current_user.id)


@router.post("/requests/{request_id}/decline", status_code=204)
def decline_request(
    request_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    request = _own_incoming_request(db, current_user.id, request_id)
    request.status = models.FriendRequestStatus.declined
    request.responded_at = datetime.now(timezone.utc)
    db.commit()


@router.delete("/requests/{request_id}", status_code=204)
def cancel_outgoing_request(
    request_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Withdraws a request *you* sent, before the other side has answered."""
    request = db.query(models.FriendRequest).filter_by(id=request_id).first()
    if not request or request.from_user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Request not found")
    if request.status != models.FriendRequestStatus.pending:
        raise HTTPException(status_code=400, detail="That request was already answered")
    db.delete(request)
    db.commit()


@router.delete("/{friend_user_id}", status_code=204)
def remove_friend(
    friend_user_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    link = _accepted_link(db, current_user.id, friend_user_id)
    if not link:
        raise HTTPException(status_code=404, detail="Not friends with that account")
    db.delete(link)
    db.commit()


def _shelf_for_status(entries: list[models.WatchlistEntry], status: models.WatchStatus) -> list[models.WatchlistEntry]:
    return [e for e in entries if e.status == status]


def _visible_activity_for_profile(
    db: Session, other: models.User, is_friend: bool, limit: int = 20
) -> list[models.ActivityEvent]:
    """`other`'s recent events a profile viewer is allowed to see, same
    relationship-gating as the shelves in get_friend_profile: an accepted
    friend (or the account's own profile) sees anything left at "friends"
    or "everyone", a stranger only sees "everyone" — "nobody" stays
    hidden no matter who's asking. Pulls a larger page than `limit` since
    some rows may get filtered out below.
    """
    candidates = (
        db.query(models.ActivityEvent)
        .filter(models.ActivityEvent.user_id == other.id)
        .order_by(models.ActivityEvent.created_at.desc())
        .limit(limit * 3)
        .all()
    )
    check = visible_to_friend if is_friend else visible_to_everyone
    return [e for e in candidates if check(other, e.verb)][:limit]


@router.get("/{user_id}/profile", response_model=FriendProfileOut)
async def get_friend_profile(
    user_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Any account's profile screen: header + the three shelves + recent
    activity, each filtered by that person's own privacy setting for it
    (see models.User.privacy_watched/watching/planned) — reachable both
    for an accepted friend (from the friends screen) and for a stranger
    (from "people you may know"). What shows depends on the relationship:
    an accepted friend (or this account looking at its own profile) sees
    anything left at "friends" or "everyone"; anyone else only sees
    "everyone". Either way "nobody" stays hidden no matter who's asking.
    """
    other = db.query(models.User).filter_by(id=user_id).first()
    if not other:
        raise HTTPException(status_code=404, detail="No such account")
    # A blocked, deleted or suspended account is a 404 from this screen,
    # not a stripped-down profile. Anything else — an empty profile, a
    # "this account is unavailable" card — is still a confirmation that
    # the account exists and a way to detect a block from the other side.
    # Someone looking at their own profile is always allowed through,
    # including while their own deletion is pending.
    if user_id != current_user.id and (
        other.deleted_at is not None
        or other.suspended_at is not None
        or is_blocked_between(db, current_user.id, user_id)
    ):
        raise HTTPException(status_code=404, detail="No such account")

    is_friend = _accepted_link(db, current_user.id, user_id) is not None

    def _shelf_ok(level: str | None) -> bool:
        level = level or "everyone"
        if level == "nobody":
            return False
        if level == "friends":
            return is_friend or user_id == current_user.id
        return True

    entries = (
        db.query(models.WatchlistEntry)
        .filter(models.WatchlistEntry.user_id == user_id)
        .order_by(models.WatchlistEntry.updated_at.desc())
        .all()
    )
    watched_ok = _shelf_ok(other.privacy_watched)
    watching_ok = _shelf_ok(other.privacy_watching)
    planned_ok = _shelf_ok(other.privacy_planned)
    favorites_ok = _shelf_ok(other.privacy_favorites)

    # Favorite films: status-independent (is_favorite=True), movies only —
    # a favorite can be pinned from any shelf, not only `watched` (see
    # WatchlistEntry.is_favorite's own docstring), and gated by its own
    # privacy_favorites setting rather than watched_ok, so someone can
    # keep a single pinned favorite public while keeping the rest of
    # their watched list private, or vice versa.
    favorite_entries = (
        [e for e in entries if e.is_favorite and e.media_type == "movie"] if favorites_ok else []
    )

    collections = FriendCollectionsOut(
        watch_later=_shelf_for_status(entries, models.WatchStatus.watch_later) if planned_ok else [],
        watch_later_visible=planned_ok,
        watching=_shelf_for_status(entries, models.WatchStatus.watching) if watching_ok else [],
        watching_visible=watching_ok,
        watched=_shelf_for_status(entries, models.WatchStatus.watched) if watched_ok else [],
        watched_visible=watched_ok,
        favorites=favorite_entries,
        favorites_visible=favorites_ok,
        top_favorite_picks=[
            TopFavoritePick(**p) for p in (other.top_favorite_picks or [])
        ] if favorites_ok else [],
    )

    is_own_profile = user_id == current_user.id
    activity_events = _visible_activity_for_profile(db, other, is_friend or is_own_profile)
    who = other.display_name or other.username
    recent_activity = [item_from_event(e, who) for e in activity_events]

    # Pinned badge showcase — always visible, not gated by any of the
    # shelf privacy settings above since it's a deliberate self-
    # presentation choice, not a log of what they watched.
    pinned_ids = set(_pinned_ids_list(other))
    pinned_achievements = []
    if pinned_ids:
        other_achievements = await compute_achievements_for_user(db, other)
        by_id = {a.id: a for a in other_achievements}
        pinned_achievements = [by_id[aid] for aid in _pinned_ids_list(other) if aid in by_id]

    friendship_status, friend_request_id = (
        ("friends", None) if is_own_profile else _friendship_status(db, current_user.id, user_id)
    )
    coview_status, coview_invite_id = (
        ("none", None) if is_own_profile else _coview_status(db, current_user.id, user_id)
    )

    return FriendProfileOut(
        user_id=other.id,
        username=other.username,
        level=compute_level_for_user(db, other.id).level,
        display_name=other.display_name,
        avatar_preset=other.avatar_preset,
        avatar_url=other.avatar_url,
        status_text=other.status_text,
        collections=collections,
        pinned_achievements=pinned_achievements,
        recent_activity=recent_activity,
        friendship_status=friendship_status,
        friend_request_id=friend_request_id,
        coview_status=coview_status,
        coview_invite_id=coview_invite_id,
    )


@router.get("/suggested", response_model=List[SuggestedFriendOut])
def get_suggested_friends(
    limit: int = Query(12, ge=1, le=30),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """"People you may know" for the bottom of the friends screen — and,
    doing double duty, onboarding's "people like you" step right after
    the favorites picker (see app/similarity.py's own docstring for why
    a few picked favorites is already enough real data to rank against).
    Anyone on teamira who isn't already a friend and has no pending
    request either way with this account. Each row carries a small
    preview of that person's most recent *public* activity (privacy
    left at "everyone" — a non-friend never sees a "friends"-only or
    "nobody" shelf, unlike the friends-list preview above), so tapping
    a card can show the same familiar preview before a request is even
    sent.

    Ranked by taste match (see similarity.compare) wherever there's
    enough shelf data on both sides to compute one, highest first;
    candidates similarity has nothing to say about yet (a brand new
    account with an empty watchlist, say) fall back to newest-account-
    first behind them — the same honest default this endpoint used
    everywhere before taste matching existed, rather than a fabricated
    0% burying them at the very end.
    """
    linked_rows = (
        db.query(models.FriendRequest)
        .filter(
            or_(
                models.FriendRequest.from_user_id == current_user.id,
                models.FriendRequest.to_user_id == current_user.id,
            ),
            models.FriendRequest.status != models.FriendRequestStatus.declined,
        )
        .all()
    )
    excluded_ids = {current_user.id}
    for r in linked_rows:
        excluded_ids.add(r.to_user_id if r.from_user_id == current_user.id else r.from_user_id)

    # A wider bounded pool than `limit` (capped, not a full-table scan)
    # so taste ranking has more than just the newest handful of accounts
    # to choose from — narrowed back down to `limit` only after scoring.
    pool = (
        db.query(models.User)
        .filter(models.User.id.notin_(excluded_ids))
        .order_by(models.User.created_at.desc())
        .limit(_SUGGESTION_POOL_CAP)
        .all()
    )

    viewer_profile = similarity.get_taste_profile_cached(db, current_user.id)
    scored: List[Tuple[models.User, Optional[similarity.TasteMatch]]] = []
    for u in pool:
        match = (
            similarity.compare(viewer_profile, similarity.get_taste_profile_cached(db, u.id))
            if viewer_profile.sample_size > 0
            else None
        )
        scored.append((u, match))

    with_match = sorted(
        (pair for pair in scored if pair[1] is not None),
        key=lambda pair: pair[1].overall,
        reverse=True,
    )
    without_match = [pair for pair in scored if pair[1] is None]  # already newest-first
    ordered = (with_match + without_match)[:limit]

    results: List[SuggestedFriendOut] = []
    for u, match in ordered:
        recent_events = (
            db.query(models.ActivityEvent)
            .filter(models.ActivityEvent.user_id == u.id)
            .order_by(models.ActivityEvent.created_at.desc())
            .limit(10)
            .all()
        )
        preview = [
            item_from_event(e, u.display_name or u.username)
            for e in recent_events
            if visible_to_everyone(u, e.verb)
        ][:3]
        results.append(SuggestedFriendOut(
            user_id=u.id,
            username=u.username,
            level=compute_level_for_user(db, u.id).level,
            display_name=u.display_name,
            avatar_preset=u.avatar_preset,
            avatar_url=u.avatar_url,
            status_text=u.status_text,
            recent_activity=preview,
            taste_match=_taste_match_schema(match),
        ))
    return results


@router.get("/{user_id}/taste-match", response_model=TasteMatchOut)
def get_taste_match(
    user_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The detailed one-pair breakdown behind a compact taste_match
    field elsewhere on this router — used when a friend-profile screen
    (or a suggested-friend card, opened for more detail) wants the full
    picture rather than the summary already inlined on the list. 404s
    exactly like a missing user would anywhere else on this router;
    returns null in the body (not a 404) when the pair simply has
    nothing to compare yet — see similarity.compare's own docstring for
    why that's not the same thing as a 0% match.
    """
    if user_id == current_user.id:
        raise HTTPException(status_code=400, detail="That's your own account")
    target = db.query(models.User).filter_by(id=user_id).first()
    if not target or target.deleted_at is not None:
        raise HTTPException(status_code=404, detail="No such user")
    if is_blocked_between(db, current_user.id, user_id):
        raise HTTPException(status_code=404, detail="No such user")
    out = _taste_match_out(db, current_user.id, user_id)
    if out is None:
        raise HTTPException(status_code=404, detail="Not enough shelf data on one or both sides yet")
    return out


@router.get("/invite", response_model=InviteOut)
def get_invite(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """This account's own standing invite code — minted once, reused for
    every share. `invited_count`/`sincerity_bonus` mirror exactly what
    app/sincerity.py::earn_friend_invited pays out per invite, so the
    number shown here never drifts from what actually landed in the
    ledger.
    """
    if not current_user.invite_code:
        current_user.invite_code = _gen_invite_code(db)
        db.commit()
        db.refresh(current_user)

    invited_count = (
        db.query(func.count(models.User.id))
        .filter(models.User.referred_by_id == current_user.id)
        .scalar()
    ) or 0

    # A real tappable link once Settings.public_web_base_url is set (see
    # routers/linking.py) — until then, fall back to the bare code the
    # registration screen already knows how to accept by hand.
    link = (
        f"{settings.public_web_base_url.rstrip('/')}/i/{current_user.invite_code}"
        if settings.public_web_base_url
        else None
    )
    share_text = build_share_text(link=link, invite_code=current_user.invite_code)

    return InviteOut(
        code=current_user.invite_code,
        share_text=share_text,
        invited_count=invited_count,
        sincerity_bonus=invited_count * sincerity.FRIEND_INVITED_AWARD,
        sincerity_per_friend=sincerity.FRIEND_INVITED_AWARD,
    )


@router.post("/invite/claim", status_code=204)
def claim_invite(
    payload: InviteClaimRequest,
    request: Request,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The no-external-service half of the referral link (see
    routers/linking.py's module docstring for the full picture): the
    registration screen already lets someone type a code up front
    (routers/auth.py::register), but the whole point of a shareable link
    is that they *shouldn't* have to. Instead, GET /i/{code} hands the
    code to the client (via the seenly:// launch, an Android App Link,
    or — if the app had to be installed first — the Play Store install
    referrer / clipboard fallback the client reads on first open), and
    the client calls this once, silently, right after login/signup.

    Deliberately forgiving about *when* it's called: works whether the
    account already existed (a returning user tapping a friend's link)
    or was just created seconds ago by the same flow — either way this
    is the only place referred_by_id gets set outside of registration
    itself, so it mirrors that endpoint's own rules exactly (can't refer
    yourself, can't overwrite a referrer already on file, code must be
    real). Any of those being false is a quiet no-op, not an error — a
    stale or already-claimed link tapped a second time shouldn't ever
    surface as a visible failure to the person who tapped it.
    """
    if current_user.referred_by_id:
        return
    code = payload.code.strip()
    if not code:
        return
    referrer = (
        db.query(models.User)
        .filter(func.upper(models.User.invite_code) == code.upper())
        .first()
    )
    if not referrer or referrer.id == current_user.id:
        return
    current_user.referred_by_id = referrer.id
    db.commit()
    # See routers/referrals.py — same reward-program hook as
    # routers/auth.py::register, for the "already had an account,
    # tapped a friend's link afterward" path.
    ip = request.client.host if request.client else None
    create_referral_for_signup(db, referrer_id=referrer.id, referred_id=current_user.id, ip=ip)
    # See app/sincerity.py::earn_friend_invited — same sincerity award
    # routers/auth.py::register pays for a code entered at signup.
    sincerity.earn_friend_invited(db, referrer, friend_name=current_user.username)
    db.commit()
