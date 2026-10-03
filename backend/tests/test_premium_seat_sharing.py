"""Couple plan seat sharing — see routers/premium.py::_seat_covers.

A purchased couple plan covers the other member of a two-person circle.
Coverage is derived on every read (nothing is stored to revoke), and the
seat can't be handed to a different person more often than
SEAT_REASSIGN_COOLDOWN. Trial days, referral days and the individual
plan are personal and never cover anyone.

The three-and-four-person family plan lives in test_premium_family_plan.py.
"""

from datetime import datetime, timedelta, timezone

from app import models
from app.routers.premium import SEAT_REASSIGN_COOLDOWN, is_premium_account


def _link(client, a, b):
    code = client.post("/partner/pair", headers=a.headers).json()["pending_code"]
    resp = client.post("/partner/join", json={"code": code}, headers=b.headers)
    assert resp.status_code == 200, resp.text


def _unlink(client, user):
    assert client.delete("/partner", headers=user.headers).status_code == 204


def _state(db_session, user) -> models.UserPremiumState:
    state = db_session.get(models.UserPremiumState, user.id)
    if state is None:
        state = models.UserPremiumState(user_id=user.id, is_premium=False, ai_asks_used=0)
        db_session.add(state)
        db_session.commit()
    return state


def _buy(db_session, user, kind=models.PremiumPlanKind.couple):
    state = _state(db_session, user)
    state.is_premium = True
    state.plan_kind = kind
    state.plan_duration = models.PremiumDuration.month
    state.purchased_at = datetime.now(timezone.utc)
    db_session.commit()


def _status(client, user) -> dict:
    resp = client.get("/premium/status", headers=user.headers)
    assert resp.status_code == 200, resp.text
    return resp.json()


class TestCoupleSeat:
    def test_partner_of_a_couple_plan_payer_is_premium(self, client, db_session, register_user):
        alice, bob = register_user(), register_user()
        _buy(db_session, alice)
        _link(client, alice, bob)

        bobs = _status(client, bob)
        assert bobs["is_premium"] is True
        assert bobs["premium_source"] == "partner"
        # A covered account has no plan of its own.
        assert bobs["plan_kind"] is None
        assert _status(client, alice)["premium_source"] == "own"
        assert is_premium_account(db_session, bob.id) is True

    def test_buying_the_plan_through_the_api_covers_an_already_linked_partner(
        self, client, register_user,
    ):
        alice, bob = register_user(), register_user()
        _link(client, alice, bob)
        assert _status(client, bob)["is_premium"] is False

        resp = client.post(
            "/premium/purchase",
            json={"plan_kind": "couple", "plan_duration": "month"},
            headers=alice.headers,
        )
        assert resp.status_code == 200, resp.text
        assert _status(client, bob)["premium_source"] == "partner"

    def test_individual_plan_does_not_cover_the_partner(self, client, db_session, register_user):
        alice, bob = register_user(), register_user()
        _buy(db_session, alice, models.PremiumPlanKind.individual)
        _link(client, alice, bob)

        assert _status(client, bob)["is_premium"] is False

    def test_trial_and_referral_days_do_not_cover_the_partner(self, client, db_session, register_user):
        alice, bob = register_user(), register_user()
        state = _state(db_session, alice)
        state.premium_expires_at = datetime.now(timezone.utc) + timedelta(days=5)
        db_session.commit()
        _link(client, alice, bob)

        assert _status(client, alice)["is_premium"] is True
        assert _status(client, bob)["is_premium"] is False

    def test_unlinked_account_is_not_covered(self, client, db_session, register_user):
        alice, bob = register_user(), register_user()
        _buy(db_session, alice)

        assert _status(client, bob)["is_premium"] is False

    def test_unlinking_ends_coverage_immediately(self, client, db_session, register_user):
        alice, bob = register_user(), register_user()
        _buy(db_session, alice)
        _link(client, alice, bob)
        assert _status(client, bob)["is_premium"] is True

        _unlink(client, bob)

        assert _status(client, bob)["is_premium"] is False
        assert _status(client, alice)["is_premium"] is True

    def test_a_third_member_ends_coverage_of_the_second_seat(self, client, db_session, register_user):
        alice, bob, carol = register_user(), register_user(), register_user()
        _buy(db_session, alice)
        _link(client, alice, bob)
        assert _status(client, bob)["is_premium"] is True

        invite = client.post("/partner/invite", json={"user_id": carol.id}, headers=alice.headers)
        assert invite.status_code == 201, invite.text
        accepted = client.post(f"/partner/invites/{invite.json()['id']}/accept", headers=carol.headers)
        assert accepted.status_code == 200, accepted.text

        assert _status(client, bob)["is_premium"] is False
        assert _status(client, carol)["is_premium"] is False
        assert _status(client, alice)["is_premium"] is True

    def test_coverage_is_not_transitive(self, client, db_session, register_user):
        """The covered person has no purchase of their own, so they have
        no seats to give — the seat comes from a purchase, never from
        another seat."""
        alice, bob = register_user(), register_user()
        _buy(db_session, alice)
        _link(client, alice, bob)
        _status(client, bob)

        from app.routers.premium import _purchased_seats

        assert _purchased_seats(_state(db_session, bob)) == 0


