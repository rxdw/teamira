"""Co-view rooms ("Гостиная") — watching together inside the app.

The rules and the reasoning are in app/co_view_room.py; this file is the
HTTP shape of them. A room belongs to a linked circle (a couple or a
company of up to four), every member can enter it, and almost nothing here
needs premium: rooms, chat, voice, reactions and every player kind are free.
The one exception is Zen mode's emotion taps (see `post_event`): a circle where
nobody has a subscription gets a 402 and the client shows the upsell.

Guests. Anyone in the circle can invite up to three friends into one room
(`POST /{id}/guests`). A guest isn't in the circle: they reach exactly this
room — watching, chat, reactions, signals, voice — and nothing else of the
circle's. They can't move the playback, flip the save switch, finish or close
the room or invite others, and they don't get a say in the joint review. When
the evening is saved they do get it in their own diary, like everyone who was
there. Free for everyone, guests and hosts alike: a bigger room is the point.

State travels the way the other sessions' does (see app/realtime.py): every
mutation publishes a NOTIFY in its own transaction, and the room socket
answers each wake-up by re-reading the whole room — state, participants and
the recent event tail — so a client never has to merge diffs.

Reading. The same room can be about a book or a manga instead of a film
(`activity == "read"`, rules in app/co_reading.py). Nothing of the text ever
passes through here: everyone opens their own copy and the room keeps only
where people are — `POST /{id}/locator` says "I'm here", and in "together"
mode `POST /{id}/lead` turns the page for everyone — or, in "aloud" mode,
moves the line being read (only the reader may). Margin notes, highlights,
reactions and zen feelings are pinned to a place; `marks` in the room's state
is what is written on the pages right now (rebuilt from the whole ledger, since
the event tail is short). `POST /{id}/album-quote` sets a paragraph aside in
the person's sealed pair-album note, which opens for both when the evening is
marked watched. Chat, voice, guests, saving and the joint review work exactly
as they do for a film.

Playing. The third kind of room (`activity == "play"`, rules in
app/co_play.py) is the evening around a real game each person runs on their
own machine: the room's clock is the session timer (play / pause / "перерыв"),
`POST /{id}/ready` is the ready check, signals are a game's ("готов", "gg"…),
and `round` events (win / loss / draw / checkpoint) are the session's tally.
Nothing of the game itself passes through here.

Saving. Whatever the room's `save_to_shared` switch says at the moment
someone finishes it decides what is written. On: the title lands on the
circle's shared list as watched, and every person who was there gets an
unrated entry on their own diary tagged "watched together" (they rate it
right after, through the ordinary diary edit). Off: nothing is written
here at all; the client offers each person the normal personal log.
"""

from __future__ import annotations

import logging
import time
from datetime import datetime, timezone
from typing import Dict, List as TypingList, Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Response
from jose import jwt
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from starlette.websockets import WebSocket

from app import co_play as play
from app import co_reading as reading
from app import co_view_room as rules
from app import blocking, content_filter, models, pair_album, push, realtime
from app.routers import pair_album as album_router
from app.config import settings
from app.database import SessionLocal, get_db
from app.deps import get_current_user, get_ws_user
from app.routers.diary import log_watched
from app.routers.partner import _circle_has_premium, _coview_item, _member_ids, get_active_link
from app.schemas import ImageFieldsModel

logger = logging.getLogger("teamira.routers.co_view_room")

router = APIRouter(prefix="/partner/rooms", tags=["co-view-rooms"])


# --- shapes -------------------------------------------------------------------

class RoomCreate(BaseModel):
    media_id: str = Field(min_length=1, max_length=200)
    media_type: str
    source: str = Field(min_length=1, max_length=40)
    title_ru: Optional[str] = Field(default=None, max_length=300)
    title_en: Optional[str] = Field(default=None, max_length=300)
    poster_url: Optional[str] = Field(default=None, max_length=600)
    year: Optional[int] = None
    player_kind: str = "parallel"
    player_ref: Optional[str] = None
    duration_ms: Optional[int] = Field(default=None, ge=0, le=rules.MAX_POSITION_MS)
    entry_id: Optional[str] = None
    save_to_shared: bool = True
    # Reading together (see app/co_reading.py). `activity` "read" makes this a
    # room about a book or manga: `read_kind` is how the text reaches people
    # (epub | cbz | parallel), `content_hash` the SHA-256 of the file the host
    # opened (not for parallel), `read_units` its length in chapters/pages.
    activity: str = "watch"
    read_kind: Optional[str] = None
    content_hash: Optional[str] = Field(default=None, max_length=80)
    read_units: Optional[int] = Field(default=None, ge=1, le=reading.MAX_UNITS)
    read_mode: str = "own"
    # Playing together (see app/co_play.py): `activity` "play" is a real game
    # each person runs on their own machine; `platform` is where this room
    # plays it (pc | ps | xbox | switch | mobile | other), kept in `player_ref`.
    platform: Optional[str] = Field(default=None, max_length=20)


class ControlIn(BaseModel):
    action: str
    position_ms: Optional[int] = Field(default=None, ge=0)


class EventIn(BaseModel):
    kind: str
    body: Optional[str] = None
    key: Optional[str] = None  # the emoji / signal / emotion key
    position_ms: Optional[int] = Field(default=None, ge=0)
    # Reading rooms: where a reaction or margin note is pinned (a locator), the
    # short passage it refers to, and how far through the book that is.
    locator: Optional[str] = Field(default=None, max_length=40)
    quote: Optional[str] = Field(default=None, max_length=600)
    progress: Optional[int] = Field(default=None, ge=0, le=reading.PROGRESS_MAX)


class RoomPatch(BaseModel):
    save_to_shared: Optional[bool] = None
    duration_ms: Optional[int] = Field(default=None, ge=0, le=rules.MAX_POSITION_MS)
    # Reading rooms: "own" | "together" (circle only), the place to start
    # following from when switching to "together", and the length once known.
    read_mode: Optional[str] = None
    locator: Optional[str] = Field(default=None, max_length=40)
    progress: Optional[int] = Field(default=None, ge=0, le=reading.PROGRESS_MAX)
    read_units: Optional[int] = Field(default=None, ge=1, le=reading.MAX_UNITS)


class LocatorIn(BaseModel):
    """"I'm here": my place in a reading room, how far through that is (a
    permille), and the fingerprint of the file I opened."""
    locator: str = Field(max_length=40)
    progress: int = Field(ge=0, le=reading.PROGRESS_MAX)
    content_hash: Optional[str] = Field(default=None, max_length=80)


class AlbumQuoteIn(BaseModel):
    """A paragraph to set aside for the pair album."""
    quote: str = Field(max_length=4000)


class AlbumQuoteOut(BaseModel):
    created: bool      # the person's sealed note for this title was just started
    added: bool        # False when this very quote was already in it
    chars_left: int    # room left in the note for more quotes


class ReadyIn(BaseModel):
    ready: bool


class LeadIn(BaseModel):
    """Turning the page for everyone ("together"), or moving the line being
    read aloud ("aloud")."""
    locator: str = Field(max_length=40)
    progress: int = Field(ge=0, le=reading.PROGRESS_MAX)


class FinishIn(BaseModel):
    position_ms: Optional[int] = Field(default=None, ge=0)


class GuestIn(BaseModel):
    user_id: str


class GuestInviteOut(BaseModel):
    """A room somebody invited me into as a guest."""
    room_id: str
    title: str
    poster_url: Optional[str] = None
    inviter_name: str
    inviter_username: str
    room_status: str
    created_at: datetime
    activity: str = "watch"


class ParticipantOut(BaseModel):
    user_id: str
    username: str
    display_name: Optional[str] = None
    avatar_preset: Optional[str] = None
    avatar_url: Optional[str] = None
    is_you: bool
    is_host: bool
    is_guest: bool = False
    invited_by: Optional[str] = None
    joined: bool        # has ever entered this room
    present: bool       # here right now
    voice_on: bool
    # Reading rooms: where this person is, how far through (permille), and
    # whether the file they opened is the same edition as the room's (None
    # while either side has no fingerprint — always so for "parallel").
    locator: Optional[str] = None
    progress: int = 0
    same_edition: Optional[bool] = None
    # Game rooms: has tapped "готов".
    ready: bool = False


