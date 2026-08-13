import random
from datetime import datetime
from typing import List

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import and_, func, or_
from sqlalchemy.orm import Session

from app.config import settings
from app import models
from app.database import get_db
from app.deps import get_current_user
from app.routers.partner import _member_ids, get_active_link
from app.routers.profile import (
    _XP_PER_FRIEND_INVITED,
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
)

router = APIRouter(prefix="/friends", tags=["friends"])

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


def _friend_out(db: Session, r: models.FriendRequest, other: models.User) -> FriendOut:
    recent = _recent_visible_event(db, other)
    return FriendOut(
        user_id=other.id,
        username=other.username,
        level=compute_level_for_user(db, other.id).level,
        friends_since=r.responded_at or r.created_at,
        display_name=other.display_name,
        avatar_preset=other.avatar_preset,
        avatar_url=other.avatar_url,
        status_text=other.status_text,
        recent_activity=item_from_event(recent, other.display_name or other.username) if recent else None,
    )


@router.get("", response_model=FriendsOut)
def list_friends(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Everything the friends screen (and the profile's own friends block)
    needs in one call: the accepted list (with each friend's live level —
    see profile.py::compute_level_for_user), who's waiting on *you* to
    answer, and who *you're* still waiting on.
    """
    rows = (
        db.query(models.FriendRequest)
        .filter(
            or_(
                models.FriendRequest.from_user_id == current_user.id,
                models.FriendRequest.to_user_id == current_user.id,
            ),
            models.FriendRequest.status != models.FriendRequestStatus.declined,
        )
        .order_by(models.FriendRequest.created_at.desc())
        .all()
    )

    friends: List[FriendOut] = []
    incoming: List[FriendRequestOut] = []
    outgoing: List[FriendRequestOut] = []

    for r in rows:
        other = r.to_user if r.from_user_id == current_user.id else r.from_user
        if other is None:
            continue
        if r.status == models.FriendRequestStatus.accepted:
            friends.append(_friend_out(db, r, other))
        elif r.from_user_id == current_user.id:
            outgoing.append(FriendRequestOut(
                id=r.id, user_id=other.id, username=other.username, created_at=r.created_at,
                display_name=other.display_name, avatar_preset=other.avatar_preset, avatar_url=other.avatar_url,
            ))
        else:
            incoming.append(FriendRequestOut(
                id=r.id, user_id=other.id, username=other.username, created_at=r.created_at,
                display_name=other.display_name, avatar_preset=other.avatar_preset, avatar_url=other.avatar_url,
            ))

    return FriendsOut(friends=friends, incoming_requests=incoming, outgoing_requests=outgoing)


@router.get("/search", response_model=List[FriendSearchResultOut])
def search_users(
    q: str = Query(..., min_length=1),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Username search to start a friend request — a relevance-free
    "starts with, then contains" shape, good enough for a username
    lookup where the list is short.
    """
    needle = q.strip().casefold()
    if not needle:
        return []

    matches = (
        db.query(models.User)
        .filter(
            models.User.id != current_user.id,
            func.lower(models.User.username).like(f"%{needle}%"),
        )
        .order_by(models.User.username)
        .limit(20)
        .all()
    )

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
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    target = (
        db.query(models.User)
        .filter(func.lower(models.User.username) == payload.username.strip().casefold())
        .first()
    )
    if not target:
        raise HTTPException(status_code=404, detail="No one on teamira has that username")
    if target.id == current_user.id:
        raise HTTPException(status_code=400, detail="That's your own username")

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
    request.responded_at = datetime.utcnow()
    db.commit()
    other = request.from_user
    return _friend_out(db, request, other)


@router.post("/requests/{request_id}/decline", status_code=204)
def decline_request(
    request_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    request = _own_incoming_request(db, current_user.id, request_id)
    request.status = models.FriendRequestStatus.declined
    request.responded_at = datetime.utcnow()
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

    # Pinned badge showcase — always visible (same treatment as the
    # current-level bunny already shown here), not gated by any of the
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
    """"People you may know" for the bottom of the friends screen —
    anyone on teamira who isn't already a friend and has no pending
    request either way with this account. Each row carries a small
    preview of that person's most recent *public* activity (privacy
    left at "everyone" — a non-friend never sees a "friends"-only or
    "nobody" shelf, unlike the friends-list preview above), so tapping
    a card can show the same familiar preview before a request is even
    sent. Ordered newest-account-first — there's no mutual-friends graph
    to rank by yet, and "who just joined" is at least a reasonable,
    honest default rather than something dressed up to look smarter
    than it is.
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

    candidates = (
        db.query(models.User)
        .filter(models.User.id.notin_(excluded_ids))
        .order_by(models.User.created_at.desc())
        .limit(limit)
        .all()
    )

    results: List[SuggestedFriendOut] = []
    for u in candidates:
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
        ))
    return results


@router.get("/invite", response_model=InviteOut)
def get_invite(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """This account's own standing invite code — minted once, reused for
    every share. `invited_count`/`xp_bonus` mirror exactly what
    profile.py::compute_level_for_user counts, so the number shown here
    never drifts from what actually lands on the level ring.
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
    if settings.public_web_base_url:
        link = f"{settings.public_web_base_url.rstrip('/')}/i/{current_user.invite_code}"
        share_text = f"join me on teamira — track what you watch, read, and play: {link}"
    else:
        share_text = (
            f"join me on teamira — track what you watch, read, and play: "
            f"code {current_user.invite_code}"
        )

    return InviteOut(
        code=current_user.invite_code,
        share_text=share_text,
        invited_count=invited_count,
        xp_bonus=invited_count * _XP_PER_FRIEND_INVITED,
        xp_per_friend=_XP_PER_FRIEND_INVITED,
    )


@router.post("/invite/claim", status_code=204)
def claim_invite(
    payload: InviteClaimRequest,
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
