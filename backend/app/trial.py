"""The "your free period is ending" reminder series.

The trial here has no card behind it (routers/premium.py::start_trial):
nothing converts on its own when it runs out, so conversion has to be
*earned* at the moment it ends. That is what this module is for — three
honest, well-timed touches instead of one loud one:

  stage 1  "ends soon"    ~1-1.5 days before the end, daytime
  stage 2  "last hours"   the final ~12 hours, daytime / evening
  stage 3  "it ended"     once, the day after — records and lists are
                          untouched, only the limits are back

After stage 3 nothing else is sent, ever. The client shows the same
moments in-app (a countdown on Home from 48h out, and the paywall opens
once per stage; see mobile PremiumService.trialNudge), so someone who
has push off still gets the series.

Everything time-related is decided by `due_stage()` — a pure function of
(stage already sent, time left, the person's local hour) — so the whole
schedule is testable without a clock, a database or Firebase. The
sender at the bottom is the thin part; scripts/send_scheduled_push.py
calls it from the existing hourly cron.

"End of the trial" is `premium_expires_at`, not `trial_started_at +
TRIAL_DAYS`: referral days stack on the same timestamp (see
referrals.grant_premium_days), and what matters to the person is when
premium actually stops.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Optional
from zoneinfo import ZoneInfo

from sqlalchemy.orm import Session

from app.bi import Bi
from app import models, push

logger = logging.getLogger(__name__)

STAGE_NONE = 0
STAGE_ENDS_SOON = 1
STAGE_LAST_HOURS = 2
STAGE_ENDED = 3

# Stage 1 fires in the first local-daytime hour after the trial gets
# within 40h of its end, as long as more than 16h are left. The window is
# 24h wide, so it always contains a daytime hour whatever the person's
# timezone is; 16h is what keeps it clear of stage 2's 12h with a
# few hours to spare between the two pushes.
ENDS_SOON_MAX_LEFT = timedelta(hours=40)
ENDS_SOON_MIN_LEFT = timedelta(hours=16)
ENDS_SOON_HOURS = range(10, 22)

# Stage 2: the last 12 hours, 08:00-22:59 local. A 12h span always
# contains at least three of those hours, so it can't be skipped by the
# end landing at an awkward time of night.
LAST_HOURS_MAX_LEFT = timedelta(hours=12)
LAST_HOURS_HOURS = range(8, 23)

# Stage 3: from one hour after the end to two days after, daytime.
ENDED_MIN_AGO = timedelta(hours=1)
ENDED_MAX_AGO = timedelta(hours=48)
ENDED_HOURS = range(10, 22)


def due_stage(stage: int, time_left: timedelta, local_hour: int) -> Optional[int]:
    """Which reminder (1/2/3) should go out right now for someone whose
    series is at `stage`, whose premium ends in `time_left` (negative =
    already ended), and whose local clock reads `local_hour` — or None.

    The later stage wins when both apply, and a skipped stage is not
    made up for afterwards: someone who first becomes reachable with
    five hours left gets the "last hours" message, not two in a row."""
    if time_left > timedelta(0):
        if stage < STAGE_LAST_HOURS and time_left <= LAST_HOURS_MAX_LEFT and local_hour in LAST_HOURS_HOURS:
            return STAGE_LAST_HOURS
        if (
            stage < STAGE_ENDS_SOON
            and ENDS_SOON_MIN_LEFT < time_left <= ENDS_SOON_MAX_LEFT
            and local_hour in ENDS_SOON_HOURS
        ):
            return STAGE_ENDS_SOON
        return None
    ago = -time_left
    if stage < STAGE_ENDED and ENDED_MIN_AGO <= ago <= ENDED_MAX_AGO and local_hour in ENDED_HOURS:
        return STAGE_ENDED
    return None


def _ru_plural(n: int, one: str, few: str, many: str) -> str:
    if 11 <= n % 100 <= 14:
        return many
    if n % 10 == 1:
        return one
    if 2 <= n % 10 <= 4:
        return few
    return many


def _when_phrase(end_local: datetime, now_local: datetime) -> str:
    days = (end_local.date() - now_local.date()).days
    clock = end_local.strftime("%H:%M")
    if days <= 0:
        return f"сегодня в {clock}"
    if days == 1:
        return f"завтра в {clock}"
    if days == 2:
        return f"послезавтра в {clock}"
    return end_local.strftime("%d.%m в %H:%M")


def _when_phrase_en(end_local: datetime, now_local: datetime) -> str:
    days = (end_local.date() - now_local.date()).days
    clock = end_local.strftime("%H:%M")
    if days <= 0:
        return f"today at {clock}"
    if days == 1:
        return f"tomorrow at {clock}"
    if days == 2:
        return f"in 2 days at {clock}"
    return end_local.strftime("%b %d at %H:%M")


@dataclass(frozen=True)
class ReminderCopy:
    title: str
    body: str


def reminder_copy(
    stage: int,
    *,
    end_local: datetime,
    now_local: datetime,
    logged_count: int,
) -> ReminderCopy:
    """Push text for a stage. Deliberately plain: it says what changes
    and what doesn't, and that nothing is charged on its own — the whole
    point of the no-card trial is that this is a reminder, not a trap.
    `logged_count` (things the person did in the app since the trial
    began) is used only when it's positive — "you did 0 things" would be
    a reminder of nothing."""
    used = ""
    used_en = ""
    if logged_count > 0:
        noun = _ru_plural(logged_count, "действие", "действия", "действий")
        used = f"За это время у вас {logged_count} {noun} в Seenly. "
        used_en = f"So far you've done {logged_count} {'thing' if logged_count == 1 else 'things'} in Seenly. "
    when_ru = _when_phrase(end_local, now_local)
    when_en = _when_phrase_en(end_local, now_local)

    if stage == STAGE_ENDS_SOON:
        return ReminderCopy(
            title=Bi(f"Бесплатный период закончится {when_ru}", f"Your free period ends {when_en}"),
            body=Bi(
                f"{used}Карту вы не привязывали — само ничего не спишется. "
                "Оформите подписку, чтобы Teamira без лимитов и всё остальное остались с вами.",
                f"{used_en}You never added a card, so nothing gets charged on its own. "
                "Subscribe to keep Teamira unlimited and everything else.",
            ),
        )
    if stage == STAGE_LAST_HOURS:
        return ReminderCopy(
            title=Bi(f"Бесплатный период заканчивается {when_ru}", f"Your free period is ending {when_en}"),
            body=Bi(
                "Дальше — 3 вопроса Teamira в месяц и лимиты на избранное и списки. "
                "Оформить подписку можно в пару касаний.",
                "After that: 3 Teamira questions a month and limits on favorites and lists. "
                "Subscribing takes a couple of taps.",
            ),
        )
    return ReminderCopy(
        title=Bi("Бесплатный период закончился", "Your free period has ended"),
        body=Bi(
            "Все ваши записи и списки на месте — вернулись только лимиты. "
            "Безлимит можно вернуть в любой момент.",
            "All your entries and lists are right where you left them — only the limits came back. "
            "You can get unlimited back any time.",
        ),
    )


_STAGE_TYPE = {
    STAGE_ENDS_SOON: "trial_ending",
    STAGE_LAST_HOURS: "trial_ending",
    STAGE_ENDED: "trial_ended",
}


def _local_now(db: Session, user_id: str, now_utc: datetime) -> Optional[datetime]:
    """The person's local time from their most recently seen device's
    reported IANA timezone — the same source and the same "no timezone,
    no push" rule as scripts/send_scheduled_push.py: guessing wrong
    means a push in the middle of the night."""
    token = (
        db.query(models.PushToken)
        .filter(models.PushToken.user_id == user_id, models.PushToken.timezone.isnot(None))
        .order_by(models.PushToken.last_seen_at.desc())
        .first()
    )
    if token is None:
        return None
    try:
        return now_utc.astimezone(ZoneInfo(token.timezone))
    except Exception:
        logger.warning("push token %s has an unrecognized timezone %r", token.id, token.timezone)
        return None


def trial_logged_count(db: Session, state: models.UserPremiumState) -> int:
    """How many things this person did in the app since the trial began
    (ActivityEvent rows: logs, ratings, list adds...). Zero when there is
    no trial or nothing was done. Also feeds the in-app expiry screen."""
    if state.trial_started_at is None:
        return 0
    return (
        db.query(models.ActivityEvent)
        .filter(
            models.ActivityEvent.user_id == state.user_id,
            models.ActivityEvent.created_at >= state.trial_started_at,
        )
        .count()
    )


def send_trial_reminders(db: Session, dry_run: bool = False, now_utc: Optional[datetime] = None) -> int:
    """One pass of the series. Returns how many reminders were (or, in
    a dry run, would be) sent. Safe to run every hour: a stage only
    advances after a delivered push, and `due_stage` only ever returns a
    stage above the one already recorded."""
    # Local import: routers.premium imports this module for the status
    # payload, and needs nothing from here at import time.
    from app.routers.premium import premium_verdict

    now_utc = now_utc or datetime.now(timezone.utc)
    lo = now_utc - ENDED_MAX_AGO
    hi = now_utc + ENDS_SOON_MAX_LEFT
    candidates = (
        db.query(models.UserPremiumState)
        .filter(
            models.UserPremiumState.trial_started_at.isnot(None),
            models.UserPremiumState.purchased_at.is_(None),
            models.UserPremiumState.is_premium.is_(False),
            models.UserPremiumState.premium_expires_at.isnot(None),
            models.UserPremiumState.premium_expires_at >= lo,
            models.UserPremiumState.premium_expires_at <= hi,
            models.UserPremiumState.trial_reminder_stage < STAGE_ENDED,
        )
        .all()
    )

    sent = 0
    for state in candidates:
        user = db.get(models.User, state.user_id)
        if user is None or user.deleted_at is not None:
            continue
        local_now = _local_now(db, state.user_id, now_utc)
        if local_now is None:
            continue
        time_left = state.premium_expires_at - now_utc
        stage = due_stage(state.trial_reminder_stage, time_left, local_now.hour)
        if stage is None:
            continue
        # Someone covered by their partner's couple plan keeps premium
        # after the trial ends — telling them it "ended" would be false.
        # (Before the end the own-trial verdict wins, so only the
        # post-expiry stage needs this check.)
        if stage == STAGE_ENDED and premium_verdict(db, state.user_id, state).is_premium:
            continue

        copy = reminder_copy(
            stage,
            end_local=state.premium_expires_at.astimezone(local_now.tzinfo),
            now_local=local_now,
            logged_count=trial_logged_count(db, state),
        )
        if dry_run:
            logger.info("[dry-run] trial stage %d -> %s: %s", stage, user.username, copy.title)
            sent += 1
            continue
        n = push.push_service.send_to_user(
            db, user, push.PushCategory.SUBSCRIPTION, copy.title, copy.body,
            data={"type": _STAGE_TYPE[stage], "stage": stage},
        )
        if n:
            state.trial_reminder_stage = stage
            state.trial_reminder_sent_at = now_utc
            db.commit()
            sent += 1
    return sent
