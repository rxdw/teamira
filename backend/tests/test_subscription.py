"""Cancel, pause and win-back — see app/subscription.py.

Same two layers as test_trial_reminders.py: the rules are pure functions
of (row, now) and are tested without a database; the endpoints, the
purchase discount and the push sender go through the real app against
Postgres.
"""

from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import pytest

from app import models, push, subscription
from app.subscription import (
    PAUSE_COOLDOWN,
    PAUSE_DAYS,
    PHASE_ACTIVE,
    PHASE_CANCELLING,
    PHASE_LAPSED,
    PHASE_PAUSED,
    WINBACK_PERCENT,
    WINBACK_WINDOW,
    SubscriptionError,
)

D = timedelta(days=1)
H = timedelta(hours=1)
NOW = datetime(2026, 5, 10, 12, 0, tzinfo=timezone.utc)  # 15:00 Moscow


def _row(
    *,
    duration=models.PremiumDuration.month,
    bought_ago=10 * D,
    kind=models.PremiumPlanKind.individual,
    **extra,
) -> models.UserPremiumState:
    """An unsaved row: the rules only read attributes."""
    return models.UserPremiumState(
        user_id="u", is_premium=True, ai_asks_used=0,
        plan_kind=kind, plan_duration=duration,
        purchased_at=NOW - bought_ago, **extra,
    )


# --------------------------------------------------------------------------
# State
# --------------------------------------------------------------------------

class TestPaidUntil:
    def test_first_period(self):
        assert subscription.paid_until(_row(bought_ago=10 * D), NOW) == NOW + 20 * D

    def test_rolls_forward_in_whole_periods(self):
        # Bought 70 days ago on a 30-day plan: periods ended at 30 and 60,
        # the current one ends at 90 -> 20 days from now.
        assert subscription.paid_until(_row(bought_ago=70 * D), NOW) == NOW + 20 * D

    def test_exact_boundary_starts_the_next_period(self):
        assert subscription.paid_until(_row(bought_ago=30 * D), NOW) == NOW + 30 * D

    def test_year_plan(self):
        row = _row(duration=models.PremiumDuration.year, bought_ago=100 * D)
        assert subscription.paid_until(row, NOW) == NOW + 265 * D

    def test_no_purchase(self):
        row = models.UserPremiumState(user_id="u", is_premium=False, ai_asks_used=0)
        assert subscription.paid_until(row, NOW) is None


class TestPhase:
    def test_never_bought(self):
        row = models.UserPremiumState(user_id="u", is_premium=False, ai_asks_used=0)
        assert subscription.phase(row, NOW) is None
        assert subscription.phase(None, NOW) is None

    def test_active(self):
        row = _row()
        assert subscription.phase(row, NOW) == PHASE_ACTIVE
        assert subscription.purchase_active(row, NOW)

    def test_cancelling_keeps_premium_until_the_end(self):
        row = _row(cancel_effective_at=NOW + 3 * D)
        assert subscription.phase(row, NOW) == PHASE_CANCELLING
        assert subscription.purchase_active(row, NOW)

    def test_lapsed_after_the_end(self):
        row = _row(cancel_effective_at=NOW - H)
        assert subscription.phase(row, NOW) == PHASE_LAPSED
        assert not subscription.purchase_active(row, NOW)

    def test_paused_is_not_active(self):
        row = _row(paused_until=NOW + 5 * D)
        assert subscription.phase(row, NOW) == PHASE_PAUSED
        assert not subscription.purchase_active(row, NOW)

    def test_finished_pause_is_active_again_on_its_own(self):
        row = _row(paused_until=NOW - H)
        assert subscription.phase(row, NOW) == PHASE_ACTIVE
        assert subscription.purchase_active(row, NOW)


class TestPauseAvailable:
    def test_available_when_active_and_never_paused(self):
        assert subscription.pause_available(_row(), NOW)

    def test_not_while_cancelling(self):
        assert not subscription.pause_available(_row(cancel_effective_at=NOW + D), NOW)

    def test_not_while_paused(self):
        assert not subscription.pause_available(_row(paused_until=NOW + D), NOW)

    def test_not_within_cooldown(self):
        row = _row(pause_used_at=NOW - (PAUSE_COOLDOWN - D))
        assert not subscription.pause_available(row, NOW)

    def test_again_after_cooldown(self):
        row = _row(pause_used_at=NOW - PAUSE_COOLDOWN)
        assert subscription.pause_available(row, NOW)

    def test_not_without_a_purchase(self):
        row = models.UserPremiumState(user_id="u", is_premium=False, ai_asks_used=0)
        assert not subscription.pause_available(row, NOW)


