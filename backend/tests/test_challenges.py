"""Tests for app/challenges.py and routers/challenges.py.

evaluate()/live_weekly()/live_yearly() all take an explicit `today`
rather than always reaching for the real date.today() — so most of this
runs against a fixed, hardcoded date instead of "whatever week it
happens to be when CI runs", the same reasoning test_rate_limit.py
monkeypatches time.time() for. The one place that can't be pinned down
this way is the HTTP layer (claim_challenge/mark_seen call date.today()
internally, with no way to inject a date through the request) — those
tests work around it by asking the real catalog which challenges are
actually live *right now* and inserting a ChallengeProgress row
directly for one of them, rather than trying to satisfy its measure
naturally through diary entries (see evaluate()'s own docstring:
completion is read from the stored row, not recomputed each time, which
is exactly what makes this shortcut valid).

FIXED_MONDAY below is a real, arbitrary Monday — only its weekday and
the fact that app/challenges.py has no month/year-specific special
casing matter.
"""

from datetime import date, datetime, timedelta, timezone

from app import challenges as catalog
from app import models


FIXED_MONDAY = date(2030, 1, 7)


def _make_diary_entry(db_session, user_id: str, watched_at: datetime, **overrides) -> models.DiaryEntry:
    fields = dict(
        user_id=user_id,
        media_id=f"tmdb-{models.gen_uuid()[:8]}",
        media_type=models.MediaType.movie,
        source="tmdb",
        title_en="Challenge Test Movie",
        watched_at=watched_at,
    )
    fields.update(overrides)
    entry = models.DiaryEntry(**fields)
    db_session.add(entry)
    db_session.commit()
    return entry


class TestLiveSelection:
    def test_exactly_three_weekly_are_live_at_once(self):
        assert len(catalog.live_weekly(FIXED_MONDAY)) == catalog.WEEKLY_LIVE_COUNT

    def test_selection_is_deterministic_for_the_same_date(self):
        first = [c.id for c in catalog.live_weekly(FIXED_MONDAY)]
        second = [c.id for c in catalog.live_weekly(FIXED_MONDAY)]
        assert first == second

    def test_a_different_week_can_select_a_different_trio(self):
        this_week = {c.id for c in catalog.live_weekly(FIXED_MONDAY)}
        # +13 weeks rather than +1 — a deterministic shuffle isn't
        # guaranteed to differ on every single adjacent week, but is
        # extremely unlikely to land on the exact same trio 13 weeks out.
        other_week = {c.id for c in catalog.live_weekly(FIXED_MONDAY + timedelta(weeks=13))}
        assert this_week != other_week

    def test_all_yearly_challenges_are_always_live(self):
        assert len(catalog.live_yearly(FIXED_MONDAY)) == len(catalog.live_yearly(FIXED_MONDAY + timedelta(days=200)))


