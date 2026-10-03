"""Tests for app/routers/together.py. create_session always builds its
deck through _build_deck, which pulls from the same 24h
"feed:collections" cache GET /feed/collections uses (see
app.cache.cached_dynamic) — pre-seeding that cache row (the same
CachedFeedSnapshot table, same approach as the *-detail cache seeding in
test_teamira_admin.py/test_media_detail.py) makes every test below run
with no live adapter call at all."""

import json

from app import models
from app.schemas import ExternalIds, LocalizedText, MediaItem


def _seed_collections_cache(db_session, items: list[MediaItem]):
    payload = [{"title": "Test Shelf", "title_en": None, "items": [i.model_dump(mode="json") for i in items]}]
    db_session.add(models.CachedFeedSnapshot(cache_key="feed:collections", payload_json=json.dumps(payload)))
    db_session.commit()


def _item(id_, media_type="movie", genres=None) -> MediaItem:
    return MediaItem(
        id=id_, media_type=media_type, external_ids=ExternalIds(tmdb=id_),
        title=LocalizedText(en=id_), description=LocalizedText(), source="tmdb",
        genres=genres or [],
    )


def _create(client, headers, **overrides):
    payload = {"type_filter": "all", "genres": [], **overrides}
    return client.post("/together", json=payload, headers=headers)


class TestCreateSession:
    def test_starts_in_waiting_with_a_code(self, client, register_user, db_session):
        alice = register_user()
        _seed_collections_cache(db_session, [_item("a")])
        resp = _create(client, alice.headers)
        assert resp.status_code == 201
        body = resp.json()
        assert body["status"] == "waiting"
        assert len(body["code"]) == 6
        assert body["my_role"] == "owner"

    def test_empty_deck_after_filtering_is_422(self, client, register_user, db_session):
        alice = register_user()
        _seed_collections_cache(db_session, [_item("a", media_type="game")])
        resp = _create(client, alice.headers, type_filter="movie")
        assert resp.status_code == 422

    def test_type_filter_series_also_matches_anime(self, client, register_user, db_session):
        alice = register_user()
        _seed_collections_cache(db_session, [_item("a", media_type="anime")])
        resp = _create(client, alice.headers, type_filter="series")
        assert resp.status_code == 201
        assert len(resp.json()["deck"]) == 1

    def test_genre_filter_requires_at_least_one_shared_genre(self, client, register_user, db_session):
        alice = register_user()
        _seed_collections_cache(db_session, [_item("a", genres=["Comedy"]), _item("b", genres=["Horror"])])
        resp = _create(client, alice.headers, genres=["Horror"])
        assert [d["id"] for d in resp.json()["deck"]] == ["b"]

    def test_requires_auth(self, client):
        assert _create(client, {}).status_code == 401


class TestJoinSession:
    def test_join_activates_the_session(self, client, register_user, db_session):
        alice = register_user()
        bob = register_user()
        _seed_collections_cache(db_session, [_item("a")])
        session = _create(client, alice.headers).json()

        resp = client.post("/together/join", json={"code": session["code"]}, headers=bob.headers)
        assert resp.status_code == 200
        body = resp.json()
        assert body["status"] == "active"
        assert body["my_role"] == "guest"

    def test_cannot_join_your_own_code(self, client, register_user, db_session):
        alice = register_user()
        _seed_collections_cache(db_session, [_item("a")])
        session = _create(client, alice.headers).json()
        resp = client.post("/together/join", json={"code": session["code"]}, headers=alice.headers)
        assert resp.status_code == 400

    def test_unknown_code_is_404(self, client, register_user):
        alice = register_user()
        resp = client.post("/together/join", json={"code": "ZZZZZZ"}, headers=alice.headers)
        assert resp.status_code == 404

    def test_a_third_person_cannot_join_an_already_taken_session(self, client, register_user, db_session):
        alice = register_user()
        bob = register_user()
        mallory = register_user()
        _seed_collections_cache(db_session, [_item("a")])
        session = _create(client, alice.headers).json()
        client.post("/together/join", json={"code": session["code"]}, headers=bob.headers)

        resp = client.post("/together/join", json={"code": session["code"]}, headers=mallory.headers)
        assert resp.status_code == 409

    def test_the_same_guest_rejoining_is_fine(self, client, register_user, db_session):
        alice = register_user()
        bob = register_user()
        _seed_collections_cache(db_session, [_item("a")])
        session = _create(client, alice.headers).json()
        client.post("/together/join", json={"code": session["code"]}, headers=bob.headers)

        again = client.post("/together/join", json={"code": session["code"]}, headers=bob.headers)
        assert again.status_code == 200
        assert again.json()["status"] == "active"

    def test_cannot_join_an_ended_session(self, client, register_user, db_session):
        alice = register_user()
        bob = register_user()
        _seed_collections_cache(db_session, [_item("a")])
        session = _create(client, alice.headers).json()
        client.delete(f"/together/{session['id']}", headers=alice.headers)

        resp = client.post("/together/join", json={"code": session["code"]}, headers=bob.headers)
        assert resp.status_code == 410


