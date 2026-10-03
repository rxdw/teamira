"""Integration tests for app/routers/friends.py — the request lifecycle
(send/accept/decline/cancel/remove) and, most importantly, that a
profile's shelves actually respect each one's own privacy setting
(everyone/friends/nobody) depending on who's looking. `GET
/friends/suggested` and the invite-code endpoints are still untested —
see tests/README.md."""


class TestFriendRequestLifecycle:
    def test_send_request_appears_on_both_sides(self, client, register_user):
        alice = register_user()
        bob = register_user()

        sent = client.post("/friends/request", json={"username": bob.username}, headers=alice.headers)
        assert sent.status_code == 201

        alices_view = client.get("/friends", headers=alice.headers).json()
        assert any(r["username"] == bob.username for r in alices_view["outgoing_requests"])

        bobs_view = client.get("/friends", headers=bob.headers).json()
        assert any(r["username"] == alice.username for r in bobs_view["incoming_requests"])

    def test_accept_makes_them_friends_both_ways(self, client, register_user):
        alice = register_user()
        bob = register_user()
        client.post("/friends/request", json={"username": bob.username}, headers=alice.headers)
        request_id = client.get("/friends", headers=bob.headers).json()["incoming_requests"][0]["id"]

        accepted = client.post(f"/friends/requests/{request_id}/accept", headers=bob.headers)
        assert accepted.status_code == 200
        assert accepted.json()["username"] == alice.username

        alices_friends = [f["username"] for f in client.get("/friends", headers=alice.headers).json()["friends"]]
        bobs_friends = [f["username"] for f in client.get("/friends", headers=bob.headers).json()["friends"]]
        assert bob.username in alices_friends
        assert alice.username in bobs_friends

    def test_decline_does_not_make_them_friends(self, client, register_user):
        alice = register_user()
        bob = register_user()
        client.post("/friends/request", json={"username": bob.username}, headers=alice.headers)
        request_id = client.get("/friends", headers=bob.headers).json()["incoming_requests"][0]["id"]

        declined = client.post(f"/friends/requests/{request_id}/decline", headers=bob.headers)
        assert declined.status_code == 204

        alices_friends = client.get("/friends", headers=alice.headers).json()["friends"]
        assert alices_friends == []

    def test_recipient_cannot_accept_a_request_not_addressed_to_them(self, client, register_user):
        alice = register_user()
        bob = register_user()
        mallory = register_user()
        client.post("/friends/request", json={"username": bob.username}, headers=alice.headers)
        request_id = client.get("/friends", headers=bob.headers).json()["incoming_requests"][0]["id"]

        resp = client.post(f"/friends/requests/{request_id}/accept", headers=mallory.headers)
        assert resp.status_code == 404

    def test_sender_can_cancel_a_still_pending_request(self, client, register_user):
        alice = register_user()
        bob = register_user()
        client.post("/friends/request", json={"username": bob.username}, headers=alice.headers)
        request_id = client.get("/friends", headers=alice.headers).json()["outgoing_requests"][0]["id"]

        cancelled = client.delete(f"/friends/requests/{request_id}", headers=alice.headers)
        assert cancelled.status_code == 204
        assert client.get("/friends", headers=alice.headers).json()["outgoing_requests"] == []

    def test_recipient_cannot_cancel_the_senders_request(self, client, register_user):
        alice = register_user()
        bob = register_user()
        client.post("/friends/request", json={"username": bob.username}, headers=alice.headers)
        request_id = client.get("/friends", headers=alice.headers).json()["outgoing_requests"][0]["id"]

        resp = client.delete(f"/friends/requests/{request_id}", headers=bob.headers)
        assert resp.status_code == 404

    def test_remove_an_accepted_friend(self, client, register_user):
        alice = register_user()
        bob = register_user()
        client.post("/friends/request", json={"username": bob.username}, headers=alice.headers)
        request_id = client.get("/friends", headers=bob.headers).json()["incoming_requests"][0]["id"]
        client.post(f"/friends/requests/{request_id}/accept", headers=bob.headers)

        removed = client.delete(f"/friends/{bob.id}", headers=alice.headers)
        assert removed.status_code == 204
        assert client.get("/friends", headers=alice.headers).json()["friends"] == []

    def test_cannot_friend_yourself(self, client, register_user):
        alice = register_user()
        resp = client.post("/friends/request", json={"username": alice.username}, headers=alice.headers)
        assert resp.status_code == 400

    def test_cannot_send_a_second_pending_request(self, client, register_user):
        alice = register_user()
        bob = register_user()
        client.post("/friends/request", json={"username": bob.username}, headers=alice.headers)
        second = client.post("/friends/request", json={"username": bob.username}, headers=alice.headers)
        assert second.status_code == 400

    def test_unknown_username_is_404(self, client, register_user):
        alice = register_user()
        resp = client.post("/friends/request", json={"username": "no_such_user_at_all"}, headers=alice.headers)
        assert resp.status_code == 404

    def test_friends_endpoints_require_auth(self, client):
        assert client.get("/friends").status_code == 401


