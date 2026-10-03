"""Tests for the "sincerity points" feature (see app/sincerity.py's
module docstring for the product idea). Two layers, matching how
test_rate_limit.py treats RateLimiter:

- The earn_*/spend_*/apply_* functions in app/sincerity.py are tested
  directly against `db_session`, not through HTTP — the interesting
  behavior (staleness thresholds, cooldown windows, decay timing) is
  much more precisely provoked by calling them with an exact
  `planned_since`/timestamp than by trying to get a real WatchlistEntry
  into that exact state through the API.
- routers/sincerity.py (GET /me, PATCH /privacy) and the one endpoint
  in routers/watchlist.py that actually triggers an award
  (POST /watchlist/drop) are tested through real HTTP.

Not covered: recommendation stakes end-to-end (spend_recommendation_stake
/resolve_recommendation_stake have direct unit tests below, but no
router in this codebase calls them yet per routers/sincerity.py's own
module docstring — "partner.py or friends.py" is written as a future
home for that, not a shipped one), and earn_closed_gestalt's "watched"
trigger from routers/diary.py::log_watched (only the watchlist.py
"not for me" trigger is exercised here).
"""

from datetime import datetime, timedelta, timezone

from app import models, sincerity


def _get_user(db_session, user_id: str) -> models.User:
    return db_session.get(models.User, user_id)


def _make_watchlist_entry(db_session, user_id: str, *, status, created_at, **overrides) -> models.WatchlistEntry:
    fields = dict(
        user_id=user_id,
        media_id=f"tmdb-{models.gen_uuid()[:8]}",
        media_type=models.MediaType.movie,
        source="tmdb",
        title_en="Sincerity Test Movie",
        status=status,
        created_at=created_at,
    )
    fields.update(overrides)
    entry = models.WatchlistEntry(**fields)
    db_session.add(entry)
    db_session.commit()
    return entry


class TestRecordTransaction:
    def test_updates_balance_and_writes_a_row(self, db_session, register_user):
        alice = register_user()
        user = _get_user(db_session, alice.id)
        assert user.sincerity_balance == 0

        sincerity.record_transaction(
            db_session, user, delta=3, reason=models.SincerityReason.honest_drop, note="test"
        )
        db_session.commit()

        assert user.sincerity_balance == 3
        rows = db_session.query(models.SincerityTransaction).filter_by(user_id=alice.id).all()
        assert len(rows) == 1
        assert rows[0].delta == 3


class TestEarnClosedGestalt:
    def test_too_fresh_earns_nothing(self, db_session, register_user):
        alice = register_user()
        user = _get_user(db_session, alice.id)
        result = sincerity.earn_closed_gestalt(
            db_session, user,
            entry_id="e1", title="Fresh Movie",
            planned_since=datetime.now(timezone.utc) - timedelta(days=10),
            closed_honestly_as="not for me",
        )
        assert result is None
        assert user.sincerity_balance == 0

    def test_just_past_threshold_earns_the_base_amount(self, db_session, register_user):
        alice = register_user()
        user = _get_user(db_session, alice.id)
        result = sincerity.earn_closed_gestalt(
            db_session, user,
            entry_id="e1", title="Old Movie",
            planned_since=datetime.now(timezone.utc) - sincerity.STALE_PLANNED_THRESHOLD - timedelta(days=1),
            closed_honestly_as="watched",
        )
        assert result is not None
        assert result.delta == sincerity.CLOSED_GESTALT_BASE
        assert user.sincerity_balance == sincerity.CLOSED_GESTALT_BASE

    def test_award_scales_with_age_up_to_the_cap(self, db_session, register_user):
        alice = register_user()
        user = _get_user(db_session, alice.id)
        # Five full threshold-periods old -> base + min(4, MAX_BONUS).
        result = sincerity.earn_closed_gestalt(
            db_session, user,
            entry_id="e1", title="Ancient Movie",
            planned_since=datetime.now(timezone.utc) - sincerity.STALE_PLANNED_THRESHOLD * 5,
            closed_honestly_as="watched",
        )
        expected = sincerity.CLOSED_GESTALT_BASE + sincerity.CLOSED_GESTALT_MAX_BONUS
        assert result.delta == expected

    def test_award_never_exceeds_the_cap_no_matter_how_old(self, db_session, register_user):
        alice = register_user()
        user = _get_user(db_session, alice.id)
        result = sincerity.earn_closed_gestalt(
            db_session, user,
            entry_id="e1", title="Forgotten For Years",
            planned_since=datetime.now(timezone.utc) - sincerity.STALE_PLANNED_THRESHOLD * 50,
            closed_honestly_as="watched",
        )
        assert result.delta == sincerity.CLOSED_GESTALT_BASE + sincerity.CLOSED_GESTALT_MAX_BONUS