class TestSwipe:
    def test_both_yes_produces_a_match(self, client, register_user, db_session):
        alice = register_user()
        bob = register_user()
        _seed_collections_cache(db_session, [_item("a")])
        session = _create(client, alice.headers).json()
        client.post("/together/join", json={"code": session["code"]}, headers=bob.headers)

        client.post(
            f"/together/{session['id']}/swipe",
            json={"media_id": "a", "source": "tmdb", "decision": True}, headers=alice.headers,
        )
        resp = client.post(
            f"/together/{session['id']}/swipe",
            json={"media_id": "a", "source": "tmdb", "decision": True}, headers=bob.headers,
        )
        assert [m["id"] for m in resp.json()["matches"]] == ["a"]

    def test_one_yes_one_no_is_not_a_match(self, client, register_user, db_session):
        alice = register_user()
        bob = register_user()
        _seed_collections_cache(db_session, [_item("a")])
        session = _create(client, alice.headers).json()
        client.post("/together/join", json={"code": session["code"]}, headers=bob.headers)

        client.post(
            f"/together/{session['id']}/swipe",
            json={"media_id": "a", "source": "tmdb", "decision": True}, headers=alice.headers,
        )
        resp = client.post(
            f"/together/{session['id']}/swipe",
            json={"media_id": "a", "source": "tmdb", "decision": False}, headers=bob.headers,
        )
        assert resp.json()["matches"] == []

    def test_a_match_reaches_the_shared_coview_list_when_linked(self, client, register_user, db_session):
        alice = register_user()
        bob = register_user()
        code = client.post("/partner/pair", headers=alice.headers).json()["pending_code"]
        client.post("/partner/join", json={"code": code}, headers=bob.headers)

        _seed_collections_cache(db_session, [_item("a")])
        session = _create(client, alice.headers).json()
        client.post("/together/join", json={"code": session["code"]}, headers=bob.headers)
        for u in (alice, bob):
            client.post(
                f"/together/{session['id']}/swipe",
                json={"media_id": "a", "source": "tmdb", "decision": True}, headers=u.headers,
            )

        planned = client.get("/partner/shared/planned", headers=alice.headers)
        assert planned.status_code == 200
        assert any(e["media_id"] == "a" for e in planned.json()["planned"])

    def test_swiping_on_a_still_waiting_session_is_409(self, client, register_user, db_session):
        alice = register_user()
        _seed_collections_cache(db_session, [_item("a")])
        session = _create(client, alice.headers).json()  # no guest joined -> still "waiting"

        resp = client.post(
            f"/together/{session['id']}/swipe",
            json={"media_id": "a", "source": "tmdb", "decision": True}, headers=alice.headers,
        )
        assert resp.status_code == 409

    def test_a_non_participant_gets_403(self, client, register_user, db_session):
        alice = register_user()
        bob = register_user()
        stranger = register_user()
        _seed_collections_cache(db_session, [_item("a")])
        session = _create(client, alice.headers).json()
        client.post("/together/join", json={"code": session["code"]}, headers=bob.headers)

        resp = client.post(
            f"/together/{session['id']}/swipe",
            json={"media_id": "a", "source": "tmdb", "decision": True}, headers=stranger.headers,
        )
        assert resp.status_code == 403


class TestEndSession:
    def test_ending_makes_it_unswipeable(self, client, register_user, db_session):
        alice = register_user()
        bob = register_user()
        _seed_collections_cache(db_session, [_item("a")])
        session = _create(client, alice.headers).json()
        client.post("/together/join", json={"code": session["code"]}, headers=bob.headers)

        ended = client.delete(f"/together/{session['id']}", headers=alice.headers)
        assert ended.status_code == 204

        resp = client.post(
            f"/together/{session['id']}/swipe",
            json={"media_id": "a", "source": "tmdb", "decision": True}, headers=bob.headers,
        )
        assert resp.status_code == 409

    def test_unknown_session_is_404(self, client, register_user):
        alice = register_user()
        resp = client.delete("/together/00000000-0000-0000-0000-000000000000", headers=alice.headers)
        assert resp.status_code == 404