class TestSearch:
    def test_finds_by_partial_username(self, client, register_user):
        alice = register_user()
        target = register_user(username="findable_target_xyz")
        results = client.get("/friends/search", params={"q": "findable_target"}, headers=alice.headers)
        assert results.status_code == 200
        assert any(r["user_id"] == target.id for r in results.json())

    def test_excludes_self(self, client, register_user):
        alice = register_user(username="search_for_self_test")
        results = client.get("/friends/search", params={"q": "search_for_self_test"}, headers=alice.headers)
        assert all(r["user_id"] != alice.id for r in results.json())

    def test_tags_status_correctly(self, client, register_user):
        alice = register_user()
        bob = register_user(username="status_tag_bob")
        client.post("/friends/request", json={"username": bob.username}, headers=alice.headers)

        results = client.get("/friends/search", params={"q": "status_tag_bob"}, headers=alice.headers).json()
        bob_result = next(r for r in results if r["user_id"] == bob.id)
        assert bob_result["status"] == "pending_outgoing"


class TestProfileVisibility:
    """The privacy-gated side of GET /friends/{user_id}/profile: does a
    shelf's everyone/friends/nobody setting actually gate who can see
    it, or does it just decorate a response everyone gets the same
    data in anyway."""

    def _give_alice_a_watched_title(self, client, alice, sample_media_item):
        client.post("/diary", json={"item": sample_media_item()}, headers=alice.headers)

    def test_everyone_level_is_visible_to_a_stranger(self, client, register_user, sample_media_item):
        alice = register_user()
        stranger = register_user()
        self._give_alice_a_watched_title(client, alice, sample_media_item)
        # privacy_watched defaults to "everyone" — no PATCH needed.

        resp = client.get(f"/friends/{alice.id}/profile", headers=stranger.headers)
        assert resp.status_code == 200
        body = resp.json()
        assert body["collections"]["watched_visible"] is True
        assert len(body["collections"]["watched"]) == 1

    def test_friends_only_level_is_hidden_from_a_stranger(self, client, register_user, sample_media_item):
        alice = register_user()
        stranger = register_user()
        self._give_alice_a_watched_title(client, alice, sample_media_item)
        client.patch("/profile/me", json={"privacy_watched": "friends"}, headers=alice.headers)

        resp = client.get(f"/friends/{alice.id}/profile", headers=stranger.headers)
        assert resp.status_code == 200
        body = resp.json()
        assert body["collections"]["watched_visible"] is False
        assert body["collections"]["watched"] == []

    def test_friends_only_level_is_visible_to_an_accepted_friend(self, client, register_user, sample_media_item):
        alice = register_user()
        friend = register_user()
        self._give_alice_a_watched_title(client, alice, sample_media_item)
        client.patch("/profile/me", json={"privacy_watched": "friends"}, headers=alice.headers)

        client.post("/friends/request", json={"username": friend.username}, headers=alice.headers)
        request_id = client.get("/friends", headers=friend.headers).json()["incoming_requests"][0]["id"]
        client.post(f"/friends/requests/{request_id}/accept", headers=friend.headers)

        resp = client.get(f"/friends/{alice.id}/profile", headers=friend.headers)
        body = resp.json()
        assert body["collections"]["watched_visible"] is True
        assert len(body["collections"]["watched"]) == 1

    def test_nobody_level_is_hidden_even_from_a_friend(self, client, register_user, sample_media_item):
        alice = register_user()
        friend = register_user()
        self._give_alice_a_watched_title(client, alice, sample_media_item)
        client.patch("/profile/me", json={"privacy_watched": "nobody"}, headers=alice.headers)

        client.post("/friends/request", json={"username": friend.username}, headers=alice.headers)
        request_id = client.get("/friends", headers=friend.headers).json()["incoming_requests"][0]["id"]
        client.post(f"/friends/requests/{request_id}/accept", headers=friend.headers)

        resp = client.get(f"/friends/{alice.id}/profile", headers=friend.headers)
        body = resp.json()
        assert body["collections"]["watched_visible"] is False
        assert body["collections"]["watched"] == []

    def test_own_profile_bypasses_the_friends_only_restriction(
        self, client, register_user, sample_media_item
    ):
        alice = register_user()
        self._give_alice_a_watched_title(client, alice, sample_media_item)
        client.patch("/profile/me", json={"privacy_watched": "friends"}, headers=alice.headers)

        resp = client.get(f"/friends/{alice.id}/profile", headers=alice.headers)
        assert resp.json()["collections"]["watched_visible"] is True

    def test_own_profile_does_not_bypass_the_nobody_restriction(
        self, client, register_user, sample_media_item
    ):
        # Asymmetric with the "friends" case just above: routers/friends.py's
        # _shelf_ok() explicitly special-cases `user_id == current_user.id`
        # for the "friends" branch but not for "nobody" (see that function),
        # so setting a shelf to "nobody" hides it from you too through this
        # specific endpoint. In practice this never bites anyone — the
        # mobile client only ever calls GET /friends/{id}/profile with
        # someone *else's* id (see FriendProfileScreen/FavoriteFilmsScreen's
        # own docstrings — your own profile always goes through the
        # unrestricted GET /profile/collections instead) — but it's real,
        # current backend behavior, so pinning it here beats leaving it to
        # be rediscovered by surprise later.
        alice = register_user()
        self._give_alice_a_watched_title(client, alice, sample_media_item)
        client.patch("/profile/me", json={"privacy_watched": "nobody"}, headers=alice.headers)

        resp = client.get(f"/friends/{alice.id}/profile", headers=alice.headers)
        assert resp.json()["collections"]["watched_visible"] is False
