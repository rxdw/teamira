import random
from datetime import datetime
from typing import List as TypingList

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from app import models
from app.database import get_db
from app.deps import get_current_user
from app.routers.diary import log_watched
from app.routers.feed import add_watchlist_status
from app.schemas import (
    CoViewEntryOut,
    CoViewOut,
    CoViewBulkAddRequest,
    ExternalIds,
    LocalizedText,
    MediaItem,
    PartnerInviteOut,
    PartnerInvitesOut,
    PartnerJoinRequest,
    PartnerMemberOut,
    PartnerOut,
    PlanCoViewingRequest,
    SendPartnerInviteRequest,
    SuggestionOut,
    SuggestRequest,
)

router = APIRouter(prefix="/partner", tags=["partner"])

# Same alphabet as Watch Together's session codes — no 0/O/1/I, easy to
# read aloud or type on a cramped keyboard.
_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


def _gen_code(db: Session) -> str:
    while True:
        code = "".join(random.choices(_CODE_ALPHABET, k=6))
        if not db.query(models.PartnerLink).filter_by(code=code).first():
            return code


def _active_link(db: Session, user_id: str) -> models.PartnerLink | None:
    member_link_ids = [
        m.link_id for m in db.query(models.PartnerLinkMember).filter_by(user_id=user_id).all()
    ]
    return (
        db.query(models.PartnerLink)
        .filter(
            models.PartnerLink.status == models.PartnerLinkStatus.active,
            or_(
                models.PartnerLink.owner_id == user_id,
                models.PartnerLink.partner_id == user_id,
                models.PartnerLink.id.in_(member_link_ids) if member_link_ids else False,
            ),
        )
        .first()
    )


def get_active_link(db: Session, user_id: str) -> models.PartnerLink | None:
    """Public wrapper around [_active_link] for other routers (e.g.
    co_view_vote.py) that need "the standing link this account is part
    of" without reaching into a private helper."""
    return _active_link(db, user_id)


def _member_ids(link: models.PartnerLink) -> TypingList[str]:
    """Every seat currently filled on this circle, owner first — a plain
    couple is always exactly two ids straight off the link's own
    columns; a company adds one more id per [PartnerLinkMember] row.
    Used everywhere something needs to treat "who's in this" as a list
    rather than a fixed pair (co-view voting, watchlist sync, mark-
    watched fan-out) so those call sites don't need their own
    couple-vs-company branch."""
    ids = [link.owner_id]
    if link.partner_id:
        ids.append(link.partner_id)
    ids.extend(m.user_id for m in link.extra_members)
    return ids


def _is_company(link: models.PartnerLink) -> bool:
    return len(link.extra_members) > 0


def _partner_username(link: models.PartnerLink, user_id: str) -> str | None:
    """The first *other* member's username — exact and only name for a
    couple, and a reasonable single name to keep populating on
    [PartnerOut.partner_username] for a company too (see that field's
    own docstring) so UI that hasn't been updated for companies yet
    still shows someone's name instead of nothing."""
    others = _other_members(link, user_id)
    return others[0].username if others else None


def _other_members(link: models.PartnerLink, user_id: str) -> TypingList[models.User]:
    """Every member's User row except `user_id`'s own — the company-
    aware sibling of [_partner_username], for anywhere the client wants
    the whole "everyone but me" list rather than just one name."""
    people = [link.owner, link.partner] + [m.user for m in link.extra_members]
    return [p for p in people if p is not None and p.id != user_id]


def find_link_between(db: Session, user_a: str, user_b: str) -> models.PartnerLink | None:
    """Used by Watch Together (network mode) — a match there is between
    whichever two accounts joined that session's code, which may or may
    not be this pair's standing partner link. Only mirror the match into
    co-viewing when they *are* linked (and, for a company, when both
    happen to be members of the same one)."""
    link = _active_link(db, user_a)
    if link is None:
        return None
    return link if user_b in _member_ids(link) else None


