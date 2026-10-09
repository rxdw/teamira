"""Keeping people who are about to leave, and bringing back the ones who did.

Two levers, both deliberately gentle:

  pause     "freeze it for a month" offered *instead of* cancelling. The
            purchase's premium is suspended for PAUSE_DAYS, the month is
            not paid for (the renewal grid moves out by the same time),
            and it comes back on its own. Once per PAUSE_COOLDOWN, or it
            would just be a cancel that never ends.
  win-back  when a *cancelled* plan actually runs out, one personal
            discount for WINBACK_WINDOW — a push and a Home strip at
            that moment, not the generic paywall. One per account, ever.

Cancelling itself takes effect at the end of the period the person
already has (`cancel_effective_at`): they keep what they paid for, and
that end — not the tap — is what opens the win-back window.

Nothing here talks to a payment processor, because there isn't one yet
(routers/premium.py). `purchased_at` + the plan length, rolled forward in
whole periods (`paid_until`), stands in for the store's renewal date;
when real billing arrives that is the one function to replace. The
*rules* — what is offered when, and the once-only guards — don't change.

Like the trial series (app/trial.py) the schedule decisions are pure
functions of (state, now, local hour), so they are testable without a
clock, a database or Firebase. The sender at the bottom is the thin part
and runs from the existing hourly cron (scripts/send_scheduled_push.py).

Everything about "is this person premium right now" still goes through
routers/premium.py::premium_verdict; this module only supplies the
purchase half of that answer (`purchase_active`).
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Optional

from sqlalchemy.orm import Session

from app import models, push
from app.trial import _local_now, _ru_plural
from app.bi import Bi

logger = logging.getLogger(__name__)

# Length of one paid period, per plan length. Matches what the paywall
# sells (PremiumService.PremiumDuration.months on the mobile side).
PLAN_DAYS = {
    models.PremiumDuration.month: 30,
    models.PremiumDuration.three_months: 90,
    models.PremiumDuration.six_months: 180,
    models.PremiumDuration.year: 365,
}

PAUSE_DAYS = 30
# Measured from the start of the last pause. Six months: long enough that
# nobody can hold a subscription in permanent "pause", short enough that
# someone with a genuinely busy season twice a year is still served.
PAUSE_COOLDOWN = timedelta(days=180)

# Personal comeback discount. One number here; the client reads it from
# the status payload rather than keeping its own copy.
WINBACK_PERCENT = 30
WINBACK_WINDOW = timedelta(days=7)
# Don't announce an offer that is about to vanish: the push goes only
# while at least this much of the window is left.
WINBACK_PUSH_MIN_LEFT = timedelta(hours=24)
WINBACK_PUSH_HOURS = range(10, 22)

PAUSE_ENDING_LEAD = timedelta(days=2)
PAUSE_ENDING_HOURS = range(10, 22)

PHASE_ACTIVE = "active"
PHASE_CANCELLING = "cancelling"
PHASE_PAUSED = "paused"
PHASE_LAPSED = "lapsed"


class SubscriptionError(Exception):
    """A request the current state doesn't allow. `detail` is the
    Russian, person-facing message the router turns into a 400 — the
    same convention as the rest of routers/premium.py."""

    def __init__(self, detail: str):
        super().__init__(detail)
        self.detail = detail


# ---------------------------------------------------------------------------
# State, as pure functions of (row, now)
# ---------------------------------------------------------------------------

def is_paused(state: models.UserPremiumState, now: datetime) -> bool:
    return state.paused_until is not None and state.paused_until > now


def is_lapsed(state: models.UserPremiumState, now: datetime) -> bool:
    """A cancelled plan whose paid period is over."""
    return state.cancel_effective_at is not None and state.cancel_effective_at <= now


def purchase_active(state: Optional[models.UserPremiumState], now: datetime) -> bool:
    """Does this account's *own purchase* give premium right now — the
    flag, minus a finished cancellation, minus a running pause. (A trial
    or referral days are a separate source; see premium._is_premium_now.)

    `is_premium` itself is never flipped by cancel or pause: it stays the
    record that a purchase exists, and this decides whether it counts."""
    if state is None or not state.is_premium:
        return False
    return not is_lapsed(state, now) and not is_paused(state, now)


def phase(state: Optional[models.UserPremiumState], now: datetime) -> Optional[str]:
    """Where a *purchased* plan is: active / cancelling / paused / lapsed —
    or None for an account that never bought anything (trials and
    referral days have their own story, app/trial.py)."""
    if state is None or state.purchased_at is None or not state.is_premium:
        return None
    if is_paused(state, now):
        return PHASE_PAUSED
    if is_lapsed(state, now):
        return PHASE_LAPSED
    if state.cancel_effective_at is not None:
        return PHASE_CANCELLING
    return PHASE_ACTIVE


def paid_until(state: models.UserPremiumState, now: datetime) -> Optional[datetime]:
    """End of the paid period we're in: `purchased_at` plus whole plan
    lengths, the first one still ahead of `now`. The stand-in for a
    store renewal date (module docstring). None without a purchase."""
    if state.purchased_at is None or state.plan_duration is None:
        return None
    period = timedelta(days=PLAN_DAYS.get(state.plan_duration, 30))
    end = state.purchased_at + period
    if end > now:
        return end
    periods_gone = (now - state.purchased_at) // period
    return state.purchased_at + period * (periods_gone + 1)


def pause_available(state: Optional[models.UserPremiumState], now: datetime) -> bool:
    """Can this person pause right now: an active, un-cancelled plan, and
    the cooldown since their last pause is over."""
    if phase(state, now) != PHASE_ACTIVE:
        return False
    if state.pause_used_at is not None and now < state.pause_used_at + PAUSE_COOLDOWN:
        return False
    return True


@dataclass(frozen=True)
class WinbackOffer:
    percent: int
    expires_at: datetime


def winback_offer(state: Optional[models.UserPremiumState], now: datetime) -> Optional[WinbackOffer]:
    """The personal comeback discount, if this account has one open right
    now. Derived, never stored: it exists exactly from the moment a
    cancelled plan runs out until WINBACK_WINDOW later, unless it was
    already redeemed (once per account, ever — cancel/re-buy/cancel must
    not be a way to a permanent discount)."""
    if phase(state, now) != PHASE_LAPSED or state.winback_used_at is not None:
        return None
    expires = state.cancel_effective_at + WINBACK_WINDOW
    if now >= expires:
        return None
    return WinbackOffer(percent=WINBACK_PERCENT, expires_at=expires)


# ---------------------------------------------------------------------------
# Actions. They change the row and leave the commit to the caller, who
# already holds the row lock (routers/premium.py).
# ---------------------------------------------------------------------------

def cancel(state: models.UserPremiumState, now: datetime) -> None:
    """Cancel at the end of the paid period. Premium stays until then.

    Cancelling during a pause means "don't come back from it": the end is
    the end of the pause, since that's when access would have resumed."""
    current = phase(state, now)
    if current == PHASE_PAUSED:
        if state.cancel_effective_at is not None:
            raise SubscriptionError("Подписка уже отменена")
        end = state.paused_until
    elif current == PHASE_ACTIVE:
        end = paid_until(state, now)
    elif current == PHASE_CANCELLING:
        raise SubscriptionError("Подписка уже отменена")
    else:
        raise SubscriptionError("Нет активной подписки")
    if end is None:
        raise SubscriptionError("Нет активной подписки")
    state.cancelled_at = now
    state.cancel_effective_at = end
    # A fresh cancellation is a fresh win-back moment.
    state.winback_push_sent_at = None