class TestEarnRevisedRating:
    def test_identical_rating_earns_nothing(self, db_session, register_user):
        alice = register_user()
        user = _get_user(db_session, alice.id)
        result = sincerity.earn_revised_rating(
            db_session, user, title_key="tmdb:603", title="The Matrix", old_rating=8, new_rating=8
        )
        assert result is None

    def test_a_real_change_earns_the_fixed_award(self, db_session, register_user):
        alice = register_user()
        user = _get_user(db_session, alice.id)
        result = sincerity.earn_revised_rating(
            db_session, user, title_key="tmdb:603", title="The Matrix", old_rating=6, new_rating=9
        )
        assert result.delta == sincerity.REVISED_RATING_AWARD
        assert "up" in result.note

    def test_second_change_inside_the_cooldown_earns_nothing(self, db_session, register_user):
        alice = register_user()
        user = _get_user(db_session, alice.id)
        sincerity.earn_revised_rating(db_session, user, title_key="tmdb:603", title="x", old_rating=6, new_rating=9)
        db_session.commit()

        again = sincerity.earn_revised_rating(
            db_session, user, title_key="tmdb:603", title="x", old_rating=9, new_rating=7
        )
        assert again is None
        assert user.sincerity_balance == sincerity.REVISED_RATING_AWARD  # unchanged by the second call

    def test_a_different_title_is_not_affected_by_another_titles_cooldown(self, db_session, register_user):
        alice = register_user()
        user = _get_user(db_session, alice.id)
        sincerity.earn_revised_rating(db_session, user, title_key="tmdb:603", title="x", old_rating=6, new_rating=9)
        db_session.commit()

        other_title = sincerity.earn_revised_rating(
            db_session, user, title_key="tmdb:604", title="y", old_rating=5, new_rating=8
        )
        assert other_title is not None

    def test_change_after_the_cooldown_has_passed_earns_again(self, db_session, register_user):
        alice = register_user()
        user = _get_user(db_session, alice.id)
        first = sincerity.earn_revised_rating(
            db_session, user, title_key="tmdb:603", title="x", old_rating=6, new_rating=9
        )
        db_session.commit()
        # Backdate the ledger row itself so the cooldown reads as expired,
        # rather than waiting REVISED_RATING_COOLDOWN in real time.
        first.created_at = datetime.now(timezone.utc) - sincerity.REVISED_RATING_COOLDOWN - timedelta(days=1)
        db_session.commit()

        second = sincerity.earn_revised_rating(
            db_session, user, title_key="tmdb:603", title="x", old_rating=9, new_rating=7
        )
        assert second is not None
        assert user.sincerity_balance == sincerity.REVISED_RATING_AWARD * 2


class TestEarnHonestDrop:
    def test_empty_reason_earns_nothing(self, db_session, register_user):
        alice = register_user()
        user = _get_user(db_session, alice.id)
        assert sincerity.earn_honest_drop(db_session, user, entry_id="e1", title="x", reason_text="") is None
        assert sincerity.earn_honest_drop(db_session, user, entry_id="e1", title="x", reason_text="   ") is None

    def test_a_real_reason_earns_the_fixed_award(self, db_session, register_user):
        alice = register_user()
        user = _get_user(db_session, alice.id)
        result = sincerity.earn_honest_drop(
            db_session, user, entry_id="e1", title="x", reason_text="too slow for me"
        )
        assert result.delta == sincerity.HONEST_DROP_AWARD


