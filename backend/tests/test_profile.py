"""Integration tests for app/routers/profile.py — scoped to the
identity/privacy editing and the favorites/collections shelves.
profile.py is a big router (stats, wrapped, achievements, avatar
upload, level); those are still untested — see tests/README.md."""


class TestGetAndUpdateMe:
    def test_get_me_reflects_registration(self, client, register_user):
        alice = register_user(username="profile_alice")
        resp = client.get("/profile/me", headers=alice.headers)
        assert resp.status_code == 200
        body = resp.json()
        assert body["username"] == "profile_alice"
        # Every shelf defaults to "everyone" until explicitly changed —
        # see models.User's own column defaults.
        assert body["privacy_watched"] == "everyone"
        assert body["privacy_watching"] == "everyone"
        assert body["privacy_planned"] == "everyone"
        assert body["privacy_favorites"] == "everyone"

    def test_update_display_name_and_status(self, client, register_user):
        alice = register_user()
        resp = client.patch(
            "/profile/me",
            json={"display_name": "Alice A.", "status_text": "watching horror movies"},
            headers=alice.headers,
        )
        assert resp.status_code == 200
        body = resp.json()
        assert body["display_name"] == "Alice A."
        assert body["status_text"] == "watching horror movies"

    def test_empty_string_clears_display_name(self, client, register_user):
        alice = register_user()
        client.patch("/profile/me", json={"display_name": "Something"}, headers=alice.headers)
        resp = client.patch("/profile/me", json={"display_name": ""}, headers=alice.headers)
        assert resp.status_code == 200
        assert resp.json()["display_name"] is None

    def test_field_left_unset_is_untouched(self, client, register_user):
        alice = register_user()
        client.patch("/profile/me", json={"status_text": "keep me"}, headers=alice.headers)
        # Sends display_name only — status_text isn't in the payload at
        # all (exclude_unset), so it should survive untouched.
        resp = client.patch("/profile/me", json={"display_name": "New Name"}, headers=alice.headers)
        assert resp.status_code == 200
        assert resp.json()["status_text"] == "keep me"

    def test_unknown_avatar_preset_is_rejected(self, client, register_user):
        alice = register_user()
        resp = client.patch("/profile/me", json={"avatar_preset": "not-a-real-preset"}, headers=alice.headers)
        assert resp.status_code == 400

    def test_privacy_level_can_be_set_to_a_valid_value(self, client, register_user):
        alice = register_user()
        resp = client.patch("/profile/me", json={"privacy_watched": "friends"}, headers=alice.headers)
        assert resp.status_code == 200
        assert resp.json()["privacy_watched"] == "friends"

    def test_invalid_privacy_level_is_rejected(self, client, register_user):
        alice = register_user()
        resp = client.patch("/profile/me", json={"privacy_watched": "only-my-cat"}, headers=alice.headers)
        assert resp.status_code == 422

    def test_requires_auth(self, client):
        assert client.get("/profile/me").status_code == 401
        assert client.patch("/profile/me", json={"display_name": "x"}).status_code == 401


class TestFavorites:
    def test_new_title_is_not_a_favorite_by_default(self, client, register_user, sample_media_item):
        alice = register_user()
        item = sample_media_item()
        resp = client.get(
            "/profile/favorites/status",
            params={"media_id": item["id"], "source": item["source"]},
            headers=alice.headers,
        )
        assert resp.status_code == 200
        assert resp.json()["is_favorite"] is False

    def test_toggle_on_then_status_reflects_it(self, client, register_user, sample_media_item):
        alice = register_user()
        item = sample_media_item()

        toggled = client.post(
            "/profile/favorites/toggle", json={"item": item, "is_favorite": True}, headers=alice.headers
        )
        assert toggled.status_code == 200
        assert toggled.json()["is_favorite"] is True

        status = client.get(
            "/profile/favorites/status",
            params={"media_id": item["id"], "source": item["source"]},
            headers=alice.headers,
        )
        assert status.json()["is_favorite"] is True

    def test_toggle_off_again(self, client, register_user, sample_media_item):
        alice = register_user()
        item = sample_media_item()
        client.post("/profile/favorites/toggle", json={"item": item, "is_favorite": True}, headers=alice.headers)

        untoggled = client.post(
            "/profile/favorites/toggle", json={"item": item, "is_favorite": False}, headers=alice.headers
        )
        assert untoggled.status_code == 200
        assert untoggled.json()["is_favorite"] is False

    def test_favoriting_an_unshelved_title_adds_it_as_watch_later(
        self, client, register_user, sample_media_item
    ):
        # toggle_favorite's own docstring: favoriting something not on any
        # shelf yet upserts a WatchlistEntry as watch_later, not just a
        # bare favorite flag with nothing backing it.
        alice = register_user()
        item = sample_media_item()
        client.post("/profile/favorites/toggle", json={"item": item, "is_favorite": True}, headers=alice.headers)

        collections = client.get("/profile/collections", headers=alice.headers)
        assert collections.status_code == 200
        watch_later_ids = [e["media_id"] for e in collections.json()["watch_later"]]
        assert item["id"] in watch_later_ids

    def test_favorites_are_private_to_the_account(self, client, register_user, sample_media_item):
        alice = register_user()
        bob = register_user()
        item = sample_media_item()
        client.post("/profile/favorites/toggle", json={"item": item, "is_favorite": True}, headers=alice.headers)

        bobs_view = client.get(
            "/profile/favorites/status",
            params={"media_id": item["id"], "source": item["source"]},
            headers=bob.headers,
        )
        assert bobs_view.json()["is_favorite"] is False


