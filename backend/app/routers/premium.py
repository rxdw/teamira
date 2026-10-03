"""Premium subscription state, owned by the server instead of only the
mobile app's local SharedPreferences.

Before this, PremiumService in the mobile app was the *only* place
"is this account premium?" lived — see that class's own (now historical)
docstring. Two concrete problems that caused, not just an abstract
"state should live on the server" one:
  - Buy premium on your phone, open the app on a tablet signed into the
    same account: still shows free tier, because nothing on the tablet
    ever heard about the purchase. Two devices, two independent
    SharedPreferences stores, no shared truth between them.
  - Reinstall, or just clear app storage: premium is gone, even though
    the account itself never stopped being premium.

This router is what fixes *where the truth lives* — it is NOT a real
payment/billing integration. `purchase()` below still just flips a flag
the same way the old local-only version did; there's no payment
processor, no IAP receipt validation, no App Store/Play Store server
notifications wired up here. Adding those is a separate, considerably
bigger project. What changed is that the flag now lives in
`user_premium_state`, one row per account, so every device signed into
that account sees the same answer and a reinstall doesn't erase it.

A purchased *shared* plan also covers the other people in a co-viewing
circle: a couple plan a circle of two, a family plan a circle of up to
four (see PLAN_SEATS, `_covered_by_partner` and `_seat_covers`). That is
what makes the paywall's "cheaper per person" true. Coverage is derived
on every read (never stored), and a plan's seats can't be handed to
different people more often than SEAT_REASSIGN_COOLDOWN.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.database import get_db
from app import models
from app.deps import get_current_user
from app.routers.referrals import (
    grant_premium_days,
    grant_purchase_bonus,
)
from app import subscription
from app.schemas import PremiumStatusOut, PremiumPurchaseIn, PremiumAiAskOut
from app.trial import trial_logged_count

router = APIRouter(prefix="/premium", tags=["premium"])

# Keep in sync with PremiumService.freeAiAsksPerMonth in the mobile app
# — also echoed back in PremiumStatusOut.free_ai_asks_per_month so the
# client reads this number rather than needing to keep its own copy
# exactly right by hand.
FREE_AI_ASKS_PER_MONTH = 3

# One-time free trial, offered on the paywall to anyone who has never
# purchased and never trialed before (see start_trial() below). Short
# on purpose: long enough to actually get a taste of an ask-limit-free
# evening or two, short enough that it doesn't read as "premium,
# forever, for free" to someone who just never comes back to convert.
TRIAL_DAYS = 3

# How many people one purchased plan covers, the payer included. This
# is what makes the paywall's "cheaper together" true: a couple plan
# pays for two accounts, a family plan for up to four, not one account at
# a higher price. Only a *purchase* has seats — trial days and referral
# days (premium_expires_at) are personal, and an individual plan stays
# personal too, otherwise nobody would ever buy a shared one. Who holds
# the seats other than the payer's own lives in models.PremiumSeat.
PLAN_SEATS = {
    models.PremiumPlanKind.individual: 1,
    models.PremiumPlanKind.couple: 2,
    models.PremiumPlanKind.family: 4,
}

# Minimum time between handing one of a payer's seats to a *different*
# person. The abuse this closes: link with someone, let them use
# premium, unlink, link with the next one — one plan renting itself out
# to a new stranger every day. Thirty days matches the shortest
# purchasable plan, so a seat can serve at most one other person per
# billing month, which is just what "one seat" means. Each seat runs its
# own clock. A breakup followed by a new partner within the window is
# the honest cost: the new partner isn't covered until it ends (the
# previous partner, if they come back, is covered again immediately —
# the seat is still theirs).
SEAT_REASSIGN_COOLDOWN = timedelta(days=30)


def _current_month_key() -> str:
    now = datetime.now(timezone.utc)
    return f"{now.year}-{now.month}"


def _get_or_create_state(db: Session, user_id: str, *, for_update: bool = False) -> models.UserPremiumState:
    """`for_update=True` takes a row lock (`SELECT ... FOR UPDATE`) on
    this account's premium-state row, held for the rest of the caller's
    transaction — same pattern as co_view_vote.py::_lock_link. Needed in
    purchase()/record_ai_ask() below: both do a "read the counter/flag,
    decide, write it back" sequence that isn't safe against two requests
    for the same account landing at the same instant (two tabs, a
    double-tap, a client retry racing the original) without it.

    The very first call for a brand-new account still has to INSERT
    before it can lock anything, so that path stays commit-then-refetch-
    locked rather than lock-from-the-start — a plain row lock can't be
    taken on a row that doesn't exist yet.
    """
    state = db.get(models.UserPremiumState, user_id, with_for_update=for_update)
    if state is None:
        state = models.UserPremiumState(user_id=user_id, is_premium=False, ai_asks_used=0)
        db.add(state)
        db.commit()
        db.refresh(state)
        if for_update:
            state = db.get(models.UserPremiumState, user_id, with_for_update=True)
    return state


def _reset_ai_asks_if_new_month(db: Session, state: models.UserPremiumState) -> None:
    current_month = _current_month_key()
    if state.ai_asks_month != current_month:
        state.ai_asks_used = 0
        state.ai_asks_month = current_month
        db.commit()


def _is_premium_now(state: models.UserPremiumState) -> bool:
    """The purchase flag OR a still-active referral bonus period — see
    models.UserPremiumState.premium_expires_at's own comment on why
    these are two independent sources rather than one merged field."""
    now = datetime.now(timezone.utc)
    # The purchase counts unless it was cancelled and has run out, or is
    # paused — see subscription.purchase_active.
    if subscription.purchase_active(state, now):
        return True
    return bool(state.premium_expires_at and state.premium_expires_at > now)


def _trial_phase(state: models.UserPremiumState) -> str | None:
    """"active" / "expired" / None — see PremiumStatusOut.trial_phase.
    A purchase ends the story: someone who bought is never "in a trial",
    even if trial_started_at is set."""
    if state.trial_started_at is None or state.purchased_at is not None:
        return None
    if state.premium_expires_at and state.premium_expires_at > datetime.now(timezone.utc):
        return "active"
    return "expired"


def _purchased_seats(state: models.UserPremiumState | None) -> int:
    """How many people this account's *purchase* covers, itself
    included — 0 when there is no active purchase. Deliberately reads
    only the purchase flag: a trial or referral bonus (premium_expires_at)
    is personal and never has seats, and a covered account has no
    purchase of its own, so coverage can't chain from person to person."""
    # A paused or run-out plan covers nobody, the payer included — the
    # partner's seat follows the purchase, not the flag.
    if not subscription.purchase_active(state, datetime.now(timezone.utc)):
        return 0
    return PLAN_SEATS.get(state.plan_kind, 1) if state.plan_kind else 1