def pause(state: models.UserPremiumState, now: datetime) -> None:
    """Suspend premium for PAUSE_DAYS. The renewal grid moves out by the
    same time, so the paused month is not paid for."""
    current = phase(state, now)
    if current == PHASE_PAUSED:
        raise SubscriptionError("Подписка уже на паузе")
    if current == PHASE_CANCELLING:
        raise SubscriptionError("Подписка отменена — сначала верните её")
    if current != PHASE_ACTIVE:
        raise SubscriptionError("Нет активной подписки")
    if not pause_available(state, now):
        raise SubscriptionError("Пауза уже использовалась недавно")
    length = timedelta(days=PAUSE_DAYS)
    state.paused_at = now
    state.paused_until = now + length
    state.pause_used_at = now
    state.pause_ending_push_sent_at = None
    state.purchased_at = state.purchased_at + length


def resume(state: models.UserPremiumState, now: datetime) -> None:
    """Undo whatever took the person off their plan: end a pause early
    (the unused part of the free month is taken back off the renewal
    grid) and/or take back a cancellation that hasn't happened yet."""
    current = phase(state, now)
    if current == PHASE_PAUSED:
        unused = state.paused_until - now
        state.purchased_at = state.purchased_at - unused
        state.paused_at = None
        state.paused_until = None
        state.cancelled_at = None
        state.cancel_effective_at = None
    elif current == PHASE_CANCELLING:
        state.cancelled_at = None
        state.cancel_effective_at = None
    elif current == PHASE_ACTIVE:
        raise SubscriptionError("Подписка и так активна")
    else:
        raise SubscriptionError("Нет подписки, которую можно вернуть")


