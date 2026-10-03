"""Streak — consecutive calendar days (UTC) with at least one
ActivityEvent, ending today or yesterday ("yesterday" so a streak
doesn't read as broken the moment midnight UTC passes and someone just
hasn't logged *today* yet — see current_streak's own docstring).

A simple, honest read of real event dates every time it's asked, never a
stored counter that could drift out of sync with what actually
happened — same reasoning as profile.py::compute_level_for_user for
level. Originally computed inline inside
profile.py::get_wrapped/get_achievements; pulled out here once
scripts/send_scheduled_push.py needed the exact same definition for its
"your streak ends tonight" reminder — one implementation of what a
streak *is*, used by both the read-only stat and the thing that nudges
someone to keep it alive.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app import models


def current_streak(db: Session, user_id: str, as_of: date | None = None) -> int:
    """Consecutive days, ending at `as_of` (default: today, UTC) or the
    day before it if `as_of` itself has no event yet — logging today
    doesn't happen at midnight for most people, so "today hasn't
    happened yet" is treated as "the streak's last completed day is
    still yesterday," not as day zero."""
    as_of = as_of or datetime.now(timezone.utc).date()
    event_dates = {
        e.created_at.date()
        for e in db.query(models.ActivityEvent).filter(models.ActivityEvent.user_id == user_id).all()
        if e.created_at
    }
    cursor = as_of
    if cursor not in event_dates:
        cursor -= timedelta(days=1)
    streak = 0
    while cursor in event_dates:
        streak += 1
        cursor -= timedelta(days=1)
    return streak


def logged_today(db: Session, user_id: str, as_of: date | None = None) -> bool:
    """Whether `user_id` already has an ActivityEvent dated `as_of`
    (default: today, UTC). Split out from current_streak rather than
    inferring it from "did the streak count include today" — a
    brand-new user with a 0-day streak and someone who logged today for
    the first time in weeks both have a 0-or-1 streak either way; this
    answers the one question scripts/send_scheduled_push.py's reminder
    actually needs directly ("have they already done tonight's thing")
    instead of reconstructing it from a length."""
    as_of = as_of or datetime.now(timezone.utc).date()
    return (
        db.query(models.ActivityEvent)
        .filter(models.ActivityEvent.user_id == user_id)
        .filter(models.ActivityEvent.created_at >= datetime(as_of.year, as_of.month, as_of.day, tzinfo=timezone.utc))
        .filter(
            models.ActivityEvent.created_at
            < datetime(as_of.year, as_of.month, as_of.day, tzinfo=timezone.utc) + timedelta(days=1)
        )
        .first()
        is not None
    )
