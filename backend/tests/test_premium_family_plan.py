"""Family plan (up to four people) — see routers/premium.py::_seat_covers.

A purchased family plan covers a co-viewing circle of up to four people,
the payer included. Same shape as the couple plan (test_premium_seat_
sharing.py), scaled to several seats: coverage is derived on every read,
a plan only covers a circle that fits in it, and each seat runs its own
SEAT_REASSIGN_COOLDOWN so the plan can't be rented out to a new person
every day. Trial days, referral days, and the individual and couple
plans never cover a circle of three or more.
"""

from datetime import datetime, timedelta, timezone

from app import models
from app.routers.premium import PLAN_SEATS, SEAT_REASSIGN_COOLDOWN, is_premium_account


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

def _link(client, a, b):
    code = client.post("/partner/pair", headers=a.headers).json()["pending_code"]
    resp = client.post("/partner/join", json={"code": code}, headers=b.headers)
    assert resp.status_code == 200, resp.text


def _grow(client, owner, newcomer):
    """Invites `newcomer` into `owner`'s circle and accepts for them."""
    invite = client.post("/partner/invite", json={"user_id": newcomer.id}, headers=owner.headers)
    assert invite.status_code == 201, invite.text
    accepted = client.post(f"/partner/invites/{invite.json()['id']}/accept", headers=newcomer.headers)
    assert accepted.status_code == 200, accepted.text


def _circle(client, owner, *others):
    """A circle of owner + others, built the way the app builds one."""
    _link(client, owner, others[0])
    for extra in others[1:]:
        _grow(client, owner, extra)


def _leave(client, user):
    assert client.delete("/partner", headers=user.headers).status_code == 204


def _state(db_session, user) -> models.UserPremiumState:
    state = db_session.get(models.UserPremiumState, user.id)
    if state is None:
        state = models.UserPremiumState(user_id=user.id, is_premium=False, ai_asks_used=0)
        db_session.add(state)
        db_session.commit()
    return state


def _buy(db_session, user, kind=models.PremiumPlanKind.family):
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


def _covered(client, user) -> bool:
    body = _status(client, user)
    return body["is_premium"] is True and body["premium_source"] == "partner"


def _seat_rows(db_session, payer):
    return db_session.query(models.PremiumSeat).filter_by(payer_id=payer.id).all()


def _age_seat(db_session, payer, holder, days):
    seat = db_session.query(models.PremiumSeat).filter_by(payer_id=payer.id, holder_id=holder.id).one()
    seat.assigned_at = datetime.now(timezone.utc) - timedelta(days=days)
    db_session.commit()


def _expired(db_session, payer, holder):
    _age_seat(db_session, payer, holder, SEAT_REASSIGN_COOLDOWN.days + 1)


# --------------------------------------------------------------------------
# what the plan is
# --------------------------------------------------------------------------

class TestFamilyPlanPurchase:
    def test_seat_counts(self):
        assert PLAN_SEATS[models.PremiumPlanKind.individual] == 1
        assert PLAN_SEATS[models.PremiumPlanKind.couple] == 2
        assert PLAN_SEATS[models.PremiumPlanKind.family] == 4

    def test_family_plan_can_be_bought_through_the_api(self, client, register_user):
        alice = register_user()

        resp = client.post(
            "/premium/purchase",
            json={"plan_kind": "family", "plan_duration": "year"},
            headers=alice.headers,
        )

        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["is_premium"] is True
        assert body["premium_source"] == "own"
        assert body["plan_kind"] == "family"
        assert body["plan_seats"] == 4

    def test_plan_seats_reports_each_plan(self, client, register_user):
        solo, pair = register_user(), register_user()
        for user, kind in ((solo, "individual"), (pair, "couple")):
            resp = client.post(
                "/premium/purchase",
                json={"plan_kind": kind, "plan_duration": "month"},
                headers=user.headers,
            )
            assert resp.status_code == 200, resp.text

        assert _status(client, solo)["plan_seats"] == 1
        assert _status(client, pair)["plan_seats"] == 2

    def test_no_purchase_means_no_seats(self, client, register_user):
        assert _status(client, register_user())["plan_seats"] is None

    def test_unknown_plan_kind_is_still_rejected(self, client, register_user):
        resp = client.post(
            "/premium/purchase",
            json={"plan_kind": "dynasty", "plan_duration": "month"},
            headers=register_user().headers,
        )
        assert resp.status_code == 400


