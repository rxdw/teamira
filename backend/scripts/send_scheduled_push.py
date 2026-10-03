#!/usr/bin/env python3
"""Engagement pushes (streak, "on this day", the trial-ending series in
app/trial.py, and the subscription pair in app/subscription.py) this app
has no request/response moment to hang off of — everything else in app/push.py fires from inside a request
(a match, a friend's log, a level-up); these two fire on a clock instead,
so they live here rather than as another BackgroundTasks call. Same
"a cron job, not an in-process scheduler" choice as
scripts/purge_deleted_accounts.py — see that script's own docstring for
why: a container that stops restarting is a container that quietly stops
doing this too, less obviously than a purge job going quiet, but the same
underlying reasoning applies.

Meant to run roughly hourly:

    0 * * * *  cd /app && python scripts/send_scheduled_push.py

Each run:
  1. **Streak reminder** — anyone whose local time (per their most-
     recently-seen device's self-reported IANA timezone; see
     models.PushToken.timezone) currently falls in the evening window
     (19:00-21:59 local by default), who hasn't logged anything yet
     today, and whose streak going into today was already at least 2
     days, gets nudged before it breaks.
  2. **"On this day" memory** — anyone with a diary entry from exactly
     N years ago today (any N >= 1; the highest-rated one if there's a
     choice) gets shown it, in the same evening window.

Neither fires for a device with no reported timezone at all (an older
client build, or someone who's never opened the app since this field was
added) — see _users_in_evening_window: there's no fallback UTC-hour
guess, because guessing wrong means a push at 4am local time, which is
worse than not sending one.

Both are guarded against a double-send within the same UTC day via
models.PushLog (see _already_sent_today) — safe to run this every hour
even though most users' evening window only lasts ~3 of them; the
job has no memory of its own between runs otherwise (this app has no
in-process scheduler — see app/push.py's own module docstring).

    --dry-run              list who would be notified and why; sends nothing
    --evening-start HOUR   local hour the window opens (default 19)
    --evening-end HOUR     local hour the window closes, exclusive (default 22)
"""

import argparse
import logging
import os
import sys
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from sqlalchemy import func  # noqa: E402

from app import models, push, subscription, trial  # noqa: E402
from app.database import SessionLocal  # noqa: E402
from app.streaks import current_streak, logged_today  # noqa: E402

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("send_scheduled_push")


def _ru_years(n: int) -> str:
    """Grammatically correct Russian for "N years" — год/года/лет,
    including the 11-14 exception (одиннадцать лет, not *одиннадцать
    года). app/ru_morph.py handles noun normalization, not count
    agreement, so there's no existing helper for this specific rule to
    reuse."""
    if 11 <= n % 100 <= 14:
        word = "лет"
    elif n % 10 == 1:
        word = "год"
    elif 2 <= n % 10 <= 4:
        word = "года"
    else:
        word = "лет"
    return f"{n} {word}"


def _already_sent_today(db, user_id: str, category: str) -> bool:
    today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    return (
        db.query(models.PushLog)
        .filter(
            models.PushLog.user_id == user_id,
            models.PushLog.category == category,
            models.PushLog.created_at >= today_start,
        )
        .first()
        is not None
    )


def _users_in_evening_window(db, start_hour: int, end_hour: int):
    """Yields (user, local_now) once per *user* — not per device — for
    everyone with at least one push token reporting a timezone that
    currently puts them in the evening window. A user with several
    devices reporting different timezones (travel since the last app
    open, most plausibly) is read from whichever token was seen most
    recently, on the theory that the phone in someone's pocket right now
    is a better guess than whichever device they registered first."""
    tokens = (
        db.query(models.PushToken)
        .filter(models.PushToken.timezone.isnot(None))
        .order_by(models.PushToken.user_id, models.PushToken.last_seen_at.desc())
        .all()
    )
    now_utc = datetime.now(timezone.utc)
    seen_users = set()
    for t in tokens:
        if t.user_id in seen_users:
            continue
        seen_users.add(t.user_id)
        try:
            local_now = now_utc.astimezone(ZoneInfo(t.timezone))
        except Exception:
            logger.warning("push token %s has an unrecognized timezone %r", t.id, t.timezone)
            continue
        if start_hour <= local_now.hour < end_hour:
            user = db.query(models.User).filter(models.User.id == t.user_id).first()
            if user is not None and user.deleted_at is None:
                yield user, local_now


