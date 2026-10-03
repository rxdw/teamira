"""Integration tests for app/routers/feed.py — scoped to POST /react,
the one endpoint in this router that's local-DB-only. GET /feed,
/feed/movies, /feed/for-you, and /feed/collections all pull live from
TMDB/IGDB/Google Books/Shikimori and aren't covered here — see
tests/README.md."""


class TestReact:
    def test_watched_adds_to_the_watched_shelf(self, client, register_user, sample_media_item):
        alice = register_user()
        item = sample_media_item()

        resp = client.post("/feed/react", json={"item": item, "action": "watched"}, headers=alice.headers)
        assert resp.status_code == 204

        watched_ids = [e["media_id"] for e in client.get("/profile/collections", headers=alice.headers).json()["watched"]]
        assert item["id"] in watched_ids

    def test_like_adds_to_watch_later_not_watched(self, client, register_user, sample_media_item):
        alice = register_user()
        item = sample_media_item()

        resp = client.post("/feed/react", json={"item": item, "action": "like"}, headers=alice.headers)
        assert resp.status_code == 204

        collections = client.get("/profile/collections", headers=alice.headers).json()
        assert item["id"] in [e["media_id"] for e in collections["watch_later"]]
        assert item["id"] not in [e["media_id"] for e in collections["watched"]]

    def test_skip_does_not_touch_any_shelf(self, client, register_user, sample_media_item):
        alice = register_user()
        item = sample_media_item()

        resp = client.post("/feed/react", json={"item": item, "action": "skip"}, headers=alice.headers)
        assert resp.status_code == 204

        collections = client.get("/profile/collections", headers=alice.headers).json()
        assert collections == {"watch_later": [], "watching": [], "watched": []}

    def test_invalid_action_is_rejected(self, client, register_user, sample_media_item):
        alice = register_user()
        resp = client.post(
            "/feed/react", json={"item": sample_media_item(), "action": "not-a-real-action"}, headers=alice.headers
        )
        assert resp.status_code == 400

    def test_requires_auth(self, client, sample_media_item):
        resp = client.post("/feed/react", json={"item": sample_media_item(), "action": "watched"})
        assert resp.status_code == 401