class TestSeatRotationCooldown:
    def test_seat_cannot_be_handed_to_someone_new_within_the_cooldown(
        self, client, db_session, register_user,
    ):
        alice, bob, carol = register_user(), register_user(), register_user()
        _buy(db_session, alice)
        _link(client, alice, bob)
        assert _status(client, bob)["is_premium"] is True  # binds the seat to bob

        _unlink(client, alice)
        _link(client, alice, carol)

        assert _status(client, carol)["is_premium"] is False
        assert _status(client, alice)["is_premium"] is True

    def test_the_previous_holder_is_covered_again_if_they_come_back(
        self, client, db_session, register_user,
    ):
        alice, bob, carol = register_user(), register_user(), register_user()
        _buy(db_session, alice)
        _link(client, alice, bob)
        _status(client, bob)
        _unlink(client, alice)
        _link(client, alice, carol)
        assert _status(client, carol)["is_premium"] is False
        _unlink(client, alice)

        _link(client, alice, bob)

        assert _status(client, bob)["is_premium"] is True

    def test_seat_can_move_after_the_cooldown(self, client, db_session, register_user):
        alice, bob, carol = register_user(), register_user(), register_user()
        _buy(db_session, alice)
        _link(client, alice, bob)
        _status(client, bob)
        _unlink(client, alice)
        _link(client, alice, carol)
        assert _status(client, carol)["is_premium"] is False

        seat = db_session.query(models.PremiumSeat).filter_by(payer_id=alice.id).one()
        assert seat.holder_id == bob.id
        seat.assigned_at = datetime.now(timezone.utc) - SEAT_REASSIGN_COOLDOWN - timedelta(days=1)
        db_session.commit()

        assert _status(client, carol)["is_premium"] is True
        db_session.refresh(seat)
        assert seat.holder_id == carol.id
        assert db_session.query(models.PremiumSeat).filter_by(payer_id=alice.id).count() == 1

    def test_seat_of_a_deleted_account_is_free_again(self, client, db_session, register_user):
        alice, bob, carol = register_user(), register_user(), register_user()
        _buy(db_session, alice)
        _link(client, alice, bob)
        _status(client, bob)
        _unlink(client, alice)
        _link(client, alice, carol)

        # What ON DELETE CASCADE does to the seat when bob's account is
        # removed.
        db_session.query(models.PremiumSeat).filter_by(
            payer_id=alice.id, holder_id=bob.id,
        ).delete()
        db_session.commit()

        assert _status(client, carol)["is_premium"] is True


class TestWhatCoverageUnlocks:
    def test_covered_partner_is_not_held_to_the_free_ai_ask_ceiling(
        self, client, db_session, register_user,
    ):
        alice, bob = register_user(), register_user()
        _buy(db_session, alice)
        _link(client, alice, bob)

        for _ in range(5):
            resp = client.post("/premium/ai-ask", headers=bob.headers)
            assert resp.status_code == 200, resp.text
            assert resp.json()["allowed"] is True

    def test_free_account_still_hits_the_ceiling(self, client, register_user):
        alice = register_user()

        results = [client.post("/premium/ai-ask", headers=alice.headers).json()["allowed"] for _ in range(4)]

        assert results == [True, True, True, False]

    def test_ceiling_returns_when_the_coverage_ends(self, client, db_session, register_user):
        alice, bob = register_user(), register_user()
        _buy(db_session, alice)
        _link(client, alice, bob)
        assert client.post("/premium/ai-ask", headers=bob.headers).json()["allowed"] is True

        _unlink(client, bob)

        results = [client.post("/premium/ai-ask", headers=bob.headers).json()["allowed"] for _ in range(4)]
        assert results == [True, True, True, False]

    def test_trial_days_lift_the_ai_ask_ceiling(self, client, register_user):
        """Regression: the ceiling used to look at the purchase flag
        only, so a trial — sold as ask-limit-free — still hit it."""
        alice = register_user()
        assert client.post("/premium/start-trial", headers=alice.headers).status_code == 200

        for _ in range(5):
            assert client.post("/premium/ai-ask", headers=alice.headers).json()["allowed"] is True

    def test_trial_is_not_offered_while_covered_and_returns_after(
        self, client, db_session, register_user,
    ):
        alice, bob = register_user(), register_user()
        _buy(db_session, alice)
        _link(client, alice, bob)
        assert _status(client, bob)["trial_available"] is False

        _unlink(client, bob)

        assert _status(client, bob)["trial_available"] is True
