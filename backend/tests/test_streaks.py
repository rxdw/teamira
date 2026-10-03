"""app/streaks.py — pulled out of profile.py's own wrapped-stats
calculation (untested there; see this file's own docstring), now shared
with scripts/send_scheduled_push.py's streak reminder. No HTTP layer to
go through here, so these hit ActivityEvent rows directly rather than
via a diary log — see tests/test_push_triggers_diary.py for the
"logging through the real endpoint produces a correct streak" version.
"""

from datetime import datetime, timedelta, timezone

from app import models
from app.streaks import current_streak, logged_today


def _event(db, user_id, days_ago: int):
    when = datetime.now(timezone.utc) - timedelta(days=days_ago)
    db.add(models.ActivityEvent(
        user_id=user_id, verb="watched", media_title="Something",
        media_type=models.MediaType.movie, created_at=when,
    ))


class TestCurrentStreak:
    def test_no_events_is_zero(self, db_session, register_user):
        alice = register_user()
        assert current_streak(db_session, alice.id) == 0

    def test_one_event_today_is_a_streak_of_one(self, db_session, register_user):
        alice = register_user()
        _event(db_session, alice.id, days_ago=0)
        db_session.commit()
        assert current_streak(db_session, alice.id) == 1

    def test_three_consecutive_days_ending_today(self, db_session, register_user):
        alice = register_user()
        for d in (0, 1, 2):
            _event(db_session, alice.id, days_ago=d)
        db_session.commit()
        assert current_streak(db_session, alice.id) == 3

    def test_a_gap_stops_the_count(self, db_session, register_user):
        alice = register_user()
        for d in (0, 1, 3, 4):  # gap at day 2
            _event(db_session, alice.id, days_ago=d)
        db_session.commit()
        assert current_streak(db_session, alice.id) == 2

    def test_not_logging_today_yet_does_not_reset_yesterdays_streak(self, db_session, register_user):
        """The whole point of the "today hasn't happened yet" allowance
        — someone with a real 5-day streak who hasn't opened the app yet
        today still has a 5-day streak as far as this is concerned,
        right up until the UTC day rolls over with nothing logged."""
        alice = register_user()
        for d in (1, 2, 3, 4, 5):  # nothing today (day 0)
            _event(db_session, alice.id, days_ago=d)
        db_session.commit()
        assert current_streak(db_session, alice.id) == 5

    def test_a_gap_before_yesterday_means_the_streak_is_already_zero(self, db_session, register_user):
        alice = register_user()
        _event(db_session, alice.id, days_ago=3)  # too long ago
        db_session.commit()
        assert current_streak(db_session, alice.id) == 0

    def test_as_of_lets_the_caller_pin_a_specific_day(self, db_session, register_user):
        """scripts/send_scheduled_push.py doesn't need this (it always
        asks about "now"), but a fixed `as_of` makes the rest of this
        test class's assertions reproducible regardless of what day it
        actually is when the suite runs."""
        alice = register_user()
        today = datetime.now(timezone.utc).date()
        for d in (0, 1, 2):
            _event(db_session, alice.id, days_ago=d)
        db_session.commit()
        assert current_streak(db_session, alice.id, as_of=today) == 3
        assert current_streak(db_session, alice.id, as_of=today - timedelta(days=10)) == 0


class TestLoggedToday:
    def test_false_with_no_events(self, db_session, register_user):
        alice = register_user()
        assert logged_today(db_session, alice.id) is False

    def test_true_after_todays_event(self, db_session, register_user):
        alice = register_user()
        _event(db_session, alice.id, days_ago=0)
        db_session.commit()
        assert logged_today(db_session, alice.id) is True

    def test_false_when_only_yesterday_has_an_event(self, db_session, register_user):
        alice = register_user()
        _event(db_session, alice.id, days_ago=1)
        db_session.commit()
        assert logged_today(db_session, alice.id) is False