def _seat_is_free_to_move(seat: models.PremiumSeat, now: datetime) -> bool:
    return now >= seat.assigned_at + SEAT_REASSIGN_COOLDOWN


def _holds_seat(db: Session, payer_id: str, user_id: str) -> bool:
    return (
        db.query(models.PremiumSeat.id)
        .filter_by(payer_id=payer_id, holder_id=user_id)
        .first()
        is not None
    )


def _seat_covers(db: Session, payer_id: str, user_id: str, circle_size: int) -> bool:
    """Does `payer_id`'s purchased plan cover `user_id`, a member of a
    circle of `circle_size` people that includes the payer? The caller
    has already established the circle and that both are in it — this
    answers the plan/seat half.

    A plan covers a circle only while the whole circle fits in it
    (`circle_size <= seats`): a family plan stops covering the moment a
    fifth person joins, and stays off for everyone, rather than quietly
    choosing whom to drop. Same rule that makes a couple plan stop at
    three.

    Fast path is a plain read: the seat is already this person's, which
    is the case on nearly every call. Only when it isn't (first time
    after linking, or after buying the plan while already linked) does
    it take the payer's row lock, re-check under it — two requests
    racing for the last seat must not both win — and bind a seat:
    a never-used one at once, or one whose previous holder has left this
    circle and whose SEAT_REASSIGN_COOLDOWN has run out. A current
    member's seat is never taken away.
    """
    payer = db.get(models.UserPremiumState, payer_id)
    seats = _purchased_seats(payer)
    if seats < circle_size:
        return False
    if _holds_seat(db, payer_id, user_id):
        return True

    payer = db.get(models.UserPremiumState, payer_id, with_for_update=True, populate_existing=True)
    seats = _purchased_seats(payer)
    if seats < circle_size:
        return False
    if _holds_seat(db, payer_id, user_id):
        return True

    now = datetime.now(timezone.utc)
    held = (
        db.query(models.PremiumSeat)
        .filter_by(payer_id=payer_id)
        .order_by(models.PremiumSeat.assigned_at.asc())
        .all()
    )
    if len(held) < seats - 1:
        db.add(models.PremiumSeat(payer_id=payer_id, holder_id=user_id, assigned_at=now))
        db.commit()
        return True

    from app.routers.partner import get_active_link, _member_ids

    link = get_active_link(db, user_id)
    current_members = set(_member_ids(link)) if link is not None else set()
    for seat in held:
        if seat.holder_id in current_members:
            continue
        if _seat_is_free_to_move(seat, now):
            seat.holder_id = user_id
            seat.assigned_at = now
            db.commit()
            return True
    return False