class EventOut(BaseModel):
    seq: int
    kind: str
    user_id: Optional[str] = None
    username: Optional[str] = None
    body: Optional[str] = None
    emoji: Optional[str] = None  # the reaction / signal / emotion key
    position_ms: Optional[int] = None
    locator: Optional[str] = None
    quote: Optional[str] = None
    created_at: datetime


class MarkOut(BaseModel):
    """What is written on the pages right now: a note in the margin or a
    highlight on a paragraph (see co_reading.reduce_marks). The room's event
    tail only carries the last few events, so this is how a client rebuilds
    the margins of a book read over days."""
    seq: int
    user_id: Optional[str] = None
    kind: str  # margin | highlight
    locator: str
    body: Optional[str] = None
    quote: Optional[str] = None
    position_ms: Optional[int] = None  # how far through the book (scaled), for ticks on the bar


class RoomOut(ImageFieldsModel):
    id: str
    status: str
    media_id: str
    media_type: str
    source: str
    title_ru: Optional[str] = None
    title_en: Optional[str] = None
    poster_url: Optional[str] = None
    year: Optional[int] = None
    player_kind: str
    player_ref: Optional[str] = None
    duration_ms: Optional[int] = None
    is_playing: bool
    position_ms: int               # already advanced to `server_now`
    server_now: datetime
    control_seq: int
    save_to_shared: bool
    entry_id: Optional[str] = None
    saved_entry_id: Optional[str] = None
    my_diary_entry_id: Optional[str] = None
    review_id: Optional[str] = None
    host_user_id: Optional[str] = None
    participants: TypingList[ParticipantOut]
    events: TypingList[EventOut]
    last_seq: int
    voice_available: bool
    # Zen mode is open for this circle (any member subscribed). The client
    # gates the switch on this, not on the person's own flag, so one
    # subscription covers everyone it covers.
    zen_available: bool = False
    me_is_guest: bool = False
    guest_slots_left: int = 0
    # Reading together: "watch" (the clock above) or "read" (a place in a
    # book). For a reading room `position_ms` is the shared place's progress in
    # the room's scaled clock units and `duration_ms` is READ_DURATION_MS.
    activity: str = "watch"
    read_kind: Optional[str] = None
    read_units: Optional[int] = None
    read_mode: str = "own"
    lead_locator: Optional[str] = None
    lead_user_id: Optional[str] = None
    content_hash: Optional[str] = None
    marks: TypingList[MarkOut] = []
    # Game rooms: how many rounds of each kind have been played this session
    # (win / loss / draw / checkpoint — always all four keys), and whether
    # everybody who is here has said they're ready.
    rounds: Dict[str, int] = {}
    all_ready: bool = False
    created_at: datetime
    started_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class VoiceTokenOut(BaseModel):
    url: str
    token: str
    room_name: str
    identity: str


# --- helpers ------------------------------------------------------------------

def _now() -> datetime:
    return rules.utcnow()


def _fallback_title(activity: str | None) -> str:
    """What to call a room whose title is missing."""
    return {"read": "книга", "play": "игра"}.get(activity or "", "фильм")


def _name(user: models.User | None) -> str:
    if user is None:
        return "кто-то"
    return (user.display_name or "").strip() or user.username


def _voice_available() -> bool:
    return bool(settings.livekit_url and settings.livekit_api_key and settings.livekit_api_secret)


def _require_link(db: Session, user: models.User) -> models.PartnerLink:
    link = get_active_link(db, user.id)
    if link is None:
        raise HTTPException(status_code=409, detail="Link with a partner first")
    return link


def _close_if_abandoned(db: Session, room: models.CoViewRoom) -> bool:
    if room.status == models.CoViewRoomStatus.ended:
        return False
    if not rules.is_abandoned(room.status.value, room.last_activity_at):
        return False
    room.status = models.CoViewRoomStatus.ended
    room.ended_at = _now()
    room.is_playing = False
    for m in room.members:
        m.left_at = m.left_at or room.ended_at
        m.voice_on = False
    realtime.publish(db, realtime.topic_for("room", room.id))
    db.commit()
    return True


def _circle_ids(link: models.PartnerLink) -> list[str]:
    return _member_ids(link)


def _active_guests(db: Session, room: models.CoViewRoom) -> list[models.CoViewRoomGuest]:
    return (
        db.query(models.CoViewRoomGuest)
        .filter_by(room_id=room.id, status="invited")
        .order_by(models.CoViewRoomGuest.created_at.asc())
        .all()
    )


def _can_reach(db: Session, user_id: str, room: models.CoViewRoom, link: models.PartnerLink) -> bool:
    """In the circle, or invited into this room as a guest."""
    if user_id in _circle_ids(link):
        return True
    guest = db.query(models.CoViewRoomGuest).filter_by(room_id=room.id, user_id=user_id).first()
    return guest is not None and guest.status == "invited"


def _load(db: Session, user: models.User, room_id: str, *, lock: bool = False) -> tuple[models.PartnerLink, models.CoViewRoom]:
    """The room and its circle for someone who may reach it: a circle member
    or an invited guest. Anyone else gets a plain 404 — a room's existence
    isn't something an outsider learns."""
    q = db.query(models.CoViewRoom).filter_by(id=room_id)
    if lock:
        q = q.with_for_update()
    room = q.first()
    link = db.query(models.PartnerLink).filter_by(id=room.link_id).first() if room is not None else None
    if room is None or link is None or not _can_reach(db, user.id, room, link):
        raise HTTPException(status_code=404, detail="Комната не найдена")
    if _close_if_abandoned(db, room):
        # committing released the row lock; take it again for the caller
        if lock:
            room = db.query(models.CoViewRoom).filter_by(id=room_id).with_for_update().first()
    return link, room


def _require_circle(link: models.PartnerLink, user: models.User) -> None:
    """Playback, saving, finishing and inviting belong to the circle."""
    if user.id not in _circle_ids(link):
        raise HTTPException(status_code=403, detail="Это могут только те, кто в круге")


def _open(room: models.CoViewRoom) -> bool:
    return room.status != models.CoViewRoomStatus.ended


def _member_row(room: models.CoViewRoom, user_id: str) -> models.CoViewRoomMember | None:
    return next((m for m in room.members if m.user_id == user_id), None)


def _add_event(
    db: Session, room: models.CoViewRoom, user_id: str | None, kind: str, *,
    body: str | None = None, emoji: str | None = None, position_ms: int | None = None,
    locator: str | None = None, quote: str | None = None,
) -> models.CoViewRoomEvent:
    """Caller holds the room's row lock, which is what keeps `seq` gapless."""
    room.event_seq = (room.event_seq or 0) + 1
    ev = models.CoViewRoomEvent(
        room_id=room.id, seq=room.event_seq, user_id=user_id, kind=kind,
        body=body, emoji=emoji, position_ms=position_ms, locator=locator, quote=quote,
    )
    db.add(ev)
    room.last_activity_at = _now()
    return ev


def _publish(db: Session, room: models.CoViewRoom) -> None:
    realtime.publish(db, realtime.topic_for("room", room.id))


def _my_diary_entry_id(db: Session, room: models.CoViewRoom, user_id: str) -> str | None:
    if not room.saved_entry_id:
        return None
    row = (
        db.query(models.DiaryEntry.id)
        .filter(
            models.DiaryEntry.user_id == user_id,
            models.DiaryEntry.media_id == room.media_id,
            models.DiaryEntry.source == room.source,
        )
        .order_by(models.DiaryEntry.created_at.desc())
        .first()
    )
    return row[0] if row else None