def add_coview_entries(
    db: Session,
    link: models.PartnerLink,
    items: TypingList[MediaItem],
    added_by_id: str | None = None,
    sync_own_watchlist: bool = True,
) -> None:
    """Idempotently drops titles onto a linked circle's shared co-viewing
    list as "planned" — the one place the suggest heart, network Watch
    Together matches, and local pass-the-phone matches all feed into.
    Works the same for a couple or a company; everything below reads
    the circle's membership through [_member_ids] rather than assuming
    exactly two seats.

    `sync_own_watchlist` (default True, i.e. today's behavior for a
    suggestion someone explicitly accepted — a deliberate personal
    "yes") additionally drops each item onto *every* member's own
    personal "plan to watch" shelf. Watch Together callers (network
    swipe and local pass-the-phone sync) pass False here: whether a
    swipe match also lands on someone's own shelf is governed entirely
    by that account's own "add matches to my own list too" toggle, not
    by this shared-list write — and this function has no way to know
    every other side's toggle value (a bulk sync request only carries
    the caller's own account, never anyone else's preference), so it
    must not silently write to a personal shelf on a toggle it can't
    see. Callers that need it apply it themselves, already gated by the
    right toggle (see TogetherScreen._decide and
    together.py::_add_match_to_both_lists). Doesn't commit; callers
    batch this with their own write.
    """
    for item in items:
        existing = (
            db.query(models.CoViewEntry)
            .filter_by(link_id=link.id, source=item.source, media_id=item.id)
            .first()
        )
        if existing is None:
            db.add(models.CoViewEntry(
                link_id=link.id,
                media_id=item.id,
                media_type=item.media_type,
                source=item.source,
                title_ru=item.title.ru,
                title_en=item.title.en,
                poster_url=item.poster_url,
                year=item.year,
                genres=item.genres,
                rating=item.rating,
                added_by_id=added_by_id,
            ))
        if sync_own_watchlist:
            for uid in _member_ids(link):
                add_watchlist_status(
                    db, uid, item, models.WatchStatus.watch_later, "added to watch later",
                )


def _coview_item(entry: models.CoViewEntry) -> MediaItem:
    """Rebuilds the MediaItem shape `log_watched` needs from a stored
    snapshot — same reasoning as every other snapshot table in this app."""
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


def _coview_out(entry: models.CoViewEntry) -> CoViewEntryOut:
    return CoViewEntryOut(
        id=entry.id,
        media_id=entry.media_id,
        media_type=entry.media_type.value,
        source=entry.source,
        title_ru=entry.title_ru,
        title_en=entry.title_en,
        poster_url=entry.poster_url,
        year=entry.year,
        status=entry.status.value,
        added_by_username=entry.added_by.username if entry.added_by else None,
        watched_at=entry.watched_at,
        created_at=entry.created_at,
        scheduled_date=entry.scheduled_date,
        scheduled_hour=entry.scheduled_hour,
        scheduled_minute=entry.scheduled_minute,
    )


def _member_out_list(link: models.PartnerLink, current_user_id: str) -> TypingList[PartnerMemberOut]:
    people = [link.owner, link.partner] + [m.user for m in link.extra_members]
    return [
        PartnerMemberOut(
            user_id=p.id,
            username=p.username,
            display_name=p.display_name,
            avatar_preset=p.avatar_preset,
            avatar_url=p.avatar_url,
            is_you=p.id == current_user_id,
        )
        for p in people
        if p is not None
    ]


