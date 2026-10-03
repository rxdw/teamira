"""Circle reviews (routers/circle_review.py, app/circle_review.py).

The promise: nobody's rating is visible to anyone else until everyone has
written (or skipped) or a week has passed, the verdict is derived from the
entries, the review opens from a saved room *and* from any "watched with"
log, and reading is free while only the moments timeline depends on premium.
"""

from datetime import datetime, timedelta, timezone

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
    state = db_session.get(models.UserPremiumState, user.id) or models.UserPremiumState(user_id=user.id, is_premium=False, ai_asks_used=0)
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


def _log_together(client, user, item, **over):
    # No rating by default: a rated log seals the logger's own part of the
    # review straight away (see TestLoggingSealsTheLoggersPart), and most
    # tests here want to write that part themselves.
    body = {"item": item, "watched_with_partner": True}
    body.update(over)
    r = client.post("/diary", json=body, headers=user.headers)
    assert r.status_code == 201, r.text
    return r.json()


def _pending(client, user):
    return client.get("/partner/reviews/pending", headers=user.headers).json()


def _put(client, user, rid, **body):
    return client.put(f"/partner/reviews/{rid}/mine", json=body, headers=user.headers)


class TestPureRules:
    def test_verdict_bands(self):
        mk = lambda *rs: [{"user_id": str(i), "rating": r, "tags": []} for i, r in enumerate(rs)]
        assert rules.summarize(mk(9, 9))["verdict"] == "unison"
        assert rules.summarize(mk(9, 8))["verdict"] == "unison"
        assert rules.summarize(mk(9, 6))["verdict"] == "close"
        assert rules.summarize(mk(9, 4))["verdict"] == "split"
        assert rules.summarize(mk(7))["verdict"] == "solo"
        assert rules.summarize(mk(None, 7))["verdict"] == "solo"

    def test_average_and_spread(self):
        s = rules.summarize([{"user_id": "a", "rating": 9, "tags": []}, {"user_id": "b", "rating": 6, "tags": []}])
        assert s["average"] == 7.5 and s["spread"] == 3 and s["rated_count"] == 2

    def test_shared_tags_need_two_people_and_ignore_case(self):
        s = rules.summarize([
            {"user_id": "a", "rating": 8, "tags": ["The Music", "story"]},
            {"user_id": "b", "rating": 8, "tags": ["the music", "humor"]},
            {"user_id": "c", "rating": 8, "tags": ["story", "the music"]},
        ])
        assert s["shared_tags"] == ["The Music", "story"]

    def test_skipped_people_do_not_count(self):
        s = rules.summarize([
            {"user_id": "a", "rating": 8, "tags": ["x"]},
            {"user_id": "b", "rating": 2, "tags": ["x"], "skipped": True},
        ])
        assert s["rated_count"] == 1 and s["verdict"] == "solo" and s["shared_tags"] == []

    def test_clean_tags(self):
        assert rules.clean_tags(["  Музыка ", "музыка", "", "x" * 40]) == ["Музыка", "x" * 24]
        assert len(rules.clean_tags([str(i) for i in range(20)])) == rules.MAX_TAGS

    def test_moments_rank_shared_first_and_come_back_in_film_order(self):
        ev = [
            {"user_id": "a", "kind": "reaction", "emoji": "😂", "position_ms": 61_000},
            {"user_id": "b", "kind": "emotion", "emoji": "funny", "position_ms": 70_000},
            {"user_id": "a", "kind": "reaction", "emoji": "❤️", "position_ms": 400_000},
            {"user_id": "a", "kind": "chat", "emoji": None, "position_ms": 5_000},
            {"user_id": "a", "kind": "signal", "emoji": "pulse", "position_ms": 5_000},
        ]
        ms = rules.build_moments(ev)
        assert [m["position_ms"] for m in ms] == [61_000, 400_000]
        assert ms[0]["shared"] is True and ms[0]["people"] == 2 and ms[0]["count"] == 2
        assert ms[1]["shared"] is False
        assert rules.build_moments(ev, limit=1)[0]["shared"] is True

    def test_expiry(self):
        now = datetime(2026, 1, 10, tzinfo=timezone.utc)
        assert rules.is_expired(now - timedelta(seconds=1), now) is True
        assert rules.is_expired(now + timedelta(days=1), now) is False


