"""The trial-ending reminder series — see app/trial.py.

Two layers: `due_stage` is a pure function and is tested exhaustively
without a database; the sender and the status payload go through the
real app against Postgres like every other test here.
"""

from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import pytest

from app import models, push, trial
from app.trial import (
    STAGE_ENDED,
    STAGE_ENDS_SOON,
    STAGE_LAST_HOURS,
    STAGE_NONE,
    due_stage,
    reminder_copy,
)

H = timedelta(hours=1)


class TestDueStage:
    def test_nothing_far_from_the_end(self):
        assert due_stage(STAGE_NONE, 60 * H, 12) is None

    def test_first_reminder_in_daytime_window(self):
        assert due_stage(STAGE_NONE, 30 * H, 12) == STAGE_ENDS_SOON

    def test_first_reminder_waits_for_daytime(self):
        assert due_stage(STAGE_NONE, 30 * H, 3) is None
        assert due_stage(STAGE_NONE, 30 * H, 23) is None

    def test_first_reminder_never_repeats(self):
        assert due_stage(STAGE_ENDS_SOON, 30 * H, 12) is None

    def test_last_hours_reminder(self):
        assert due_stage(STAGE_ENDS_SOON, 9 * H, 15) == STAGE_LAST_HOURS

    def test_last_hours_waits_out_the_night(self):
        assert due_stage(STAGE_ENDS_SOON, 9 * H, 2) is None

    def test_skipped_first_stage_is_not_made_up_for(self):
        # First reachable with 5h left: gets the last-hours message, and
        # only that one.
        assert due_stage(STAGE_NONE, 5 * H, 14) == STAGE_LAST_HOURS
        assert due_stage(STAGE_LAST_HOURS, 4 * H, 15) is None

    def test_two_pushes_are_never_back_to_back(self):
        # Stage 1 stops at 16h left, stage 2 starts at 12h.
        assert due_stage(STAGE_NONE, 14 * H, 12) is None

    def test_win_back_after_the_end(self):
        assert due_stage(STAGE_LAST_HOURS, -3 * H, 11) == STAGE_ENDED

    def test_win_back_not_immediately_and_not_forever(self):
        assert due_stage(STAGE_LAST_HOURS, -10 * 60 * timedelta(seconds=1), 11) is None
        assert due_stage(STAGE_LAST_HOURS, -60 * H, 11) is None

    def test_win_back_sent_once(self):
        assert due_stage(STAGE_ENDED, -3 * H, 11) is None

    @pytest.mark.parametrize("tz_offset_hours", range(-11, 13))
    def test_every_timezone_gets_a_chance_at_every_stage(self, tz_offset_hours):
        """Whatever the local offset, sweeping the clock hour by hour
        through each window must hit at least one allowed hour — the
        property the window sizes in app/trial.py are chosen for."""
        end = datetime(2026, 1, 10, 7, 0, tzinfo=timezone.utc)  # arbitrary end moment
        for start_stage, lo_h, hi_h, expect in (
            (STAGE_NONE, 16, 40, STAGE_ENDS_SOON),
            (STAGE_ENDS_SOON, 0, 12, STAGE_LAST_HOURS),
        ):
            hit = False
            for minutes in range(int(lo_h * 60) + 1, int(hi_h * 60) + 1, 60):
                left = timedelta(minutes=minutes)
                now = end - left
                local_hour = (now + timedelta(hours=tz_offset_hours)).hour
                if due_stage(start_stage, left, local_hour) == expect:
                    hit = True
                    break
            assert hit, (tz_offset_hours, expect)


