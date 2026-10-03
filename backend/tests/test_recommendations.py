"""Integration tests for app/routers/recommendations.py — staking
sincerity points on a friend's future rating. Resolution itself is
exercised here too even though it lives in routers/diary.py::log_watched
(see that function's own comments), since from the outside "the friend
logs a rating" is the only way to observe it working.
"""

from datetime import datetime, timedelta, timezone

from app import models, sincerity


def _befriend(client, a, b) -> None:
    client.post("/friends/request", json={"username": b.username}, headers=a.headers)
    request_id = client.get("/friends", headers=b.headers).json()["incoming_requests"][0]["id"]
    accepted = client.post(f"/friends/requests/{request_id}/accept", headers=b.headers)
    assert accepted.status_code == 200


def _give_points(db_session, user_id: str, amount: int) -> None:
    user = db_session.get(models.User, user_id)
    sincerity.record_transaction(db_session, user, delta=amount, reason=models.SincerityReason.honest_drop, note="setup")
    db_session.commit()


class TestCreateRecommendation:
    def test_stakes_points_and_debits_the_staker(self, client, register_user, sample_media_item):
        alice = register_user()
        bob = register_user()
        _befriend(client, alice, bob)
        item = sample_media_item()

        resp = client.post(
            "/recommendations",
            json={
                "friend_id": bob.id, "source": item["source"], "media_id": item["id"],
                "title": "Test Movie", "predicted_rating": 8, "stake": 2,
            },
            headers=alice.headers,
        )
        assert resp.status_code == 201
        body = resp.json()
        assert body["status"] == "pending"
        assert body["is_mine"] is True
        assert body["staked_amount"] == 2

        assert client.get("/sincerity/me", headers=alice.headers).json()["balance"] == -2

    def test_cannot_stake_on_a_non_friend(self, client, register_user, sample_media_item):
        alice = register_user()
        stranger = register_user()
        item = sample_media_item()
        resp = client.post(
            "/recommendations",
            json={"friend_id": stranger.id, "source": item["source"], "media_id": item["id"],
                  "title": "x", "predicted_rating": 8, "stake": 1},
            headers=alice.headers,
        )
        assert resp.status_code == 403

    def test_cannot_stake_on_yourself(self, client, register_user, sample_media_item):
        alice = register_user()
        item = sample_media_item()
        resp = client.post(
            "/recommendations",
            json={"friend_id": alice.id, "source": item["source"], "media_id": item["id"],
                  "title": "x", "predicted_rating": 8, "stake": 1},
            headers=alice.headers,
        )
        assert resp.status_code == 400

    def test_stake_is_clamped_to_the_max(self, client, register_user, db_session, sample_media_item):
        alice = register_user()
        bob = register_user()
        _befriend(client, alice, bob)
        _give_points(db_session, alice.id, 100)
        item = sample_media_item()

        resp = client.post(
            "/recommendations",
            json={"friend_id": bob.id, "source": item["source"], "media_id": item["id"],
                  "title": "x", "predicted_rating": 8, "stake": 999},
            headers=alice.headers,
        )
        assert resp.status_code == 201
        assert resp.json()["staked_amount"] == sincerity.MAX_RECOMMENDATION_STAKE

    def test_not_enough_balance_is_rejected(self, client, register_user, sample_media_item):
        alice = register_user()
        bob = register_user()
        _befriend(client, alice, bob)
        item = sample_media_item()
        resp = client.post(
            "/recommendations",
            json={"friend_id": bob.id, "source": item["source"], "media_id": item["id"],
                  "title": "x", "predicted_rating": 8, "stake": 5},
            headers=alice.headers,
        )
        assert resp.status_code == 400

    def test_duplicate_pending_stake_on_the_same_title_is_rejected(
        self, client, register_user, db_session, sample_media_item
    ):
        alice = register_user()
        bob = register_user()
        _befriend(client, alice, bob)
        _give_points(db_session, alice.id, 10)
        item = sample_media_item()
        payload = {"friend_id": bob.id, "source": item["source"], "media_id": item["id"],
                   "title": "x", "predicted_rating": 8, "stake": 1}
        assert client.post("/recommendations", json=payload, headers=alice.headers).status_code == 201
        assert client.post("/recommendations", json=payload, headers=alice.headers).status_code == 400