class TestOpeningFromALog:
    def test_logging_watched_with_opens_a_review_and_invites_the_others(self, client, pair, sample_media_item):
        alice, bob = pair
        _log_together(client, alice, sample_media_item(id="tt1"))
        mine = _pending(client, alice)
        theirs = _pending(client, bob)
        assert len(mine) == 1 and len(theirs) == 1
        assert theirs[0]["i_am_done"] is False and theirs[0]["revealed"] is False
        assert {p["username"] for p in theirs[0]["people"]} == {alice.username, bob.username}

    def test_a_plain_log_opens_nothing(self, client, pair, sample_media_item):
        alice, bob = pair
        _log_together(client, alice, sample_media_item(), watched_with_partner=False)
        assert _pending(client, alice) == [] and _pending(client, bob) == []

    def test_the_second_log_of_the_same_evening_joins_the_same_review(self, client, pair, sample_media_item):
        alice, bob = pair
        item = sample_media_item(id="tt2")
        _log_together(client, alice, item)
        _log_together(client, bob, item)
        assert len(client.get("/partner/reviews", headers=alice.headers).json()) == 1

    def test_marking_a_planned_evening_watched_opens_one_too(self, client, pair, sample_media_item):
        alice, bob = pair
        planned = client.post("/partner/co-viewing/plan", json={"item": sample_media_item(id="tt3")}, headers=alice.headers).json()
        client.post(f"/partner/co-viewing/{planned['id']}/watched", headers=alice.headers)
        assert len(_pending(client, bob)) == 1

    def test_solo_users_have_nothing_pending(self, client, register_user):
        assert _pending(client, register_user()) == []