class TestCopy:
    def _copy(self, stage, logged=0, end_hour=19, days_ahead=1):
        now = datetime(2026, 5, 1, 12, 0, tzinfo=timezone.utc)
        end = (now + timedelta(days=days_ahead)).replace(hour=end_hour, minute=40)
        return reminder_copy(stage, end_local=end, now_local=now, logged_count=logged)

    def test_ends_soon_says_when_and_that_nothing_is_charged(self):
        c = self._copy(STAGE_ENDS_SOON)
        assert "завтра в 19:40" in c.title
        assert "не спишется" in c.body

    def test_activity_line_only_when_there_is_activity(self):
        assert "За это время" not in self._copy(STAGE_ENDS_SOON, logged=0).body
        assert "3 действия" in self._copy(STAGE_ENDS_SOON, logged=3).body
        assert "11 действий" in self._copy(STAGE_ENDS_SOON, logged=11).body
        assert "21 действие" in self._copy(STAGE_ENDS_SOON, logged=21).body

    def test_ended_reassures_about_records(self):
        c = self._copy(STAGE_ENDED)
        assert "закончился" in c.title
        assert "на месте" in c.body


# --------------------------------------------------------------------------
# Sender + status payload, against the real app
# --------------------------------------------------------------------------

NOW = datetime(2026, 5, 10, 12, 0, tzinfo=timezone.utc)  # 12:00 UTC == 15:00 Moscow


def _state(db, user) -> models.UserPremiumState:
    st = db.get(models.UserPremiumState, user.id)
    if st is None:
        st = models.UserPremiumState(user_id=user.id, is_premium=False, ai_asks_used=0)
        db.add(st)
        db.commit()
    return st


def _trial(db, user, ends_in: timedelta, stage=0, started_ago=timedelta(days=2)):
    st = _state(db, user)
    st.trial_started_at = NOW - started_ago
    st.premium_expires_at = NOW + ends_in
    st.trial_reminder_stage = stage
    db.commit()
    return st


def _token(db, user, tz="Europe/Moscow"):
    db.add(models.PushToken(
        user_id=user.id, token=f"tok-{user.id}", platform="android", timezone=tz,
        last_seen_at=NOW,
    ))
    db.commit()


@pytest.fixture()
def fake_push():
    """Firebase is unconfigured in tests; replace the one send call so
    the sender's own logic (who, when, what, and stage bookkeeping) is
    what's under test."""
    sent = []

    def _send(db, user, category, title, body, data=None):
        sent.append((user.id, category, title, body, data))
        return 1

    with patch.object(push.push_service, "send_to_user", side_effect=_send):
        yield sent