class TestRecommendationResolution:
    def test_an_accurate_prediction_pays_out_when_the_friend_rates_it(
        self, client, register_user, db_session, sample_media_item
    ):
        alice = register_user()
        bob = register_user()
        _befriend(client, alice, bob)
        _give_points(db_session, alice.id, 10)
        item = sample_media_item()
        client.post(
            "/recommendations",
            json={"friend_id": bob.id, "source": item["source"], "media_id": item["id"],
                  "title": "x", "predicted_rating": 8, "stake": 2},
            headers=alice.headers,
        )

        resp = client.post("/diary", json={"item": item, "rating": 7}, headers=bob.headers)
        assert resp.status_code == 201

        rec = client.get("/recommendations", headers=alice.headers).json()["outgoing"][0]
        assert rec["status"] == "hit"
        assert rec["actual_rating"] == 7

        expected_payout = 2 + round(2 * sincerity.ACCURATE_RECOMMENDATION_BONUS_RATE)
        assert client.get("/sincerity/me", headers=alice.headers).json()["balance"] == 10 - 2 + expected_payout

    def test_a_miss_forfeits_the_stake(self, client, register_user, db_session, sample_media_item):
        alice = register_user()
        bob = register_user()
        _befriend(client, alice, bob)
        _give_points(db_session, alice.id, 10)
        item = sample_media_item()
        client.post(
            "/recommendations",
            json={"friend_id": bob.id, "source": item["source"], "media_id": item["id"],
                  "title": "x", "predicted_rating": 9, "stake": 2},
            headers=alice.headers,
        )

        client.post("/diary", json={"item": item, "rating": 2}, headers=bob.headers)

        rec = client.get("/recommendations", headers=alice.headers).json()["outgoing"][0]
        assert rec["status"] == "missed"
        assert client.get("/sincerity/me", headers=alice.headers).json()["balance"] == 10 - 2

    def test_a_stranger_rating_the_same_title_does_not_resolve_it(
        self, client, register_user, db_session, sample_media_item
    ):
        alice = register_user()
        bob = register_user()
        someone_else = register_user()
        _befriend(client, alice, bob)
        _give_points(db_session, alice.id, 10)
        item = sample_media_item()
        client.post(
            "/recommendations",
            json={"friend_id": bob.id, "source": item["source"], "media_id": item["id"],
                  "title": "x", "predicted_rating": 8, "stake": 2},
            headers=alice.headers,
        )

        client.post("/diary", json={"item": item, "rating": 8}, headers=someone_else.headers)

        rec = client.get("/recommendations", headers=alice.headers).json()["outgoing"][0]
        assert rec["status"] == "pending"


class TestRecommendationExpiry:
    def test_a_stake_past_expiry_with_no_rating_is_refunded(
        self, client, register_user, db_session, sample_media_item
    ):
        alice = register_user()
        bob = register_user()
        _befriend(client, alice, bob)
        _give_points(db_session, alice.id, 10)
        item = sample_media_item()
        client.post(
            "/recommendations",
            json={"friend_id": bob.id, "source": item["source"], "media_id": item["id"],
                  "title": "x", "predicted_rating": 8, "stake": 2},
            headers=alice.headers,
        )
        rec_row = db_session.query(models.Recommendation).filter_by(staker_id=alice.id).first()
        rec_row.created_at = datetime.now(timezone.utc) - sincerity.RECOMMENDATION_EXPIRY - timedelta(days=1)
        db_session.commit()

        listed = client.get("/recommendations", headers=alice.headers).json()
        assert listed["outgoing"][0]["status"] == "expired"
        assert client.get("/sincerity/me", headers=alice.headers).json()["balance"] == 10
