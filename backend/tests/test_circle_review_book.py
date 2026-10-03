"""The data behind the PDF "book of your evenings" (GET /partner/reviews/book).

The promises: the book is a premium thing for the circle (402 without a plan,
one member's plan is enough), it carries only what everybody can already see
(opened reviews the caller was at, with something written in them), oldest
evening first, with the moments of room evenings computed even when they
opened while the circle was still free — and it has a ceiling.
"""

from datetime import date, datetime, timedelta, timezone

import pytest

from app import circle_review as rules
from app import models


def _link(client, a, b):
    code = client.post("/partner/pair", headers=a.headers).json()["pending_code"]
    assert client.post("/partner/join", json={"code": code}, headers=b.headers).status_code == 200


def _invite(client, owner, other):
    assert client.post("/partner/invite", json={"user_id": other.id}, headers=owner.headers).status_code == 201
    inv = client.get("/partner/invites", headers=other.headers).json()["incoming"][0]["id"]
    assert client.post(f"/partner/invites/{inv}/accept", headers=other.headers).status_code == 200


def _buy(db_session, user):
    state = db_session.get(models.UserPremiumState, user.id) or models.UserPremiumState(
        user_id=user.id, is_premium=False, ai_asks_used=0
    )
    state.is_premium = True
    state.plan_kind = models.PremiumPlanKind.couple
    state.plan_duration = models.PremiumDuration.month
    state.purchased_at = datetime.now(timezone.utc)
    db_session.add(state)
    db_session.commit()


@pytest.fixture
def pair(client, register_user):
    a, b = register_user(), register_user()
    _link(client, a, b)
    return a, b


@pytest.fixture
def company(client, register_user):
    a, b, c = register_user(), register_user(), register_user()
    _link(client, a, b)
    _invite(client, a, c)
    return a, b, c


def _open_review(client, user, item):
    """Logs `item` as watched together (no rating, so nobody's part is sealed
    yet) and returns the id of the review that opened."""
    r = client.post("/diary", json={"item": item, "watched_with_partner": True}, headers=user.headers)
    assert r.status_code == 201, r.text
    found = client.get(
        f"/partner/reviews/by-title?source={item['source']}&media_id={item['id']}", headers=user.headers
    )
    return found.json()["id"]


def _put(client, user, rid, **body):
    return client.put(f"/partner/reviews/{rid}/mine", json=body, headers=user.headers)


def _evening(client, users, item, ratings, **extra):
    """A revealed evening: the first user logs it, everyone writes their part."""
    rid = _open_review(client, users[0], item)
    for user, rating in zip(users, ratings):
        r = _put(client, user, rid, rating=rating, **extra)
        assert r.status_code == 200, r.text
    return rid


def _book(client, user):
    return client.get("/partner/reviews/book", headers=user.headers)


def _room_evening(client, users):
    host, *rest = users
    body = {
        "media_id": "dQw4w9WgXcQ", "media_type": "video", "source": "youtube",
        "title_ru": "Ролик", "player_kind": "youtube", "player_ref": "dQw4w9WgXcQ", "duration_ms": 600_000,
    }
    room = client.post("/partner/rooms", json=body, headers=host.headers).json()
    for u in rest:
        assert client.post(f"/partner/rooms/{room['id']}/join", headers=u.headers).status_code == 200
    client.post(f"/partner/rooms/{room['id']}/control", json={"action": "play", "position_ms": 0}, headers=host.headers)
    return room


def _react(client, user, room_id, pos, key="😂"):
    r = client.post(
        f"/partner/rooms/{room_id}/events", json={"kind": "reaction", "key": key, "position_ms": pos}, headers=user.headers
    )
    assert r.status_code == 200, r.text


class TestPureRules:
    def test_something_written_is_printable(self):
        assert rules.has_printable_content([{"rating": 7, "tags": [], "line": None, "skipped": False}])
        assert rules.has_printable_content([{"rating": None, "tags": ["уют"], "line": None, "skipped": False}])
        assert rules.has_printable_content([{"rating": None, "tags": [], "line": "до слёз", "skipped": False}])

    def test_skips_and_blanks_are_not(self):
        assert not rules.has_printable_content([])
        assert not rules.has_printable_content([{"rating": None, "tags": [], "line": None, "skipped": True}])
        assert not rules.has_printable_content([{"rating": None, "tags": [], "line": "   ", "skipped": False}])
        # a skipped entry never counts, even if some stale value is left on it
        assert not rules.has_printable_content([{"rating": 8, "tags": ["x"], "line": "y", "skipped": True}])