class TestSealing:
    def test_partner_sees_nothing_of_my_part_until_they_have_written(self, client, pair, sample_media_item):
        alice, bob = pair
        _log_together(client, alice, sample_media_item(id="tt4"))
        rid = _pending(client, alice)[0]["id"]
        mine = _put(client, alice, rid, rating=9, tags=["музыка"], line="секретная фраза").json()
        assert mine["i_am_done"] is True and mine["revealed"] is False
        me = next(p for p in mine["people"] if p["is_you"])
        assert me["rating"] == 9 and me["line"] == "секретная фраза"

        seen_by_bob = client.get(f"/partner/reviews/{rid}", headers=bob.headers).json()
        her = next(p for p in seen_by_bob["people"] if not p["is_you"])
        assert her["done"] is True
        assert her["rating"] is None and her["line"] is None and her["tags"] == []
        assert "секретная фраза" not in str(seen_by_bob)
        assert seen_by_bob["summary"] is None

    def test_opens_for_everyone_the_moment_the_last_person_writes(self, client, pair, sample_media_item):
        alice, bob = pair
        _log_together(client, alice, sample_media_item(id="tt5"))
        rid = _pending(client, alice)[0]["id"]
        _put(client, alice, rid, rating=9, tags=["музыка", "финал"], line="плакала")
        opened = _put(client, bob, rid, rating=8, tags=["Музыка"], line="красиво").json()
        assert opened["revealed"] is True and opened["status"] == "revealed"
        assert opened["summary"]["verdict"] == "unison" and opened["summary"]["average"] == 8.5
        assert opened["summary"]["shared_tags"] == ["музыка"]
        assert {p["line"] for p in opened["people"]} == {"плакала", "красиво"}
        for u in (alice, bob):
            seen = client.get(f"/partner/reviews/{rid}", headers=u.headers).json()
            assert seen["revealed"] is True and all(p["rating"] is not None for p in seen["people"])

    def test_a_skip_counts_as_done_and_shows_as_a_blank(self, client, pair, sample_media_item):
        alice, bob = pair
        _log_together(client, alice, sample_media_item(id="tt6"))
        rid = _pending(client, alice)[0]["id"]
        _put(client, alice, rid, rating=7)
        out = client.post(f"/partner/reviews/{rid}/skip", headers=bob.headers).json()
        assert out["revealed"] is True
        skipper = next(p for p in out["people"] if p["is_you"])
        assert skipper["skipped"] is True and skipper["rating"] is None
        assert out["summary"]["verdict"] == "solo"

    def test_after_it_opens_it_is_frozen(self, client, pair, sample_media_item):
        alice, bob = pair
        _log_together(client, alice, sample_media_item(id="tt7"))
        rid = _pending(client, alice)[0]["id"]
        _put(client, alice, rid, rating=7)
        _put(client, bob, rid, rating=8)
        assert _put(client, alice, rid, rating=1).status_code == 409
        assert client.post(f"/partner/reviews/{rid}/skip", headers=alice.headers).status_code == 409

    def test_until_it_opens_each_person_can_rewrite_their_part(self, client, pair, sample_media_item):
        alice, bob = pair
        _log_together(client, alice, sample_media_item(id="tt8"))
        rid = _pending(client, alice)[0]["id"]
        _put(client, alice, rid, rating=5, line="первая мысль")
        again = _put(client, alice, rid, rating=9, line="вторая мысль").json()
        me = next(p for p in again["people"] if p["is_you"])
        assert me["rating"] == 9 and me["line"] == "вторая мысль"

    def test_a_week_later_it_opens_even_if_someone_never_wrote(self, client, pair, sample_media_item, db_session):
        alice, bob = pair
        _log_together(client, alice, sample_media_item(id="tt9"))
        rid = _pending(client, alice)[0]["id"]
        _put(client, alice, rid, rating=9, line="я написала")
        row = db_session.get(models.CircleReview, rid)
        row.expires_at = datetime.now(timezone.utc) - timedelta(minutes=1)
        db_session.commit()
        seen = client.get(f"/partner/reviews/{rid}", headers=bob.headers).json()
        assert seen["revealed"] is True
        assert {p["line"] for p in seen["people"] if p["done"]} == {"я написала"}
        assert any(p["done"] is False for p in seen["people"])

    def test_empty_or_rude_parts_are_rejected(self, client, pair, sample_media_item):
        alice, _ = pair
        _log_together(client, alice, sample_media_item(id="tt10"))
        rid = _pending(client, alice)[0]["id"]
        assert _put(client, alice, rid).status_code == 400
        assert _put(client, alice, rid, line="   ").status_code == 400
        assert _put(client, alice, rid, line="я" * (rules.LINE_MAX_CHARS + 1)).status_code == 400
        assert _put(client, alice, rid, rating=11).status_code == 422

    def test_outsiders_cannot_read_or_write(self, client, pair, register_user, sample_media_item):
        alice, _ = pair
        _log_together(client, alice, sample_media_item(id="tt11"))
        rid = _pending(client, alice)[0]["id"]
        stranger = register_user()
        assert client.get(f"/partner/reviews/{rid}", headers=stranger.headers).status_code == 409
        x, y = register_user(), register_user()
        _link(client, x, y)
        assert client.get(f"/partner/reviews/{rid}", headers=x.headers).status_code == 404
        assert _put(client, x, rid, rating=5).status_code == 404

    def test_people_who_were_not_there_cannot_join_in(self, client, company, sample_media_item):
        alice, bob, carol = company
        item = sample_media_item(id="tt12")
        _log_together(client, alice, item)
        rid = _pending(client, alice)[0]["id"]
        assert len(_pending(client, carol)) == 1  # a company log invites everyone