class TestCollections:
    def test_empty_for_a_fresh_account(self, client, register_user):
        alice = register_user()
        resp = client.get("/profile/collections", headers=alice.headers)
        assert resp.status_code == 200
        body = resp.json()
        assert body["watch_later"] == []
        assert body["watching"] == []
        assert body["watched"] == []

    def test_logging_a_diary_entry_puts_the_title_on_the_watched_shelf(
        self, client, register_user, sample_media_item
    ):
        alice = register_user()
        item = sample_media_item()
        logged = client.post("/diary", json={"item": item}, headers=alice.headers)
        assert logged.status_code == 201

        collections = client.get("/profile/collections", headers=alice.headers)
        watched_ids = [e["media_id"] for e in collections.json()["watched"]]
        assert item["id"] in watched_ids

    def test_collections_do_not_leak_between_accounts(self, client, register_user, sample_media_item):
        alice = register_user()
        bob = register_user()
        client.post("/diary", json={"item": sample_media_item()}, headers=alice.headers)

        bobs_collections = client.get("/profile/collections", headers=bob.headers)
        assert bobs_collections.json() == {"watch_later": [], "watching": [], "watched": []}


class TestUploadAvatar:
    """upload_avatar (POST /profile/avatar) — added alongside the
    bounded-read + magic-byte-sniffing fix (see that function's own
    comments in app/routers/profile.py for why both exist). Uses
    minimal-but-real signature bytes for each format rather than actual
    decodable images: storage.py's save() just writes the bytes through
    unchanged, and _sniff_avatar_type only ever looks at the header, so
    nothing here needs a real, renderable image."""

    _PNG_HEAD = b"\x89PNG\r\n\x1a\n" + b"\x00" * 32
    _JPEG_HEAD = b"\xff\xd8\xff" + b"\x00" * 32
    _WEBP_HEAD = b"RIFF" + b"\x24\x00\x00\x00" + b"WEBP" + b"\x00" * 32

    def test_valid_png_upload_succeeds(self, client, register_user):
        alice = register_user()
        resp = client.post(
            "/profile/avatar",
            files={"file": ("avatar.png", self._PNG_HEAD, "image/png")},
            headers=alice.headers,
        )
        assert resp.status_code == 200
        assert resp.json()["avatar_url"]

        me = client.get("/profile/me", headers=alice.headers)
        assert me.json()["avatar_url"] == resp.json()["avatar_url"]
        # An uploaded photo always beats a preset — see upload_avatar's
        # own comment on this mutual exclusivity.
        assert me.json()["avatar_preset"] is None

    def test_valid_jpeg_and_webp_also_succeed(self, client, register_user):
        alice = register_user()
        for head, ctype, name in [
            (self._JPEG_HEAD, "image/jpeg", "a.jpg"),
            (self._WEBP_HEAD, "image/webp", "a.webp"),
        ]:
            resp = client.post(
                "/profile/avatar",
                files={"file": (name, head, ctype)},
                headers=alice.headers,
            )
            assert resp.status_code == 200, (ctype, resp.text)

    def test_unsupported_content_type_is_rejected(self, client, register_user):
        alice = register_user()
        resp = client.post(
            "/profile/avatar",
            files={"file": ("avatar.gif", b"GIF89a" + b"\x00" * 16, "image/gif")},
            headers=alice.headers,
        )
        assert resp.status_code == 400

    def test_spoofed_content_type_is_rejected_by_magic_bytes(self, client, register_user):
        """The header says image/png; the bytes are actually a JPEG
        signature. This is exactly what _sniff_avatar_type exists to
        catch — a client can put whatever it wants in Content-Type."""
        alice = register_user()
        resp = client.post(
            "/profile/avatar",
            files={"file": ("avatar.png", self._JPEG_HEAD, "image/png")},
            headers=alice.headers,
        )
        assert resp.status_code == 400
        assert "match" in resp.json()["detail"].lower()

    def test_garbage_bytes_with_an_allowed_content_type_is_rejected(self, client, register_user):
        alice = register_user()
        resp = client.post(
            "/profile/avatar",
            files={"file": ("avatar.jpg", b"not actually an image, just text" * 4, "image/jpeg")},
            headers=alice.headers,
        )
        assert resp.status_code == 400

    def test_oversized_upload_is_rejected_without_buffering_it_all(self, client, register_user):
        """Doesn't (and shouldn't need to) prove memory stays bounded —
        that's what the bounded-read loop is for, not something an
        integration test can observe from the outside. What this proves
        is the outcome: a file over the cap is a clean 400, not a
        connection reset or a 500 from something further down choking on
        a too-large body."""
        alice = register_user()
        from app.routers.profile import _MAX_AVATAR_BYTES

        oversized = self._JPEG_HEAD + b"\x00" * _MAX_AVATAR_BYTES
        resp = client.post(
            "/profile/avatar",
            files={"file": ("avatar.jpg", oversized, "image/jpeg")},
            headers=alice.headers,
        )
        assert resp.status_code == 400
        assert "5 MB" in resp.json()["detail"]

    def test_requires_auth(self, client):
        resp = client.post(
            "/profile/avatar",
            files={"file": ("avatar.png", self._PNG_HEAD, "image/png")},
        )
        assert resp.status_code == 401
