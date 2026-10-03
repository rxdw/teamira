"""Rules for co-view rooms ("Гостиная"): watching together inside the app.

Everything that can be decided without a database lives here — the clock
arithmetic, what a player reference may look like, which reactions exist,
when a room counts as abandoned — so it can be tested directly and the
router stays a thin HTTP shell (see routers/co_view_room.py).

Design notes that shaped the rules:

* **A room is a clock, not a stream.** The server never touches video. It
  keeps `position_ms` true at `position_updated_at` and whether the clock
  is running. Clients compute "where are we now" from those and the
  server's own `server_now`, never from their own wall clock.
* **Almost nothing here is premium.** Rooms, chat, voice, reactions, signals
  and every player kind are free for everyone, on purpose (people would
  otherwise just use another app). Two things are premium, both for the whole
  circle as soon as any one member has a subscription (see
  routers/partner.py::_circle_has_premium): **Zen mode**, whose own input —
  the one-tap emotion — the server refuses to record for a free circle (402),
  and the **moments timeline**, which is computed from reactions only when
  the review opens for a premium circle. Reactions are recorded for everyone,
  so a subscription bought later still unlocks the timeline of past evenings.
* **Emoji and signals are an allow-list.** Free text exists in exactly one
  place — chat — and goes through the content filter; everything else is a
  key from a fixed set, which keeps the cozy tone and makes the moments
  timeline countable.
"""

from __future__ import annotations

import re
from datetime import datetime, timedelta, timezone
from urllib.parse import parse_qs, urlparse

# How the picture reaches each person.
PLAYER_KINDS = ("youtube", "twitch", "direct", "parallel")

# Up to four people in a circle (see PLAN_SEATS' family plan); the room
# simply follows the circle.
MAX_ROOM_MEMBERS = 4

# Guests: friends of someone in the circle, invited into one room. At most
# three, and never more than six people in total, so a couple can bring three
# friends and a full circle of four two.
MAX_GUESTS = 3
MAX_ROOM_TOTAL = 6


def guest_slots_left(circle_size: int, active_guests: int) -> int:
    """How many more guests this room can take."""
    cap = min(MAX_GUESTS, MAX_ROOM_TOTAL - max(0, circle_size))
    return max(0, cap - max(0, active_guests))


# An un-ended room nobody has touched for this long is treated as
# abandoned and closed without saving. A lobby is shorter-lived than a
# room that has been playing: nobody arrives at a cold lobby after an
# hour, but a paused film can wait out a long dinner.
LOBBY_IDLE_LIMIT = timedelta(minutes=30)
LIVE_IDLE_LIMIT = timedelta(hours=4)

# A member is "here" when their socket touched last_seen_at this recently.
PRESENCE_WINDOW = timedelta(seconds=75)

# Flood guard: per person, per window.
EVENT_RATE_WINDOW = timedelta(seconds=10)
EVENT_RATE_MAX = 20

CHAT_MAX_CHARS = 400
EVENT_TAIL = 60  # how many recent events ride along with every state push

# Emoji reactions — float across the picture and land in the timeline.
REACTION_KEYS = ("❤️", "😂", "😱", "🥹", "😮", "👏", "😭", "🔥", "🫶", "😴")

# Signals — small nudges to the others, not text.
#   pause      "давай на паузу?"
#   rewind     "перемотай назад"
#   pulse      a soft heartbeat: the other phones vibrate once
#   hold       "держу за руку"
SIGNAL_KEYS = ("pause", "rewind", "pulse", "hold")

# Emotion taps — Zen mode's own input, so premium (see the module docstring).
EMOTION_KEYS = ("warm", "funny", "tense", "touching", "beautiful", "sad", "wow", "bored")

# "margin" is a note pinned to a place in a book or manga (reading rooms only,
# see app/co_reading.py); like chat it is free text and goes through the filter.
# "highlight" is a soft tint on a paragraph (on/off, see co_reading.reduce_marks).
# "round" is one finished round of a game (win / loss / draw / checkpoint, see
# co_play.py).
CLIENT_EVENT_KINDS = ("chat", "reaction", "signal", "emotion", "margin", "highlight", "round")

CONTROL_ACTIONS = ("play", "pause", "seek")

# A video is "watched to the end" from here on, matching what the client
# uses to trigger the finish ritual on its own.
WATCHED_FRACTION = 0.9