class TestWinbackOffer:
    def test_opens_when_a_cancelled_plan_runs_out(self):
        row = _row(cancel_effective_at=NOW - H)
        offer = subscription.winback_offer(row, NOW)
        assert offer is not None
        assert offer.percent == WINBACK_PERCENT
        assert offer.expires_at == NOW - H + WINBACK_WINDOW

    def test_not_while_the_plan_still_runs(self):
        assert subscription.winback_offer(_row(cancel_effective_at=NOW + D), NOW) is None

    def test_not_for_an_active_plan(self):
        assert subscription.winback_offer(_row(), NOW) is None

    def test_closes_after_the_window(self):
        row = _row(cancel_effective_at=NOW - WINBACK_WINDOW - H)
        assert subscription.winback_offer(row, NOW) is None

    def test_only_once_per_account(self):
        row = _row(cancel_effective_at=NOW - H, winback_used_at=NOW - 400 * D)
        assert subscription.winback_offer(row, NOW) is None

    def test_never_for_someone_who_never_bought(self):
        row = models.UserPremiumState(user_id="u", is_premium=False, ai_asks_used=0)
        assert subscription.winback_offer(row, NOW) is None


# --------------------------------------------------------------------------
# Actions
# --------------------------------------------------------------------------

class TestCancel:
    def test_ends_at_the_end_of_the_paid_period(self):
        row = _row(bought_ago=10 * D)
        subscription.cancel(row, NOW)
        assert row.cancel_effective_at == NOW + 20 * D
        assert row.cancelled_at == NOW
        assert subscription.purchase_active(row, NOW)

    def test_twice_is_refused(self):
        row = _row()
        subscription.cancel(row, NOW)
        with pytest.raises(SubscriptionError):
            subscription.cancel(row, NOW)

    def test_without_a_plan_is_refused(self):
        row = models.UserPremiumState(user_id="u", is_premium=False, ai_asks_used=0)
        with pytest.raises(SubscriptionError):
            subscription.cancel(row, NOW)

    def test_after_lapse_is_refused(self):
        with pytest.raises(SubscriptionError):
            subscription.cancel(_row(cancel_effective_at=NOW - H), NOW)

    def test_during_a_pause_means_dont_come_back(self):
        row = _row(paused_until=NOW + 12 * D)
        subscription.cancel(row, NOW)
        assert row.cancel_effective_at == NOW + 12 * D

    def test_a_new_cancellation_resets_the_winback_push(self):
        row = _row(winback_push_sent_at=NOW - 100 * D)
        subscription.cancel(row, NOW)
        assert row.winback_push_sent_at is None


class TestPause:
    def test_suspends_premium_and_moves_the_renewal_out(self):
        row = _row(bought_ago=10 * D)
        before = row.purchased_at
        subscription.pause(row, NOW)
        assert row.paused_until == NOW + PAUSE_DAYS * D
        assert row.pause_used_at == NOW
        assert not subscription.purchase_active(row, NOW)
        # The free month is not paid for.
        assert row.purchased_at == before + PAUSE_DAYS * D

    def test_comes_back_by_itself(self):
        row = _row()
        subscription.pause(row, NOW)
        later = NOW + PAUSE_DAYS * D + H
        assert subscription.purchase_active(row, later)

    def test_refused_inside_cooldown(self):
        row = _row(pause_used_at=NOW - 30 * D)
        with pytest.raises(SubscriptionError):
            subscription.pause(row, NOW)

    def test_refused_while_cancelling(self):
        row = _row(cancel_effective_at=NOW + 5 * D)
        with pytest.raises(SubscriptionError):
            subscription.pause(row, NOW)

    def test_refused_twice_in_a_row(self):
        row = _row()
        subscription.pause(row, NOW)
        with pytest.raises(SubscriptionError):
            subscription.pause(row, NOW + D)


