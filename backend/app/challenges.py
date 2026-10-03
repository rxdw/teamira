"""Challenges — small, dated goals that give the diary something to aim at
this week (and this year) beyond "log more things".

How this relates to the two systems that already exist and look similar:

  - Achievements (routers/profile.py::get_achievements) are *lifetime* and
    permanent: "200 films watched" is true forever once it's true. They
    never expire, never reset, and there's nothing to miss.
  - Franchise challenges on Home (routers/teamira.py) are *catalog*
    goals: finish this specific saga, in this specific order.
  - Challenges here are *periodic and personal*: they start, they end,
    and if you don't finish one it quietly goes away and a different one
    takes its place. That's the whole retention mechanic — an achievement
    you're 12% of the way toward after two years is not a reason to open
    the app tonight; "три вечера до конца недели, осталось два фильма"
    is.

Two cadences, deliberately:

  - **Weekly** (the product brief asks for weekly, not seasonal). Three
    are live at a time, Monday to Sunday, drawn deterministically from
    the pool below by ISO week number — so everyone with the same week
    gets the same three, and next week's are genuinely different without
    anyone scheduling anything. No cron job exists in this backend (see
    routers/referrals.py's note on the same constraint) and none is
    needed: the "which challenges are live" question is a pure function
    of today's date, answered at read time.
  - **Yearly**, including the "12 films from 12 countries" one. These run
    all year, are the same for everyone, and are where the bigger rewards
    sit.

Progress is recomputed from DiaryEntry on every read — never stored. See
models.ChallengeProgress for what *is* stored (completion/claim/seen) and
why those three specifically can't be derived.

Rewards are sincerity points now, same currency as everything else in the
app (see app/sincerity.py's module docstring for why the honest-acts-only
and general-activity systems merged into one) — a claim is a flat,
one-time award via app/sincerity.py::earn_challenge_claimed, scaled down
from what used to be a much larger XP number to match sincerity's own
"small, unglamorous integer" scale (weekly challenges: 3-5 points; the
yearly ones: 7-13). routers/challenges.py::claim_challenge is the only
place that ever calls earn_challenge_claimed, guarded by
ChallengeProgress.claimed_at already being unset.
"""

from __future__ import annotations

import random
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from typing import Callable, Dict, List, Optional

from sqlalchemy.orm import Session

from app import models

# ---------------------------------------------------------------------------
# Periods
# ---------------------------------------------------------------------------


def week_bounds(today: Optional[date] = None) -> tuple[date, date]:
    """Monday..Sunday containing `today`. Weeks start Monday because the
    whole app's audience is RU/EU-facing; an off-by-one day here would
    show "3 дня осталось" on what people read as the last day."""
    today = today or date.today()
    monday = today - timedelta(days=today.weekday())
    return monday, monday + timedelta(days=6)


def week_period_key(today: Optional[date] = None) -> str:
    today = today or date.today()
    iso = today.isocalendar()
    return f"{iso.year}-W{iso.week:02d}"


def year_period_key(today: Optional[date] = None) -> str:
    return str((today or date.today()).year)


def period_key(cadence: str, today: Optional[date] = None) -> str:
    return week_period_key(today) if cadence == "weekly" else year_period_key(today)


def period_bounds(cadence: str, today: Optional[date] = None) -> tuple[datetime, datetime]:
    """Half-open [start, end) in UTC-aware datetimes, matching how
    DiaryEntry.watched_at is now stored (see app/models.py —
    DateTime(timezone=True) — and the migration that backfilled existing
    rows to UTC). Used to bound a SQLAlchemy filter against that column
    (see _rows_for_period below); a naive boundary here would still
    "work" syntactically against an aware column, but Postgres would
    interpret it in the connection's own session timezone rather than
    UTC, silently shifting the week/year boundary by however many hours
    that happens to be."""
    today = today or date.today()
    if cadence == "weekly":
        start, last = week_bounds(today)
        return (
            datetime(start.year, start.month, start.day, tzinfo=timezone.utc),
            datetime(last.year, last.month, last.day, tzinfo=timezone.utc) + timedelta(days=1),
        )
    return (
        datetime(today.year, 1, 1, tzinfo=timezone.utc),
        datetime(today.year + 1, 1, 1, tzinfo=timezone.utc),
    )