def _covered_by_partner(db: Session, user_id: str) -> bool:
    """True when another member of this account's co-viewing circle has
    a purchased shared plan that covers this account: a couple plan for
    a circle of two, a family plan for a circle of up to four.

    Derived on every call, never stored: unlink and the coverage is gone
    on the next read; the payer's plan ends and so do its seats.
    Imported lazily for the same reason partner.py imports this module
    lazily (_circle_has_premium) — the two routers reference each other.
    """
    from app.routers.partner import get_active_link, _member_ids

    link = get_active_link(db, user_id)
    if link is None:
        return False
    members = _member_ids(link)
    if user_id not in members:
        return False
    others = [m for m in members if m != user_id]

    # Nobody else has a plan big enough for this circle → nothing to
    # claim, and no reason to take a lock.
    payers = [
        m for m in others
        if _purchased_seats(db.get(models.UserPremiumState, m)) >= len(members)
    ]
    # A seat this person already holds wins over binding a new one.
    for payer_id in payers:
        if _holds_seat(db, payer_id, user_id):
            return True
    return any(_seat_covers(db, payer_id, user_id, len(members)) for payer_id in payers)


@dataclass(frozen=True)
class PremiumVerdict:
    is_premium: bool
    # "own" | "partner" | None
    source: str | None


def premium_verdict(
    db: Session, user_id: str, state: models.UserPremiumState | None = None,
) -> PremiumVerdict:
    """The single answer to "is this account premium right now, and
    why". Own premium (purchase, trial, referral days) is checked first
    and short-circuits, so paying accounts never touch the circle
    tables. Everything that reports or gates premium — the status
    endpoint, the AI-ask ceiling, the co-viewing queue — goes through
    here, so they can't disagree about who's premium."""
    if state is None:
        state = _get_or_create_state(db, user_id)
    if _is_premium_now(state):
        return PremiumVerdict(True, "own")
    if _covered_by_partner(db, user_id):
        return PremiumVerdict(True, "partner")
    return PremiumVerdict(False, None)


def is_premium_account(db: Session, user_id: str) -> bool:
    """"Is this account premium right now?" for any other router that
    needs to gate something — currently the co-viewing queue's free-tier
    ceiling (routers/partner.py::CO_VIEW_FREE_LIMIT) and the shared
    diary's report of it (routers/shared_diary.py).

    Counts, in order: this account's own premium (purchase flag, or a
    still-active referral/trial period — see _is_premium_now), then
    coverage by another circle member's purchased couple/family plan
    (see _covered_by_partner). A gate that disagrees with the status screen
    about who's premium is worse than no gate, which is why both call
    premium_verdict().
    """
    return premium_verdict(db, user_id).is_premium