class TestResume:
    def test_takes_back_a_cancellation(self):
        row = _row(cancel_effective_at=NOW + 5 * D, cancelled_at=NOW - D)
        subscription.resume(row, NOW)
        assert row.cancel_effective_at is None
        assert row.cancelled_at is None
        assert subscription.phase(row, NOW) == PHASE_ACTIVE

    def test_ends_a_pause_early_and_gives_back_the_unused_days(self):
        row = _row(bought_ago=10 * D)
        original = row.purchased_at
        subscription.pause(row, NOW)
        subscription.resume(row, NOW + 10 * D)
        assert row.paused_until is None
        assert subscription.purchase_active(row, NOW + 10 * D)
        # 10 of the 30 free days were used, so the grid moved out by 10.
        assert row.purchased_at == original + 10 * D

    def test_resuming_keeps_the_pause_cooldown(self):
        row = _row()
        subscription.pause(row, NOW)
        subscription.resume(row, NOW + D)
        assert not subscription.pause_available(row, NOW + 2 * D)

    def test_active_plan_has_nothing_to_resume(self):
        with pytest.raises(SubscriptionError):
            subscription.resume(_row(), NOW)

    def test_lapsed_plan_cannot_be_resumed(self):
        with pytest.raises(SubscriptionError):
            subscription.resume(_row(cancel_effective_at=NOW - H), NOW)


# --------------------------------------------------------------------------
# Push schedule and copy
# --------------------------------------------------------------------------

class TestPushSchedule:
    def test_winback_in_the_daytime_right_after_the_end(self):
        row = _row(cancel_effective_at=NOW - 2 * H)
        assert subscription.winback_push_due(row, NOW, 15)

    def test_winback_waits_out_the_night(self):
        row = _row(cancel_effective_at=NOW - 2 * H)
        assert not subscription.winback_push_due(row, NOW, 3)
        assert not subscription.winback_push_due(row, NOW, 23)

    def test_winback_only_once(self):
        row = _row(cancel_effective_at=NOW - 2 * H, winback_push_sent_at=NOW - H)
        assert not subscription.winback_push_due(row, NOW, 15)

    def test_winback_not_announced_when_it_is_about_to_expire(self):
        row = _row(cancel_effective_at=NOW - WINBACK_WINDOW + 5 * H)
        assert not subscription.winback_push_due(row, NOW, 15)

    def test_winback_not_after_it_was_redeemed(self):
        row = _row(cancel_effective_at=NOW - 2 * H, winback_used_at=NOW - H)
        assert not subscription.winback_push_due(row, NOW, 15)

    def test_pause_ending_in_the_last_two_days(self):
        row = _row(paused_until=NOW + D)
        assert subscription.pause_ending_push_due(row, NOW, 15)

    def test_pause_ending_not_earlier(self):
        row = _row(paused_until=NOW + 10 * D)
        assert not subscription.pause_ending_push_due(row, NOW, 15)

    def test_pause_ending_not_when_it_will_not_resume(self):
        row = _row(paused_until=NOW + D, cancel_effective_at=NOW + D)
        assert not subscription.pause_ending_push_due(row, NOW, 15)

    def test_pause_ending_only_once(self):
        row = _row(paused_until=NOW + D, pause_ending_push_sent_at=NOW - H)
        assert not subscription.pause_ending_push_due(row, NOW, 15)

    def test_pause_ending_waits_for_daytime(self):
        row = _row(paused_until=NOW + D)
        assert not subscription.pause_ending_push_due(row, NOW, 2)


class TestCopy:
    def test_winback_names_the_discount_and_the_date(self):
        c = subscription.winback_copy(30, datetime(2026, 5, 17, 19, 0))
        assert "30%" in c.title
        assert "17.05" in c.body
        assert "на месте" in c.body

    @pytest.mark.parametrize("days, phrase", [
        (0, "сегодня"), (1, "завтра"), (2, "через 2 дня"), (5, "через 5 дней"),
    ])
    def test_pause_ending_says_when(self, days, phrase):
        now_local = datetime(2026, 5, 10, 15, 0)
        c = subscription.pause_ending_copy(now_local + timedelta(days=days), now_local)
        assert phrase in c.title


# --------------------------------------------------------------------------
# Endpoints, against the real app
# --------------------------------------------------------------------------

