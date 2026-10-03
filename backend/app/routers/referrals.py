"""Referral program: turning User.referred_by_id (the plain "who invited
whom" fact set at signup, see routers/auth.py::register and
routers/friends.py::claim_invite) into actual rewards.

Three things live here that don't belong on the plain invite graph:
  - Anti-fraud gating (models.Referral) — a signup only ever counts once
    it looks like a real, sticking-around person, not the instant the
    link is tapped.
  - Milestone bonuses (models.ReferralReward) — cumulative premium days
    for the referrer as their confirmed-invite count crosses thresholds.
  - The personal purchase-discount code (models.PromoCode) — separate
    from User.invite_code; that one gets someone *into* the program,
    this one is what a referred person spends, once, on their own first
    premium purchase.

No scheduler/cron infra exists anywhere else in this backend (see
app/main.py — startup runs migrations and a one-off seed, nothing
recurring). Rather than bolt one on just for this, verification is
recomputed lazily, the same "recompute on read" shape this codebase
already uses for streaks and the AI-ask monthly reset (see
routers/profile.py's own comment on why streak is computed from real
event dates, and routers/premium.py::_reset_ai_asks_if_new_month):
every GET /referrals/status recomputes that referrer's own *pending*
rows before answering. A referrer who never opens "Мои приглашения"
simply has their payouts wait until the next time they do — acceptable
here since nothing about the reward is time-critical, and the mobile
app calls this from the home screen's referral card too (see
ReferralService), not just the dedicated screen.
"""

from __future__ import annotations

import random
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db
from app import models
from app.deps import get_current_user, require_admin_user
from app.invite_copy import REFERRAL_RULES_TEXT
from app.schemas import ReferralStatusOut, ReferredUserOut, AdminReferralOut

router = APIRouter(prefix="/referrals", tags=["referrals"])

# ---------------------------------------------------------------------------
# Tunables. Everything a product decision touches lives here, not scattered
# through the functions below.
# ---------------------------------------------------------------------------

# "Добавил больше 2 записей (дневник/watchlist, суммарно)" — strictly more
# than 2 means at least 3.
ENTRIES_REQUIRED = 3
# "Заходил в приложение 5 дней подряд (не суммарно — именно подряд)".
STREAK_REQUIRED_DAYS = 5
# "С момента регистрации по ссылке прошло не менее 7 дней".
DAYS_SINCE_SIGNUP_REQUIRED = 7
# "не более 5 засчитанных приглашений в сутки на одного реферера".
DAILY_VERIFY_CAP = 5

# Cumulative confirmed-invite count -> bonus days granted the moment the
# referrer's tally reaches that count. Additive/stacking, not "highest
# tier only": reaching 10 grants all three (3 + 30 + 90 = 123 days
# total), since 1 and 5 were already paid out on the way there.
# Confirmed by product: 1 invite -> 3 days, 5 invites -> +30 days (1
# month), 10 invites -> +90 days (3 months).
MILESTONES: dict[int, int] = {1: 3, 5: 30, 10: 90}

# Beyond the highest named tier above, the reward keeps going rather
# than stopping cold — every RECURRING_MILESTONE_STEP confirmed
# referrals past that point grants another flat RECURRING_MILESTONE_DAYS
# (15th, 20th, 25th confirmed, and so on). This is the direct
# replacement for the old standing influencer discount: a genuinely
# prolific referrer still keeps earning something, it's just always
# another block of free days rather than a percentage that reapplies to
# every future purchase.
#
# Two separate limits, not one, because they guard against two
# different things:
#   - RECURRING_MILESTONE_DAYS is how much any ONE crossing is worth —
#     kept well under the named ladder's own biggest single grant (90,
#     at 10 confirmed), so no single reward ever escalates past what a
#     genuine milestone already pays.
#   - RECURRING_MILESTONE_LAST_AT is a hard ceiling on the whole
#     recurring tier — repeating even a small grant forever still adds
#     up to an unbounded total given enough confirmed referrals
#     (30+30+30+... grows exactly as unboundedly as 90+90+90+... did,
#     just slower), so this is what actually stops the total, not the
#     per-grant size. Past this many confirmed referrals, NOTHING
#     further pays out — see _next_milestone, which returns (None,
#     None) once verified_count reaches it, same "nothing left to earn"
#     shape as the old influencer discount had at its own cap.
# RECURRING_MILESTONE_LAST_AT must land exactly on a
# RECURRING_MILESTONE_STEP boundary past the named ladder (10 + a
# multiple of 5) — the math in _next_milestone assumes it does.
# At 50: named (123 days) + 8 recurring crossings (15..50) x 30 days =
# 363 days lifetime, max, however many people one account ever refers.
RECURRING_MILESTONE_STEP = 5
RECURRING_MILESTONE_DAYS = 30
RECURRING_MILESTONE_LAST_AT = 50