@router.get("", response_model=PartnerOut)
def get_status(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The co-viewing card's whole state in one call: already linked (as
    a couple or, once a third person's joined, a company), a code you
    generated that's still waiting to be used, or neither."""
    active = _active_link(db, current_user.id)
    if active is not None:
        return PartnerOut(
            linked=True,
            partner_username=_partner_username(active, current_user.id),
            members=_member_out_list(active, current_user.id),
            is_company=_is_company(active),
        )

    pending = (
        db.query(models.PartnerLink)
        .filter_by(owner_id=current_user.id, status=models.PartnerLinkStatus.pending)
        .order_by(models.PartnerLink.created_at.desc())
        .first()
    )
    return PartnerOut(linked=False, pending_code=pending.code if pending else None)


@router.post("/pair", response_model=PartnerOut, status_code=201)
def create_pairing_code(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Issues a code to send to a partner — starts a brand new circle
    from scratch. Reuses one already waiting to be joined rather than
    piling up unused codes every time the card is opened. Only for
    going from "linked to no one" to "linked" — growing an existing
    couple into a company happens through a direct invite instead (see
    send_invite below), since a fresh code always starts an unrelated
    new link rather than adding a seat to this one."""
    if _active_link(db, current_user.id) is not None:
        raise HTTPException(status_code=409, detail="You already have a partner linked")

    existing = (
        db.query(models.PartnerLink)
        .filter_by(owner_id=current_user.id, status=models.PartnerLinkStatus.pending)
        .order_by(models.PartnerLink.created_at.desc())
        .first()
    )
    if existing is not None:
        return PartnerOut(linked=False, pending_code=existing.code)

    row = models.PartnerLink(code=_gen_code(db), owner_id=current_user.id)
    db.add(row)
    db.commit()
    return PartnerOut(linked=False, pending_code=row.code)


@router.post("/join", response_model=PartnerOut)
def join_pairing(
    payload: PartnerJoinRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if _active_link(db, current_user.id) is not None:
        raise HTTPException(status_code=409, detail="You already have a partner linked")

    code = payload.code.strip().upper()
    row = db.query(models.PartnerLink).filter_by(code=code).first()
    if row is None:
        raise HTTPException(status_code=404, detail="That code doesn't match anything")
    if row.owner_id == current_user.id:
        raise HTTPException(status_code=400, detail="That's your own code — send it to them instead")
    if row.status == models.PartnerLinkStatus.active:
        raise HTTPException(status_code=409, detail="That code has already been used")

    row.partner_id = current_user.id
    row.status = models.PartnerLinkStatus.active
    db.commit()
    return PartnerOut(linked=True, partner_username=row.owner.username)


@router.delete("", status_code=204)
def unlink_partner(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Leaves the current circle. For a plain couple this is the same as
    always — the whole link goes away for both sides, since "unlinking"
    from one other person and "ending the circle" are the same thing.
    For a company (3+), leaving only removes this account's own seat;
    everyone else keeps the circle exactly as it was, same as leaving
    any other group chat. If the person leaving happened to be the
    owner (whose id can't just go blank — see PartnerLink.owner_id),
    the next-longest-standing member is promoted into that seat first;
    nothing about their membership changes from their own point of
    view, it's purely bookkeeping for who the link's single required
    owner_id points at.
    """
    active = _active_link(db, current_user.id)
    if active is not None:
        extra = active.extra_members
        if not extra:
            # A plain couple (or a solo owner with nobody joined yet) —
            # unchanged from before: the whole link is done.
            db.delete(active)
        elif active.owner_id == current_user.id:
            # Promote the longest-standing extra member into the now-
            # vacant owner seat, then drop their now-redundant member row.
            promoted = extra[0]
            active.owner_id = promoted.user_id
            db.delete(promoted)
        elif active.partner_id == current_user.id:
            # Same idea for the second seat — free it up by promoting an
            # extra member into it, rather than leaving it null (which
            # would misrepresent a company as "waiting for a partner").
            promoted = extra[0]
            active.partner_id = promoted.user_id
            db.delete(promoted)
        else:
            member_row = next((m for m in extra if m.user_id == current_user.id), None)
            if member_row is not None:
                db.delete(member_row)
    pending = (
        db.query(models.PartnerLink)
        .filter_by(owner_id=current_user.id, status=models.PartnerLinkStatus.pending)
        .all()
    )
    for row in pending:
        db.delete(row)
    # Any invites this account sent or received, for the circle it's
    # now leaving, no longer mean anything — an invite dangling after
    # the inviter (or the circle itself) is gone would otherwise sit
    # forever as a stale "pending" on the other person's screen.
    if active is not None:
        db.query(models.PartnerLinkInvite).filter_by(link_id=active.id).delete()
    db.commit()


@router.post("/invite", response_model=PartnerInviteOut, status_code=201)
def send_invite(
    payload: SendPartnerInviteRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Invites one specific person straight into this account's
    co-viewing circle — no code to share. The one way to grow a couple
    into a company (a fresh /pair code always starts a brand new,
    unrelated link — see create_pairing_code above), and generally the
    friendlier path for a first pairing too, from a friend's own
    profile screen instead of a code changing hands.

    Starts a brand new circle on the spot if this account isn't linked
    to anyone yet, same one-person-then-invite shape a company reaches
    naturally after its second invite goes out.
    """
    target = db.query(models.User).filter_by(id=payload.user_id).first()
    if target is None:
        raise HTTPException(status_code=404, detail="No such account")
    if target.id == current_user.id:
        raise HTTPException(status_code=400, detail="That's you")

    link = _active_link(db, current_user.id)
    target_link = _active_link(db, target.id)
    if target_link is not None and (link is None or target_link.id != link.id):
        raise HTTPException(status_code=409, detail=f"{target.username} is already in a co-viewing circle")
    if link is not None and target.id in _member_ids(link):
        raise HTTPException(status_code=409, detail=f"{target.username} is already in your circle")
    if link is None:
        link = models.PartnerLink(code=_gen_code(db), owner_id=current_user.id, status=models.PartnerLinkStatus.active)
        db.add(link)
        db.flush()

    existing_invite = (
        db.query(models.PartnerLinkInvite)
        .filter_by(link_id=link.id, to_user_id=target.id, status=models.PartnerLinkInviteStatus.pending)
        .first()
    )
    if existing_invite is not None:
        return PartnerInviteOut(
            id=existing_invite.id, user_id=target.id, username=target.username,
            display_name=target.display_name, avatar_preset=target.avatar_preset,
            avatar_url=target.avatar_url, status=existing_invite.status.value,
            created_at=existing_invite.created_at,
        )

    row = models.PartnerLinkInvite(link_id=link.id, from_user_id=current_user.id, to_user_id=target.id)
    db.add(row)
    db.commit()
    db.refresh(row)
    return PartnerInviteOut(
        id=row.id, user_id=target.id, username=target.username,
        display_name=target.display_name, avatar_preset=target.avatar_preset,
        avatar_url=target.avatar_url, status=row.status.value, created_at=row.created_at,
    )


@router.get("/invites", response_model=PartnerInvitesOut)
def list_invites(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    rows = (
        db.query(models.PartnerLinkInvite)
        .filter(
            models.PartnerLinkInvite.status == models.PartnerLinkInviteStatus.pending,
            or_(
                models.PartnerLinkInvite.from_user_id == current_user.id,
                models.PartnerLinkInvite.to_user_id == current_user.id,
            ),
        )
        .order_by(models.PartnerLinkInvite.created_at.desc())
        .all()
    )
    incoming, outgoing = [], []
    for r in rows:
        if r.to_user_id == current_user.id:
            other = r.from_user
            bucket = incoming
        else:
            other = r.to_user
            bucket = outgoing
        bucket.append(PartnerInviteOut(
            id=r.id, user_id=other.id, username=other.username,
            display_name=other.display_name, avatar_preset=other.avatar_preset,
            avatar_url=other.avatar_url, status=r.status.value, created_at=r.created_at,
        ))
    return PartnerInvitesOut(incoming=incoming, outgoing=outgoing)


@router.post("/invites/{invite_id}/accept", response_model=PartnerOut)
def accept_invite(
    invite_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    row = db.query(models.PartnerLinkInvite).filter_by(id=invite_id).first()
    if row is None or row.to_user_id != current_user.id:
        raise HTTPException(status_code=404, detail="No such invite")
    if row.status != models.PartnerLinkInviteStatus.pending:
        raise HTTPException(status_code=409, detail="That invite isn't pending anymore")
    if _active_link(db, current_user.id) is not None:
        raise HTTPException(status_code=409, detail="Leave your current circle first")

    link = row.link
    if link.partner_id is None and link.owner_id != current_user.id:
        link.partner_id = current_user.id
    else:
        db.add(models.PartnerLinkMember(link_id=link.id, user_id=current_user.id))
    row.status = models.PartnerLinkInviteStatus.accepted
    row.responded_at = datetime.utcnow()
    db.commit()
    db.refresh(link)
    return PartnerOut(
        linked=True,
        partner_username=_partner_username(link, current_user.id),
        members=_member_out_list(link, current_user.id),
        is_company=_is_company(link),
    )


@router.post("/invites/{invite_id}/decline", status_code=204)
def decline_invite(
    invite_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Also how the *sender* cancels their own still-pending invite —
    same "make this invite stop existing" action either way, so the
    button on both ends of the profile screen can call the same
    endpoint."""
    row = db.query(models.PartnerLinkInvite).filter_by(id=invite_id).first()
    if row is None or current_user.id not in (row.to_user_id, row.from_user_id):
        raise HTTPException(status_code=404, detail="No such invite")
    if row.status != models.PartnerLinkInviteStatus.pending:
        return
    row.status = models.PartnerLinkInviteStatus.declined
    row.responded_at = datetime.utcnow()
    db.commit()


@router.post("/suggest", response_model=SuggestionOut, status_code=201)
def suggest(
    payload: SuggestRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The one-tap "I'm suggesting this for tonight" from a title screen —
    drops a snapshot of the title in the rest of the circle's suggestion
    feed, picked up next time their Home polls it. For a company this
    fans out to everyone else in it, not just one person. Deliberately
    does NOT touch the shared co-viewing list yet — it only becomes
    "planned together" once someone taps to agree, via
    `accept_suggestion` below."""
    link = _active_link(db, current_user.id)
    if link is None:
        raise HTTPException(status_code=409, detail="Link with a partner first")
    receiver_ids = [uid for uid in _member_ids(link) if uid != current_user.id]
    if not receiver_ids:
        raise HTTPException(status_code=409, detail="Link with a partner first")

    item = payload.item
    rows = []
    for receiver_id in receiver_ids:
        row = models.Suggestion(
            sender_id=current_user.id,
            receiver_id=receiver_id,
            media_id=item.id,
            media_type=item.media_type,
            source=item.source,
            title_ru=item.title.ru,
            title_en=item.title.en,
            poster_url=item.poster_url,
            year=item.year,
        )
        db.add(row)
        rows.append(row)
    db.commit()
    for row in rows:
        db.refresh(row)
    first = rows[0]
    return SuggestionOut(
        id=first.id,
        media_id=first.media_id,
        media_type=first.media_type.value,
        source=first.source,
        title_ru=first.title_ru,
        title_en=first.title_en,
        poster_url=first.poster_url,
        year=first.year,
        sender_username=current_user.username,
        created_at=first.created_at,
    )


@router.get("/suggestions", response_model=TypingList[SuggestionOut])
def list_suggestions(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Polled from Home — every suggestion sent to this account that hasn't
    been dismissed yet, newest first."""
    rows = (
        db.query(models.Suggestion)
        .filter_by(receiver_id=current_user.id, seen=0)
        .order_by(models.Suggestion.created_at.desc())
        .all()
    )
    return [
        SuggestionOut(
            id=r.id,
            media_id=r.media_id,
            media_type=r.media_type.value,
            source=r.source,
            title_ru=r.title_ru,
            title_en=r.title_en,
            poster_url=r.poster_url,
            year=r.year,
            sender_username=r.sender.username,
            created_at=r.created_at,
        )
        for r in rows
    ]


@router.post("/suggestions/{suggestion_id}/accept", response_model=CoViewEntryOut, status_code=201)
def accept_suggestion(
    suggestion_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The receiver agreeing to watch it — this, not the original suggest
    tap, is what actually drops the title onto the shared "planned
    together" list (and out of the Home inbox). added_by is recorded as
    whoever originally suggested it, so the co-viewing row still reads
    "added by <sender>" the same way a Watch Together match would."""
    link = _active_link(db, current_user.id)
    if link is None:
        raise HTTPException(status_code=409, detail="Link with a partner first")
    row = (
        db.query(models.Suggestion)
        .filter_by(id=suggestion_id, receiver_id=current_user.id)
        .first()
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Suggestion not found")

    item = MediaItem(
        id=row.media_id,
        media_type=row.media_type.value,
        external_ids=ExternalIds(),
        title=LocalizedText(ru=row.title_ru, en=row.title_en),
        description=LocalizedText(),
        poster_url=row.poster_url,
        year=row.year,
        source=row.source,
    )
    add_coview_entries(db, link, [item], added_by_id=row.sender_id)
    row.seen = 1
    db.commit()

    entry = (
        db.query(models.CoViewEntry)
        .filter_by(link_id=link.id, source=row.source, media_id=row.media_id)
        .first()
    )
    return _coview_out(entry)


@router.delete("/suggestions/{suggestion_id}", status_code=204)
def dismiss_suggestion(
    suggestion_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Declining a suggestion — since `suggest` no longer touches the
    co-viewing list, this simply makes it stop showing up in the Home
    inbox; nothing ever lands on the shared "planned" list."""
    row = (
        db.query(models.Suggestion)
        .filter_by(id=suggestion_id, receiver_id=current_user.id)
        .first()
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Suggestion not found")
    row.seen = 1
    db.commit()


# ---------------------------------------------------------------------------
# Co-viewing — the shared "planned together" / "watched together" screen.
# Fed from three places: the suggest heart above, a network Watch Together
# match (backend/app/routers/together.py), and a local pass-the-phone Watch
# Together match (synced via the bulk endpoint below).
# ---------------------------------------------------------------------------

@router.get("/co-viewing", response_model=CoViewOut)
def get_co_viewing(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    link = _active_link(db, current_user.id)
    if link is None:
        raise HTTPException(status_code=409, detail="Link with a partner first")

    rows = db.query(models.CoViewEntry).filter_by(link_id=link.id).all()
    # A scheduled evening (from "plan an evening"'s co-viewing toggle)
    # sorts by how soon it is, ahead of everything else; unscheduled
    # entries (suggest heart, Watch Together matches) keep the old
    # newest-first order behind them.
    planned = sorted(
        (r for r in rows if r.status == models.CoViewStatus.planned),
        key=lambda r: (0, r.scheduled_date) if r.scheduled_date else (1, -r.created_at.timestamp()),
    )
    watched = sorted(
        (r for r in rows if r.status == models.CoViewStatus.watched),
        key=lambda r: r.watched_at or r.created_at, reverse=True,
    )
    return CoViewOut(
        my_username=current_user.username,
        partner_username=_partner_username(link, current_user.id),
        other_usernames=[p.username for p in _other_members(link, current_user.id)],
        planned=[_coview_out(r) for r in planned],
        watched=[_coview_out(r) for r in watched],
    )


@router.post("/co-viewing/plan", response_model=CoViewEntryOut, status_code=201)
def plan_co_viewing(
    payload: PlanCoViewingRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """"Plan an evening", scheduled with the co-viewing toggle on — puts
    (or updates) this title on the shared co-viewing list with a
    schedule attached, so the partner sees the same evening on their own
    side too, not just as a device-local ticket (see PlannedEvening on
    the client). Unlike [add_coview_entries] this never touches either
    side's personal "plan to watch" shelf — a co-viewing evening isn't
    automatically a personal one."""
    link = _active_link(db, current_user.id)
    if link is None:
        raise HTTPException(status_code=409, detail="Link with a partner first")

    item = payload.item
    existing = (
        db.query(models.CoViewEntry)
        .filter_by(link_id=link.id, source=item.source, media_id=item.id)
        .first()
    )
    if existing is None:
        entry = models.CoViewEntry(
            link_id=link.id,
            media_id=item.id,
            media_type=item.media_type,
            source=item.source,
            title_ru=item.title.ru,
            title_en=item.title.en,
            poster_url=item.poster_url,
            year=item.year,
            genres=item.genres,
            rating=item.rating,
            added_by_id=current_user.id,
            scheduled_date=payload.scheduled_date,
            scheduled_hour=payload.scheduled_hour,
            scheduled_minute=payload.scheduled_minute,
        )
        db.add(entry)
    else:
        # Planning the same title again (a new date, a changed time)
        # updates the one shared row rather than duplicating it — same
        # idempotent-by-(link, source, media_id) rule [add_coview_entries]
        # already follows.
        entry = existing
        entry.scheduled_date = payload.scheduled_date
        entry.scheduled_hour = payload.scheduled_hour
        entry.scheduled_minute = payload.scheduled_minute
        if entry.status == models.CoViewStatus.watched:
            # Re-planning something already marked watched puts it back
            # on the "planned" list — that's the whole point of doing it
            # again.
            entry.status = models.CoViewStatus.planned
            entry.watched_at = None

    db.commit()
    db.refresh(entry)
    return _coview_out(entry)


@router.post("/co-viewing/bulk", status_code=201)
def add_co_viewing_bulk(
    payload: CoViewBulkAddRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Best-effort sync for the local pass-the-phone Watch Together mode,
    called once a swipe round ends: if this account has a linked partner,
    the matches from that round are mirrored onto the shared co-viewing
    list too. Silently does nothing (no error) when there's no partner
    linked — swiping solo shouldn't fail."""
    link = _active_link(db, current_user.id)
    if link is not None and payload.items:
        add_coview_entries(db, link, payload.items, added_by_id=current_user.id, sync_own_watchlist=False)
        db.commit()
    return {"added": link is not None}


@router.post("/co-viewing/{entry_id}/watched", response_model=CoViewEntryOut)
def mark_co_viewing_watched(
    entry_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Logs the same evening into every member's personal diary (and
    their own watched shelf) — the point of doing this from the
    co-viewing screen instead of each person separately marking it in
    their own diary."""
    link = _active_link(db, current_user.id)
    if link is None:
        raise HTTPException(status_code=409, detail="Link with a partner first")
    entry = db.query(models.CoViewEntry).filter_by(id=entry_id, link_id=link.id).first()
    if entry is None:
        raise HTTPException(status_code=404, detail="Not found")

    if entry.status != models.CoViewStatus.watched:
        entry.watched_at = datetime.utcnow()
        entry.status = models.CoViewStatus.watched
        item = _coview_item(entry)
        # Each member's diary entry is tagged with everyone *else* in the
        # circle's username(s) — logged from the co-viewing screen always
        # means it was watched together, so this doesn't need its own
        # toggle the way the manual log form does. A couple gets the
        # single familiar "watched with X"; a company joins names with a
        # comma so nobody's left out of the credit.
        for uid in _member_ids(link):
            others = ", ".join(p.username for p in _other_members(link, uid))
            log_watched(db, uid, item, watched_at=entry.watched_at,
                        watched_with_username=others or None)
        db.commit()
        db.refresh(entry)
    return _coview_out(entry)


@router.delete("/co-viewing/{entry_id}", status_code=204)
def remove_co_viewing_entry(
    entry_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    link = _active_link(db, current_user.id)
    if link is None:
        raise HTTPException(status_code=409, detail="Link with a partner first")
    entry = db.query(models.CoViewEntry).filter_by(id=entry_id, link_id=link.id).first()
    if entry is None:
        raise HTTPException(status_code=404, detail="Not found")
    db.delete(entry)
    db.commit()