def reactivate_on_purchase(state: models.UserPremiumState) -> None:
    """A new purchase supersedes any earlier cancellation or pause.
    `pause_used_at` and `winback_used_at` stay: they are the memory the
    once-only rules are built on."""
    state.cancelled_at = None
    state.cancel_effective_at = None
    state.paused_at = None
    state.paused_until = None


# ---------------------------------------------------------------------------
# Pushes
# ---------------------------------------------------------------------------

def winback_push_due(
    state: models.UserPremiumState, now: datetime, local_hour: int,
) -> bool:
    """Send the comeback push now? Only for an open offer that hasn't been
    announced yet, while enough of it is left to act on, and in the
    person's daytime."""
    offer = winback_offer(state, now)
    if offer is None or state.winback_push_sent_at is not None:
        return False
    if offer.expires_at - now < WINBACK_PUSH_MIN_LEFT:
        return False
    return local_hour in WINBACK_PUSH_HOURS


def pause_ending_push_due(
    state: models.UserPremiumState, now: datetime, local_hour: int,
) -> bool:
    """Warn that a pause is about to end — once, in the last
    PAUSE_ENDING_LEAD, in the person's daytime. Not when the plan is
    already cancelled: nothing is going to resume."""
    if phase(state, now) != PHASE_PAUSED or state.cancel_effective_at is not None:
        return False
    if state.pause_ending_push_sent_at is not None:
        return False
    left = state.paused_until - now
    if not (timedelta(0) < left <= PAUSE_ENDING_LEAD):
        return False
    return local_hour in PAUSE_ENDING_HOURS


@dataclass(frozen=True)
class SubscriptionCopy:
    title: str
    body: str


def winback_copy(percent: int, expires_local: datetime) -> SubscriptionCopy:
    return SubscriptionCopy(
        title=Bi(f"Вернём Seenly Premium со скидкой {percent}%", f"Come back to Seenly Premium for {percent}% off"),
        body=Bi(
            "Все ваши записи и списки на месте. Это личное предложение — "
            f"оно действует до {expires_local.strftime('%d.%m')}, скидка применится сама.",
            "All your entries and lists are right where you left them. This is a personal offer — "
            f"it's valid until {expires_local.strftime('%b %d')}, and the discount applies automatically.",
        ),
    )