# ---------------------------------------------------------------------------
# Catalog
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Challenge:
    """One challenge definition. `measure` gets the person's diary rows
    for the relevant period and returns how far along they are; `target`
    is what counts as done.

    `icon_key` is a small fixed vocabulary the client maps to its own
    icon set, exactly like AchievementOut.icon_key already does — no
    asset paths or icon names cross the wire.
    """
    id: str
    cadence: str                  # "weekly" | "yearly"
    icon_key: str
    title_ru: str
    title_en: str
    caption_ru: str
    caption_en: str
    target: int
    points: int
    measure: Callable[[List[models.DiaryEntry]], int] = field(repr=False)
    # Shown on the card as "как это считается" — the honest version of
    # the rule, so nobody has to guess why a logged evening didn't count.
    rule_ru: str = ""
    rule_en: str = ""


def _distinct(rows: List[models.DiaryEntry], key: Callable[[models.DiaryEntry], Optional[str]]) -> int:
    seen = set()
    for r in rows:
        value = key(r)
        if value:
            seen.add(value.strip().lower())
    return len(seen)


def _count(rows: List[models.DiaryEntry], pred: Callable[[models.DiaryEntry], bool]) -> int:
    return sum(1 for r in rows if pred(r))


def _genres(row: models.DiaryEntry) -> List[str]:
    return [g for g in (row.genres or []) if g]


def _distinct_genres(rows: List[models.DiaryEntry]) -> int:
    seen = set()
    for r in rows:
        for g in _genres(r):
            seen.add(g.strip().lower())
    return len(seen)


def _distinct_days(rows: List[models.DiaryEntry]) -> int:
    return len({r.watched_at.date() for r in rows if r.watched_at})


# --- Weekly pool -----------------------------------------------------------
# Kept broad on purpose: a pool of eight means the three live this week
# genuinely differ from last week's, and nobody sees the same trio twice
# in a row. Targets are small — a weekly challenge that needs five films
# is a weekly challenge most people fail, and a challenge you reliably
# fail stops being a reason to open the app after about two weeks.

_WEEKLY: List[Challenge] = [
    Challenge(
        id="w_three_evenings",
        cadence="weekly",
        icon_key="calendar",
        title_ru="три вечера",
        title_en="three evenings",
        caption_ru="запиши что-нибудь в три разных дня",
        caption_en="log something on three different days",
        rule_ru="считаются разные календарные дни, а не количество записей",
        rule_en="counts distinct calendar days, not number of entries",
        target=3,
        points=4,
        measure=_distinct_days,
    ),
    Challenge(
        id="w_two_genres",
        cadence="weekly",
        icon_key="palette",
        title_ru="смена настроения",
        title_en="change of mood",
        caption_ru="посмотри что-то из трёх разных жанров",
        caption_en="watch something from three different genres",
        rule_ru="жанры берутся из карточки тайтла на момент записи",
        rule_en="genres come from the title as it was when you logged it",
        target=3,
        points=4,
        measure=_distinct_genres,
    ),
    Challenge(
        id="w_short_evening",
        cadence="weekly",
        icon_key="clock",
        title_ru="короткий вечер",
        title_en="a short evening",
        caption_ru="два вечера короче 100 минут",
        caption_en="two evenings under 100 minutes",
        rule_ru="нужна известная длительность — у игр и книг её нет",
        rule_en="needs a known runtime — games and books have none",
        target=2,
        points=3,
        measure=lambda rows: _count(
            rows, lambda r: r.runtime_minutes is not None and 0 < r.runtime_minutes <= 100
        ),
    ),
    Challenge(
        id="w_rate_honestly",
        cadence="weekly",
        icon_key="heart",
        title_ru="не молчи",
        title_en="say something",
        caption_ru="поставь оценку трём вечерам",
        caption_en="rate three evenings",
        rule_ru="оценка, поставленная позже при редактировании, тоже считается",
        rule_en="a rating added later by editing the entry counts too",
        target=3,
        points=3,
        measure=lambda rows: _count(rows, lambda r: r.rating is not None),
    ),
    Challenge(
        id="w_write_note",
        cadence="weekly",
        icon_key="pen",
        title_ru="пара слов",
        title_en="a few words",
        caption_ru="оставь заметку к двум вечерам",
        caption_en="leave a note on two evenings",
        rule_ru="засчитывается заметка длиннее 20 символов",
        rule_en="a note longer than 20 characters counts",
        target=2,
        points=5,
        measure=lambda rows: _count(rows, lambda r: bool(r.note) and len(r.note.strip()) > 20),
    ),
    Challenge(
        id="w_old_film",
        cadence="weekly",
        icon_key="film",
        title_ru="из архива",
        title_en="from the archive",
        caption_ru="посмотри что-то старше 2000 года",
        caption_en="watch something made before 2000",
        rule_ru="по году выпуска из карточки тайтла",
        rule_en="by the title's release year",
        target=1,
        points=4,
        measure=lambda rows: _count(rows, lambda r: r.year is not None and r.year < 2000),
    ),
    Challenge(
        id="w_together",
        cadence="weekly",
        icon_key="users",
        title_ru="не в одиночку",
        title_en="not alone",
        caption_ru="проведи вечер с кем-то",
        caption_en="spend an evening with someone",
        rule_ru="запись с отметкой «смотрели вместе» или из совместного просмотра",
        rule_en="an entry marked 'watched with' or logged from co-viewing",
        target=1,
        points=4,
        measure=lambda rows: _count(
            rows, lambda r: bool(r.watched_together) or bool(r.watched_with_username)
        ),
    ),
    Challenge(
        id="w_two_media_types",
        cadence="weekly",
        icon_key="shuffle",
        title_ru="не только кино",
        title_en="not only films",
        caption_ru="запиши два разных типа: фильм, игра, книга, сериал…",
        caption_en="log two different kinds: film, game, book, series…",
        rule_ru="считаются разные типы медиа за неделю",
        rule_en="counts distinct media types this week",
        target=2,
        points=4,
        measure=lambda rows: _distinct(rows, lambda r: r.media_type.value if r.media_type else None),
    ),
]