class TestFromARoom:
    def _room_evening(self, client, users, **create):
        host, *rest = users
        body = {
            "media_id": "dQw4w9WgXcQ", "media_type": "video", "source": "youtube",
            "title_ru": "Ролик", "player_kind": "youtube", "player_ref": "dQw4w9WgXcQ", "duration_ms": 600_000,
        }
        body.update(create)
        room = client.post("/partner/rooms", json=body, headers=host.headers).json()
        for u in rest:
            assert client.post(f"/partner/rooms/{room['id']}/join", headers=u.headers).status_code == 200
        client.post(f"/partner/rooms/{room['id']}/control", json={"action": "play", "position_ms": 0}, headers=host.headers)
        return room

    def _react(self, client, user, room_id, pos, kind="reaction", key="😂"):
        r = client.post(f"/partner/rooms/{room_id}/events", json={"kind": kind, "key": key, "position_ms": pos}, headers=user.headers)
        assert r.status_code == 200, r.text

    def test_finishing_a_saved_room_opens_a_review_for_who_was_there(self, client, company):
        alice, bob, carol = company
        room = self._room_evening(client, [alice, bob])
        out = client.post(f"/partner/rooms/{room['id']}/finish", headers=alice.headers).json()
        assert out["review_id"]
        review = client.get(f"/partner/reviews/{out['review_id']}", headers=bob.headers).json()
        assert review["origin"] == "room" and review["room_id"] == room["id"]
        assert {p["username"] for p in review["people"]} == {alice.username, bob.username}
        assert _pending(client, carol) == []
        assert client.get(f"/partner/reviews/by-room/{room['id']}", headers=alice.headers).json()["id"] == out["review_id"]

    def test_a_room_that_is_not_saved_opens_no_review(self, client, pair):
        alice, bob = pair
        room = self._room_evening(client, [alice, bob], save_to_shared=False)
        out = client.post(f"/partner/rooms/{room['id']}/finish", headers=alice.headers).json()
        assert out["review_id"] is None and _pending(client, bob) == []

    def test_a_log_then_a_room_for_the_same_title_share_one_review(self, client, pair, sample_media_item):
        alice, bob = pair
        item = sample_media_item(id="tt99")
        _log_together(client, alice, item)
        room = self._room_evening(
            client, [alice, bob], media_id="tt99", media_type="movie", source="tmdb", player_kind="parallel", player_ref=None,
        )
        out = client.post(f"/partner/rooms/{room['id']}/finish", headers=alice.headers).json()
        reviews = client.get("/partner/reviews", headers=alice.headers).json()
        assert len(reviews) == 1 and reviews[0]["id"] == out["review_id"] and reviews[0]["room_id"] == room["id"]

    def test_moments_need_a_premium_circle_then_stay_readable_forever(self, client, db_session, pair):
        alice, bob = pair
        room = self._room_evening(client, [alice, bob])
        self._react(client, alice, room["id"], 61_000)
        self._react(client, bob, room["id"], 65_000, key="😮")  # reactions are free; emotion taps are Zen's
        self._react(client, alice, room["id"], 400_000, key="❤️")
        out = client.post(f"/partner/rooms/{room['id']}/finish", headers=alice.headers).json()
        rid = out["review_id"]
        _put(client, alice, rid, rating=9)
        opened = _put(client, bob, rid, rating=8).json()

        assert opened["revealed"] is True
        assert opened["moments"] is None and opened["moments_locked"] is True

        _buy(db_session, alice)  # subscribing later unlocks the past
        unlocked = client.get(f"/partner/reviews/{rid}", headers=bob.headers).json()
        assert unlocked["moments_locked"] is False
        assert [m["position_ms"] for m in unlocked["moments"]] == [61_000, 400_000]
        assert unlocked["moments"][0]["shared"] is True

        state = db_session.get(models.UserPremiumState, alice.id)
        state.is_premium = False  # the subscription ends
        db_session.commit()
        still = client.get(f"/partner/reviews/{rid}", headers=alice.headers).json()
        assert still["moments"] and still["moments_locked"] is False

    def test_moments_are_computed_at_the_opening_when_already_premium(self, client, db_session, pair):
        alice, bob = pair
        _buy(db_session, bob)
        room = self._room_evening(client, [alice, bob])
        self._react(client, alice, room["id"], 10_000)
        rid = client.post(f"/partner/rooms/{room['id']}/finish", headers=alice.headers).json()["review_id"]
        _put(client, alice, rid, rating=9)
        opened = _put(client, bob, rid, rating=9).json()
        assert opened["moments"] and opened["moments_locked"] is False

    def test_reviews_without_a_room_never_show_a_locked_timeline(self, client, pair, sample_media_item):
        alice, bob = pair
        _log_together(client, alice, sample_media_item(id="tt55"))
        rid = _pending(client, alice)[0]["id"]
        _put(client, alice, rid, rating=9)
        opened = _put(client, bob, rid, rating=9).json()
        assert opened["moments"] is None and opened["moments_locked"] is False


