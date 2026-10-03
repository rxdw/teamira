"""routers/diary.py::log_entry's two push triggers (audit 4.4.1):
friend-activity (respecting privacy + an actual accepted friendship) and
level-up (a before/after compare within the same request — level itself
is a derived read, never a stored counter; see
profile.py::compute_level_for_user). Both fire via BackgroundTasks after
db.commit() — TestClient runs those synchronously as part of the
request/response cycle, so patching the function and asserting on the
call is enough here, same pattern as tests/test_co_view_vote.py and
tests/test_partner.py's own push tests.
"""

from unittest.mock import patch

from app import sincerity


def _log(client, headers, sample_media_item, **overrides):
    payload = {"item": sample_media_item(), **overrides}
    resp = client.post("/diary", json=payload, headers=headers)
    assert resp.status_code == 201, resp.text
    return resp.json()


def _befriend(client, a, b):
    client.post("/friends/request", json={"username": b.username}, headers=a.headers)
    request_id = client.get("/friends", headers=b.headers).json()["incoming_requests"][0]["id"]
    accepted = client.post(f"/friends/requests/{request_id}/accept", headers=b.headers)
    assert accepted.status_code == 200


class TestFriendActivityPush:
    def test_friend_gets_notified_when_you_log_something(self, client, register_user, sample_media_item):
        alice = register_user()
        bob = register_user()
        _befriend(client, alice, bob)

        with patch("app.routers.diary.push.notify_friend_activity") as mock_notify:
            _log(client, alice.headers, sample_media_item, rating=9)

        assert mock_notify.called
        (friend_ids, actor_name, title_name, rating, *_rest) = mock_notify.call_args[0]
        assert friend_ids == [bob.id]
        assert actor_name == alice.username
        assert title_name == "Тестовый фильм"  # sample_media_item's title.ru
        assert rating == 9

    def test_stranger_is_not_notified(self, client, register_user, sample_media_item):
        alice = register_user()
        register_user()  # bob exists but is not alice's friend

        with patch("app.routers.diary.push.notify_friend_activity") as mock_notify:
            _log(client, alice.headers, sample_media_item)
        assert not mock_notify.called

    def test_respects_privacy_watched_set_to_nobody(self, client, register_user, sample_media_item):
        alice = register_user()
        bob = register_user()
        _befriend(client, alice, bob)
        client.patch("/profile/me", json={"privacy_watched": "nobody"}, headers=alice.headers)

        with patch("app.routers.diary.push.notify_friend_activity") as mock_notify:
            _log(client, alice.headers, sample_media_item)
        assert not mock_notify.called

    def test_multiple_friends_all_get_the_recipient_list(self, client, register_user, sample_media_item):
        alice = register_user()
        bob = register_user()
        carol = register_user()
        _befriend(client, alice, bob)
        _befriend(client, alice, carol)

        with patch("app.routers.diary.push.notify_friend_activity") as mock_notify:
            _log(client, alice.headers, sample_media_item)

        (friend_ids, *_rest) = mock_notify.call_args[0]
        assert set(friend_ids) == {bob.id, carol.id}

    def test_importing_history_never_triggers_this(self, client, register_user, sample_media_item):
        """log_watched (the shared helper) is also called from
        imports.py's CSV import path — this asserts the push trigger
        itself only lives in log_entry's own body, not inside
        log_watched, so a future import-path call can never pick it up
        by accident. Exercised here indirectly: a plain diary log is the
        only thing under test elsewhere in this file, so this is really
        a documentation test — see routers/diary.py::log_entry's own
        comment on why imports/integrations/co-view logging are
        deliberately excluded."""
        import inspect
        from app.routers import diary as diary_module

        log_watched_src = inspect.getsource(diary_module.log_watched)
        assert "notify_friend_activity" not in log_watched_src


class TestLevelUpPush:
    def test_no_push_when_level_does_not_change(self, client, register_user, sample_media_item):
        alice = register_user()
        with patch("app.routers.diary.push.notify_level_up") as mock_notify:
            _log(client, alice.headers, sample_media_item)
        assert not mock_notify.called

    def test_push_fires_exactly_when_crossing_a_level_threshold(self, client, register_user, sample_media_item):
        """Each log here is a brand-new distinct title (sample_media_item()
        mints a fresh id every call) with no note, genres, or together
        flag, so each one earns exactly sincerity.WATCHED_LOGGED_AWARD
        (1 point) via app/sincerity.py::earn_watched_logged — nothing
        blurs which log crosses the line. With
        sincerity.LEVEL_BASE_POINTS points needed for level 2, the log
        at that count is exactly the one that should cross from level 1
        to level 2."""
        alice = register_user()
        for _ in range(sincerity.LEVEL_BASE_POINTS - 1):
            with patch("app.routers.diary.push.notify_level_up") as mock_notify:
                _log(client, alice.headers, sample_media_item)
            assert not mock_notify.called, "should still be level 1 before the threshold"

        with patch("app.routers.diary.push.notify_level_up") as mock_notify:
            _log(client, alice.headers, sample_media_item)
        assert mock_notify.called
        (user_id, new_level) = mock_notify.call_args[0]
        assert user_id == alice.id
        assert new_level == 2

        level_now = client.get("/profile/level", headers=alice.headers).json()["level"]
        assert level_now == 2