def _review_id_for(db: Session, room: models.CoViewRoom) -> str | None:
    row = db.query(models.CircleReview.id).filter_by(room_id=room.id).first()
    return row[0] if row else None


def _room_out(db: Session, link: models.PartnerLink, room: models.CoViewRoom, me_id: str) -> RoomOut:
    now = _now()
    people = [link.owner, link.partner] + [m.user for m in link.extra_members]
    people = [p for p in people if p is not None]
    circle_ids = {p.id for p in people}
    guest_rows = _active_guests(db, room)
    guest_people = [g.user for g in guest_rows if g.user is not None]
    inviter_name = {
        g.user_id: (_name(g.invited_by) if g.invited_by is not None else None) for g in guest_rows
    }
    everyone = people + guest_people
    by_id = {p.id: p for p in everyone}
    rows = {m.user_id: m for m in room.members}
    participants = []
    for p in everyone:
        m = rows.get(p.id)
        participants.append(ParticipantOut(
            user_id=p.id, username=p.username, display_name=p.display_name,
            avatar_preset=p.avatar_preset, avatar_url=p.avatar_url,
            is_you=p.id == me_id, is_host=p.id == room.host_id,
            is_guest=p.id not in circle_ids, invited_by=inviter_name.get(p.id),
            joined=m is not None,
            present=bool(m and _open(room) and rules.is_present(m.left_at, m.last_seen_at, now)),
            voice_on=bool(m and _open(room) and m.voice_on and m.left_at is None),
            locator=m.locator if (m and reading.is_reading(room.activity)) else None,
            progress=int(m.progress or 0) if (m and reading.is_reading(room.activity)) else 0,
            same_edition=(
                reading.same_edition(room.content_hash, m.content_hash)
                if (m and reading.is_reading(room.activity)) else None
            ),
            ready=bool(m and play.is_play(room.activity) and _open(room) and m.ready and m.left_at is None),
        ))
    rounds: dict[str, int] = {}
    all_ready = False
    if play.is_play(room.activity):
        rounds = play.tally([
            r[0] for r in db.query(models.CoViewRoomEvent.emoji)
            .filter(models.CoViewRoomEvent.room_id == room.id, models.CoViewRoomEvent.kind == "round")
            .all()
        ])
        all_ready = play.everyone_ready([p.ready for p in participants if p.present])
    tail = (
        db.query(models.CoViewRoomEvent)
        .filter_by(room_id=room.id)
        .order_by(models.CoViewRoomEvent.seq.desc())
        .limit(rules.EVENT_TAIL)
        .all()
    )
    tail.reverse()
    marks: list[MarkOut] = []
    if reading.is_reading(room.activity):
        mark_rows = (
            db.query(
                models.CoViewRoomEvent.seq, models.CoViewRoomEvent.user_id, models.CoViewRoomEvent.kind,
                models.CoViewRoomEvent.emoji, models.CoViewRoomEvent.locator, models.CoViewRoomEvent.body,
                models.CoViewRoomEvent.quote, models.CoViewRoomEvent.position_ms,
            )
            .filter(
                models.CoViewRoomEvent.room_id == room.id,
                models.CoViewRoomEvent.kind.in_(["margin", "highlight"]),
                models.CoViewRoomEvent.locator.isnot(None),
            )
            .order_by(models.CoViewRoomEvent.seq)
            .all()
        )
        marks = [
            MarkOut(**m) for m in reading.reduce_marks([
                {"seq": r.seq, "user_id": r.user_id, "kind": r.kind, "emoji": r.emoji,
                 "locator": r.locator, "body": r.body, "quote": r.quote, "position_ms": r.position_ms}
                for r in mark_rows
            ])
        ]
    events = [
        EventOut(
            seq=e.seq, kind=e.kind, user_id=e.user_id,
            username=(by_id[e.user_id].username if e.user_id in by_id else None),
            body=e.body, emoji=e.emoji, position_ms=e.position_ms,
            locator=e.locator, quote=e.quote, created_at=e.created_at,
        )
        for e in tail
    ]
    return RoomOut(
        id=room.id, status=room.status.value,
        media_id=room.media_id, media_type=room.media_type.value, source=room.source,
        title_ru=room.title_ru, title_en=room.title_en, poster_url=room.poster_url, year=room.year,
        player_kind=room.player_kind, player_ref=room.player_ref, duration_ms=room.duration_ms,
        is_playing=bool(room.is_playing) and _open(room),
        position_ms=rules.current_position_ms(bool(room.is_playing) and _open(room), room.position_ms, room.position_updated_at, now),
        server_now=now, control_seq=room.control_seq or 0,
        save_to_shared=bool(room.save_to_shared),
        entry_id=room.entry_id, saved_entry_id=room.saved_entry_id,
        my_diary_entry_id=_my_diary_entry_id(db, room, me_id),
        review_id=_review_id_for(db, room) if me_id in circle_ids else None,
        host_user_id=room.host_id,
        participants=participants, events=events, last_seq=room.event_seq or 0,
        voice_available=_voice_available(),
        zen_available=_circle_has_premium(db, link),
        me_is_guest=me_id not in circle_ids,
        guest_slots_left=rules.guest_slots_left(len(circle_ids), len(guest_rows)),
        activity=room.activity or "watch", read_kind=room.read_kind, read_units=room.read_units,
        read_mode=room.read_mode or "own", lead_locator=room.lead_locator,
        lead_user_id=room.lead_user_id, content_hash=room.content_hash, marks=marks,
        rounds=rounds, all_ready=all_ready,
        created_at=room.created_at, started_at=room.started_at, ended_at=room.ended_at,
    )


def _active_room(db: Session, link: models.PartnerLink) -> models.CoViewRoom | None:
    room = (
        db.query(models.CoViewRoom)
        .filter(
            models.CoViewRoom.link_id == link.id,
            models.CoViewRoom.status.in_([models.CoViewRoomStatus.lobby, models.CoViewRoomStatus.live]),
        )
        .first()
    )
    if room is not None and _close_if_abandoned(db, room):
        return None
    return room


def _touch_member(db: Session, room: models.CoViewRoom, user_id: str) -> models.CoViewRoomMember:
    m = _member_row(room, user_id)
    now = _now()
    if m is None:
        m = models.CoViewRoomMember(room_id=room.id, user_id=user_id, joined_at=now, last_seen_at=now)
        db.add(m)
        room.members.append(m)
    else:
        m.left_at = None
        m.last_seen_at = now
    return m


def _require_in_room(room: models.CoViewRoom, user_id: str) -> models.CoViewRoomMember:
    m = _member_row(room, user_id)
    if m is None or m.left_at is not None:
        raise HTTPException(status_code=409, detail="Сначала войдите в комнату")
    return m


# --- endpoints ----------------------------------------------------------------