# Confirmed by product: 14 days. Fires at most once per referrer — see
# this constant's own use in grant_purchase_bonus below and PromoCode's
# docstring: the code is one-per-referrer and single-use overall (first
# redemption wins), so there's no way for a second referred person's
# purchase to trigger this again for the same referrer. A referrer who
# also crosses a MILESTONES threshold still gets that separately and on
# top of this — this is its own independent reason in the
# ReferralReward log, not a replacement for the milestone bonuses.
PURCHASE_BONUS_DAYS = 14

# The referred person's own reward — see ReferralRewardReason.
# referred_welcome's own comment on why this exists and why it's the
# same size as MILESTONES[1]. Granted once, the moment their Referral
# passes verification (same gate the referrer's rewards go through),
# regardless of whether that particular referral also happens to cross
# one of the referrer's milestone thresholds.
REFERRED_WELCOME_DAYS = 3

PROMO_DISCOUNT_PERCENT = 15

# Same no-0/O/1/I alphabet and length as User.invite_code (see
# routers/friends.py::_gen_invite_code) — a promo code is read aloud and
# typed by hand the same way an invite code is, so it gets the same
# easy-to-transcribe shape.
_PROMO_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
_PROMO_CODE_LENGTH = 8


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


# ---------------------------------------------------------------------------
# Signup hook — called from routers/auth.py::register and
# routers/friends.py::claim_invite, the two (and only) places
# User.referred_by_id gets set.
# ---------------------------------------------------------------------------

def create_referral_for_signup(db: Session, referrer_id: str, referred_id: str, ip: Optional[str]) -> None:
    """Idempotent: safe to call even if a Referral for this referred_id
    somehow already exists (shouldn't happen given the two call sites
    each only fire once per account, but referred_id is unique on the
    table regardless, so this is the defensive check that matches it).
    Self-referral is guarded by both call sites already; guarded again
    here since this is the one place that actually writes the row.
    """
    if referrer_id == referred_id:
        return
    existing = db.query(models.Referral).filter(models.Referral.referred_id == referred_id).first()
    if existing is not None:
        return

    # Basic dedup: the one anti-fraud signal available without a device
    # SDK or SMS verification (see this module's own docstring, and the
    # planning doc's explicit "без SMS-верификации"). Two signups from
    # the same referrer sharing the same signup IP reads as one person
    # working the program with a second account rather than two real
    # invitees — reject the second one outright rather than letting it
    # sit in "pending" forever looking like a stalled real person.
    status = models.ReferralStatus.pending
    if ip:
        duplicate = (
            db.query(models.Referral)
            .filter(
                models.Referral.referrer_id == referrer_id,
                models.Referral.ip_at_signup == ip,
                models.Referral.status != models.ReferralStatus.rejected,
            )
            .first()
        )
        if duplicate is not None:
            status = models.ReferralStatus.rejected

    referral = models.Referral(
        referrer_id=referrer_id,
        referred_id=referred_id,
        status=status,
        ip_at_signup=ip,
    )
    db.add(referral)
    db.commit()


# ---------------------------------------------------------------------------
# Promo code — lazily minted per referrer, same shape as User.invite_code.
# ---------------------------------------------------------------------------

def _gen_promo_code(db: Session) -> str:
    while True:
        code = "".join(random.choices(_PROMO_CODE_ALPHABET, k=_PROMO_CODE_LENGTH))
        if not db.query(models.PromoCode).filter_by(code=code).first():
            return code


def get_or_create_promo_code(db: Session, referrer_id: str) -> models.PromoCode:
    promo = db.query(models.PromoCode).filter(models.PromoCode.referrer_id == referrer_id).first()
    if promo is None:
        promo = models.PromoCode(
            referrer_id=referrer_id,
            code=_gen_promo_code(db),
            discount_percent=PROMO_DISCOUNT_PERCENT,
        )
        db.add(promo)
        db.commit()
        db.refresh(promo)
    return promo


# ---------------------------------------------------------------------------
# Premium-days ledger. Extends models.UserPremiumState.premium_expires_at —
# see that column's own comment for how it combines with the purchase-flag
# `is_premium`.
# ---------------------------------------------------------------------------

