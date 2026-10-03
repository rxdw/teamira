"""Tests for routers/card_shares.py and the informational
`watched_together_count` stat in routers/profile.py::compute_level_for_user
(sharing a card, evenings watched together).

Since app/sincerity.py's merge of the old XP system into sincerity
points (see that module's docstring), points only ever land on
User.lifetime_sincerity_earned through an actual ledger write — a
DiaryEntry inserted directly in the test database (bypassing
routers/diary.py::log_watched) shows up in the *informational* counts
below (watched_together_count and friends) but earns nothing, exactly
like it wouldn't in the real app if a row somehow existed without ever
being logged through the diary endpoint.
"""

from datetime import datetime, timezone

from app import models, sincerity
from app.routers.card_shares import MAX_REWARDED_SHARES_PER_DAY


def _level(client, user) -> dict:
    resp = client.get("/profile/level", headers=user.headers)
    assert resp.status_code == 200
    return resp.json()


def _share(client, user, key: str):
    return client.post("/shares/card", json={"card_key": key}, headers=user.headers)


def _diary_entry(db_session, user_id: str, **overrides) -> models.DiaryEntry:
    fields = dict(
        user_id=user_id,
        media_id=f"tmdb-{models.gen_uuid()[:8]}",
        media_type=models.MediaType.movie,
        source="tmdb",
        title_en="Sincerity Test Movie",
        watched_at=datetime.now(timezone.utc),
    )
    fields.update(overrides)
    entry = models.DiaryEntry(**fields)
    db_session.add(entry)
    db_session.commit()
    return entry


class TestCardShareEndpoint:
    def test_requires_auth(self, client):
        resp = client.post("/shares/card", json={"card_key": "seenly-abc"})
        assert resp.status_code in (401, 403)

    def test_empty_key_is_rejected(self, client, register_user):
        alice = register_user()
        assert _share(client, alice, "").status_code == 422

    def test_overlong_key_is_rejected(self, client, register_user):
        alice = register_user()
        assert _share(client, alice, "x" * 129).status_code == 422

    def test_first_share_of_a_card_pays_out(self, client, register_user):
        alice = register_user()
        before = _level(client, alice)

        resp = _share(client, alice, "seenly-entry-1")
        assert resp.status_code == 200
        body = resp.json()
        assert body["counted"] is True
        assert body["points_awarded"] == sincerity.CARD_SHARE_AWARD
        assert body["reason"] is None
        assert body["total_points"] == before["points"] + sincerity.CARD_SHARE_AWARD

        after = _level(client, alice)
        assert after["points"] == before["points"] + sincerity.CARD_SHARE_AWARD
        assert after["card_shares_count"] == 1

    def test_sharing_the_same_card_again_pays_nothing(self, client, register_user):
        alice = register_user()
        _share(client, alice, "seenly-entry-1")
        points_after_first = _level(client, alice)["points"]

        again = _share(client, alice, "seenly-entry-1")
        assert again.status_code == 200
        body = again.json()
        assert body["counted"] is False
        assert body["reason"] == "already_counted"
        assert body["points_awarded"] == 0
        assert _level(client, alice)["points"] == points_after_first

    def test_key_is_trimmed_before_deduping(self, client, register_user):
        alice = register_user()
        _share(client, alice, "seenly-entry-1")
        again = _share(client, alice, "  seenly-entry-1  ")
        assert again.json()["reason"] == "already_counted"

    def test_daily_cap_stops_further_rewards(self, client, register_user):
        alice = register_user()
        for i in range(MAX_REWARDED_SHARES_PER_DAY):
            assert _share(client, alice, f"seenly-card-{i}").json()["counted"] is True
        points_at_cap = _level(client, alice)["points"]

        over = _share(client, alice, "seenly-one-too-many")
        assert over.status_code == 200
        body = over.json()
        assert body["counted"] is False
        assert body["reason"] == "daily_limit"
        assert _level(client, alice)["points"] == points_at_cap

    def test_a_card_turned_away_by_the_cap_can_still_earn_later(
        self, client, register_user, db_session
    ):
        """Going over the cap must not 'use up' the card — it isn't
        recorded, so the same card pays on a day with room left."""
        alice = register_user()
        for i in range(MAX_REWARDED_SHARES_PER_DAY):
            _share(client, alice, f"seenly-card-{i}")
        assert _share(client, alice, "seenly-late").json()["reason"] == "daily_limit"
        assert _level(client, alice)["card_shares_count"] == MAX_REWARDED_SHARES_PER_DAY

        # Roll today's rows back a day, as if the day had turned over.
        db_session.query(models.CardShare).filter_by(user_id=alice.id).update(
            {"day_key": "2000-01-01"}
        )
        db_session.commit()

        retry = _share(client, alice, "seenly-late")
        assert retry.json()["counted"] is True

    def test_cap_is_per_user(self, client, register_user):
        alice = register_user()
        bob = register_user()
        for i in range(MAX_REWARDED_SHARES_PER_DAY):
            _share(client, alice, f"seenly-card-{i}")
        assert _share(client, bob, "seenly-card-0").json()["counted"] is True

    def test_leveled_up_is_reported_when_a_share_crosses_a_level(
        self, client, register_user, db_session
    ):
        alice = register_user()
        # Park the account one point under level 2's threshold, so this
        # one share is exactly what crosses it.
        user = db_session.query(models.User).filter_by(id=alice.id).one()
        user.lifetime_sincerity_earned = sincerity.LEVEL_BASE_POINTS - sincerity.CARD_SHARE_AWARD
        db_session.commit()
        assert _level(client, alice)["level"] == 1

        body = _share(client, alice, "seenly-level-up").json()
        assert body["counted"] is True
        assert body["level"] == 2
        assert body["leveled_up"] is True


class TestWatchedTogetherStat:
    """watched_together_count is purely informational now — see this
    file's own module docstring — so these only check the raw count,
    not any point contribution from it."""

    def test_together_evening_is_counted(self, client, register_user, db_session):
        alice = register_user()
        _diary_entry(db_session, alice.id, watched_together=1)
        assert _level(client, alice)["watched_together_count"] == 1

    def test_watched_with_username_alone_also_counts(
        self, client, register_user, db_session
    ):
        """Same predicate app/challenges.py uses for its own together
        measures — the log form's toggle leaves the username snapshot."""
        alice = register_user()
        _diary_entry(db_session, alice.id, watched_with_username="someone")
        assert _level(client, alice)["watched_together_count"] == 1

    def test_solo_evening_is_not_counted(self, client, register_user, db_session):
        alice = register_user()
        _diary_entry(db_session, alice.id)
        assert _level(client, alice)["watched_together_count"] == 0

    def test_only_the_owners_evenings_count(self, client, register_user, db_session):
        alice = register_user()
        bob = register_user()
        _diary_entry(db_session, alice.id, watched_together=1)
        assert _level(client, bob)["watched_together_count"] == 0