class TestFindingReviews:
    def test_by_title_and_list(self, client, pair, sample_media_item):
        alice, bob = pair
        item = sample_media_item(id="tt77")
        _log_together(client, alice, item)
        found = client.get(f"/partner/reviews/by-title?source={item['source']}&media_id=tt77", headers=bob.headers).json()
        assert found["media_id"] == "tt77"
        assert client.get("/partner/reviews/by-title?source=tmdb&media_id=nope", headers=bob.headers).json() is None
        assert len(client.get("/partner/reviews", headers=bob.headers).json()) == 1

    def test_unlinking_takes_the_reviews_with_it(self, client, pair, db_session, sample_media_item):
        alice, bob = pair
        _log_together(client, alice, sample_media_item(id="tt88"))
        rid = _pending(client, alice)[0]["id"]
        assert client.delete("/partner", headers=bob.headers).status_code == 204
        db_session.expire_all()
        assert db_session.get(models.CircleReview, rid) is None


class TestLoggingSealsTheLoggersPart:
    """A person who rates the evening while logging has already written their
    part of the joint review — it is sealed from the log, not asked again."""

    def _review_for(self, client, user, item):
        return client.get(
            f"/partner/reviews/by-title?source={item['source']}&media_id={item['id']}", headers=user.headers,
        ).json()

    def test_a_rated_log_seals_the_loggers_part_and_only_the_other_is_asked(self, client, pair, sample_media_item):
        alice, bob = pair
        item = sample_media_item(id="tt201")
        _log_together(client, alice, item, rating=9, mood_tags=["музыка"])
        mine = self._review_for(client, alice, item)
        assert mine["i_am_done"] is True and mine["revealed"] is False
        me = next(p for p in mine["people"] if p["is_you"])
        assert me["rating"] == 9 and me["tags"] == ["музыка"]
        assert _pending(client, alice) == []
        assert len(_pending(client, bob)) == 1
        seen_by_bob = self._review_for(client, bob, item)
        assert all(p["rating"] is None for p in seen_by_bob["people"])

    def test_an_unrated_log_leaves_the_part_to_write(self, client, pair, sample_media_item):
        alice, _ = pair
        item = sample_media_item(id="tt202")
        _log_together(client, alice, item, rating=None)
        assert self._review_for(client, alice, item)["i_am_done"] is False
        assert len(_pending(client, alice)) == 1

    def test_when_both_log_the_same_evening_the_review_opens_at_the_second_log(self, client, pair, sample_media_item):
        alice, bob = pair
        item = sample_media_item(id="tt203")
        _log_together(client, alice, item, rating=9)
        _log_together(client, bob, item, rating=6)
        opened = self._review_for(client, bob, item)
        assert opened["revealed"] is True
        assert opened["summary"]["average"] == 7.5 and opened["summary"]["verdict"] == "close"
        assert {p["rating"] for p in opened["people"]} == {9, 6}
        assert client.get("/partner/reviews/pending", headers=alice.headers).json() == []

    def test_a_late_partner_rating_through_the_review_opens_it(self, client, pair, sample_media_item):
        alice, bob = pair
        item = sample_media_item(id="tt204")
        _log_together(client, alice, item, rating=8)
        rid = self._review_for(client, bob, item)["id"]
        opened = _put(client, bob, rid, rating=8, tags=["смех"]).json()
        assert opened["revealed"] is True and opened["summary"]["verdict"] == "unison"

    def test_a_company_waits_for_everyone(self, client, company, sample_media_item):
        alice, bob, carol = company
        item = sample_media_item(id="tt205")
        _log_together(client, alice, item, rating=9)
        _log_together(client, bob, item, rating=9)
        assert self._review_for(client, alice, item)["revealed"] is False
        _log_together(client, carol, item, rating=7)
        assert self._review_for(client, alice, item)["revealed"] is True