# --- Yearly pool -----------------------------------------------------------
# All of these run at once, all year. Bigger targets, bigger XP, and the
# one the brief names explicitly sits at the top.

_YEARLY: List[Challenge] = [
    Challenge(
        id="y_twelve_countries",
        cadence="yearly",
        icon_key="globe",
        title_ru="12 стран за год",
        title_en="12 countries in a year",
        caption_ru="фильмы и сериалы из двенадцати разных стран",
        caption_en="films and series from twelve different countries",
        rule_ru=(
            "страна берётся из карточки тайтла. если у записи страна неизвестна, "
            "она не считается — открой страницу тайтла один раз, и она подтянется."
        ),
        rule_en=(
            "country comes from the title. an entry with no known country doesn't "
            "count — open the title page once and it gets filled in."
        ),
        target=12,
        points=13,
        measure=lambda rows: _distinct(rows, lambda r: r.country),
    ),
    Challenge(
        id="y_fifty_evenings",
        cadence="yearly",
        icon_key="calendar",
        title_ru="пятьдесят вечеров",
        title_en="fifty evenings",
        caption_ru="пятьдесят записанных вечеров за год",
        caption_en="fifty logged evenings this year",
        rule_ru="каждая запись в дневнике — один вечер",
        rule_en="each diary entry is one evening",
        target=50,
        points=10,
        measure=len,
    ),
    Challenge(
        id="y_ten_genres",
        cadence="yearly",
        icon_key="palette",
        title_ru="широкий вкус",
        title_en="wide taste",
        caption_ru="десять разных жанров за год",
        caption_en="ten different genres this year",
        rule_ru="жанры со всех записей года, без повторов",
        rule_en="genres across the whole year, deduplicated",
        target=10,
        points=8,
        measure=_distinct_genres,
    ),
    Challenge(
        id="y_five_decades",
        cadence="yearly",
        icon_key="film",
        title_ru="пять десятилетий",
        title_en="five decades",
        caption_ru="кино из пяти разных десятилетий",
        caption_en="films from five different decades",
        rule_ru="по году выпуска: 1970-е, 1980-е и так далее",
        rule_en="by release year: the 1970s, the 1980s, and so on",
        target=5,
        points=9,
        measure=lambda rows: _distinct(
            rows, lambda r: str(r.year // 10) if r.year else None
        ),
    ),
    Challenge(
        id="y_twelve_directors",
        cadence="yearly",
        icon_key="pen",
        title_ru="двенадцать режиссёров",
        title_en="twelve directors",
        caption_ru="фильмы двенадцати разных режиссёров",
        caption_en="films by twelve different directors",
        rule_ru="режиссёр известен только если ты открывал страницу тайтла",
        rule_en="the director is only known if you opened the title page",
        target=12,
        points=9,
        measure=lambda rows: _distinct(rows, lambda r: r.director),
    ),
    Challenge(
        id="y_twenty_together",
        cadence="yearly",
        icon_key="users",
        title_ru="двадцать вечеров вдвоём",
        title_en="twenty evenings together",
        caption_ru="двадцать вечеров, проведённых не в одиночку",
        caption_en="twenty evenings that weren't spent alone",
        rule_ru="совместные просмотры и записи с отметкой «смотрели вместе»",
        rule_en="co-viewing entries and anything marked 'watched with'",
        target=20,
        points=11,
        measure=lambda rows: _count(
            rows, lambda r: bool(r.watched_together) or bool(r.watched_with_username)
        ),
    ),
]

BY_ID: Dict[str, Challenge] = {c.id: c for c in (_WEEKLY + _YEARLY)}

# How many weeklies run simultaneously. Three is the most that fits the
# Home card without it becoming its own screen, and enough that a person
# who can't do one of them still has two live.
WEEKLY_LIVE_COUNT = 3


def live_weekly(today: Optional[date] = None) -> List[Challenge]:
    """This week's three, chosen deterministically from the pool by ISO
    week so the answer doesn't depend on who's asking or when in the week
    they ask. Seeded with the year too, so the same week number in two
    different years isn't the identical trio.

    `random.Random(seed)` rather than a hand-written hash: the point is a
    stable shuffle, and a locally-seeded Random instance never touches
    the global RNG that other modules (routers/partner.py's code
    generator) rely on.
    """
    today = today or date.today()
    iso = today.isocalendar()
    rng = random.Random(iso.year * 100 + iso.week)
    pool = list(_WEEKLY)
    rng.shuffle(pool)
    return pool[:WEEKLY_LIVE_COUNT]


def live_yearly(today: Optional[date] = None) -> List[Challenge]:
    return list(_YEARLY)


def live_challenges(today: Optional[date] = None) -> List[Challenge]:
    return live_weekly(today) + live_yearly(today)


# ---------------------------------------------------------------------------
# Evaluation
# ---------------------------------------------------------------------------


@dataclass
class ChallengeState:
    challenge: Challenge
    period_key: str
    current: int
    completed: bool
    completed_at: Optional[datetime]
    claimed: bool
    needs_announcement: bool
    days_left: Optional[int]


def _rows_for_period(db: Session, user_id: str, cadence: str, today: date) -> List[models.DiaryEntry]:
    start, end = period_bounds(cadence, today)
    return (
        db.query(models.DiaryEntry)
        .filter(
            models.DiaryEntry.user_id == user_id,
            models.DiaryEntry.watched_at >= start,
            models.DiaryEntry.watched_at < end,
        )
        .all()
    )


def evaluate(db: Session, user_id: str, today: Optional[date] = None) -> List[ChallengeState]:
    """Every live challenge with this person's progress in it, and the
    stored completion/claim state alongside.

    Writes (but does not commit) a ChallengeProgress row the first time a
    challenge crosses its target — that timestamp has to be captured when
    it happens, since deleting a diary entry afterwards would otherwise
    silently un-complete something already celebrated. The caller commits;
    same convention as routers/diary.py::log_watched.
    """
    today = today or date.today()
    # One query per cadence, not per challenge — eight weeklies all read
    # the same week's rows.
    rows_by_cadence = {
        "weekly": _rows_for_period(db, user_id, "weekly", today),
        "yearly": _rows_for_period(db, user_id, "yearly", today),
    }

    live = live_challenges(today)
    keys = {(c.id, period_key(c.cadence, today)) for c in live}
    stored = {
        (p.challenge_id, p.period_key): p
        for p in db.query(models.ChallengeProgress)
        .filter(models.ChallengeProgress.user_id == user_id)
        .all()
        if (p.challenge_id, p.period_key) in keys
    }

    _, week_end = week_bounds(today)
    states: List[ChallengeState] = []
    for c in live:
        pkey = period_key(c.cadence, today)
        current = min(c.measure(rows_by_cadence[c.cadence]), c.target)
        row = stored.get((c.id, pkey))
        just_completed = current >= c.target

        if just_completed and row is None:
            row = models.ChallengeProgress(
                user_id=user_id,
                challenge_id=c.id,
                period_key=pkey,
                completed_at=datetime.now(timezone.utc),
            )
            db.add(row)
            stored[(c.id, pkey)] = row
        elif just_completed and row is not None and row.completed_at is None:
            row.completed_at = datetime.now(timezone.utc)

        completed_at = row.completed_at if row is not None else None
        completed = completed_at is not None
        claimed = row is not None and row.claimed_at is not None

        if c.cadence == "weekly":
            days_left = max(0, (week_end - today).days)
        else:
            days_left = max(0, (date(today.year, 12, 31) - today).days)

        states.append(ChallengeState(
            challenge=c,
            period_key=pkey,
            current=current,
            completed=completed,
            completed_at=completed_at,
            claimed=claimed,
            # The Home banner condition: finished, and the client hasn't
            # acknowledged showing it yet.
            needs_announcement=completed and (row is not None and row.seen_at is None),
            days_left=days_left,
        ))
    return states