def send_streak_reminders(db, start_hour: int, end_hour: int, dry_run: bool) -> int:
    sent = 0
    for user, local_now in _users_in_evening_window(db, start_hour, end_hour):
        if _already_sent_today(db, user.id, push.PushCategory.STREAK_REMINDERS.value):
            continue
        if logged_today(db, user.id):
            continue
        # `as_of` is the person's *local* date, not UTC's — someone whose
        # local evening it is but whose UTC date already rolled over
        # needs their streak read as of the day they're actually in
        # right now, or a real streak reads as already-broken for
        # several hours around the UTC boundary depending how far from
        # UTC they are.
        streak = current_streak(db, user.id, as_of=local_now.date())
        if streak < 2:
            continue
        if dry_run:
            logger.info("[dry-run] streak reminder -> %s (streak=%d)", user.username, streak)
            sent += 1
            continue
        n = push.push_service.send_to_user(
            db, user, push.PushCategory.STREAK_REMINDERS,
            title=f"Серия {streak} дней под угрозой 🔥",
            body="Отметьте что-нибудь сегодня, чтобы не потерять серию",
            data={"type": "streak_reminder", "streak": streak},
        )
        if n:
            sent += 1
    return sent


def send_memories(db, start_hour: int, end_hour: int, dry_run: bool) -> int:
    sent = 0
    for user, local_now in _users_in_evening_window(db, start_hour, end_hour):
        if _already_sent_today(db, user.id, push.PushCategory.MEMORIES.value):
            continue
        today = local_now.date()
        candidates = (
            db.query(models.DiaryEntry)
            .filter(
                models.DiaryEntry.user_id == user.id,
                func.extract("month", models.DiaryEntry.watched_at) == today.month,
                func.extract("day", models.DiaryEntry.watched_at) == today.day,
                func.extract("year", models.DiaryEntry.watched_at) < today.year,
            )
            .order_by(models.DiaryEntry.rating.desc().nullslast())
            .all()
        )
        if not candidates:
            continue
        entry = candidates[0]
        years_ago = today.year - entry.watched_at.year
        title_name = entry.title_ru or entry.title_en or "что-то"
        if dry_run:
            logger.info("[dry-run] memory -> %s (%s, %s)", user.username, title_name, _ru_years(years_ago))
            sent += 1
            continue
        n = push.push_service.send_to_user(
            db, user, push.PushCategory.MEMORIES,
            title=f"{_ru_years(years_ago)} назад сегодня 🎬",
            body=f"Вы смотрели «{title_name}» — пересмотреть?",
            data={
                "type": "memory", "media_id": entry.media_id, "source": entry.source,
                "media_type": entry.media_type.value if hasattr(entry.media_type, "value") else entry.media_type,
                "title": title_name,
            },
        )
        if n:
            sent += 1
    return sent


def _sent_today_with_title(db, user_id: str, category: str, title: str) -> bool:
    """Like _already_sent_today, but keyed by the exact title too. The
    album shares one category between its real-time pushes (a note was
    left) and these clock-driven ones, so "any album push today" would
    let a note swallow the anniversary. The titles below are distinct per
    occasion, which makes the title the natural idempotency key."""
    today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    return (
        db.query(models.PushLog)
        .filter(
            models.PushLog.user_id == user_id,
            models.PushLog.category == category,
            models.PushLog.title == title,
            models.PushLog.created_at >= today_start,
        )
        .first()
        is not None
    )