class TestRecommendationStakes:
    def test_spend_deducts_the_staked_amount(self, db_session, register_user):
        alice = register_user()
        user = _get_user(db_session, alice.id)
        sincerity.record_transaction(db_session, user, delta=5, reason=models.SincerityReason.honest_drop)
        db_session.commit()

        sincerity.spend_recommendation_stake(
            db_session, user, friend_id="f1", friend_name="Bob", title="x", amount=2
        )
        db_session.commit()
        assert user.sincerity_balance == 3

    def test_a_hit_within_tolerance_pays_back_the_stake_plus_bonus(self, db_session, register_user):
        alice = register_user()
        user = _get_user(db_session, alice.id)
        result = sincerity.resolve_recommendation_stake(
            db_session, user, friend_id="f1", friend_name="Bob", title="x",
            staked_amount=2, predicted_rating=8, actual_rating=7,  # within RECOMMENDATION_TOLERANCE=2
        )
        assert result.reason == models.SincerityReason.accurate_recommendation
        assert result.delta == 2 + round(2 * sincerity.ACCURATE_RECOMMENDATION_BONUS_RATE)

    def test_a_miss_forfeits_with_a_zero_delta_note(self, db_session, register_user):
        alice = register_user()
        user = _get_user(db_session, alice.id)
        result = sincerity.resolve_recommendation_stake(
            db_session, user, friend_id="f1", friend_name="Bob", title="x",
            staked_amount=2, predicted_rating=9, actual_rating=2,  # well outside tolerance
        )
        assert result.reason == models.SincerityReason.stake_forfeited
        assert result.delta == 0


class TestStalePlannedDecay:
    def test_no_charge_before_the_threshold(self, db_session, register_user):
        alice = register_user()
        user = _get_user(db_session, alice.id)
        result = sincerity.apply_stale_planned_decay(
            db_session, user, entry_id="e1", title="x",
            planned_since=datetime.now(timezone.utc) - timedelta(days=30),
        )
        assert result is None

    def test_charges_once_past_the_threshold(self, db_session, register_user):
        alice = register_user()
        user = _get_user(db_session, alice.id)
        result = sincerity.apply_stale_planned_decay(
            db_session, user, entry_id="e1", title="x",
            planned_since=datetime.now(timezone.utc) - sincerity.STALE_DEBT_THRESHOLD - timedelta(days=1),
        )
        assert result is not None
        assert result.delta == -sincerity.STALE_DEBT_AMOUNT

    def test_does_not_double_charge_inside_the_same_period(self, db_session, register_user):
        alice = register_user()
        user = _get_user(db_session, alice.id)
        planned_since = datetime.now(timezone.utc) - sincerity.STALE_DEBT_THRESHOLD - timedelta(days=1)
        sincerity.apply_stale_planned_decay(db_session, user, entry_id="e1", title="x", planned_since=planned_since)
        db_session.commit()

        again = sincerity.apply_stale_planned_decay(
            db_session, user, entry_id="e1", title="x", planned_since=planned_since
        )
        assert again is None

    def test_charges_again_once_a_new_period_has_passed(self, db_session, register_user):
        alice = register_user()
        user = _get_user(db_session, alice.id)
        planned_since = datetime.now(timezone.utc) - sincerity.STALE_DEBT_THRESHOLD - timedelta(days=1)
        first = sincerity.apply_stale_planned_decay(
            db_session, user, entry_id="e1", title="x", planned_since=planned_since
        )
        db_session.commit()
        first.created_at = datetime.now(timezone.utc) - sincerity.STALE_DEBT_PERIOD - timedelta(days=1)
        db_session.commit()

        second = sincerity.apply_stale_planned_decay(
            db_session, user, entry_id="e1", title="x", planned_since=planned_since
        )
        assert second is not None
        assert user.sincerity_balance == -sincerity.STALE_DEBT_AMOUNT * 2

    def test_for_user_sweeps_every_watch_later_entry(self, db_session, register_user):
        alice = register_user()
        user = _get_user(db_session, alice.id)
        old_time = datetime.now(timezone.utc) - sincerity.STALE_DEBT_THRESHOLD - timedelta(days=1)
        _make_watchlist_entry(db_session, alice.id, status=models.WatchStatus.watch_later, created_at=old_time)
        _make_watchlist_entry(db_session, alice.id, status=models.WatchStatus.watch_later, created_at=old_time)
        # Not watch_later -> should not be swept.
        _make_watchlist_entry(db_session, alice.id, status=models.WatchStatus.watched, created_at=old_time)

        charged = sincerity.apply_stale_planned_decay_for_user(db_session, user)
        assert len(charged) == 2