# --------------------------------------------------------------------------
# who is covered
# --------------------------------------------------------------------------

class TestFamilyCoverage:
    def test_covers_a_circle_of_four(self, client, db_session, register_user):
        alice, bob, carol, dave = (register_user() for _ in range(4))
        _buy(db_session, alice)
        _circle(client, alice, bob, carol, dave)

        for member in (bob, carol, dave):
            body = _status(client, member)
            assert body["is_premium"] is True
            assert body["premium_source"] == "partner"
            # A covered account has no plan of its own — and no seats.
            assert body["plan_kind"] is None
            assert body["plan_seats"] is None
            assert is_premium_account(db_session, member.id) is True
        assert _status(client, alice)["premium_source"] == "own"
        assert len(_seat_rows(db_session, alice)) == 3

    def test_covers_a_circle_of_three_and_a_plain_pair(self, client, db_session, register_user):
        alice, bob, carol = (register_user() for _ in range(3))
        _buy(db_session, alice)
        _link(client, alice, bob)
        assert _covered(client, bob)

        _grow(client, alice, carol)

        assert _covered(client, bob)
        assert _covered(client, carol)
        assert len(_seat_rows(db_session, alice)) == 2

    def test_a_fifth_member_turns_coverage_off_for_everyone(self, client, db_session, register_user):
        alice, bob, carol, dave, erin = (register_user() for _ in range(5))
        _buy(db_session, alice)
        _circle(client, alice, bob, carol, dave)
        assert all(_covered(client, m) for m in (bob, carol, dave))

        _grow(client, alice, erin)

        for member in (bob, carol, dave, erin):
            assert _status(client, member)["is_premium"] is False
        assert _status(client, alice)["is_premium"] is True

    def test_coverage_returns_when_the_circle_fits_again(self, client, db_session, register_user):
        alice, bob, carol, dave, erin = (register_user() for _ in range(5))
        _buy(db_session, alice)
        _circle(client, alice, bob, carol, dave)
        _grow(client, alice, erin)
        assert _status(client, bob)["is_premium"] is False

        _leave(client, erin)

        assert all(_covered(client, m) for m in (bob, carol, dave))

    def test_buying_after_linking_covers_everyone(self, client, register_user):
        alice, bob, carol = (register_user() for _ in range(3))
        _circle(client, alice, bob, carol)
        assert _status(client, bob)["is_premium"] is False

        resp = client.post(
            "/premium/purchase",
            json={"plan_kind": "family", "plan_duration": "month"},
            headers=alice.headers,
        )
        assert resp.status_code == 200, resp.text

        assert _covered(client, bob)
        assert _covered(client, carol)

    def test_a_member_leaving_uncovers_only_them(self, client, db_session, register_user):
        alice, bob, carol, dave = (register_user() for _ in range(4))
        _buy(db_session, alice)
        _circle(client, alice, bob, carol, dave)
        assert all(_covered(client, m) for m in (bob, carol, dave))

        _leave(client, carol)

        assert _status(client, carol)["is_premium"] is False
        assert _covered(client, bob)
        assert _covered(client, dave)

    def test_the_payer_can_be_any_member_of_the_circle(self, client, db_session, register_user):
        """Not only the circle's owner: whoever holds the plan covers the
        others, including the owner."""
        alice, bob, carol = (register_user() for _ in range(3))
        _buy(db_session, carol)
        _circle(client, alice, bob, carol)

        assert _covered(client, alice)
        assert _covered(client, bob)
        assert _status(client, carol)["premium_source"] == "own"

    def test_couple_plan_does_not_stretch_to_a_third_person(self, client, db_session, register_user):
        alice, bob, carol = (register_user() for _ in range(3))
        _buy(db_session, alice, models.PremiumPlanKind.couple)
        _circle(client, alice, bob, carol)

        assert _status(client, bob)["is_premium"] is False
        assert _status(client, carol)["is_premium"] is False

    def test_individual_plan_covers_nobody(self, client, db_session, register_user):
        alice, bob, carol = (register_user() for _ in range(3))
        _buy(db_session, alice, models.PremiumPlanKind.individual)
        _circle(client, alice, bob, carol)

        assert _status(client, bob)["is_premium"] is False

    def test_trial_and_referral_days_cover_nobody(self, client, db_session, register_user):
        alice, bob, carol = (register_user() for _ in range(3))
        state = _state(db_session, alice)
        state.premium_expires_at = datetime.now(timezone.utc) + timedelta(days=5)
        db_session.commit()
        _circle(client, alice, bob, carol)

        assert _status(client, alice)["is_premium"] is True
        assert _status(client, bob)["is_premium"] is False
        assert _status(client, carol)["is_premium"] is False

    def test_coverage_is_not_transitive(self, client, db_session, register_user):
        """A covered member has no purchase, so no seats to give: the
        circle they alone belong to (a different one after leaving) is
        not covered through them."""
        alice, bob, carol, dave = (register_user() for _ in range(4))
        _buy(db_session, alice)
        _link(client, alice, bob)
        assert _covered(client, bob)
        _leave(client, bob)
        _circle(client, carol, bob, dave)

        assert _status(client, carol)["is_premium"] is False
        assert _status(client, dave)["is_premium"] is False

    def test_unlinked_payer_covers_nobody(self, client, db_session, register_user):
        alice, bob = register_user(), register_user()
        _buy(db_session, alice)

        assert _status(client, bob)["is_premium"] is False

    def test_covered_member_is_not_offered_a_trial(self, client, db_session, register_user):
        alice, bob, carol = (register_user() for _ in range(3))
        _buy(db_session, alice)
        _circle(client, alice, bob, carol)

        assert _status(client, carol)["trial_available"] is False
        _leave(client, carol)
        assert _status(client, carol)["trial_available"] is True

    def test_covered_member_is_not_held_to_the_free_ai_ask_ceiling(
        self, client, db_session, register_user,
    ):
        alice, bob, carol = (register_user() for _ in range(3))
        _buy(db_session, alice)
        _circle(client, alice, bob, carol)

        for _ in range(5):
            resp = client.post("/premium/ai-ask", headers=carol.headers)
            assert resp.status_code == 200, resp.text
            assert resp.json()["allowed"] is True