class TestPremiumGate:
    def test_a_free_circle_is_told_to_subscribe(self, client, pair, sample_media_item):
        alice, bob = pair
        _evening(client, [alice, bob], sample_media_item(id="tt1"), [8, 8])
        r = _book(client, alice)
        assert r.status_code == 402

    def test_one_members_plan_is_enough_for_both(self, client, db_session, pair, sample_media_item):
        alice, bob = pair
        _evening(client, [alice, bob], sample_media_item(id="tt2"), [8, 8])
        _buy(db_session, bob)
        assert _book(client, alice).status_code == 200
        assert _book(client, bob).status_code == 200

    def test_nobody_without_a_circle_has_a_book(self, client, register_user):
        loner = register_user()
        assert _book(client, loner).status_code == 409

    def test_the_route_is_not_mistaken_for_a_review_id(self, client, db_session, pair):
        alice, bob = pair
        _buy(db_session, alice)
        r = _book(client, alice)
        assert r.status_code == 200
        body = r.json()
        assert body["reviews"] == [] and body["truncated"] is False and len(body["people"]) == 2


class TestWhatGoesIn:
    def test_the_circle_and_who_is_you(self, client, db_session, pair):
        alice, bob = pair
        _buy(db_session, alice)
        out = _book(client, bob).json()
        assert {p["username"] for p in out["people"]} == {alice.username, bob.username}
        assert [p["username"] for p in out["people"] if p["is_you"]] == [bob.username]

    def test_only_opened_reviews_make_the_book(self, client, db_session, pair, sample_media_item):
        alice, bob = pair
        done = _evening(client, [alice, bob], sample_media_item(id="tt10"), [9, 9], line="чудесно")
        waiting = _open_review(client, alice, sample_media_item(id="tt11"))
        _put(client, alice, waiting, rating=7)  # bob hasn't written: still sealed
        _buy(db_session, alice)
        ids = [r["id"] for r in _book(client, alice).json()["reviews"]]
        assert ids == [done]

    def test_a_week_old_unopened_review_is_opened_and_included(self, client, db_session, pair, sample_media_item):
        alice, bob = pair
        rid = _open_review(client, alice, sample_media_item(id="tt12"))
        _put(client, alice, rid, rating=9, line="я написала")
        row = db_session.get(models.CircleReview, rid)
        row.expires_at = datetime.now(timezone.utc) - timedelta(minutes=1)
        db_session.commit()
        _buy(db_session, alice)
        reviews = _book(client, alice).json()["reviews"]
        assert [r["id"] for r in reviews] == [rid] and reviews[0]["revealed"] is True

    def test_an_evening_everyone_skipped_leaves_no_blank_page(self, client, db_session, pair, sample_media_item):
        alice, bob = pair
        rid = _open_review(client, alice, sample_media_item(id="tt13"))
        for user in (alice, bob):
            assert client.post(f"/partner/reviews/{rid}/skip", headers=user.headers).status_code == 200
        _buy(db_session, alice)
        assert _book(client, alice).json()["reviews"] == []

    def test_one_part_written_and_one_skipped_still_prints(self, client, db_session, pair, sample_media_item):
        alice, bob = pair
        rid = _open_review(client, alice, sample_media_item(id="tt14"))
        _put(client, alice, rid, rating=8, tags=["уют"])
        assert client.post(f"/partner/reviews/{rid}/skip", headers=bob.headers).status_code == 200
        _buy(db_session, alice)
        assert [r["id"] for r in _book(client, alice).json()["reviews"]] == [rid]

    def test_evenings_the_caller_was_not_at_stay_out(self, client, db_session, company):
        alice, bob, carol = company
        # A room that only two of the three joined opens a review for those two.
        room = _room_evening(client, [alice, bob])
        rid = client.post(f"/partner/rooms/{room['id']}/finish", headers=alice.headers).json()["review_id"]
        _put(client, alice, rid, rating=8)
        _put(client, bob, rid, rating=8)
        assert carol.id not in (db_session.get(models.CircleReview, rid).participant_ids or [])
        _buy(db_session, carol)
        assert _book(client, carol).json()["reviews"] == []
        assert [r["id"] for r in _book(client, alice).json()["reviews"]] == [rid]

    def test_oldest_evening_first(self, client, db_session, pair, sample_media_item):
        alice, bob = pair
        newer = _evening(client, [alice, bob], sample_media_item(id="tt20"), [8, 8])
        older = _evening(client, [alice, bob], sample_media_item(id="tt21"), [7, 7])
        # Both were written "today"; pin the dates so the order is not a tie.
        db_session.get(models.CircleReview, newer).watched_on = date(2026, 9, 20)
        db_session.get(models.CircleReview, older).watched_on = date(2026, 3, 1)
        db_session.commit()
        _buy(db_session, alice)
        ids = [r["id"] for r in _book(client, alice).json()["reviews"]]
        assert ids == [older, newer]