def grant_premium_days(db: Session, user_id: str, days: int) -> None:
    state = db.get(models.UserPremiumState, user_id)
    if state is None:
        state = models.UserPremiumState(user_id=user_id, is_premium=False, ai_asks_used=0)
        db.add(state)
    base = state.premium_expires_at if (state.premium_expires_at and state.premium_expires_at > _utcnow()) else _utcnow()
    state.premium_expires_at = base + timedelta(days=days)
    db.commit()


def grant_purchase_bonus(db: Session, promo: models.PromoCode) -> None:
    """Called from routers/premium.py::purchase once a promo code has
    been validated and marked used on this purchase — rewards the code's
    OWNER (the referrer), not the buyer (who gets their discount applied
    to the price instead, entirely client-side; see that router)."""
    source_referral = (
        db.query(models.Referral)
        .filter(
            models.Referral.referrer_id == promo.referrer_id,
            models.Referral.referred_id == promo.referred_id,
        )
        .first()
    )
    db.add(models.ReferralReward(
        user_id=promo.referrer_id,
        reason=models.ReferralRewardReason.purchase_bonus,
        granted_days=PURCHASE_BONUS_DAYS,
        source_referral_id=source_referral.id if source_referral else None,
    ))
    db.commit()
    grant_premium_days(db, promo.referrer_id, PURCHASE_BONUS_DAYS)


# ---------------------------------------------------------------------------
# Verification — the "real human" gate, and the milestone rewards it
# unlocks. See this module's own docstring for why this runs on read
# rather than off a cron.
# ---------------------------------------------------------------------------

def _entries_count(db: Session, user_id: str) -> int:
    diary = db.query(models.DiaryEntry).filter(models.DiaryEntry.user_id == user_id).count()
    watchlist = db.query(models.WatchlistEntry).filter(models.WatchlistEntry.user_id == user_id).count()
    return diary + watchlist


def _current_streak_days(db: Session, user_id: str) -> int:
    """Consecutive calendar days (ending today or yesterday) with at
    least one ActivityEvent — same "derive from real event dates, don't
    keep a counter that can drift" approach as routers/profile.py's own
    year-stats streak. Duplicated here in full rather than imported: the
    profile.py version is a local variable inside a larger endpoint
    function, not something worth extracting into a shared cross-module
    dependency for one four-line loop."""
    event_dates = {
        e.created_at.date()
        for e in db.query(models.ActivityEvent).filter(models.ActivityEvent.user_id == user_id).all()
        if e.created_at
    }
    streak = 0
    cursor = datetime.now(timezone.utc).date()
    if cursor not in event_dates:
        cursor -= timedelta(days=1)
    while cursor in event_dates:
        streak += 1
        cursor -= timedelta(days=1)
    return streak


def _grant_milestone_if_crossed(db: Session, referrer_id: str, referral: models.Referral) -> bool:
    """Called right after `referral` flips to verified. Returns True if
    this particular referral is the one that crossed a milestone
    threshold (caller marks it `rewarded` instead of plain `verified`
    when that happens).

    Two shapes of threshold, both one-time-per-crossing:
      - A named tier in MILESTONES (1, 5, 10) — each has its own
        ReferralRewardReason value, so "already granted?" is just "does
        a reward with this reason exist for this user" (a named tier can
        only ever be crossed once in a lifetime).
      - Past the highest named tier, a recurring crossing every
        RECURRING_MILESTONE_STEP (15, 20, 25, ..., up to
        RECURRING_MILESTONE_LAST_AT — nothing pays out past that) —
        these all share ONE reason (milestone_recurring), so "already
        granted?" has to be scoped to *this specific* referral's own
        source_referral_id instead, or the very first recurring payout
        would block every one after it.
    """
    cumulative = (
        db.query(models.Referral)
        .filter(
            models.Referral.referrer_id == referrer_id,
            models.Referral.status.in_([models.ReferralStatus.verified, models.ReferralStatus.rewarded]),
        )
        .count()
    )
    highest_named = max(MILESTONES)

    if cumulative in MILESTONES:
        days = MILESTONES[cumulative]
        reason = models.ReferralRewardReason(f"milestone_{cumulative}")
        already_granted = (
            db.query(models.ReferralReward)
            .filter(
                models.ReferralReward.user_id == referrer_id,
                models.ReferralReward.reason == reason,
            )
            .first()
        )
    elif (
        highest_named < cumulative <= RECURRING_MILESTONE_LAST_AT
        and (cumulative - highest_named) % RECURRING_MILESTONE_STEP == 0
    ):
        days = RECURRING_MILESTONE_DAYS
        reason = models.ReferralRewardReason.milestone_recurring
        already_granted = (
            db.query(models.ReferralReward)
            .filter(
                models.ReferralReward.user_id == referrer_id,
                models.ReferralReward.reason == reason,
                models.ReferralReward.source_referral_id == referral.id,
            )
            .first()
        )
    else:
        return False

    if already_granted is not None:
        return False
    db.add(models.ReferralReward(
        user_id=referrer_id,
        reason=reason,
        granted_days=days,
        source_referral_id=referral.id,
    ))
    db.commit()
    grant_premium_days(db, referrer_id, days)
    return True