# --------------------------------------------------------------------------
# seats can't be rented out
# --------------------------------------------------------------------------

class TestFamilySeatRotation:
    def test_new_person_cannot_take_a_used_seat_within_the_cooldown(
        self, client, db_session, register_user,
    ):
        alice, bob, carol, dave, erin = (register_user() for _ in range(5))
        _buy(db_session, alice)
        _circle(client, alice, bob, carol, dave)
        assert all(_covered(client, m) for m in (bob, carol, dave))

        _leave(client, bob)
        _grow(client, alice, erin)

        assert _status(client, erin)["is_premium"] is False
        assert _covered(client, carol)
        assert _covered(client, dave)
        assert {s.holder_id for s in _seat_rows(db_session, alice)} == {bob.id, carol.id, dave.id}

    def test_a_seat_moves_once_its_own_cooldown_has_run_out(
        self, client, db_session, register_user,
    ):
        alice, bob, carol, dave, erin = (register_user() for _ in range(5))
        _buy(db_session, alice)
        _circle(client, alice, bob, carol, dave)
        assert all(_covered(client, m) for m in (bob, carol, dave))
        _leave(client, bob)
        _grow(client, alice, erin)
        assert _status(client, erin)["is_premium"] is False

        _expired(db_session, alice, bob)

        assert _covered(client, erin)
        rows = _seat_rows(db_session, alice)
        assert len(rows) == 3
        assert {s.holder_id for s in rows} == {erin.id, carol.id, dave.id}

    def test_each_seat_runs_its_own_clock(self, client, db_session, register_user):
        """Two seats are vacated, only bob's cooldown is over: the
        newcomer takes bob's seat and carol's fresh one stays hers."""
        alice, bob, carol, dave, erin = (register_user() for _ in range(5))
        _buy(db_session, alice)
        _circle(client, alice, bob, carol, dave)
        assert all(_covered(client, m) for m in (bob, carol, dave))
        _leave(client, bob)
        _leave(client, carol)
        _grow(client, alice, erin)
        assert _status(client, erin)["is_premium"] is False  # both seats still fresh

        _expired(db_session, alice, bob)

        assert _covered(client, erin)
        assert _covered(client, dave)
        assert {s.holder_id for s in _seat_rows(db_session, alice)} == {erin.id, carol.id, dave.id}

    def test_previous_holder_is_covered_again_if_they_come_back(
        self, client, db_session, register_user,
    ):
        alice, bob, carol, dave, erin = (register_user() for _ in range(5))
        _buy(db_session, alice)
        _circle(client, alice, bob, carol, dave)
        assert all(_covered(client, m) for m in (bob, carol, dave))
        _leave(client, bob)
        _grow(client, alice, erin)
        assert _status(client, erin)["is_premium"] is False
        _leave(client, erin)

        _grow(client, alice, bob)

        assert _covered(client, bob)

    def test_a_current_member_never_loses_their_seat_to_the_clock(
        self, client, db_session, register_user,
    ):
        alice, bob, carol, dave = (register_user() for _ in range(4))
        _buy(db_session, alice)
        _circle(client, alice, bob, carol, dave)
        assert all(_covered(client, m) for m in (bob, carol, dave))

        for holder in (bob, carol, dave):
            _age_seat(db_session, alice, holder, 400)

        assert all(_covered(client, m) for m in (bob, carol, dave))
        assert {s.holder_id for s in _seat_rows(db_session, alice)} == {bob.id, carol.id, dave.id}

    def test_never_used_seats_are_free_to_take_at_once(self, client, db_session, register_user):
        alice, bob, carol, dave = (register_user() for _ in range(4))
        _buy(db_session, alice)
        _link(client, alice, bob)
        assert _covered(client, bob)

        _grow(client, alice, carol)
        _grow(client, alice, dave)

        assert _covered(client, carol)
        assert _covered(client, dave)

    def test_a_deleted_account_frees_its_seat(self, client, db_session, register_user):
        from sqlalchemy import text

        alice, bob, carol, dave, erin = (register_user() for _ in range(5))
        _buy(db_session, alice)
        _circle(client, alice, bob, carol, dave)
        assert all(_covered(client, m) for m in (bob, carol, dave))
        _leave(client, bob)
        _grow(client, alice, erin)
        assert _status(client, erin)["is_premium"] is False

        # ON DELETE CASCADE on holder_id — what removing bob's account does.
        db_session.execute(text("DELETE FROM premium_seats WHERE holder_id = :id"), {"id": bob.id})
        db_session.commit()

        assert _covered(client, erin)

    def test_two_payers_in_one_circle_do_not_double_book(self, client, db_session, register_user):
        alice, bob, carol = (register_user() for _ in range(3))
        _buy(db_session, alice)
        _buy(db_session, bob)
        _circle(client, alice, bob, carol)

        assert _covered(client, carol)
        rows = db_session.query(models.PremiumSeat).filter_by(holder_id=carol.id).all()
        assert len(rows) == 1

    def test_seat_is_held_only_once_per_person_per_plan(self, client, db_session, register_user):
        alice, bob, carol = (register_user() for _ in range(3))
        _buy(db_session, alice)
        _circle(client, alice, bob, carol)

        for _ in range(3):
            assert _covered(client, bob)

        rows = db_session.query(models.PremiumSeat).filter_by(payer_id=alice.id, holder_id=bob.id).all()
        assert len(rows) == 1

    def test_a_shrunken_plan_never_covers_more_than_it_has_seats_for(
        self, client, db_session, register_user,
    ):
        """Family → couple leaves old seat rows behind, but coverage is
        still bounded by the circle fitting the *current* plan."""
        alice, bob, carol = (register_user() for _ in range(3))
        _buy(db_session, alice)
        _circle(client, alice, bob, carol)
        assert _covered(client, bob) and _covered(client, carol)

        _buy(db_session, alice, models.PremiumPlanKind.couple)

        assert _status(client, bob)["is_premium"] is False
        assert _status(client, carol)["is_premium"] is False
        _leave(client, carol)
        assert _covered(client, bob)


# --------------------------------------------------------------------------
# what the co-viewing queue sees
# --------------------------------------------------------------------------

class TestFamilyAndTheSharedQueue:
    def test_a_free_company_with_a_family_plan_inside_is_premium(
        self, client, db_session, register_user,
    ):
        from app.routers.partner import _circle_has_premium, get_active_link

        alice, bob, carol = (register_user() for _ in range(3))
        _circle(client, alice, bob, carol)
        link = get_active_link(db_session, bob.id)
        assert _circle_has_premium(db_session, link) is False

        _buy(db_session, carol)

        assert _circle_has_premium(db_session, link) is True
