"""Rules for playing together: a *real* game, each on their own console or PC.

A game room is the same room as a watching one (see app/co_view_room.py) —
same circle, guests, chat, voice, reactions, "save to our list" and joint
review. And, like the other kinds of room, **the app carries nothing of the
thing itself**: there is no game here, nothing of it is streamed or relayed,
and nothing inside anyone's game is read or controlled. People launch the game
wherever they play it (a PC, a PlayStation, a Switch, a phone) and the room is
the evening around it:

* **the session clock** — the room's own clock, used as a play timer. "Play"
  starts it (the first press opens the evening), "pause" is a break (anyone in
  the circle can press either, as with a film), and the last person to leave
  stops it where it stands. It can't be jumped around: time spent playing is
  not something to seek in. A game has no length, so there is no end to reach.

* **a ready check** — before the session starts everybody taps "готов", and
  the room shows who is. It is a courtesy, not a gate: anybody can start the
  clock whenever they like.

* **game signals instead of film signals** — a film's "pause / rewind / pulse /
  hold" are about a picture. Players say other things: "готов", "отойду",
  "нужна помощь", "gg", "ещё раз". They are allow-listed keys like every
  signal, never free text.

* **rounds** — "победа", "поражение", "ничья", "рубеж". One tap writes one into
  the room's ledger stamped with the session time; the room shows the tally
  and the review's moments timeline picks them up, so the evening has its own
  story afterwards (see circle_review.build_moments).

* **no zen, no notes** — zen's feelings are a film's; margins belong to books.

The platform a room is played on is a short allow-listed key kept in the
room's `player_ref` (the column a film uses for its player reference, which a
parallel room doesn't need).
"""

from __future__ import annotations

ACTIVITY = "play"

# Only a game can be played together.
PLAY_MEDIA_TYPES = ("game",)

# Where the game is played; shown as a chip, never anything the app acts on.
PLATFORMS = ("pc", "ps", "xbox", "switch", "mobile", "other")

# What players say mid-session (a film's signals are co_view_room.SIGNAL_KEYS).
GAME_SIGNAL_KEYS = ("ready", "brb", "help", "gg", "again")

# One tap per round.
ROUND_KEYS = ("win", "loss", "draw", "checkpoint")

# What a round counts as in the review's moments timeline.
ROUND_MOMENT_KEYS = {"win": "🏆", "loss": "💀", "draw": "🤝", "checkpoint": "🚩"}

# A session of rounds is long; a room that has recorded this many is a room
# someone is mashing a button in. (The per-person rate limit does the rest.)
MAX_ROUNDS = 500


def is_play(activity: str | None) -> bool:
    return activity == ACTIVITY


def normalize_platform(raw: str | None) -> str | None:
    """A platform key, None when none was given, ValueError (safe to show)
    for anything else."""
    text = (raw or "").strip().lower()
    if not text:
        return None
    if text not in PLATFORMS:
        raise ValueError("Неизвестная платформа")
    return text


def signal_keys(activity: str | None, film_keys: tuple[str, ...]) -> tuple[str, ...]:
    """The signals this kind of room speaks: a game's own, or a film's."""
    return GAME_SIGNAL_KEYS if is_play(activity) else film_keys


def empty_tally() -> dict[str, int]:
    return {key: 0 for key in ROUND_KEYS}


def tally(keys: list[str | None]) -> dict[str, int]:
    """Counts of each kind of round from the `emoji` fields of round events.
    Anything that isn't a round key is ignored; every key is always present."""
    out = empty_tally()
    for key in keys:
        if key in out:
            out[key] += 1
    return out


def everyone_ready(flags: list[bool]) -> bool:
    """`flags` is one entry per person who is in the room right now. True
    when there is somebody and all of them are ready — what the room shows
    as "все готовы"."""
    return bool(flags) and all(flags)