class TestMoments:
    def test_the_past_is_unlocked_when_the_circle_subscribes(self, client, db_session, pair):
        alice, bob = pair
        room = _room_evening(client, [alice, bob])
        _react(client, alice, room["id"], 61_000)
        _react(client, bob, room["id"], 65_000, key="😮")
        rid = client.post(f"/partner/rooms/{room['id']}/finish", headers=alice.headers).json()["review_id"]
        _put(client, alice, rid, rating=9)
        opened = _put(client, bob, rid, rating=8).json()
        assert opened["moments"] is None  # it opened while the circle was free

        _buy(db_session, bob)
        reviews = _book(client, alice).json()["reviews"]
        assert len(reviews) == 1
        assert reviews[0]["moments_locked"] is False
        assert [m["position_ms"] for m in reviews[0]["moments"]] == [61_000]
        assert reviews[0]["moments"][0]["shared"] is True

    def test_a_room_with_no_reactions_has_an_empty_timeline(self, client, db_session, pair):
        alice, bob = pair
        _buy(db_session, alice)
        room = _room_evening(client, [alice, bob])
        rid = client.post(f"/partner/rooms/{room['id']}/finish", headers=alice.headers).json()["review_id"]
        _put(client, alice, rid, rating=9)
        _put(client, bob, rid, rating=9)
        review = _book(client, alice).json()["reviews"][0]
        assert review["moments"] == [] and review["moments_locked"] is False

    def test_an_evening_logged_without_a_room_has_no_timeline(self, client, db_session, pair, sample_media_item):
        alice, bob = pair
        _evening(client, [alice, bob], sample_media_item(id="tt30"), [9, 9])
        _buy(db_session, alice)
        review = _book(client, alice).json()["reviews"][0]
        assert review["moments"] is None and review["moments_locked"] is False


class TestCeiling:
    def test_when_there_are_more_evenings_than_fit_the_newest_win(self, client, db_session, pair, sample_media_item, monkeypatch):
        alice, bob = pair
        ids = [_evening(client, [alice, bob], sample_media_item(id=f"tt4{i}"), [8, 8]) for i in range(3)]
        for offset, rid in enumerate(ids):
            db_session.get(models.CircleReview, rid).watched_on = date(2026, 1, 1) + timedelta(days=offset)
        db_session.commit()
        _buy(db_session, alice)
        monkeypatch.setattr(rules, "BOOK_MAX_REVIEWS", 2)

        out = _book(client, alice).json()
        assert out["truncated"] is True
        assert [r["id"] for r in out["reviews"]] == [ids[1], ids[2]]

    def test_a_book_that_fits_is_not_marked_truncated(self, client, db_session, pair, sample_media_item, monkeypatch):
        alice, bob = pair
        _evening(client, [alice, bob], sample_media_item(id="tt50"), [8, 8])
        _buy(db_session, alice)
        monkeypatch.setattr(rules, "BOOK_MAX_REVIEWS", 1)
        out = _book(client, alice).json()
        assert out["truncated"] is False and len(out["reviews"]) == 1