def _buy(client, user, *, kind="individual", duration="month", promo=None):
    body = {"plan_kind": kind, "plan_duration": duration}
    if promo:
        body["promo_code"] = promo
    return client.post("/premium/purchase", json=body, headers=user.headers)


def _status(client, user):
    return client.get("/premium/status", headers=user.headers).json()


def _lapse(db, user, ago=timedelta(hours=2)):
    """Make the account's cancelled plan run out `ago` ago."""
    st = db.get(models.UserPremiumState, user.id)
    st.cancelled_at = datetime.now(timezone.utc) - ago - D
    st.cancel_effective_at = datetime.now(timezone.utc) - ago
    db.commit()
    return st


class TestEndpoints:
    def test_status_of_an_active_plan(self, client, register_user):
        alice = register_user()
        _buy(client, alice)
        body = _status(client, alice)
        assert body["subscription_phase"] == "active"
        assert body["pause_available"] is True
        assert body["pause_days"] == PAUSE_DAYS
        assert body["winback_percent"] is None
        assert body["paid_until"] is not None

    def test_paid_until_only_while_active(self, client, register_user):
        alice = register_user()
        _buy(client, alice)
        client.post("/premium/cancel", headers=alice.headers)
        assert _status(client, alice)["paid_until"] is None

    def test_status_of_an_account_that_never_bought(self, client, register_user):
        body = _status(client, register_user())
        assert body["subscription_phase"] is None
        assert body["pause_available"] is False

    def test_cancel_keeps_premium_and_reports_the_end(self, client, register_user):
        alice = register_user()
        _buy(client, alice)
        resp = client.post("/premium/cancel", headers=alice.headers)
        assert resp.status_code == 200
        body = resp.json()
        assert body["subscription_phase"] == "cancelling"
        assert body["is_premium"] is True
        assert body["cancel_effective_at"] is not None
        assert body["pause_available"] is False

    def test_cancel_twice_is_a_400(self, client, register_user):
        alice = register_user()
        _buy(client, alice)
        client.post("/premium/cancel", headers=alice.headers)
        assert client.post("/premium/cancel", headers=alice.headers).status_code == 400

    def test_cancel_without_a_plan_is_a_400(self, client, register_user):
        resp = client.post("/premium/cancel", headers=register_user().headers)
        assert resp.status_code == 400

    def test_undo_cancel(self, client, register_user):
        alice = register_user()
        _buy(client, alice)
        client.post("/premium/cancel", headers=alice.headers)
        body = client.post("/premium/resume", headers=alice.headers).json()
        assert body["subscription_phase"] == "active"
        assert body["cancel_effective_at"] is None

    def test_pause_turns_premium_off_and_resume_turns_it_on(self, client, register_user):
        alice = register_user()
        _buy(client, alice)
        body = client.post("/premium/pause", headers=alice.headers).json()
        assert body["subscription_phase"] == "paused"
        assert body["is_premium"] is False
        assert body["paused_until"] is not None
        assert body["pause_available"] is False

        body = client.post("/premium/resume", headers=alice.headers).json()
        assert body["subscription_phase"] == "active"
        assert body["is_premium"] is True
        assert body["paused_until"] is None
        # Ending it early doesn't hand the pause back.
        assert body["pause_available"] is False

    def test_pause_twice_is_a_400(self, client, register_user):
        alice = register_user()
        _buy(client, alice)
        client.post("/premium/pause", headers=alice.headers)
        assert client.post("/premium/pause", headers=alice.headers).status_code == 400

    def test_a_paused_account_is_back_on_the_free_limits(self, client, db_session, register_user):
        alice = register_user()
        _buy(client, alice)
        client.post("/premium/pause", headers=alice.headers)
        st = db_session.get(models.UserPremiumState, alice.id)
        st.ai_asks_used = 3
        st.ai_asks_month = f"{datetime.now(timezone.utc).year}-{datetime.now(timezone.utc).month}"
        db_session.commit()
        assert client.post("/premium/ai-ask", headers=alice.headers).json()["allowed"] is False

    def test_a_run_out_plan_is_not_premium(self, client, db_session, register_user):
        alice = register_user()
        _buy(client, alice)
        client.post("/premium/cancel", headers=alice.headers)
        _lapse(db_session, alice)
        body = _status(client, alice)
        assert body["is_premium"] is False
        assert body["subscription_phase"] == "lapsed"
        assert body["winback_percent"] == WINBACK_PERCENT
        assert body["winback_expires_at"] is not None
        # A lapsed plan is not offered a trial: it was bought before.
        assert body["trial_available"] is False

    def test_pause_finishes_by_itself(self, client, db_session, register_user):
        alice = register_user()
        _buy(client, alice)
        client.post("/premium/pause", headers=alice.headers)
        st = db_session.get(models.UserPremiumState, alice.id)
        st.paused_until = datetime.now(timezone.utc) - H
        db_session.commit()
        body = _status(client, alice)
        assert body["subscription_phase"] == "active"
        assert body["is_premium"] is True

    def test_referral_days_still_work_during_a_pause(self, client, db_session, register_user):
        alice = register_user()
        _buy(client, alice)
        client.post("/premium/pause", headers=alice.headers)
        st = db_session.get(models.UserPremiumState, alice.id)
        st.premium_expires_at = datetime.now(timezone.utc) + 5 * D
        db_session.commit()
        assert _status(client, alice)["is_premium"] is True

    def test_partner_seat_pauses_with_the_payer(self, client, register_user):
        alice, bob = register_user(), register_user()
        code = client.post("/partner/pair", headers=alice.headers).json()["pending_code"]
        assert client.post("/partner/join", json={"code": code}, headers=bob.headers).status_code == 200
        _buy(client, alice, kind="couple")
        assert _status(client, bob)["premium_source"] == "partner"

        client.post("/premium/pause", headers=alice.headers)
        assert _status(client, bob)["is_premium"] is False

        client.post("/premium/resume", headers=alice.headers)
        assert _status(client, bob)["premium_source"] == "partner"

    def test_a_covered_partner_has_nothing_to_cancel_or_pause(self, client, register_user):
        alice, bob = register_user(), register_user()
        code = client.post("/partner/pair", headers=alice.headers).json()["pending_code"]
        client.post("/partner/join", json={"code": code}, headers=bob.headers)
        _buy(client, alice, kind="couple")
        assert client.post("/premium/cancel", headers=bob.headers).status_code == 400
        assert client.post("/premium/pause", headers=bob.headers).status_code == 400