def _recompute_pending(db: Session, referrer_id: str) -> None:
    pending = (
        db.query(models.Referral)
        .filter(models.Referral.referrer_id == referrer_id, models.Referral.status == models.ReferralStatus.pending)
        .all()
    )
    if not pending:
        return

    today = _utcnow().date()
    verified_today = (
        db.query(models.Referral)
        .filter(
            models.Referral.referrer_id == referrer_id,
            models.Referral.status.in_([models.ReferralStatus.verified, models.ReferralStatus.rewarded]),
        )
        .all()
    )
    verified_today_count = sum(1 for r in verified_today if r.verified_at and r.verified_at.date() == today)

    for referral in pending:
        referral.entries_count_snapshot = _entries_count(db, referral.referred_id)
        referral.streak_days_current = _current_streak_days(db, referral.referred_id)
        days_since_signup = (_utcnow().date() - referral.created_at.date()).days if referral.created_at else 0

        meets_conditions = (
            referral.entries_count_snapshot >= ENTRIES_REQUIRED
            and referral.streak_days_current >= STREAK_REQUIRED_DAYS
            and days_since_signup >= DAYS_SINCE_SIGNUP_REQUIRED
        )
        if not meets_conditions:
            continue
        if verified_today_count >= DAILY_VERIFY_CAP:
            # Eligible, but the daily cap is already spent — stays
            # pending and gets picked up again on the next recompute
            # (tomorrow, or whenever the referrer next opens this
            # screen), per the planning doc's explicit per-day ceiling.
            continue

        referral.verified_at = _utcnow()
        referral.status = models.ReferralStatus.verified
        db.commit()
        verified_today_count += 1

        # The referred person's own reward — independent of whether this
        # particular confirmation also happens to cross one of the
        # referrer's milestone thresholds below. See ReferralRewardReason.
        # referred_welcome's own comment for why this exists.
        db.add(models.ReferralReward(
            user_id=referral.referred_id,
            reason=models.ReferralRewardReason.referred_welcome,
            granted_days=REFERRED_WELCOME_DAYS,
            source_referral_id=referral.id,
        ))
        db.commit()
        grant_premium_days(db, referral.referred_id, REFERRED_WELCOME_DAYS)

        if _grant_milestone_if_crossed(db, referrer_id, referral):
            referral.status = models.ReferralStatus.rewarded
            db.commit()


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

def _next_milestone(verified_count: int) -> tuple[Optional[int], Optional[int]]:
    """(threshold, days it grants) for the next milestone above
    verified_count — a named MILESTONES entry while there's still one
    left, then the recurring RECURRING_MILESTONE_STEP ladder up to
    RECURRING_MILESTONE_LAST_AT. (None, None) once verified_count has
    reached that ceiling — same "nothing left to earn" shape the old
    influencer discount had at its own cap, just at a much higher bar."""
    named = next((t for t in sorted(MILESTONES) if t > verified_count), None)
    if named is not None:
        return named, MILESTONES[named]
    if verified_count >= RECURRING_MILESTONE_LAST_AT:
        return None, None
    highest_named = max(MILESTONES)
    steps_done = max(0, verified_count - highest_named) // RECURRING_MILESTONE_STEP
    next_at = highest_named + (steps_done + 1) * RECURRING_MILESTONE_STEP
    return next_at, RECURRING_MILESTONE_DAYS