def pause_ending_copy(resume_local: datetime, now_local: datetime) -> SubscriptionCopy:
    days = (resume_local.date() - now_local.date()).days
    if days <= 0:
        when, when_en = "сегодня", "today"
    elif days == 1:
        when, when_en = "завтра", "tomorrow"
    else:
        when = f"через {days} {_ru_plural(days, 'день', 'дня', 'дней')}"
        when_en = f"in {days} days"
    return SubscriptionCopy(
        title=Bi(f"Пауза заканчивается {when}", f"Your pause ends {when_en}"),
        body=Bi(
            f"Премиум вернётся {resume_local.strftime('%d.%m')}. "
            "Если планы изменились — подписку можно отменить в настройках.",
            f"Premium comes back on {resume_local.strftime('%b %d')}. "
            "If your plans changed, you can cancel in the settings.",
        ),
    )


def send_subscription_pushes(
    db: Session, dry_run: bool = False, now_utc: Optional[datetime] = None,
) -> int:
    """One pass over both messages. Returns how many were (or, in a dry
    run, would be) sent. Safe to run every hour: each message records its
    own `*_push_sent_at` and only after a push was actually delivered, so
    someone with push off or no timezone is retried harmlessly until the
    window for that message closes."""
    now_utc = now_utc or datetime.now(timezone.utc)
    sent = 0

    winback_candidates = (
        db.query(models.UserPremiumState)
        .filter(
            models.UserPremiumState.cancel_effective_at.isnot(None),
            models.UserPremiumState.cancel_effective_at <= now_utc,
            models.UserPremiumState.cancel_effective_at > now_utc - WINBACK_WINDOW,
            models.UserPremiumState.winback_used_at.is_(None),
            models.UserPremiumState.winback_push_sent_at.is_(None),
        )
        .all()
    )
    for state in winback_candidates:
        user = db.get(models.User, state.user_id)
        if user is None or user.deleted_at is not None:
            continue
        local_now = _local_now(db, state.user_id, now_utc)
        if local_now is None or not winback_push_due(state, now_utc, local_now.hour):
            continue
        offer = winback_offer(state, now_utc)
        copy = winback_copy(offer.percent, offer.expires_at.astimezone(local_now.tzinfo))
        if dry_run:
            logger.info("[dry-run] win-back -> %s: %s", user.username, copy.title)
            sent += 1
            continue
        n = push.push_service.send_to_user(
            db, user, push.PushCategory.SUBSCRIPTION, copy.title, copy.body,
            data={"type": "winback", "percent": offer.percent},
        )
        if n:
            state.winback_push_sent_at = now_utc
            db.commit()
            sent += 1

    pause_candidates = (
        db.query(models.UserPremiumState)
        .filter(
            models.UserPremiumState.paused_until.isnot(None),
            models.UserPremiumState.paused_until > now_utc,
            models.UserPremiumState.paused_until <= now_utc + PAUSE_ENDING_LEAD,
            models.UserPremiumState.cancel_effective_at.is_(None),
            models.UserPremiumState.pause_ending_push_sent_at.is_(None),
        )
        .all()
    )
    for state in pause_candidates:
        user = db.get(models.User, state.user_id)
        if user is None or user.deleted_at is not None:
            continue
        local_now = _local_now(db, state.user_id, now_utc)
        if local_now is None or not pause_ending_push_due(state, now_utc, local_now.hour):
            continue
        copy = pause_ending_copy(state.paused_until.astimezone(local_now.tzinfo), local_now)
        if dry_run:
            logger.info("[dry-run] pause ending -> %s: %s", user.username, copy.title)
            sent += 1
            continue
        n = push.push_service.send_to_user(
            db, user, push.PushCategory.SUBSCRIPTION, copy.title, copy.body,
            data={"type": "pause_ending"},
        )
        if n:
            state.pause_ending_push_sent_at = now_utc
            db.commit()
            sent += 1
    return sent