MAX_POSITION_MS = 1000 * 60 * 60 * 24  # a day; anything bigger is a bug


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _aware(dt: datetime | None) -> datetime | None:
    if dt is None:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def current_position_ms(is_playing: bool, position_ms: int, updated_at: datetime | None, now: datetime | None = None) -> int:
    """Where the room's clock is right now. Paused: exactly the stored
    position. Playing: the stored position plus the time since it was
    stored. Never negative."""
    base = int(position_ms or 0)
    if not is_playing or updated_at is None:
        return max(0, base)
    now = _aware(now) or utcnow()
    elapsed = int((now - _aware(updated_at)).total_seconds() * 1000)
    return max(0, base + max(0, elapsed))


def clamp_position(ms: int | None, duration_ms: int | None = None) -> int:
    value = max(0, int(ms or 0))
    value = min(value, MAX_POSITION_MS)
    if duration_ms and duration_ms > 0:
        value = min(value, int(duration_ms))
    return value


def is_abandoned(status: str, last_activity_at: datetime | None, now: datetime | None = None) -> bool:
    """Has an open room gone quiet for long enough to be closed."""
    if status == "ended":
        return False
    now = _aware(now) or utcnow()
    last = _aware(last_activity_at) or now
    limit = LOBBY_IDLE_LIMIT if status == "lobby" else LIVE_IDLE_LIMIT
    return now - last > limit


def is_present(left_at: datetime | None, last_seen_at: datetime | None, now: datetime | None = None) -> bool:
    if left_at is not None:
        return False
    now = _aware(now) or utcnow()
    seen = _aware(last_seen_at)
    return seen is not None and now - seen <= PRESENCE_WINDOW


def reached_the_end(position_ms: int, duration_ms: int | None) -> bool:
    return bool(duration_ms and duration_ms > 0 and position_ms >= duration_ms * WATCHED_FRACTION)


# --- player references -------------------------------------------------------

_YT_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")
_TWITCH_VOD = re.compile(r"^\d{5,12}$")


def youtube_id(raw: str | None) -> str | None:
    """A bare 11-character id, or any of the usual YouTube URL shapes."""
    text = (raw or "").strip()
    if not text:
        return None
    if _YT_ID.match(text):
        return text
    try:
        url = urlparse(text if "://" in text else f"https://{text}")
    except ValueError:
        return None
    host = (url.hostname or "").lower()
    if host in ("youtu.be", "www.youtu.be"):
        cand = url.path.strip("/").split("/")[0]
        return cand if _YT_ID.match(cand) else None
    if host.endswith("youtube.com"):
        if url.path == "/watch":
            cand = (parse_qs(url.query).get("v") or [""])[0]
            return cand if _YT_ID.match(cand) else None
        parts = [p for p in url.path.split("/") if p]
        if len(parts) >= 2 and parts[0] in ("embed", "shorts", "live", "v"):
            return parts[1] if _YT_ID.match(parts[1]) else None
    return None


def twitch_vod_id(raw: str | None) -> str | None:
    text = (raw or "").strip()
    if not text:
        return None
    if _TWITCH_VOD.match(text):
        return text
    try:
        url = urlparse(text if "://" in text else f"https://{text}")
    except ValueError:
        return None
    host = (url.hostname or "").lower()
    if host.endswith("twitch.tv"):
        parts = [p for p in url.path.split("/") if p]
        if len(parts) >= 2 and parts[0] == "videos" and _TWITCH_VOD.match(parts[1]):
            return parts[1]
    return None


def normalize_player(kind: str, ref: str | None) -> tuple[str, str | None]:
    """Returns (kind, cleaned ref) or raises ValueError with a message that
    is safe to show the person. A `direct` reference must be an https URL —
    it is only ever handed to the client's own player, never fetched here."""
    kind = (kind or "").strip().lower()
    if kind not in PLAYER_KINDS:
        raise ValueError("Неизвестный тип плеера")
    if kind == "parallel":
        return kind, None
    if kind == "youtube":
        vid = youtube_id(ref)
        if vid is None:
            raise ValueError("Не похоже на ссылку YouTube")
        return kind, vid
    if kind == "twitch":
        vid = twitch_vod_id(ref)
        if vid is None:
            raise ValueError("Не похоже на ссылку на запись Twitch")
        return kind, vid
    text = (ref or "").strip()
    try:
        url = urlparse(text)
    except ValueError:
        raise ValueError("Не похоже на ссылку на видео")
    if url.scheme != "https" or not url.hostname or len(text) > 600:
        raise ValueError("Ссылка на видео должна начинаться с https://")
    return kind, text