class TestEvaluateWeekly:
    """Driven through w_rate_honestly (rate 3 evenings, target=3) —
    whichever weekly challenges are live for FIXED_MONDAY, that one is
    among them (see the module-level check this file's test run would
    fail loudly on, below, if the catalog ever changes)."""

    def setup_method(self):
        assert any(c.id == "w_rate_honestly" for c in catalog.live_weekly(FIXED_MONDAY)), (
            "this test file assumes w_rate_honestly is live for FIXED_MONDAY — "
            "if the catalog pool changed, pick a different fixed date or challenge"
        )

    def test_zero_progress_before_any_entries(self, db_session, register_user):
        alice = register_user()
        states = catalog.evaluate(db_session, alice.id, today=FIXED_MONDAY)
        state = next(s for s in states if s.challenge.id == "w_rate_honestly")
        assert state.current == 0
        assert state.completed is False

    def test_partial_progress_is_not_completed(self, db_session, register_user):
        alice = register_user()
        for _ in range(2):
            _make_diary_entry(db_session, alice.id, datetime(2030, 1, 8), rating=7)
        states = catalog.evaluate(db_session, alice.id, today=FIXED_MONDAY)
        state = next(s for s in states if s.challenge.id == "w_rate_honestly")
        assert state.current == 2
        assert state.completed is False

    def test_hitting_the_target_marks_it_completed(self, db_session, register_user):
        alice = register_user()
        for _ in range(3):
            _make_diary_entry(db_session, alice.id, datetime(2030, 1, 8), rating=7)
        states = catalog.evaluate(db_session, alice.id, today=FIXED_MONDAY)
        db_session.commit()
        state = next(s for s in states if s.challenge.id == "w_rate_honestly")
        assert state.current == 3
        assert state.completed is True
        assert state.completed_at is not None
        assert state.needs_announcement is True  # not yet claimed or seen

    def test_entries_outside_the_week_do_not_count(self, db_session, register_user):
        alice = register_user()
        for _ in range(3):
            # The following Monday — a different ISO week entirely.
            _make_diary_entry(db_session, alice.id, datetime(2030, 1, 14), rating=7)
        states = catalog.evaluate(db_session, alice.id, today=FIXED_MONDAY)
        state = next(s for s in states if s.challenge.id == "w_rate_honestly")
        assert state.current == 0

    def test_unrated_entries_do_not_count(self, db_session, register_user):
        alice = register_user()
        for _ in range(3):
            _make_diary_entry(db_session, alice.id, datetime(2030, 1, 8), rating=None)
        states = catalog.evaluate(db_session, alice.id, today=FIXED_MONDAY)
        state = next(s for s in states if s.challenge.id == "w_rate_honestly")
        assert state.current == 0

    def test_completion_timestamp_survives_deleting_the_entries_afterwards(self, db_session, register_user):
        # The exact scenario evaluate()'s own docstring calls out: once
        # completed_at is stored, un-logging the entries that earned it
        # doesn't quietly un-complete the challenge.
        alice = register_user()
        entries = [_make_diary_entry(db_session, alice.id, datetime(2030, 1, 8), rating=7) for _ in range(3)]
        first_pass = catalog.evaluate(db_session, alice.id, today=FIXED_MONDAY)
        db_session.commit()
        completed_at = next(s for s in first_pass if s.challenge.id == "w_rate_honestly").completed_at

        for e in entries:
            db_session.delete(e)
        db_session.commit()

        second_pass = catalog.evaluate(db_session, alice.id, today=FIXED_MONDAY)
        state = next(s for s in second_pass if s.challenge.id == "w_rate_honestly")
        assert state.completed is True
        assert state.completed_at == completed_at
        assert state.current == 0  # progress itself does recompute — just not completion


class TestEvaluateYearly:
    """Driven through y_five_decades (5 distinct release decades)."""

    def test_four_decades_is_not_enough(self, db_session, register_user):
        alice = register_user()
        for year in (1975, 1985, 1995, 2005):
            _make_diary_entry(db_session, alice.id, datetime(2030, 6, 1), year=year)
        states = catalog.evaluate(db_session, alice.id, today=FIXED_MONDAY)
        state = next(s for s in states if s.challenge.id == "y_five_decades")
        assert state.current == 4
        assert state.completed is False

    def test_five_distinct_decades_completes_it(self, db_session, register_user):
        alice = register_user()
        for year in (1975, 1985, 1995, 2005, 2015):
            _make_diary_entry(db_session, alice.id, datetime(2030, 6, 1), year=year)
        states = catalog.evaluate(db_session, alice.id, today=FIXED_MONDAY)
        state = next(s for s in states if s.challenge.id == "y_five_decades")
        assert state.current == 5
        assert state.completed is True

    def test_same_decade_twice_only_counts_once(self, db_session, register_user):
        alice = register_user()
        for year in (1975, 1976, 1977, 1985, 1995):  # first three share the 1970s
            _make_diary_entry(db_session, alice.id, datetime(2030, 6, 1), year=year)
        states = catalog.evaluate(db_session, alice.id, today=FIXED_MONDAY)
        state = next(s for s in states if s.challenge.id == "y_five_decades")
        assert state.current == 3  # 1970s, 1980s, 1990s

    def test_entries_from_a_different_year_do_not_count(self, db_session, register_user):
        alice = register_user()
        for year in (1975, 1985, 1995, 2005, 2015):
            _make_diary_entry(db_session, alice.id, datetime(2029, 6, 1), year=year)  # wrong calendar year
        states = catalog.evaluate(db_session, alice.id, today=FIXED_MONDAY)
        state = next(s for s in states if s.challenge.id == "y_five_decades")
        assert state.current == 0