def _status_out(
    db: Session,
    state: models.UserPremiumState,
    applied_discount_percent: int | None = None,
    verdict: PremiumVerdict | None = None,
    applied_discount_kind: str | None = None,
) -> PremiumStatusOut:
    if verdict is None:
        verdict = premium_verdict(db, state.user_id, state)
    remaining = max(0, FREE_AI_ASKS_PER_MONTH - state.ai_asks_used)
    phase = _trial_phase(state)
    now = datetime.now(timezone.utc)
    offer = subscription.winback_offer(state, now)
    return PremiumStatusOut(
        is_premium=verdict.is_premium,
        premium_source=verdict.source,
        plan_kind=state.plan_kind.value if state.plan_kind else None,
        # People this account's own purchase covers, itself included —
        # None without one. Read from the same table the coverage check
        # uses, so the app never keeps its own copy of "how many seats".
        plan_seats=_purchased_seats(state) or None,
        plan_duration=state.plan_duration.value if state.plan_duration else None,
        ai_asks_used=state.ai_asks_used,
        ai_asks_remaining=remaining,
        free_ai_asks_per_month=FREE_AI_ASKS_PER_MONTH,
        premium_expires_at=state.premium_expires_at,
        applied_discount_percent=applied_discount_percent,
        applied_discount_kind=applied_discount_kind,
        # Not offered to someone who is already covered by their
        # partner — it would spend their one trial on nothing. Computed
        # live, so it comes back the moment the coverage ends.
        trial_available=(
            state.purchased_at is None
            and state.trial_started_at is None
            and verdict.source != "partner"
        ),
        trial_days=TRIAL_DAYS,
        trial_phase=phase,
        trial_ends_at=state.premium_expires_at if phase == "active" else None,
        trial_logged_count=trial_logged_count(db, state) if phase else 0,
        subscription_phase=subscription.phase(state, now),
        paid_until=(
            subscription.paid_until(state, now)
            if subscription.phase(state, now) == subscription.PHASE_ACTIVE
            else None
        ),
        cancel_effective_at=state.cancel_effective_at,
        paused_until=state.paused_until if subscription.is_paused(state, now) else None,
        pause_available=subscription.pause_available(state, now),
        pause_days=subscription.PAUSE_DAYS,
        winback_percent=offer.percent if offer else None,
        winback_expires_at=offer.expires_at if offer else None,
    )


