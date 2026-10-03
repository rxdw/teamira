"""Tests for app/routers/integrations.py. The Plex/Jellyfin/generic
webhook tests below all use payloads with no tmdb_id/imdb_id, so
_ingest's "no catalog match -> log a synthetic standalone entry" path
runs (see that function) rather than the real TmdbAdapter.resolve_external_id
call, keeping this offline and deterministic — the matched/resolved path
isn't covered here."""

from app.routers.integrations import _parse_jellyfin_payload, _parse_plex_metadata


class TestParsePlexMetadata:
    def test_movie(self):
        parsed = _parse_plex_metadata({"type": "movie", "title": "The Matrix", "year": 1999})
        assert parsed.title == "The Matrix"
        assert parsed.media_type == "movie"
        assert parsed.year == 1999

    def test_episode_uses_the_show_title_not_the_episode_title(self):
        parsed = _parse_plex_metadata({
            "type": "episode", "title": "Pilot", "grandparentTitle": "Breaking Bad",
            "parentIndex": 1, "index": 1,
        })
        assert parsed.title == "Breaking Bad"
        assert parsed.media_type == "series"
        assert parsed.season == 1
        assert parsed.episode == 1

    def test_extracts_tmdb_and_imdb_guids(self):
        parsed = _parse_plex_metadata({
            "type": "movie", "title": "x",
            "Guid": [{"id": "tmdb://603"}, {"id": "imdb://tt0133093"}],
        })
        assert parsed.tmdb_id == "603"
        assert parsed.imdb_id == "tt0133093"

    def test_unsupported_type_returns_none(self):
        assert _parse_plex_metadata({"type": "track", "title": "x"}) is None

    def test_missing_type_returns_none(self):
        assert _parse_plex_metadata({"title": "x"}) is None


class TestParseJellyfinPayload:
    def test_movie(self):
        parsed = _parse_jellyfin_payload({"ItemType": "Movie", "Name": "The Matrix", "Year": 1999})
        assert parsed.title == "The Matrix"
        assert parsed.media_type == "movie"

    def test_episode_uses_the_series_name(self):
        parsed = _parse_jellyfin_payload({
            "ItemType": "Episode", "Name": "Pilot", "SeriesName": "Breaking Bad",
            "SeasonNumber": 1, "EpisodeNumber": 1,
        })
        assert parsed.title == "Breaking Bad"
        assert parsed.media_type == "series"

    def test_is_case_insensitive_on_item_type(self):
        assert _parse_jellyfin_payload({"ItemType": "movie", "Name": "x"}) is not None

    def test_extracts_provider_ids(self):
        parsed = _parse_jellyfin_payload({"ItemType": "Movie", "Name": "x", "Provider_tmdb": 603})
        assert parsed.tmdb_id == "603"

    def test_unsupported_type_returns_none(self):
        assert _parse_jellyfin_payload({"ItemType": "Audio", "Name": "x"}) is None

    def test_missing_type_returns_none(self):
        assert _parse_jellyfin_payload({"Name": "x"}) is None


class TestTokenManagement:
    def test_requires_auth(self, client):
        assert client.get("/integrations/token").status_code == 401

    def test_creates_a_token_on_first_request(self, client, register_user):
        alice = register_user()
        resp = client.get("/integrations/token", headers=alice.headers)
        assert resp.status_code == 200
        body = resp.json()
        assert body["token"]
        assert body["token"] in body["plex_webhook_url"]
        assert body["token"] in body["kodi_url"]

    def test_is_idempotent_across_calls(self, client, register_user):
        alice = register_user()
        first = client.get("/integrations/token", headers=alice.headers).json()["token"]
        second = client.get("/integrations/token", headers=alice.headers).json()["token"]
        assert first == second

    def test_rotate_changes_it(self, client, register_user):
        alice = register_user()
        first = client.get("/integrations/token", headers=alice.headers).json()["token"]
        rotated = client.post("/integrations/token/rotate", headers=alice.headers).json()["token"]
        assert rotated != first

    def test_the_old_token_stops_working_after_rotation(self, client, register_user):
        alice = register_user()
        old_token = client.get("/integrations/token", headers=alice.headers).json()["token"]
        client.post("/integrations/token/rotate", headers=alice.headers)

        resp = client.post(f"/integrations/{old_token}/scrobble", json={"title": "x"})
        assert resp.status_code == 404