class TestWinbackPurchase:
    def _lapsed_account(self, client, db_session, register_user):
        alice = register_user()
        _buy(client, alice)
        client.post("/premium/cancel", headers=alice.headers)
        _lapse(db_session, alice)
        return alice

    def test_the_purchase_carries_the_discount_and_is_marked_as_winback(
        self, client, db_session, register_user,
    ):
        alice = self._lapsed_account(client, db_session, register_user)
        body = _buy(client, alice, duration="year").json()
        assert body["applied_discount_percent"] == WINBACK_PERCENT
        assert body["applied_discount_kind"] == "winback"
        assert body["is_premium"] is True
        assert body["subscription_phase"] == "active"
        assert body["cancel_effective_at"] is None
        assert body["winback_percent"] is None

    def test_only_once_ever(self, client, db_session, register_user):
        alice = self._lapsed_account(client, db_session, register_user)
        _buy(client, alice)
        client.post("/premium/cancel", headers=alice.headers)
        _lapse(db_session, alice)
        body = _status(client, alice)
        assert body["subscription_phase"] == "lapsed"
        assert body["winback_percent"] is None
        assert _buy(client, alice).json()["applied_discount_percent"] is None

    def test_no_discount_after_the_window(self, client, db_session, register_user):
        alice = register_user()
        _buy(client, alice)
        client.post("/premium/cancel", headers=alice.headers)
        _lapse(db_session, alice, ago=WINBACK_WINDOW + D)
        assert _buy(client, alice).json()["applied_discount_percent"] is None

    def test_a_first_purchase_has_no_winback(self, client, register_user):
        body = _buy(client, register_user()).json()
        assert body["applied_discount_percent"] is None
        assert body["applied_discount_kind"] is None

    def test_buying_again_while_cancelling_takes_the_cancellation_back(
        self, client, register_user,
    ):
        alice = register_user()
        _buy(client, alice)
        client.post("/premium/cancel", headers=alice.headers)
        body = _buy(client, alice).json()
        assert body["subscription_phase"] == "active"
        assert body["cancel_effective_at"] is None
        # Still running, so no comeback discount was spent.
        assert body["applied_discount_percent"] is None