def _referred_user_out(db: Session, referral: models.Referral) -> ReferredUserOut:
    user = db.get(models.User, referral.referred_id)
    days_since_signup = (_utcnow().date() - referral.created_at.date()).days if referral.created_at else 0
    eligible_not_before = (referral.created_at or _utcnow()) + timedelta(days=DAYS_SINCE_SIGNUP_REQUIRED)
    return ReferredUserOut(
        referred_user_id=referral.referred_id,
        display_name=user.display_name if user else None,
        username=user.username if user else "",
        status=referral.status.value,
        created_at=referral.created_at,
        verified_at=referral.verified_at,
        entries_count=referral.entries_count_snapshot,
        entries_required=ENTRIES_REQUIRED,
        streak_days=referral.streak_days_current,
        streak_days_required=STREAK_REQUIRED_DAYS,
        days_since_signup=max(0, days_since_signup),
        days_since_signup_required=DAYS_SINCE_SIGNUP_REQUIRED,
        eligible_not_before=eligible_not_before,
    )


@router.get("/status", response_model=ReferralStatusOut)
def get_status(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Recomputes this account's own pending invitees (see
    _recompute_pending's docstring on why that happens here rather than
    off a cron), then returns the full picture: cumulative confirmed
    count, progress to the next milestone, every invitee with live
    per-person progress, and this account's own shareable promo code."""
    _recompute_pending(db, current_user.id)

    referrals = (
        db.query(models.Referral)
        .filter(models.Referral.referrer_id == current_user.id)
        .order_by(models.Referral.created_at.desc())
        .all()
    )
    verified_count = sum(
        1 for r in referrals if r.status in (models.ReferralStatus.verified, models.ReferralStatus.rewarded)
    )
    pending_count = sum(1 for r in referrals if r.status == models.ReferralStatus.pending)

    next_threshold, next_days = _next_milestone(verified_count)

    promo = get_or_create_promo_code(db, current_user.id)

    return ReferralStatusOut(
        verified_count=verified_count,
        pending_count=pending_count,
        next_milestone_at=next_threshold,
        next_milestone_days=next_days,
        referred=[_referred_user_out(db, r) for r in referrals],
        promo_code=promo.code,
        promo_discount_percent=PROMO_DISCOUNT_PERCENT,
        referred_welcome_days=REFERRED_WELCOME_DAYS,
        rules_text=REFERRAL_RULES_TEXT,
    )


# ---------------------------------------------------------------------------
# Admin — not a public surface; see require_admin_user. Mirrors the shape
# of routers/teamira.py's own admin endpoints.
# ---------------------------------------------------------------------------

@router.get(
    "/admin/suspicious",
    response_model=list[AdminReferralOut],
    dependencies=[Depends(require_admin_user)],
)
def admin_list_suspicious(db: Session = Depends(get_db)):
    """Rejected rows (auto-rejected duplicates) plus anything still
    pending well past the point it should have verified — the two
    shapes worth a human glance. Not literally every referral ever
    made; that list is unbounded and not useful for spotting fraud."""
    stale_cutoff = _utcnow() - timedelta(days=DAYS_SINCE_SIGNUP_REQUIRED + 14)
    rows = (
        db.query(models.Referral)
        .filter(
            (models.Referral.status == models.ReferralStatus.rejected)
            | (
                (models.Referral.status == models.ReferralStatus.pending)
                & (models.Referral.created_at < stale_cutoff)
            )
        )
        .order_by(models.Referral.created_at.desc())
        .limit(200)
        .all()
    )
    out = []
    for r in rows:
        referrer = db.get(models.User, r.referrer_id)
        referred = db.get(models.User, r.referred_id)
        out.append(AdminReferralOut(
            id=r.id,
            referrer_username=referrer.username if referrer else "",
            referred_username=referred.username if referred else "",
            status=r.status.value,
            created_at=r.created_at,
            verified_at=r.verified_at,
            entries_count_snapshot=r.entries_count_snapshot,
            streak_days_current=r.streak_days_current,
            ip_at_signup=r.ip_at_signup,
        ))
    return out


@router.post(
    "/admin/{referral_id}/reject",
    status_code=204,
    dependencies=[Depends(require_admin_user)],
)
def admin_reject(referral_id: str, db: Session = Depends(get_db)):
    """Sets a referral to rejected regardless of its current status —
    including clawing back an already-rewarded one after the fact (the
    planning doc's "каждое начисление отзываемо задним числом"). Note
    this does NOT revoke premium days already granted to the referrer;
    ReferralReward stays as the permanent log of what was paid out and
    when, for a human to reconcile by hand if a payout genuinely needs
    clawing back — automatically walking back a partially-spent premium
    period isn't attempted here."""
    referral = db.get(models.Referral, referral_id)
    if referral is None:
        raise HTTPException(status_code=404, detail="Referral not found")
    referral.status = models.ReferralStatus.rejected
    db.commit()