class TestGenericScrobble:
    def test_completed_logs_a_diary_entry(self, client, register_user):
        alice = register_user()
        token = client.get("/integrations/token", headers=alice.headers).json()["token"]

        resp = client.post(f"/integrations/{token}/scrobble", json={"title": "Some Movie", "completed": True})
        assert resp.status_code == 200
        assert resp.json()["status"] == "ok"

        diary = client.get("/diary", headers=alice.headers).json()
        assert len(diary) == 1
        assert diary[0]["title_en"] == "Some Movie"

    def test_below_the_watched_threshold_is_ignored(self, client, register_user):
        alice = register_user()
        token = client.get("/integrations/token", headers=alice.headers).json()["token"]

        resp = client.post(
            f"/integrations/{token}/scrobble",
            json={"title": "x", "completed": False, "progress": 0.3},
        )
        assert resp.status_code == 200
        assert resp.json()["ignored"] == "below watched threshold"
        assert client.get("/diary", headers=alice.headers).json() == []

    def test_above_the_watched_threshold_still_logs_even_if_not_marked_completed(self, client, register_user):
        alice = register_user()
        token = client.get("/integrations/token", headers=alice.headers).json()["token"]

        resp = client.post(
            f"/integrations/{token}/scrobble",
            json={"title": "x", "completed": False, "progress": 0.95},
        )
        assert resp.json()["status"] == "ok"
        assert len(client.get("/diary", headers=alice.headers).json()) == 1

    def test_unknown_token_is_404(self, client):
        resp = client.post("/integrations/not-a-real-token/scrobble", json={"title": "x"})
        assert resp.status_code == 404

    def test_shows_up_in_recent_events(self, client, register_user):
        alice = register_user()
        token = client.get("/integrations/token", headers=alice.headers).json()["token"]
        client.post(f"/integrations/{token}/scrobble", json={"title": "x", "completed": True})

        events = client.get("/integrations/events", headers=alice.headers)
        assert events.status_code == 200
        assert len(events.json()) == 1
        assert events.json()[0]["action"] == "logged"

    def test_events_require_auth(self, client):
        assert client.get("/integrations/events").status_code == 401

    def test_events_do_not_leak_between_accounts(self, client, register_user):
        alice = register_user()
        bob = register_user()
        token = client.get("/integrations/token", headers=alice.headers).json()["token"]
        client.post(f"/integrations/{token}/scrobble", json={"title": "x", "completed": True})

        assert client.get("/integrations/events", headers=bob.headers).json() == []


class TestPlexWebhook:
    def _post(self, client, token, payload_dict):
        import json as _json
        return client.post(f"/integrations/{token}/plex", data={"payload": _json.dumps(payload_dict)})

    def test_scrobble_event_logs_an_entry(self, client, register_user):
        alice = register_user()
        token = client.get("/integrations/token", headers=alice.headers).json()["token"]

        resp = self._post(client, token, {
            "event": "media.scrobble",
            "Metadata": {"type": "movie", "title": "The Matrix", "year": 1999},
        })
        assert resp.status_code == 200
        assert resp.json()["status"] == "ok"
        assert len(client.get("/diary", headers=alice.headers).json()) == 1

    def test_non_scrobble_events_are_ignored(self, client, register_user):
        alice = register_user()
        token = client.get("/integrations/token", headers=alice.headers).json()["token"]

        resp = self._post(client, token, {"event": "media.play", "Metadata": {"type": "movie", "title": "x"}})
        assert resp.json()["ignored"] == "media.play"
        assert client.get("/diary", headers=alice.headers).json() == []

    def test_unsupported_media_type_is_ignored(self, client, register_user):
        alice = register_user()
        token = client.get("/integrations/token", headers=alice.headers).json()["token"]

        resp = self._post(client, token, {"event": "media.scrobble", "Metadata": {"type": "track", "title": "x"}})
        assert resp.json()["ignored"] == "unsupported media type"

    def test_no_payload_field_is_ignored_not_a_500(self, client, register_user):
        alice = register_user()
        token = client.get("/integrations/token", headers=alice.headers).json()["token"]
        resp = client.post(f"/integrations/{token}/plex", data={})
        assert resp.status_code == 200
        assert resp.json()["ignored"] == "no payload field"

    def test_unknown_token_is_404(self, client):
        resp = self._post(client, "not-a-real-token", {"event": "media.scrobble", "Metadata": {}})
        assert resp.status_code == 404


class TestJellyfinWebhook:
    def test_playback_stop_completed_logs_an_entry(self, client, register_user):
        alice = register_user()
        token = client.get("/integrations/token", headers=alice.headers).json()["token"]

        resp = client.post(f"/integrations/{token}/jellyfin", json={
            "NotificationType": "PlaybackStop", "PlayedToCompletion": True,
            "ItemType": "Movie", "Name": "The Matrix",
        })
        assert resp.status_code == 200
        assert resp.json()["status"] == "ok"
        assert len(client.get("/diary", headers=alice.headers).json()) == 1

    def test_playback_stop_not_completed_is_ignored(self, client, register_user):
        alice = register_user()
        token = client.get("/integrations/token", headers=alice.headers).json()["token"]

        resp = client.post(f"/integrations/{token}/jellyfin", json={
            "NotificationType": "PlaybackStop", "PlayedToCompletion": False,
            "ItemType": "Movie", "Name": "x",
        })
        assert resp.json()["ignored"] == "stopped before the end"
        assert client.get("/diary", headers=alice.headers).json() == []

    def test_item_marked_as_played_logs_without_needing_playback_stop(self, client, register_user):
        alice = register_user()
        token = client.get("/integrations/token", headers=alice.headers).json()["token"]

        resp = client.post(f"/integrations/{token}/jellyfin", json={
            "NotificationType": "ItemMarkedAsPlayed", "ItemType": "Movie", "Name": "x",
        })
        assert resp.json()["status"] == "ok"

    def test_irrelevant_notification_types_are_ignored(self, client, register_user):
        alice = register_user()
        token = client.get("/integrations/token", headers=alice.headers).json()["token"]

        resp = client.post(f"/integrations/{token}/jellyfin", json={"NotificationType": "PlaybackStart"})
        assert resp.json()["ignored"] == "PlaybackStart"