class TestSender:
    def test_sends_first_reminder_and_records_stage(self, db_session, register_user, fake_push):
        alice = register_user()
        _token(db_session, alice)
        st = _trial(db_session, alice, ends_in=timedelta(hours=30))

        assert trial.send_trial_reminders(db_session, now_utc=NOW) == 1
        assert len(fake_push) == 1
        _, category, title, _body, data = fake_push[0]
        assert category == push.PushCategory.SUBSCRIPTION
        assert "Бесплатный период закончится" in title
        assert data == {"type": "trial_ending", "stage": STAGE_ENDS_SOON}
        db_session.refresh(st)
        assert st.trial_reminder_stage == STAGE_ENDS_SOON

        # Same hour, run again: nothing more.
        assert trial.send_trial_reminders(db_session, now_utc=NOW) == 0

    def test_no_timezone_means_no_push(self, db_session, register_user, fake_push):
        alice = register_user()
        _token(db_session, alice, tz=None)
        _trial(db_session, alice, ends_in=timedelta(hours=30))
        assert trial.send_trial_reminders(db_session, now_utc=NOW) == 0
        assert fake_push == []

    def test_night_locally_waits(self, db_session, register_user, fake_push):
        alice = register_user()
        _token(db_session, alice, tz="Asia/Tokyo")  # 21:00 JST... shift to 03:00
        _trial(db_session, alice, ends_in=timedelta(hours=30))
        night = NOW + timedelta(hours=6)  # 18:00 UTC == 03:00 JST
        # The trial's end is relative to `night` here, not NOW.
        st = db_session.get(models.UserPremiumState, alice.id)
        st.premium_expires_at = night + timedelta(hours=30)
        db_session.commit()
        assert trial.send_trial_reminders(db_session, now_utc=night) == 0

    def test_paying_customer_is_never_reminded(self, db_session, register_user, fake_push):
        alice = register_user()
        _token(db_session, alice)
        st = _trial(db_session, alice, ends_in=timedelta(hours=8), stage=STAGE_ENDS_SOON)
        st.purchased_at = NOW - timedelta(hours=1)
        st.is_premium = True
        db_session.commit()
        assert trial.send_trial_reminders(db_session, now_utc=NOW) == 0

    def test_undelivered_push_does_not_burn_the_stage(self, db_session, register_user):
        alice = register_user()
        _token(db_session, alice)
        st = _trial(db_session, alice, ends_in=timedelta(hours=30))
        with patch.object(push.push_service, "send_to_user", return_value=0):
            assert trial.send_trial_reminders(db_session, now_utc=NOW) == 0
        db_session.refresh(st)
        assert st.trial_reminder_stage == STAGE_NONE

    def test_win_back_after_expiry_then_silence(self, db_session, register_user, fake_push):
        alice = register_user()
        _token(db_session, alice)
        st = _trial(db_session, alice, ends_in=-timedelta(hours=3), stage=STAGE_LAST_HOURS)
        assert trial.send_trial_reminders(db_session, now_utc=NOW) == 1
        assert fake_push[0][4] == {"type": "trial_ended", "stage": STAGE_ENDED}
        db_session.refresh(st)
        assert st.trial_reminder_stage == STAGE_ENDED
        assert trial.send_trial_reminders(db_session, now_utc=NOW + timedelta(hours=1)) == 0

    def test_partner_covered_account_is_not_told_it_ended(
        self, client, db_session, register_user, fake_push,
    ):
        alice, bob = register_user(), register_user()
        _token(db_session, bob)
        code = client.post("/partner/pair", headers=alice.headers).json()["pending_code"]
        assert client.post("/partner/join", json={"code": code}, headers=bob.headers).status_code == 200
        a = _state(db_session, alice)
        a.is_premium, a.plan_kind = True, models.PremiumPlanKind.couple
        a.plan_duration, a.purchased_at = models.PremiumDuration.month, NOW
        db_session.commit()
        _trial(db_session, bob, ends_in=-timedelta(hours=3), stage=STAGE_LAST_HOURS)
        assert trial.send_trial_reminders(db_session, now_utc=NOW) == 0


class TestStatusPayload:
    def test_never_trialed(self, client, register_user):
        alice = register_user()
        body = client.get("/premium/status", headers=alice.headers).json()
        assert body["trial_phase"] is None
        assert body["trial_ends_at"] is None
        assert body["trial_available"] is True

    def test_active_then_expired(self, client, db_session, register_user):
        alice = register_user()
        assert client.post("/premium/start-trial", headers=alice.headers).status_code == 200
        body = client.get("/premium/status", headers=alice.headers).json()
        assert body["trial_phase"] == "active"
        assert body["trial_ends_at"] is not None
        assert body["is_premium"] is True

        st = db_session.get(models.UserPremiumState, alice.id)
        st.premium_expires_at = datetime.now(timezone.utc) - timedelta(hours=1)
        db_session.commit()
        body = client.get("/premium/status", headers=alice.headers).json()
        assert body["trial_phase"] == "expired"
        assert body["trial_ends_at"] is None
        assert body["is_premium"] is False
        assert body["trial_available"] is False

    def test_purchase_clears_the_trial_phase(self, client, register_user):
        alice = register_user()
        client.post("/premium/start-trial", headers=alice.headers)
        resp = client.post(
            "/premium/purchase",
            json={"plan_kind": "individual", "plan_duration": "year"},
            headers=alice.headers,
        )
        assert resp.status_code == 200
        assert resp.json()["trial_phase"] is None

    def test_subscription_category_is_listed_in_push_preferences(self, client, register_user):
        alice = register_user()
        cats = client.get("/push/preferences", headers=alice.headers).json()["categories"]
        assert "subscription" in {c["category"] for c in cats}
