"""Rules for the pair album ("Альбом пары") that don't need a request.

Kept apart from routers/pair_album.py so the same arithmetic serves the
API, the scheduled push script and the tests without any of them
importing a router — same reasoning as app/streaks.py.

The design in one paragraph
---------------------------
A couple leaves each other *notes* on a title's card **before** they watch
it (each has their own, one per person per viewing). Notes stay sealed —
the server never returns the other person's text — until that evening is
marked watched, at which point every pending note on that title flips to
revealed for both. Alongside that: *capsules* (letters for two, sealed on
submit, unreadable by anyone until a date) and the *date the two of them
started*, which powers the anniversary screen.

Two principles decide most edge cases and are worth stating once:

1. **Unlimited writing is premium, reading never is.** A circle where
   either member has premium (the same rule the co-viewing queue uses)
   writes notes and capsules without a ceiling and can set the date. A
   free circle gets a *taste* — FREE_NOTES_PER_AUTHOR notes each and
   FREE_CAPSULES_PER_LINK capsule between them — because the album is a
   habit (leaving each other notes before an evening), and a habit can't
   form behind a wall: the first note has to cost nothing for the second
   to feel like something worth paying for. Once something exists it
   stays readable forever, including after premium lapses — charging to
   read your own memories is the wrong shape (the same argument
   routers/partner.py makes for CO_VIEW_FREE_LIMIT), and a capsule that
   refused to open because a subscription ended would be a betrayal of
   the one thing it promises. The partner's letter into a capsule that
   already exists is never gated either: the capsule is the promise, and
   half of it can't be locked.

2. **The server owns time.** Whether a capsule is open, and whether a
   date is "in the future", is judged against the server's UTC date. The
   client's clock is only ever used to *display* a countdown.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from typing import List as TypingList

from sqlalchemy import func
from sqlalchemy.orm import Session

from app import models

# --- notes ---------------------------------------------------------------

NOTE_MAX_CHARS = 400
# A sticky note, not a letter — the length is the design. Letters are what
# capsules are for.

# Unrevealed notes one person may have outstanding at once. Nobody plans
# thirty evenings ahead and writes to each; this only stops a script.
MAX_PENDING_NOTES_PER_AUTHOR = 30

# The free taste of the album, per `app/pair_album.py`'s principle 1.
#
# Notes are counted *per person* and by what exists, not by what was ever
# written: a sealed note taken back gives its slot back (it was a draft,
# never read), a revealed note keeps it for good (it's in the book now).
# Editing a note you already left never costs a slot — only creating one.
# Per person rather than per couple so that both halves get to form the
# habit; a couple-wide count would let whoever is keener use up both.
FREE_NOTES_PER_AUTHOR = 3

# Capsules are counted per couple, opened ones included. Counting only the
# sealed ones would make the limit a queue depth, and since a capsule can't
# be shorter than CAPSULE_MIN_DAYS that would hand out one free capsule a
# month for ever — i.e. no limit at all. A capsule taken back (only
# possible while the partner hasn't written into it) gives its slot back.
FREE_CAPSULES_PER_LINK = 1

# What a recipient can answer a revealed note with. A closed set keeps the
# column trivially safe and the UI a single row of buttons.
ALLOWED_REACTIONS = ("❤️", "😂", "🥹", "🔥", "👏")

# What an author can tag a note with. Purely decorative; also a closed set.
ALLOWED_MOODS = ("💌", "😘", "🍿", "🥰", "😴", "🌙", "✨", "🤭")

# --- capsules ------------------------------------------------------------

CAPSULE_MIN_DAYS = 30            # shorter than a month isn't a capsule
CAPSULE_MAX_DAYS = 3650          # ten years
CAPSULE_LETTER_MAX_CHARS = 4000
CAPSULE_TITLE_MAX_CHARS = 60
MAX_SEALED_CAPSULES_PER_LINK = 3  # unopened ones at once

# --- anniversary ---------------------------------------------------------

# Day counts worth a celebration. Yearly anniversaries are handled by
# calendar, not by this list (a year is 365 *or* 366 days).
DAY_MILESTONES = (
    100, 200, 300, 500, 777, 1000, 1500, 2000, 2500, 3000, 4000, 5000, 7500, 10000,
)

TOGETHER_SINCE_MAX_YEARS_BACK = 80


def utc_today() -> date:
    """The server's idea of "today" — the only clock capsules answer to.
    A function rather than `date.today()` inline so tests can move it."""
    return datetime.now(timezone.utc).date()


def capsule_is_open(opens_on: date, today: date | None = None) -> bool:
    return (today or utc_today()) >= opens_on


def days_until(target: date, today: date | None = None) -> int:
    return (target - (today or utc_today())).days


def valid_opens_on(opens_on: date, today: date | None = None) -> str | None:
    """None if `opens_on` is an acceptable capsule date, else a message
    fit to show as-is."""
    d = days_until(opens_on, today)
    if d < CAPSULE_MIN_DAYS:
        return f"Капсулу можно открыть не раньше чем через {CAPSULE_MIN_DAYS} дней"
    if d > CAPSULE_MAX_DAYS:
        return "Капсулу можно запечатать не дальше чем на 10 лет"
    return None


def valid_together_since(d: date, today: date | None = None) -> str | None:
    t = today or utc_today()
    if d > t:
        return "Дата не может быть в будущем"
    try:
        earliest = t.replace(year=t.year - TOGETHER_SINCE_MAX_YEARS_BACK)
    except ValueError:  # Feb 29 → the same day 80 years ago may not exist
        earliest = t.replace(year=t.year - TOGETHER_SINCE_MAX_YEARS_BACK, day=28)
    if d < earliest:
        return "Слишком давняя дата"
    return None


def _anniversary_in_year(start: date, year: int) -> date:
    """The day the anniversary falls on in `year`. A Feb 29 start
    celebrates on Feb 28 in common years — the day before, so it always
    lands inside the month it belongs to."""
    try:
        return start.replace(year=year)
    except ValueError:
        return date(year, 2, 28)


def full_years(start: date, today: date) -> int:
    """Whole years elapsed, by calendar (not by 365-day blocks)."""
    years = today.year - start.year
    if today < _anniversary_in_year(start, today.year):
        years -= 1
    return max(years, 0)


def next_anniversary(start: date, today: date) -> date:
    """The next anniversary on or after `today` — if today *is* one, it's
    today, because the anniversary screen celebrates on the day itself
    rather than skipping past it. Day one isn't an anniversary, so a
    start date of today points at next year."""
    candidate = _anniversary_in_year(start, today.year)
    if candidate < today or candidate.year <= start.year:
        candidate = _anniversary_in_year(start, today.year + 1)
    return candidate


def is_anniversary_today(start: date, today: date) -> bool:
    return today.year > start.year and _anniversary_in_year(start, today.year) == today


def days_together(start: date, today: date) -> int:
    """Days since `start`, counting the first day as day 1 — "we've been
    together 100 days" on the hundredth calendar day, which is how
    everyone actually counts it."""
    return (today - start).days + 1


def milestone_today(start: date, today: date) -> int | None:
    n = days_together(start, today)
    return n if n in DAY_MILESTONES else None


def next_day_milestone(start: date, today: date) -> tuple[int, date] | None:
    n = days_together(start, today)
    for m in DAY_MILESTONES:
        if m > n:
            return m, start + timedelta(days=m - 1)
    return None


def ru_plural(n: int, one: str, few: str, many: str) -> str:
    """"1 год / 2 года / 5 лет" — the 11-14 exception included."""
    n = abs(n)
    if 11 <= n % 100 <= 14:
        return many
    if n % 10 == 1:
        return one
    if 2 <= n % 10 <= 4:
        return few
    return many


def ru_years(n: int) -> str:
    return f"{n} {ru_plural(n, 'год', 'года', 'лет')}"


def ru_days(n: int) -> str:
    return f"{n} {ru_plural(n, 'день', 'дня', 'дней')}"


# --- free-tier arithmetic (needs a session, still no request) ------------------

def notes_used(db: Session, link_id: str, author_id: str) -> int:
    """Notes `author_id` currently has in this album, sealed or revealed."""
    return (
        db.query(models.PairNote)
        .filter(models.PairNote.link_id == link_id, models.PairNote.author_id == author_id)
        .count()
    )


def capsules_used(db: Session, link_id: str) -> int:
    """Capsules this couple currently has, opened ones included."""
    return db.query(models.PairCapsule).filter(models.PairCapsule.link_id == link_id).count()


# --- note rounds & reveal (need a session, still no request) -----------------

def current_round(db: Session, link_id: str, source: str, media_id: str) -> int:
    """The viewing a new note belongs to. Moves on only once a round has
    been revealed, so re-planning a title after watching it starts a fresh
    sealed round instead of touching notes that were already read."""
    last = (
        db.query(func.max(models.PairNote.round))
        .filter(
            models.PairNote.link_id == link_id,
            models.PairNote.source == source,
            models.PairNote.media_id == media_id,
            models.PairNote.revealed_at.isnot(None),
        )
        .scalar()
    )
    return (last or 0) + 1


def reveal_notes(
    db: Session, link: models.PartnerLink, entry: models.CoViewEntry,
) -> TypingList[models.PairNote]:
    """Opens every sealed note on this title for both sides. Called from
    partner.py::mark_co_viewing_watched inside its own transaction — it
    only flushes, the caller commits — and returns the rows it opened so
    the caller can tell who to notify."""
    rows = (
        db.query(models.PairNote)
        .filter(
            models.PairNote.link_id == link.id,
            models.PairNote.source == entry.source,
            models.PairNote.media_id == entry.media_id,
            models.PairNote.revealed_at.is_(None),
        )
        .all()
    )
    if not rows:
        return []
    now = datetime.now(timezone.utc)
    evening = (entry.watched_at or now).date()
    for row in rows:
        row.revealed_at = now
        row.evening_on = evening
    db.flush()
    return rows