class TestChallengesHttp:
    def test_get_challenges_requires_auth(self, client):
        assert client.get("/challenges").status_code == 401

    def test_get_challenges_lists_three_weekly_and_all_yearly(self, client, register_user):
        alice = register_user()
        resp = client.get("/challenges", headers=alice.headers)
        assert resp.status_code == 200
        body = resp.json()
        assert len(body["weekly"]) == catalog.WEEKLY_LIVE_COUNT
        assert len(body["yearly"]) == len(catalog.live_yearly())

    def test_claim_before_completion_is_409(self, client, register_user):
        alice = register_user()
        challenge_id = catalog.live_weekly(date.today())[0].id
        resp = client.post(f"/challenges/{challenge_id}/claim", headers=alice.headers)
        assert resp.status_code == 409

    def test_claim_an_unknown_challenge_id_is_404(self, client, register_user):
        alice = register_user()
        resp = client.post("/challenges/not-a-real-challenge-id/claim", headers=alice.headers)
        assert resp.status_code == 404

    def test_claiming_a_completed_challenge_awards_its_points(self, client, register_user, db_session):
        alice = register_user()
        challenge = catalog.live_weekly(date.today())[0]
        pkey = catalog.period_key(challenge.cadence, date.today())
        db_session.add(models.ChallengeProgress(
            user_id=alice.id, challenge_id=challenge.id, period_key=pkey,
            completed_at=datetime.now(timezone.utc),
        ))
        db_session.commit()

        resp = client.post(f"/challenges/{challenge.id}/claim", headers=alice.headers)
        assert resp.status_code == 200
        body = resp.json()
        assert body["points_awarded"] == challenge.points
        assert body["challenge"]["claimed"] is True

    def test_claiming_twice_is_409_the_second_time(self, client, register_user, db_session):
        alice = register_user()
        challenge = catalog.live_weekly(date.today())[0]
        pkey = catalog.period_key(challenge.cadence, date.today())
        db_session.add(models.ChallengeProgress(
            user_id=alice.id, challenge_id=challenge.id, period_key=pkey,
            completed_at=datetime.now(timezone.utc),
        ))
        db_session.commit()

        client.post(f"/challenges/{challenge.id}/claim", headers=alice.headers)
        again = client.post(f"/challenges/{challenge.id}/claim", headers=alice.headers)
        assert again.status_code == 409

    def test_claim_increases_the_account_level_points(self, client, register_user, db_session):
        alice = register_user()
        challenge = catalog.live_weekly(date.today())[0]
        pkey = catalog.period_key(challenge.cadence, date.today())
        db_session.add(models.ChallengeProgress(
            user_id=alice.id, challenge_id=challenge.id, period_key=pkey,
            completed_at=datetime.now(timezone.utc),
        ))
        db_session.commit()

        before = client.get("/profile/level", headers=alice.headers).json()
        client.post(f"/challenges/{challenge.id}/claim", headers=alice.headers)
        after = client.get("/profile/level", headers=alice.headers).json()
        assert after["points"] == before["points"] + challenge.points

    def test_mark_seen_clears_the_announcement(self, client, register_user, db_session):
        alice = register_user()
        challenge = catalog.live_weekly(date.today())[0]
        pkey = catalog.period_key(challenge.cadence, date.today())
        db_session.add(models.ChallengeProgress(
            user_id=alice.id, challenge_id=challenge.id, period_key=pkey,
            completed_at=datetime.now(timezone.utc),
        ))
        db_session.commit()

        before = client.get("/challenges", headers=alice.headers).json()
        assert any(c["id"] == challenge.id for c in before["to_announce"])

        seen = client.post("/challenges/seen", headers=alice.headers)
        assert seen.status_code == 204

        after = client.get("/challenges", headers=alice.headers).json()
        assert all(c["id"] != challenge.id for c in after["to_announce"])

    def test_marking_seen_does_not_claim_the_reward(self, client, register_user, db_session):
        alice = register_user()
        challenge = catalog.live_weekly(date.today())[0]
        pkey = catalog.period_key(challenge.cadence, date.today())
        db_session.add(models.ChallengeProgress(
            user_id=alice.id, challenge_id=challenge.id, period_key=pkey,
            completed_at=datetime.now(timezone.utc),
        ))
        db_session.commit()

        client.post("/challenges/seen", headers=alice.headers)
        still_unclaimed = client.get("/challenges", headers=alice.headers).json()
        matching = next(c for c in still_unclaimed["weekly"] + still_unclaimed["yearly"] if c["id"] == challenge.id)
        assert matching["claimed"] is False