def send_pair_album_pushes(db, dry_run: bool) -> int:
    """The album's two calendar-driven moments, sent in the morning of the
    *recipient's own* day (their device's timezone, like the evening
    pushes above): the day a capsule can be opened, and an anniversary or
    a round day count. Each is sent at most once per person per day.

    Couples only — a circle of three has no album. Judged against the
    recipient's local date, not the server's, so \"today\" in the push is
    today on the phone that receives it (the album's own screens use the
    server's UTC day; on the rare day the two differ by one, the push and
    the screen disagree for a few hours, which is the lesser evil against
    a 3 a.m. push for someone in Sydney)."""
    from app import pair_album as album

    sent = 0
    for user, local_now in _users_in_evening_window(db, 8, 12):
        today = local_now.date()
        from app.routers.partner import _member_ids, get_active_link

        link = get_active_link(db, user.id)
        if link is None or len(_member_ids(link)) != 2:
            continue

        # 1. A capsule whose day it is (or that opened while nobody was
        # looking) and that this person hasn't opened yet.
        title = "Капсула ждёт вас 🕰️"
        capsules = db.query(models.PairCapsule).filter(
            models.PairCapsule.link_id == link.id, models.PairCapsule.opens_on <= today,
        ).all()
        for cap in capsules:
            opened = db.get(models.PairCapsuleRead, (cap.id, user.id)) is not None
            # Only announce it on its own day and the day after — a
            # capsule left unopened for a month is a choice, not a miss.
            if opened or (today - cap.opens_on).days > 1:
                continue
            if _sent_today_with_title(db, user.id, push.PushCategory.PAIR_ALBUM.value, title):
                break
            if dry_run:
                logger.info("[dry-run] capsule -> %s", user.username)
                sent += 1
                break
            n = push.push_service.send_to_user(
                db, user, push.PushCategory.PAIR_ALBUM, title=title,
                body="Ваша капсула времени готова — откройте её вместе",
                data={"type": "pair_album_capsule"},
            )
            if n:
                sent += 1
            break

        # 2. Anniversary / round day count.
        settings = db.get(models.PairAlbumSettings, link.id)
        if settings is None or settings.together_since is None:
            continue
        start = settings.together_since
        if album.is_anniversary_today(start, today):
            years = album.full_years(start, today)
            title = f"{_ru_years(years)} вместе 💞"
            body = "Сегодня ваша годовщина — загляните в альбом"
        else:
            milestone = album.milestone_today(start, today)
            if milestone is None:
                continue
            title = f"{album.ru_days(milestone)} вместе ✨"
            body = "Круглая дата — загляните в альбом"
        if _sent_today_with_title(db, user.id, push.PushCategory.PAIR_ALBUM.value, title):
            continue
        if dry_run:
            logger.info("[dry-run] anniversary -> %s (%s)", user.username, title)
            sent += 1
            continue
        n = push.push_service.send_to_user(
            db, user, push.PushCategory.PAIR_ALBUM, title=title, body=body,
            data={"type": "pair_album_anniversary"},
        )
        if n:
            sent += 1
    return sent


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--evening-start", type=int, default=19)
    parser.add_argument("--evening-end", type=int, default=22)
    args = parser.parse_args()

    db = SessionLocal()
    try:
        streak_sent = send_streak_reminders(db, args.evening_start, args.evening_end, args.dry_run)
        memory_sent = send_memories(db, args.evening_start, args.evening_end, args.dry_run)
        # Has its own per-stage daytime windows (app/trial.py) rather
        # than the evening window above — "your free period ends
        # tomorrow" reads best mid-day, not at 21:00.
        trial_sent = trial.send_trial_reminders(db, args.dry_run)
        # Same idea for the subscription pair (app/subscription.py): the
        # win-back offer the moment a cancelled plan runs out, and "your
        # pause is ending". Each has its own daytime window and is sent
        # at most once.
        subscription_sent = subscription.send_subscription_pushes(db, args.dry_run)
        album_sent = send_pair_album_pushes(db, args.dry_run)
        logger.info(
            "%sstreak reminders: %d, memories: %d, trial reminders: %d, subscription: %d, pair album: %d",
            "[dry-run] " if args.dry_run else "", streak_sent, memory_sent, trial_sent,
            subscription_sent, album_sent,
        )
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