@router.get("/active", response_model=Optional[RoomOut])
def get_active(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The circle's open room, if there is one — what the big card on the
    "вы и …" screen asks for to decide between "start" and "join"."""
    link = get_active_link(db, current_user.id)
    if link is None:
        return None
    room = _active_room(db, link)
    if room is None:
        return None
    return _room_out(db, link, room, current_user.id)


@router.get("/invites", response_model=TypingList[GuestInviteOut])
def my_guest_invites(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Rooms friends have invited me into as a guest and that are still open —
    what the banner at the top of Home reads, since a guest need not be in
    any circle and so never sees the circle's own screen."""
    rows = (
        db.query(models.CoViewRoomGuest, models.CoViewRoom)
        .join(models.CoViewRoom, models.CoViewRoom.id == models.CoViewRoomGuest.room_id)
        .filter(
            models.CoViewRoomGuest.user_id == current_user.id,
            models.CoViewRoomGuest.status == "invited",
            models.CoViewRoom.status.in_([models.CoViewRoomStatus.lobby, models.CoViewRoomStatus.live]),
        )
        .order_by(models.CoViewRoomGuest.created_at.desc())
        .limit(10)
        .all()
    )
    out: list[GuestInviteOut] = []
    for guest, room in rows:
        if _close_if_abandoned(db, room):
            continue
        inviter = guest.invited_by
        if inviter is not None and blocking.is_blocked_between(db, current_user.id, inviter.id):
            continue
        out.append(GuestInviteOut(
            room_id=room.id,
            title=room.title_ru or room.title_en or _fallback_title(room.activity),
            poster_url=room.poster_url, inviter_name=_name(inviter),
            inviter_username=inviter.username if inviter is not None else "",
            room_status=room.status.value, created_at=guest.created_at or _now(),
            activity=room.activity or "watch",
        ))
    return out


@router.post("", response_model=RoomOut, status_code=201)
def create_room(
    payload: RoomCreate,
    response: Response,
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Opens a room and puts the creator in it. One open room per circle: if
    there already is one, that one is returned (200) rather than an error,
    so two people tapping "start" at once end up in the same place."""
    link = _require_link(db, current_user)
    existing = _active_room(db, link)
    if existing is not None:
        response.status_code = 200
        return _room_out(db, link, existing, current_user.id)

    try:
        media_type = models.MediaType(payload.media_type)
    except ValueError:
        raise HTTPException(status_code=400, detail="Неизвестный тип медиа")
    activity = (payload.activity or "watch").strip().lower()
    if activity not in reading.ACTIVITIES:
        raise HTTPException(status_code=400, detail="Неизвестный вид комнаты")
    read_kind: str | None = None
    digest: str | None = None
    units: int | None = None
    read_mode = "own"
    if activity == "read":
        # A book or a manga: nothing is played, so there is no player — the
        # room only keeps where people are (see app/co_reading.py).
        if media_type.value not in reading.READING_MEDIA_TYPES:
            raise HTTPException(status_code=400, detail="Читать вместе можно книги и мангу")
        try:
            read_kind, digest, units = reading.normalize_reading(
                payload.read_kind, payload.content_hash, payload.read_units,
            )
            read_mode = reading.normalize_mode(payload.read_mode, read_kind)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))
        kind, ref = "parallel", None
        duration_ms: int | None = reading.READ_DURATION_MS
    elif activity == "play":
        # A real game, played on everybody's own machine: no player, no length
        # (a game has no end to reach) — the room's clock is the session timer.
        if media_type.value not in play.PLAY_MEDIA_TYPES:
            raise HTTPException(status_code=400, detail="Играть вместе можно в игры")
        try:
            platform = play.normalize_platform(payload.platform)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))
        kind, ref = "parallel", platform
        duration_ms = None
    else:
        try:
            kind, ref = rules.normalize_player(payload.player_kind, payload.player_ref)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))
        duration_ms = payload.duration_ms
    if len(_member_ids(link)) > rules.MAX_ROOM_MEMBERS:
        raise HTTPException(status_code=409, detail="В комнате может быть не больше четырёх человек")

    now = _now()
    room = models.CoViewRoom(
        link_id=link.id, host_id=current_user.id,
        media_id=payload.media_id, media_type=media_type, source=payload.source,
        title_ru=payload.title_ru, title_en=payload.title_en,
        poster_url=payload.poster_url, year=payload.year,
        player_kind=kind, player_ref=ref, duration_ms=duration_ms,
        status=models.CoViewRoomStatus.lobby, is_playing=False, position_ms=0,
        position_updated_at=now, control_seq=0, event_seq=0,
        save_to_shared=payload.save_to_shared, entry_id=payload.entry_id,
        last_activity_at=now,
        activity=activity, read_kind=read_kind, content_hash=digest, read_units=units,
        read_mode=read_mode,
        lead_locator=(reading.start_locator(read_kind) if read_kind and reading.has_shared_place(read_mode) else None),
        lead_user_id=(current_user.id if read_kind and reading.has_shared_place(read_mode) else None),
    )
    db.add(room)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        link = _require_link(db, current_user)
        existing = _active_room(db, link)
        if existing is None:
            raise HTTPException(status_code=409, detail="Не удалось открыть комнату, попробуйте ещё раз")
        response.status_code = 200
        return _room_out(db, link, existing, current_user.id)
    host_member = _touch_member(db, room, current_user.id)
    if digest:
        host_member.content_hash = digest
    _add_event(db, room, current_user.id, "join")
    _publish(db, room)
    db.commit()
    db.refresh(room)

    title = room.title_ru or room.title_en or _fallback_title(activity)
    for other in (link.owner, link.partner, *[m.user for m in link.extra_members]):
        if other is not None and other.id != current_user.id:
            background_tasks.add_task(push.notify_room_invite, other.id, _name(current_user), title, activity)
    return _room_out(db, link, room, current_user.id)


@router.get("/{room_id}", response_model=RoomOut)
def get_room(
    room_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    link, room = _load(db, current_user, room_id)
    return _room_out(db, link, room, current_user.id)


@router.post("/{room_id}/join", response_model=RoomOut)
def join_room(
    room_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    link, room = _load(db, current_user, room_id, lock=True)
    if not _open(room):
        raise HTTPException(status_code=409, detail="Просмотр уже закончился")
    if current_user.id not in _circle_ids(link) and any(
        blocking.is_blocked_between(db, current_user.id, uid) for uid in _circle_ids(link)
    ):
        raise HTTPException(status_code=404, detail="Комната не найдена")
    existing = _member_row(room, current_user.id)
    fresh = existing is None or existing.left_at is not None
    _touch_member(db, room, current_user.id)
    if fresh:
        _add_event(db, room, current_user.id, "join")
    _publish(db, room)
    db.commit()
    db.refresh(room)
    return _room_out(db, link, room, current_user.id)


@router.post("/{room_id}/leave", response_model=RoomOut)
def leave_room(
    room_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Stepping out. The last person to go pauses a running film where it
    stands, and closes a lobby nobody ever pressed play in."""
    link, room = _load(db, current_user, room_id, lock=True)
    m = _member_row(room, current_user.id)
    if m is None or m.left_at is not None or not _open(room):
        return _room_out(db, link, room, current_user.id)
    now = _now()
    m.left_at = now
    m.voice_on = False
    m.ready = False  # a tick next to somebody who has gone would be a lie
    _add_event(db, room, current_user.id, "leave")
    circle = set(_circle_ids(link))
    # Guests keep nobody company: a film with only guests left in front of it
    # is a film nobody can pause, so only the circle's own presence counts.
    still_here = [
        x for x in room.members
        if x.user_id != current_user.id and x.user_id in circle
        and rules.is_present(x.left_at, x.last_seen_at, now)
    ]
    if not still_here:
        if room.is_playing:
            room.position_ms = rules.current_position_ms(True, room.position_ms, room.position_updated_at, now)
            room.position_updated_at = now
            room.is_playing = False
            room.control_seq = (room.control_seq or 0) + 1
        if room.status == models.CoViewRoomStatus.lobby:
            room.status = models.CoViewRoomStatus.ended
            room.ended_at = now
    _publish(db, room)
    db.commit()
    db.refresh(room)
    return _room_out(db, link, room, current_user.id)


@router.post("/{room_id}/control", response_model=RoomOut)
def control_room(
    room_id: str,
    payload: ControlIn,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Play, pause, or jump. Anyone in the room can do any of them — a room
    with a single remote is a room people quarrel in."""
    if payload.action not in rules.CONTROL_ACTIONS:
        raise HTTPException(status_code=400, detail="Неизвестное действие")
    link, room = _load(db, current_user, room_id, lock=True)
    _require_circle(link, current_user)
    if not _open(room):
        raise HTTPException(status_code=409, detail="Просмотр уже закончился")
    if reading.is_reading(room.activity):
        raise HTTPException(status_code=409, detail="В чтении нет паузы — просто листайте")
    if play.is_play(room.activity) and payload.action == "seek":
        # The clock is the session timer: time spent playing isn't a place to jump to.
        raise HTTPException(status_code=409, detail="В игре время идёт само — можно играть и ставить на перерыв")
    m = _require_in_room(room, current_user.id)
    now = _now()
    m.last_seen_at = now
    here = rules.current_position_ms(bool(room.is_playing), room.position_ms, room.position_updated_at, now)
    if payload.position_ms is not None:
        target = rules.clamp_position(payload.position_ms, room.duration_ms)
    else:
        target = rules.clamp_position(here, room.duration_ms)

    if payload.action == "play":
        room.is_playing = True
        if room.status == models.CoViewRoomStatus.lobby:
            room.status = models.CoViewRoomStatus.live
            room.started_at = now
    elif payload.action == "pause":
        room.is_playing = False
    # "seek" keeps whatever is_playing already was
    room.position_ms = target
    room.position_updated_at = now
    room.control_seq = (room.control_seq or 0) + 1
    _add_event(db, room, current_user.id, "control", body=payload.action, position_ms=target)
    _publish(db, room)
    db.commit()
    db.refresh(room)
    return _room_out(db, link, room, current_user.id)


@router.post("/{room_id}/events", response_model=RoomOut)
def post_event(
    room_id: str,
    payload: EventIn,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """A chat line, a reaction, a signal or an emotion tap — and, in a reading
    room, a note in the margin or a highlight on a paragraph. Chat, reactions,
    signals, notes and highlights are free; an emotion tap is Zen mode's input
    and needs a circle with premium (402 otherwise)."""
    if payload.kind not in rules.CLIENT_EVENT_KINDS:
        raise HTTPException(status_code=400, detail="Неизвестный тип события")
    body: str | None = None
    key: str | None = None
    if payload.kind in ("chat", "margin"):
        body = (payload.body or "").strip()
        if not body:
            raise HTTPException(status_code=400, detail="Пустое сообщение" if payload.kind == "chat" else "Пустая заметка")
        if len(body) > rules.CHAT_MAX_CHARS:
            raise HTTPException(status_code=400, detail=f"Слишком длинно — не больше {rules.CHAT_MAX_CHARS} символов")
        try:
            content_filter.check(body, field="chat", allow_links=payload.kind == "chat")
        except content_filter.ContentRejected as exc:
            raise HTTPException(status_code=400, detail=str(exc))
    elif payload.kind == "highlight":
        try:
            key = reading.normalize_highlight(payload.key)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))
    else:
        key = (payload.key or "").strip()
        # A signal is checked against the room's own kind of signals below,
        # once the room is loaded; here it only has to be one that exists.
        allowed = {
            "reaction": rules.REACTION_KEYS,
            "signal": rules.SIGNAL_KEYS + play.GAME_SIGNAL_KEYS,
            "emotion": rules.EMOTION_KEYS,
            "round": play.ROUND_KEYS,
        }[payload.kind]
        if key not in allowed:
            raise HTTPException(status_code=400, detail="Неизвестный вариант")

    link, room = _load(db, current_user, room_id, lock=True)
    if not _open(room):
        raise HTTPException(status_code=409, detail="Просмотр уже закончился")
    is_read = reading.is_reading(room.activity)
    is_game = play.is_play(room.activity)
    if payload.kind in ("margin", "highlight") and not is_read:
        raise HTTPException(status_code=400, detail="Заметки и подсветка бывают только в чтении")
    if payload.kind == "round" and not is_game:
        raise HTTPException(status_code=400, detail="Раунды бывают только в игре")
    if payload.kind == "emotion" and is_game:
        raise HTTPException(status_code=400, detail="В игре нет дзен-режима")
    if payload.kind == "signal" and key not in play.signal_keys(room.activity, rules.SIGNAL_KEYS):
        raise HTTPException(status_code=400, detail="Такого сигнала в этой комнате нет")
    if payload.kind == "round":
        played = (
            db.query(func.count(models.CoViewRoomEvent.id))
            .filter(models.CoViewRoomEvent.room_id == room.id, models.CoViewRoomEvent.kind == "round")
            .scalar()
        )
        if (played or 0) >= play.MAX_ROUNDS:
            raise HTTPException(status_code=409, detail="Очень много раундов — пора подвести итог")
    locator: str | None = None
    quote: str | None = None
    if is_read and (payload.kind in ("margin", "highlight") or payload.locator):
        try:
            locator = reading.normalize_locator(room.read_kind or "", payload.locator)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))
        if payload.kind == "margin" or (payload.kind == "highlight" and key == reading.HIGHLIGHT_ON):
            quote = reading.clean_quote(payload.quote)
    if payload.kind == "emotion" and not _circle_has_premium(db, link):
        # 402, not 409: the request is fine, the circle just hasn't unlocked
        # Zen (same convention as the album's writes).
        raise HTTPException(
            status_code=402,
            detail="Дзен — для подписчиков: одна подписка на двоих, и вдвоём дешевле",
        )
    m = _require_in_room(room, current_user.id)
    now = _now()
    recent = (
        db.query(func.count(models.CoViewRoomEvent.id))
        .filter(
            models.CoViewRoomEvent.room_id == room.id,
            models.CoViewRoomEvent.user_id == current_user.id,
            models.CoViewRoomEvent.created_at > now - rules.EVENT_RATE_WINDOW,
        )
        .scalar()
    )
    if (recent or 0) >= rules.EVENT_RATE_MAX:
        raise HTTPException(status_code=429, detail="Чуть помедленнее")
    m.last_seen_at = now
    if is_read:
        # Where in the book, in the room's scaled clock units: what the person
        # says (the place they pinned it to), else where they are now. This is
        # what lets the moments timeline work for reading without new code.
        at = reading.progress_to_ms(payload.progress if payload.progress is not None else m.progress)
        if payload.kind == "emotion" and locator is None:
            locator = m.locator  # a feeling is about where you are
    elif payload.position_ms is not None:
        at = rules.clamp_position(payload.position_ms, room.duration_ms)
    else:
        at = rules.clamp_position(
            rules.current_position_ms(bool(room.is_playing), room.position_ms, room.position_updated_at, now),
            room.duration_ms,
        )
    _add_event(
        db, room, current_user.id, payload.kind, body=body, emoji=key, position_ms=at,
        locator=locator, quote=quote,
    )
    _publish(db, room)
    db.commit()
    db.refresh(room)
    return _room_out(db, link, room, current_user.id)


@router.get("/{room_id}/events", response_model=TypingList[EventOut])
def list_events(
    room_id: str,
    after: int = 0,
    limit: int = 200,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Everything after `after` (oldest first) — for a client that joined
    late or reconnected after a long gap and needs more than the tail that
    rides along with every state push."""
    link, room = _load(db, current_user, room_id)
    limit = max(1, min(limit, 500))
    rows = (
        db.query(models.CoViewRoomEvent)
        .filter(models.CoViewRoomEvent.room_id == room.id, models.CoViewRoomEvent.seq > max(0, after))
        .order_by(models.CoViewRoomEvent.seq.asc())
        .limit(limit)
        .all()
    )
    names = {p.id: p.username for p in (link.owner, link.partner, *[m.user for m in link.extra_members]) if p is not None}
    return [
        EventOut(
            seq=e.seq, kind=e.kind, user_id=e.user_id, username=names.get(e.user_id),
            body=e.body, emoji=e.emoji, position_ms=e.position_ms,
            locator=e.locator, quote=e.quote, created_at=e.created_at,
        )
        for e in rows
    ]


@router.patch("/{room_id}", response_model=RoomOut)
def patch_room(
    room_id: str,
    payload: RoomPatch,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The "save to our shared list" switch (anyone in the room may flip it
    until the room ends), and the video's length once a player learns it."""
    link, room = _load(db, current_user, room_id, lock=True)
    _require_circle(link, current_user)
    if not _open(room):
        raise HTTPException(status_code=409, detail="Просмотр уже закончился")
    _require_in_room(room, current_user.id)
    changes = payload.model_dump(exclude_unset=True)
    changed = False
    if "save_to_shared" in changes and changes["save_to_shared"] is not None:
        if bool(room.save_to_shared) != changes["save_to_shared"]:
            room.save_to_shared = changes["save_to_shared"]
            _add_event(db, room, current_user.id, "system", body="save_on" if room.save_to_shared else "save_off")
            changed = True
    if "duration_ms" in changes and changes["duration_ms"] and not room.duration_ms:
        room.duration_ms = changes["duration_ms"]
        changed = True
    if reading.is_reading(room.activity):
        if changes.get("read_units") and not room.read_units:
            room.read_units = changes["read_units"]
            changed = True
        if changes.get("read_mode") is not None:
            try:
                mode = reading.normalize_mode(changes["read_mode"], room.read_kind)
            except ValueError as exc:
                raise HTTPException(status_code=400, detail=str(exc))
            # Reading aloud has one reader: asking for it again as somebody
            # else is taking the reading over ("читать вместо ...").
            takeover = mode == "aloud" and room.read_mode == "aloud" and room.lead_user_id != current_user.id
            if mode != room.read_mode or takeover:
                now = _now()
                room.read_mode = mode
                if reading.has_shared_place(mode):
                    # Everybody starts following from where the person who
                    # switched it on is (or, failing that, where the shared
                    # place already was, or the very beginning).
                    me = _member_row(room, current_user.id)
                    try:
                        # Taking over a reading aloud carries on from the line the
                        # last reader reached; anything else starts from you.
                        first = (
                            [changes.get("locator"), room.lead_locator, me.locator if me else None]
                            if takeover else
                            [changes.get("locator"), me.locator if me else None, room.lead_locator]
                        )
                        start = reading.normalize_locator(room.read_kind or "", next((x for x in first if x), None))
                    except ValueError:
                        start = reading.start_locator(room.read_kind or "parallel")
                    prog = changes.get("progress")
                    if prog is None:
                        prog = (
                            reading.ms_to_progress(room.position_ms) if takeover
                            else (me.progress if me is not None else 0)
                        )
                    room.lead_locator = start
                    room.lead_user_id = current_user.id
                    room.position_ms = reading.progress_to_ms(prog)
                    room.position_updated_at = now
                    room.control_seq = (room.control_seq or 0) + 1
                _add_event(
                    db, room, current_user.id, "system",
                    body={"together": "read_together", "aloud": "read_aloud"}.get(mode, "read_own"),
                )
                changed = True
    if changed:
        _publish(db, room)
        db.commit()
        db.refresh(room)
    return _room_out(db, link, room, current_user.id)


# --- reading --------------------------------------------------------------------

def _require_reading(room: models.CoViewRoom) -> None:
    if not reading.is_reading(room.activity):
        raise HTTPException(status_code=409, detail="Это комната для просмотра, а не для чтения")


def _begin_if_lobby(room: models.CoViewRoom, link: models.PartnerLink, user_id: str, now: datetime) -> bool:
    """A reading room goes live when the first person of the circle opens a
    page (a film goes live on play). A guest alone in a lobby doesn't start
    the evening. Returns whether it just started."""
    if room.status == models.CoViewRoomStatus.lobby and user_id in _circle_ids(link):
        room.status = models.CoViewRoomStatus.live
        room.started_at = now
        return True
    return False


@router.post("/{room_id}/locator", response_model=RoomOut)
def report_locator(
    room_id: str,
    payload: LocatorIn,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """"I'm here" — where I am in the book, as the app keeps it. Called as
    pages turn (the client sends it a moment after the last turn, not on
    every swipe); everyone else sees it as the little marker of where you are.
    Doesn't write an event, so a long evening of reading doesn't bury the
    chat; it wakes the room's sockets only when something actually moved."""
    link, room = _load(db, current_user, room_id, lock=True)
    _require_reading(room)
    if not _open(room):
        raise HTTPException(status_code=409, detail="Чтение уже закончилось")
    m = _require_in_room(room, current_user.id)
    try:
        locator = reading.normalize_locator(room.read_kind or "", payload.locator)
        digest = reading.normalize_hash(payload.content_hash) if payload.content_hash else None
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    now = _now()
    progress = reading.clamp_progress(payload.progress)
    moved = m.locator != locator or int(m.progress or 0) != progress
    if digest and m.content_hash != digest:
        m.content_hash = digest
        moved = True
    m.locator, m.progress, m.locator_at = locator, progress, now
    m.last_seen_at = now
    room.last_activity_at = now
    started = _begin_if_lobby(room, link, current_user.id, now)
    if moved or started:
        _publish(db, room)
    db.commit()
    db.refresh(room)
    return _room_out(db, link, room, current_user.id)


@router.post("/{room_id}/lead", response_model=RoomOut)
def lead_room(
    room_id: str,
    payload: LeadIn,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Turning the page for everyone, in "together" mode. Anyone in the circle
    can, exactly as anyone can press play — a room with a single remote is a
    room people quarrel in. Guests follow. In "aloud" mode the shared place is
    the line being read, and only the reader moves it."""
    link, room = _load(db, current_user, room_id, lock=True)
    _require_circle(link, current_user)
    _require_reading(room)
    if not _open(room):
        raise HTTPException(status_code=409, detail="Чтение уже закончилось")
    m = _require_in_room(room, current_user.id)
    if not reading.has_shared_place(room.read_mode):
        raise HTTPException(status_code=409, detail="Сейчас каждый читает в своём темпе")
    if room.read_mode == "aloud" and room.lead_user_id != current_user.id:
        # Two people can't read one line aloud: the page belongs to the reader.
        reader = db.get(models.User, room.lead_user_id) if room.lead_user_id else None
        raise HTTPException(
            status_code=409,
            detail=f"Сейчас читает вслух {_name(reader)}" if reader is not None else "Сейчас кто-то читает вслух",
        )
    try:
        locator = reading.normalize_locator(room.read_kind or "", payload.locator)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    now = _now()
    progress = reading.clamp_progress(payload.progress)
    moved = room.lead_locator != locator
    room.lead_locator = locator
    room.lead_user_id = current_user.id
    room.position_ms = reading.progress_to_ms(progress)
    room.position_updated_at = now
    if moved:
        room.control_seq = (room.control_seq or 0) + 1
    # The person turning the page is, by definition, at that place.
    m.locator, m.progress, m.locator_at = locator, progress, now
    m.last_seen_at = now
    room.last_activity_at = now
    started = _begin_if_lobby(room, link, current_user.id, now)
    if moved or started:
        _publish(db, room)
    db.commit()
    db.refresh(room)
    return _room_out(db, link, room, current_user.id)


@router.post("/{room_id}/ready", response_model=RoomOut)
def set_ready(
    room_id: str,
    payload: ReadyIn,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The ready check of a game room: "готов" on or off. A courtesy, not a
    gate — anybody can start the session clock whenever they like. Anyone who
    is in the room can tap it, guests included. Doesn't write an event, so the
    chat stays a chat; wakes the room's sockets only when something changed."""
    link, room = _load(db, current_user, room_id, lock=True)
    if not play.is_play(room.activity):
        raise HTTPException(status_code=409, detail="Проверка готовности бывает только в игре")
    if not _open(room):
        raise HTTPException(status_code=409, detail="Игра уже закончилась")
    m = _require_in_room(room, current_user.id)
    changed = bool(m.ready) != payload.ready
    m.ready = payload.ready
    m.last_seen_at = _now()
    if changed:
        _publish(db, room)
    db.commit()
    db.refresh(room)
    return _room_out(db, link, room, current_user.id)


@router.post("/{room_id}/album-quote", response_model=AlbumQuoteOut)
def quote_to_album(
    room_id: str,
    payload: AlbumQuoteIn,
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Sets a paragraph aside for the pair album: it goes into *my* sealed note
    for this book (started if I have none), and the note opens for both of
    you when the evening is marked watched — the album's own rule, so the
    quotes each of you kept appear together when you finish. Only a couple has
    an album. A note is a sticky note (pair_album.NOTE_MAX_CHARS): what does
    not fit is refused, never cut, and the free allowance of notes is the
    album's own (402 once it is spent)."""
    link, room = _load(db, current_user, room_id, lock=True)
    _require_circle(link, current_user)
    _require_reading(room)
    if not _open(room):
        raise HTTPException(status_code=409, detail="Чтение уже закончилось")
    _require_in_room(room, current_user.id)
    if len(_member_ids(link)) != 2:
        raise HTTPException(status_code=409, detail="Альбом доступен только паре")
    try:
        quote = reading.clean_album_quote(payload.quote)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    # Same order of locks as the album's own "leave a note": the shared entry
    # first, so this can't interleave with "mark watched".
    entry = (
        db.query(models.CoViewEntry)
        .filter_by(link_id=link.id, source=room.source, media_id=room.media_id)
        .with_for_update()
        .first()
    )
    if entry is not None and entry.status == models.CoViewStatus.watched:
        raise HTTPException(status_code=409, detail="Этот вечер уже прошёл")
    rnd = pair_album.current_round(db, link.id, room.source, room.media_id)

    def _find() -> models.PairNote | None:
        return (
            db.query(models.PairNote)
            .filter_by(link_id=link.id, source=room.source, media_id=room.media_id,
                       author_id=current_user.id, round=rnd)
            .first()
        )

    note = _find()
    try:
        body = reading.add_quote_to_note(note.body if note else None, quote, max_chars=pair_album.NOTE_MAX_CHARS)
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    added = note is None or body != (note.body or "").strip()
    body = album_router._clean_text(body, field="note", max_chars=pair_album.NOTE_MAX_CHARS, label="записка")

    created = note is None
    if created:
        album_router._require_note_slot(db, link, current_user.id)
        pending = (
            db.query(models.PairNote)
            .filter(
                models.PairNote.link_id == link.id,
                models.PairNote.author_id == current_user.id,
                models.PairNote.revealed_at.is_(None),
            )
            .count()
        )
        if pending >= pair_album.MAX_PENDING_NOTES_PER_AUTHOR:
            raise HTTPException(status_code=409, detail="Слишком много неоткрытых записок — сначала посмотрите что-нибудь вместе")
        note = models.PairNote(
            link_id=link.id, author_id=current_user.id, source=room.source, media_id=room.media_id,
            media_type=room.media_type, round=rnd, body=body, mood=None,
        )
        db.add(note)
    elif added:
        note.body = body
    note.title_ru, note.title_en = room.title_ru, room.title_en
    note.poster_url, note.year = room.poster_url, room.year
    try:
        db.commit()
    except IntegrityError:
        # Two devices of one person at once: the second finds the first one's note.
        db.rollback()
        raise HTTPException(status_code=409, detail="Не получилось отложить цитату — попробуйте ещё раз")

    if created:
        other = album_router._partner_user(link, current_user.id)
        if other is not None:
            background_tasks.add_task(
                push.notify_album_note, other.id, _name(current_user),
                room.title_ru or room.title_en or "книга",
            )
    return AlbumQuoteOut(created=created, added=added, chars_left=max(0, pair_album.NOTE_MAX_CHARS - len(body)))


@router.post("/{room_id}/finish", response_model=RoomOut)
def finish_room(
    room_id: str,
    background_tasks: BackgroundTasks,
    payload: FinishIn = FinishIn(),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """"Досмотрели". Ends the room for everyone and, when the save switch is
    on, writes the evening (see this module's docstring). Idempotent: a
    second call — the other person's client reacting to the same ending —
    just returns the finished room, with that caller's own diary entry id."""
    link, room = _load(db, current_user, room_id, lock=True)
    _require_circle(link, current_user)
    if not _open(room):
        return _room_out(db, link, room, current_user.id)
    _require_in_room(room, current_user.id)
    if room.started_at is None:
        raise HTTPException(status_code=409, detail="Просмотр ещё не начинался")

    now = _now()
    if payload.position_ms is None and reading.is_reading(room.activity):
        # No clock to read: the furthest anyone got is where the book "ended".
        furthest = max([int(m.progress or 0) for m in room.members] or [0])
        end_pos = rules.clamp_position(reading.progress_to_ms(furthest), room.duration_ms)
    else:
        end_pos = rules.clamp_position(
            payload.position_ms if payload.position_ms is not None
            else rules.current_position_ms(bool(room.is_playing), room.position_ms, room.position_updated_at, now),
            room.duration_ms,
        )
    room.position_ms = end_pos
    room.position_updated_at = now
    room.is_playing = False
    room.control_seq = (room.control_seq or 0) + 1

    # Everyone who was there for any of it: still here, or left after play began.
    started = room.started_at
    watchers = [
        m.user_id for m in room.members
        if m.left_at is None or (started is not None and m.left_at >= started)
    ]
    users = {p.id: p for p in (link.owner, link.partner, *[x.user for x in link.extra_members]) if p is not None}
    circle_ids = set(users)
    for g in _active_guests(db, room):
        if g.user is not None:
            users[g.user_id] = g.user
    watchers = [uid for uid in watchers if uid in users]
    circle_watchers = [uid for uid in watchers if uid in circle_ids]

    revealed: list[models.PairNote] = []
    if room.save_to_shared:
        entry = (
            db.query(models.CoViewEntry)
            .filter_by(link_id=link.id, source=room.source, media_id=room.media_id)
            .with_for_update()
            .first()
        )
        if entry is None:
            entry = models.CoViewEntry(
                link_id=link.id, media_id=room.media_id, media_type=room.media_type, source=room.source,
                title_ru=room.title_ru, title_en=room.title_en, poster_url=room.poster_url,
                year=room.year, genres=[], added_by_id=room.host_id,
            )
            db.add(entry)
            db.flush()
        first_time = entry.status != models.CoViewStatus.watched
        entry.status = models.CoViewStatus.watched
        entry.watched_at = now
        item = _coview_item(entry)
        for uid in watchers:
            others = ", ".join(users[o].username for o in watchers if o != uid)
            log_watched(db, uid, item, watched_at=now, watched_with_username=others or None, watched_together=True)
        room.saved_entry_id = entry.id
        # The joint review opens with the evening: everyone who was there
        # writes their own part right after (see routers/circle_review.py).
        from app.routers.circle_review import open_review
        open_review(
            db, link, origin="room", created_by_id=current_user.id,
            media_id=room.media_id, media_type=room.media_type, source=room.source,
            title_ru=room.title_ru, title_en=room.title_en, poster_url=room.poster_url, year=room.year,
            participant_ids=list(circle_watchers), watched_at=now, room_id=room.id,
        )
        if first_time and len(_member_ids(link)) == 2:
            from app import pair_album
            revealed = pair_album.reveal_notes(db, link, entry)

    room.status = models.CoViewRoomStatus.ended
    room.ended_at = now
    for m in room.members:
        m.voice_on = False
    _add_event(db, room, current_user.id, "system", body="finished", position_ms=end_pos)
    _publish(db, room)
    db.commit()
    db.refresh(room)

    title = room.title_ru or room.title_en or "фильм"
    for n in revealed:
        other_id = next((u for u in _member_ids(link) if u != n.author_id), None)
        if other_id is None:
            continue
        author = users.get(n.author_id)
        background_tasks.add_task(push.notify_album_reveal, other_id, _name(author), title)
    return _room_out(db, link, room, current_user.id)


@router.delete("/{room_id}", status_code=204)
def close_room(
    room_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Closing without saving anything. The host can always do it; anyone
    else only once they are the last person left in the room."""
    link, room = _load(db, current_user, room_id, lock=True)
    _require_circle(link, current_user)
    if not _open(room):
        return Response(status_code=204)
    now = _now()
    circle = set(_circle_ids(link))
    others_here = [
        m for m in room.members
        if m.user_id != current_user.id and m.user_id in circle
        and rules.is_present(m.left_at, m.last_seen_at, now)
    ]
    if room.host_id != current_user.id and others_here:
        raise HTTPException(status_code=403, detail="Закрыть комнату может тот, кто её открыл")
    room.status = models.CoViewRoomStatus.ended
    room.ended_at = now
    room.is_playing = False
    for m in room.members:
        m.left_at = m.left_at or now
        m.voice_on = False
    _add_event(db, room, current_user.id, "system", body="closed")
    _publish(db, room)
    db.commit()
    return Response(status_code=204)


# --- guests -----------------------------------------------------------------------

def _are_friends(db: Session, a: str, b: str) -> bool:
    return (
        db.query(models.FriendRequest.id)
        .filter(
            models.FriendRequest.status == models.FriendRequestStatus.accepted,
            (
                ((models.FriendRequest.from_user_id == a) & (models.FriendRequest.to_user_id == b))
                | ((models.FriendRequest.from_user_id == b) & (models.FriendRequest.to_user_id == a))
            ),
        )
        .first()
        is not None
    )


@router.post("/{room_id}/guests", response_model=RoomOut)
def invite_guest(
    room_id: str,
    payload: GuestIn,
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Invite a friend into this room. Only someone in the circle can, only a
    friend of theirs, never someone blocked by or blocking anyone already
    here, and at most `rules.MAX_GUESTS` at once. Re-inviting the same person
    is a no-op; someone who said no isn't asked again for this room."""
    link, room = _load(db, current_user, room_id, lock=True)
    _require_circle(link, current_user)
    if not _open(room):
        raise HTTPException(status_code=409, detail="Просмотр уже закончился")
    target = db.query(models.User).filter_by(id=payload.user_id).first()
    if target is None or getattr(target, "deleted_at", None) is not None:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    circle = _circle_ids(link)
    if target.id in circle:
        raise HTTPException(status_code=409, detail="Этот человек уже в вашем круге")
    if not _are_friends(db, current_user.id, target.id) or blocking.is_blocked_between(db, current_user.id, target.id):
        raise HTTPException(status_code=403, detail="Позвать можно только друзей")
    if any(blocking.is_blocked_between(db, target.id, uid) for uid in circle):
        raise HTTPException(status_code=409, detail="Этот человек не может зайти в эту комнату")

    existing = db.query(models.CoViewRoomGuest).filter_by(room_id=room.id, user_id=target.id).first()
    if existing is not None and existing.status == "invited":
        return _room_out(db, link, room, current_user.id)
    if existing is not None and existing.status == "declined":
        raise HTTPException(status_code=409, detail="Этот человек отказался от приглашения")
    if rules.guest_slots_left(len(circle), len(_active_guests(db, room))) <= 0:
        raise HTTPException(status_code=409, detail="Гостей уже достаточно — мест больше нет")

    if existing is None:
        db.add(models.CoViewRoomGuest(room_id=room.id, user_id=target.id, invited_by_id=current_user.id, status="invited"))
    else:
        existing.status = "invited"
        existing.invited_by_id = current_user.id
    room.last_activity_at = _now()
    _publish(db, room)
    db.commit()
    db.refresh(room)
    background_tasks.add_task(
        push.notify_room_guest_invite, target.id, _name(current_user),
        room.title_ru or room.title_en or _fallback_title(room.activity),
        room.activity or "watch",
    )
    return _room_out(db, link, room, current_user.id)


@router.delete("/{room_id}/guests/{user_id}", status_code=204)
def remove_guest(
    room_id: str,
    user_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Take an invitation back (anyone in the circle), or say no / leave for
    good (the guest, for themselves — `me` stands for the caller). The guest's access ends at once: their
    room socket closes on its next refresh."""
    if user_id == "me":
        user_id = current_user.id
    link, room = _load(db, current_user, room_id, lock=True)
    in_circle = current_user.id in _circle_ids(link)
    if user_id != current_user.id and not in_circle:
        raise HTTPException(status_code=403, detail="Это могут только те, кто в круге")
    guest = db.query(models.CoViewRoomGuest).filter_by(room_id=room.id, user_id=user_id).first()
    if guest is None or guest.status != "invited":
        return Response(status_code=204)
    guest.status = "declined" if user_id == current_user.id else "removed"
    m = _member_row(room, user_id)
    if m is not None and m.left_at is None:
        m.left_at = _now()
        m.voice_on = False
        _add_event(db, room, user_id, "leave")
    _publish(db, room)
    db.commit()
    return Response(status_code=204)


# --- voice ----------------------------------------------------------------------

def _voice_room_name(room_id: str) -> str:
    return f"co-view-{room_id}"


@router.post("/{room_id}/voice-token", response_model=VoiceTokenOut)
def voice_token(
    room_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """A short-lived LiveKit access token for this room's audio channel.
    Free for everyone: the only checks are "are you in this circle's open
    room" and "is voice configured on this server". Nothing is recorded."""
    if not _voice_available():
        raise HTTPException(status_code=503, detail="Голос на этом сервере не настроен")
    link, room = _load(db, current_user, room_id, lock=True)
    if not _open(room):
        raise HTTPException(status_code=409, detail="Просмотр уже закончился")
    m = _require_in_room(room, current_user.id)
    m.voice_on = True
    _publish(db, room)
    db.commit()

    now = int(time.time())
    claims = {
        "iss": settings.livekit_api_key,
        "sub": current_user.id,
        "name": _name(current_user),
        "nbf": now - 5,
        "exp": now + 2 * 60 * 60,
        "video": {
            "room": _voice_room_name(room.id),
            "roomJoin": True,
            "canPublish": True,
            "canSubscribe": True,
            "canPublishData": False,
        },
    }
    token = jwt.encode(claims, settings.livekit_api_secret, algorithm="HS256")
    return VoiceTokenOut(
        url=settings.livekit_url, token=token,
        room_name=_voice_room_name(room.id), identity=current_user.id,
    )


@router.delete("/{room_id}/voice", response_model=RoomOut)
def voice_off(
    room_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    link, room = _load(db, current_user, room_id, lock=True)
    m = _member_row(room, current_user.id)
    if m is not None and m.voice_on:
        m.voice_on = False
        _publish(db, room)
        db.commit()
        db.refresh(room)
    return _room_out(db, link, room, current_user.id)


# --- realtime -------------------------------------------------------------------

@router.websocket("/{room_id}/ws")
async def watch_room(websocket: WebSocket, room_id: str, token: str | None = None):
    """The room's live feed: the whole current room — player clock,
    participants, the recent event tail — on connect and on every change.

    Unlike the older session sockets this does not hold one database
    session for the life of the connection: authentication gets its own
    short one, and every refresh opens and closes another. A room stays
    open for hours and a pooled connection pinned to each open socket
    would starve everything else."""
    await websocket.accept()
    auth_db = SessionLocal()
    try:
        user = await get_ws_user(token, auth_db)
        user_id = user.id if user is not None else None
    finally:
        auth_db.close()
    if user_id is None:
        await websocket.close(code=4401)
        return

    def _fetch() -> str | None:
        db = SessionLocal()
        try:
            me = db.query(models.User).filter_by(id=user_id).first()
            if me is None:
                return None
            room = db.query(models.CoViewRoom).filter_by(id=room_id).first()
            link = db.query(models.PartnerLink).filter_by(id=room.link_id).first() if room is not None else None
            if room is None or link is None or not _can_reach(db, user_id, room, link):
                return None
            _close_if_abandoned(db, room)
            m = _member_row(room, user_id)
            if m is not None and m.left_at is None and _open(room):
                now = _now()
                seen = m.last_seen_at
                if seen is None or (now - (seen if seen.tzinfo else seen.replace(tzinfo=timezone.utc))).total_seconds() > 20:
                    m.last_seen_at = now
                    db.commit()
            return _room_out(db, link, room, user_id).model_dump_json()
        finally:
            db.close()

    await realtime.run_ws_loop(
        websocket, realtime.topic_for("room", room_id), _fetch, wait_seconds=20.0,
    )