@router.get("/status", response_model=PremiumStatusOut)
def get_status(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Called on sign-in/account-switch (see mobile's
    _AccountScopedPrefsScope) and whenever a screen wants a fresh read —
    the account's own premium state, synced across every device signed
    into it."""
    state = _get_or_create_state(db, current_user.id)
    _reset_ai_asks_if_new_month(db, state)
    return _status_out(db, state)


@router.post("/purchase", response_model=PremiumStatusOut)
def purchase(
    payload: PremiumPurchaseIn,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Still a stand-in, not a real checkout — see this module's own
    docstring. What's real now is that the result is written here, on
    the account, rather than only on whichever device tapped the
    button."""
    try:
        plan_kind = models.PremiumPlanKind(payload.plan_kind)
    except ValueError:
        raise HTTPException(status_code=400, detail="Unknown plan_kind")
    try:
        plan_duration = models.PremiumDuration(payload.plan_duration)
    except ValueError:
        raise HTTPException(status_code=400, detail="Unknown plan_duration")

    state = _get_or_create_state(db, current_user.id, for_update=True)

    # See models.PromoCode's own docstring: one shareable code per
    # referrer, first redemption wins. Validated here rather than
    # silently ignored on a bad code, so the purchase screen can surface
    # a real error and let the person retry without it (see
    # app/routers/referrals.py::grant_purchase_bonus for the referrer's
    # side of this).
    applied_discount_percent = None
    discount_kind = None
    promo_input = (payload.promo_code or "").strip()
    if promo_input:
        promo = (
            db.query(models.PromoCode)
            .filter(func.upper(models.PromoCode.code) == promo_input.upper())
            .with_for_update()
            .first()
        )
        # `.with_for_update()` above takes a row lock on this promo code
        # the moment it's read, held for the rest of this transaction —
        # same reasoning as co_view_vote.py::_lock_link. Without it, two
        # accounts redeeming the same code at the same instant can both
        # read used_at as NULL before either commits, so both pass every
        # check below, both get the discount, and grant_purchase_bonus
        # pays the referrer twice for what's meant to be a single-use
        # code. Locking serializes them: the second transaction blocks
        # here until the first commits, then re-reads used_at as already
        # set and correctly falls into the "уже был использован" branch.
        if promo is None:
            raise HTTPException(status_code=400, detail="Промокод не найден")
        if promo.referrer_id == current_user.id:
            raise HTTPException(status_code=400, detail="Нельзя использовать свой собственный промокод")
        if promo.used_at is not None:
            raise HTTPException(status_code=400, detail="Промокод уже был использован")
        if state.purchased_at is not None:
            # "скидка по промокоду... только за первую покупку" — this
            # account has bought premium before, so the code doesn't
            # apply. Reject rather than silently charging full price,
            # same reasoning as the checks above.
            raise HTTPException(status_code=400, detail="Скидка по промокоду действует только на первую покупку")

        # Anti-self-dealing: a PromoCode is meant to be shared publicly
        # with an entire audience (see models.PromoCode's own docstring)
        # — "some stranger found the code" is the intended outcome, not
        # a hole. What IS a hole is the same person controlling both
        # ends: a second, throwaway account redeeming its own owner's
        # code to mint itself a free purchase_bonus. Same signal
        # create_referral_for_signup already uses for the invite-link
        # flow (see that function's own comment) — two accounts sharing
        # a signup IP reads as one person working the program twice.
        # Only blocks when BOTH sides actually have a recorded IP;
        # missing data (older accounts, a proxy that hides the real
        # address) fails open rather than blocking a legitimate buyer
        # over it, same trade-off the invite-link dedup already makes.
        promo_owner = db.get(models.User, promo.referrer_id)
        if (
            promo_owner is not None
            and promo_owner.signup_ip
            and current_user.signup_ip
            and promo_owner.signup_ip == current_user.signup_ip
        ):
            raise HTTPException(status_code=400, detail="Промокод недоступен для этого аккаунта")

        promo.used_at = datetime.now(timezone.utc)
        promo.referred_id = current_user.id
        db.commit()
        applied_discount_percent = promo.discount_percent
        discount_kind = "promo"
        grant_purchase_bonus(db, promo)
    # No promo code entered — no discount. Being a prolific referrer no
    # longer earns a standing discount on this account's own purchases;
    # see routers/referrals.py::MILESTONES and RECURRING_MILESTONE_STEP
    # for what replaced it (one-time free days instead, same shape as
    # every other referral reward, nothing that reapplies at purchase
    # time).

    # Win-back: the personal comeback discount that opens when a cancelled
    # plan runs out (app/subscription.py). Read before the purchase
    # rewrites the state it is derived from, and redeemed exactly like a
    # promo code — once, under the same row lock. A promo code and this
    # can't both apply: promo codes are for a first purchase only (checked
    # above), and win-back exists only after one.
    now = datetime.now(timezone.utc)
    if applied_discount_percent is None:
        offer = subscription.winback_offer(state, now)
        if offer is not None:
            applied_discount_percent = offer.percent
            state.winback_used_at = now
            discount_kind = "winback"
    state.is_premium = True
    state.plan_kind = plan_kind
    state.plan_duration = plan_duration
    state.purchased_at = now
    subscription.reactivate_on_purchase(state)
    db.commit()
    db.refresh(state)
    return _status_out(
        db, state,
        applied_discount_percent=applied_discount_percent,
        applied_discount_kind=discount_kind,
    )


def _run_subscription_action(
    db: Session, user_id: str, action,
) -> models.UserPremiumState:
    """Shared shape of cancel / pause / resume: lock this account's row,
    apply the rule from app/subscription.py, commit. A refused request
    becomes a 400 carrying the person-facing reason. Row-locked like
    purchase() — two taps, or two devices, must not both act on the same
    reading of the state (two pauses, a cancel racing a resume)."""
    state = _get_or_create_state(db, user_id, for_update=True)
    try:
        action(state, datetime.now(timezone.utc))
    except subscription.SubscriptionError as e:
        # Every rule refuses before it changes anything, so there is
        # nothing to roll back; the row lock goes when the request's
        # session closes.
        raise HTTPException(status_code=400, detail=e.detail)
    db.commit()
    db.refresh(state)
    return state


@router.post("/cancel", response_model=PremiumStatusOut)
def cancel_subscription(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Cancel at the end of the paid period. Premium keeps working until
    then; when it runs out, the win-back offer opens (see
    app/subscription.py). Still no processor behind it — this records the
    intent on the account, which is what the rest of the system reads."""
    state = _run_subscription_action(db, current_user.id, subscription.cancel)
    return _status_out(db, state)


@router.post("/pause", response_model=PremiumStatusOut)
def pause_subscription(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Freeze the plan for a month instead of cancelling it (once per
    subscription.PAUSE_COOLDOWN). Premium is off for the duration and
    comes back on its own; on a couple plan the partner's seat pauses
    with it, because the seat follows the purchase."""
    state = _run_subscription_action(db, current_user.id, subscription.pause)
    return _status_out(db, state)


@router.post("/resume", response_model=PremiumStatusOut)
def resume_subscription(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """End a pause early, and/or take back a cancellation that hasn't
    taken effect yet."""
    state = _run_subscription_action(db, current_user.id, subscription.resume)
    return _status_out(db, state)


@router.post("/start-trial", response_model=PremiumStatusOut)
def start_trial(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The paywall's other call-to-action, offered instead of a straight
    purchase whenever `trial_available` is true (see _status_out) —
    grants TRIAL_DAYS of premium the same way a referral bonus is
    granted (grant_premium_days, stacking on top of premium_expires_at
    rather than touching the `is_premium` purchase flag), and marks
    trial_started_at so this account can never redeem a second one.

    Row-locked the same way purchase() is: two requests landing at the
    same instant (a double-tap) must not both read trial_started_at as
    NULL and both grant the trial twice.
    """
    state = _get_or_create_state(db, current_user.id, for_update=True)
    if state.purchased_at is not None or state.trial_started_at is not None:
        raise HTTPException(status_code=400, detail="Пробный период уже недоступен для этого аккаунта")

    state.trial_started_at = datetime.now(timezone.utc)
    db.commit()
    # grant_premium_days does its own commit — called after the trial
    # flag's own commit above (rather than batched into one) so a
    # crash between the two still leaves trial_started_at set and the
    # trial un-repeatable, instead of possibly granting days twice on
    # retry.
    grant_premium_days(db, current_user.id, TRIAL_DAYS)
    db.refresh(state)
    return _status_out(db, state)


@router.post("/ai-ask", response_model=PremiumAiAskOut)
def record_ai_ask(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Call right before an Ask Teamira request actually goes out (same
    spot PremiumService.recordAiAsk() used to be the only check) — the
    account-wide source of truth for the free "3 asks a month" ceiling,
    so the count is shared across every device on this account instead
    of each device tracking (and enforcing) its own separate copy of it.

    NOT the same limiter as rate_limit.ai_ask_limiter on POST /ai/ask —
    that one is generous, per-hour, abuse-prevention only. This is the
    actual product ceiling premium lifts."""
    # Decided *before* this account's own row is locked below:
    # premium_verdict() may commit (binding a shared-plan seat), and a
    # commit in the middle would release the lock the counter update
    # further down depends on.
    #
    # Uses the same verdict as the status screen — the old check here
    # was `state.is_premium` alone, which ignored referral/trial days
    # (a trial that was supposed to be "ask-limit-free" still hit the
    # ceiling) and would have ignored a covered partner too.
    verdict = premium_verdict(db, current_user.id)

    state = _get_or_create_state(db, current_user.id, for_update=True)
    _reset_ai_asks_if_new_month(db, state)

    if verdict.is_premium:
        return PremiumAiAskOut(
            allowed=True,
            ai_asks_used=state.ai_asks_used,
            ai_asks_remaining=FREE_AI_ASKS_PER_MONTH,
        )

    if state.ai_asks_used >= FREE_AI_ASKS_PER_MONTH:
        return PremiumAiAskOut(allowed=False, ai_asks_used=state.ai_asks_used, ai_asks_remaining=0)

    state.ai_asks_used += 1
    db.commit()
    return PremiumAiAskOut(
        allowed=True,
        ai_asks_used=state.ai_asks_used,
        ai_asks_remaining=max(0, FREE_AI_ASKS_PER_MONTH - state.ai_asks_used),
    )