class TestSincerityHttp:
    def test_get_me_reflects_the_balance(self, client, register_user, db_session):
        alice = register_user()
        user = _get_user(db_session, alice.id)
        sincerity.record_transaction(db_session, user, delta=4, reason=models.SincerityReason.honest_drop, note="x")
        db_session.commit()

        resp = client.get("/sincerity/me", headers=alice.headers)
        assert resp.status_code == 200
        body = resp.json()
        assert body["balance"] == 4
        assert body["visible_to_friends"] is False
        assert len(body["history"]) == 1

    def test_requires_auth(self, client):
        assert client.get("/sincerity/me").status_code == 401

    def test_privacy_toggle(self, client, register_user):
        alice = register_user()
        resp = client.patch("/sincerity/privacy", json={"visible_to_friends": True}, headers=alice.headers)
        assert resp.status_code == 200
        assert resp.json()["visible_to_friends"] is True

        still_get = client.get("/sincerity/me", headers=alice.headers)
        assert still_get.json()["visible_to_friends"] is True


class TestWatchlistDrop:
    def test_dropping_a_watching_item_with_a_reason_awards_honest_drop(self, client, register_user, db_session):
        alice = register_user()
        entry = _make_watchlist_entry(
            db_session, alice.id, status=models.WatchStatus.watching, created_at=datetime.now(timezone.utc)
        )

        resp = client.post(
            "/watchlist/drop",
            json={"media_id": entry.media_id, "source": entry.source, "reason": "too slow for me"},
            headers=alice.headers,
        )
        assert resp.status_code == 200
        body = resp.json()
        assert body["status"] == "dropped"
        assert body["sincerity_awarded"][0]["reason"] == "honest_drop"

    def test_dropping_a_watching_item_with_no_reason_awards_nothing(self, client, register_user, db_session):
        alice = register_user()
        entry = _make_watchlist_entry(
            db_session, alice.id, status=models.WatchStatus.watching, created_at=datetime.now(timezone.utc)
        )

        resp = client.post(
            "/watchlist/drop", json={"media_id": entry.media_id, "source": entry.source}, headers=alice.headers
        )
        assert resp.status_code == 200
        assert resp.json()["sincerity_awarded"] is None

    def test_dropping_a_fresh_watch_later_item_earns_nothing_but_still_drops_it(
        self, client, register_user, db_session
    ):
        alice = register_user()
        entry = _make_watchlist_entry(
            db_session, alice.id, status=models.WatchStatus.watch_later, created_at=datetime.now(timezone.utc)
        )

        resp = client.post(
            "/watchlist/drop", json={"media_id": entry.media_id, "source": entry.source}, headers=alice.headers
        )
        assert resp.status_code == 200
        assert resp.json()["status"] == "dropped"
        assert resp.json()["sincerity_awarded"] is None

    def test_already_watched_cannot_be_dropped(self, client, register_user, db_session):
        alice = register_user()
        entry = _make_watchlist_entry(
            db_session, alice.id, status=models.WatchStatus.watched, created_at=datetime.now(timezone.utc)
        )
        resp = client.post(
            "/watchlist/drop", json={"media_id": entry.media_id, "source": entry.source}, headers=alice.headers
        )
        assert resp.status_code == 400

    def test_not_on_watchlist_is_404(self, client, register_user):
        alice = register_user()
        resp = client.post(
            "/watchlist/drop", json={"media_id": "not-really-there", "source": "tmdb"}, headers=alice.headers
        )
        assert resp.status_code == 404

    def test_cannot_drop_someone_elses_entry(self, client, register_user, db_session):
        alice = register_user()
        bob = register_user()
        entry = _make_watchlist_entry(
            db_session, alice.id, status=models.WatchStatus.watching, created_at=datetime.now(timezone.utc)
        )
        resp = client.post(
            "/watchlist/drop",
            json={"media_id": entry.media_id, "source": entry.source, "reason": "not mine to drop"},
            headers=bob.headers,
        )
        assert resp.status_code == 404