# --------------------------------------------------------------------------
# Sender
# --------------------------------------------------------------------------

def _token(db, user, tz="Europe/Moscow"):
    db.add(models.PushToken(
        user_id=user.id, token=f"tok-{user.id}", platform="android", timezone=tz,
        last_seen_at=NOW,
    ))
    db.commit()


def _set(db, user, **fields):
    st = db.get(models.UserPremiumState, user.id)
    if st is None:
        st = models.UserPremiumState(user_id=user.id, is_premium=True, ai_asks_used=0)
        db.add(st)
    st.is_premium = True
    st.plan_kind = models.PremiumPlanKind.individual
    st.plan_duration = models.PremiumDuration.month
    st.purchased_at = NOW - 40 * D
    for k, v in fields.items():
        setattr(st, k, v)
    db.commit()
    return st


@pytest.fixture()
def fake_push():
    sent = []

    def _send(db, user, category, title, body, data=None):
        sent.append((user.id, category, title, body, data))
        return 1

    with patch.object(push.push_service, "send_to_user", side_effect=_send):
        yield sent


class TestSender:
    def test_winback_goes_out_once_and_is_recorded(self, db_session, register_user, fake_push):
        alice = register_user()
        _token(db_session, alice)
        st = _set(db_session, alice, cancel_effective_at=NOW - 2 * H)
        assert subscription.send_subscription_pushes(db_session, now_utc=NOW) == 1
        _, category, title, _body, data = fake_push[0]
        assert category == push.PushCategory.SUBSCRIPTION
        assert "30%" in title
        assert data["type"] == "winback"
        db_session.refresh(st)
        assert st.winback_push_sent_at is not None
        assert subscription.send_subscription_pushes(db_session, now_utc=NOW + H) == 0

    def test_no_timezone_no_push(self, db_session, register_user, fake_push):
        alice = register_user()
        _token(db_session, alice, tz=None)
        _set(db_session, alice, cancel_effective_at=NOW - 2 * H)
        assert subscription.send_subscription_pushes(db_session, now_utc=NOW) == 0

    def test_undelivered_push_is_retried(self, db_session, register_user):
        alice = register_user()
        _token(db_session, alice)
        st = _set(db_session, alice, cancel_effective_at=NOW - 2 * H)
        with patch.object(push.push_service, "send_to_user", return_value=0):
            assert subscription.send_subscription_pushes(db_session, now_utc=NOW) == 0
        db_session.refresh(st)
        assert st.winback_push_sent_at is None

    def test_no_winback_push_after_the_offer_was_used(self, db_session, register_user, fake_push):
        alice = register_user()
        _token(db_session, alice)
        _set(db_session, alice, cancel_effective_at=NOW - 2 * H, winback_used_at=NOW - H)
        assert subscription.send_subscription_pushes(db_session, now_utc=NOW) == 0

    def test_pause_ending_goes_out_once(self, db_session, register_user, fake_push):
        alice = register_user()
        _token(db_session, alice)
        st = _set(db_session, alice, paused_until=NOW + D, paused_at=NOW - 29 * D)
        assert subscription.send_subscription_pushes(db_session, now_utc=NOW) == 1
        assert fake_push[0][4]["type"] == "pause_ending"
        assert "завтра" in fake_push[0][2]
        db_session.refresh(st)
        assert st.pause_ending_push_sent_at is not None
        assert subscription.send_subscription_pushes(db_session, now_utc=NOW + H) == 0

    def test_no_pause_ending_push_for_a_cancelled_pause(self, db_session, register_user, fake_push):
        alice = register_user()
        _token(db_session, alice)
        _set(db_session, alice, paused_until=NOW + D, cancel_effective_at=NOW + D)
        assert subscription.send_subscription_pushes(db_session, now_utc=NOW) == 0

    def test_dry_run_sends_nothing_and_records_nothing(self, db_session, register_user, fake_push):
        alice = register_user()
        _token(db_session, alice)
        st = _set(db_session, alice, cancel_effective_at=NOW - 2 * H)
        assert subscription.send_subscription_pushes(db_session, dry_run=True, now_utc=NOW) == 1
        assert fake_push == []
        db_session.refresh(st)
        assert st.winback_push_sent_at is None
