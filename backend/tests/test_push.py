"""app/push.py + routers/push.py (audit 4.4.1). firebase_admin itself is
never actually called against a real Firebase project here — every test
either leaves settings.firebase_credentials_json empty (the "disabled"
path, exercised directly) or patches
firebase_admin.messaging.send_each_for_multicast so the "enabled" path is
tested without a network call. See app/push.py's own docstring for why
that patch point is safe: _firebase_app() (which would need real
credentials to succeed) is never reached unless send_each_for_multicast
itself has already been replaced.
"""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from app import models
from app.config import settings
from app.push import CATEGORY_COPY, PushCategory, push_service


@pytest.fixture()
def with_firebase_configured():
    """Most of this module's tests need settings.firebase_credentials_json
    non-empty just to get past PushService.send_to_user's first check —
    the value itself is never parsed as real JSON unless a test also
    lets _firebase_app() run, which none of them do (see module
    docstring)."""
    original = settings.firebase_credentials_json
    settings.firebase_credentials_json = '{"type": "service_account", "project_id": "fake"}'
    yield
    settings.firebase_credentials_json = original


def _fake_batch_response(results: list[bool | Exception]):
    """Builds a fake firebase_admin.messaging.BatchResponse-shaped object
    for `results`, where True means that token's send succeeded and an
    Exception instance means it failed with that exception."""
    responses = []
    success_count = 0
    for r in results:
        m = MagicMock()
        if r is True:
            m.success = True
            m.exception = None
            success_count += 1
        else:
            m.success = False
            m.exception = r
        responses.append(m)
    batch = MagicMock()
    batch.responses = responses
    batch.success_count = success_count
    return batch


class TestPushServiceDisabled:
    def test_send_is_a_noop_without_firebase_credentials(self, db_session, register_user):
        alice = register_user()
        user = db_session.query(models.User).filter(models.User.id == alice.id).first()
        db_session.add(models.PushToken(user_id=user.id, token="tok-1", platform="android"))
        db_session.commit()

        assert settings.firebase_credentials_json == ""
        with patch("firebase_admin.messaging.send_each_for_multicast") as mock_send:
            sent = push_service.send_to_user(db_session, user, PushCategory.MATCHES, "T", "B")
        assert sent == 0
        assert not mock_send.called
        assert db_session.query(models.PushLog).count() == 0


class TestPushServiceSending:
    def test_sends_to_every_registered_token(self, db_session, register_user, with_firebase_configured):
        alice = register_user()
        user = db_session.query(models.User).filter(models.User.id == alice.id).first()
        db_session.add(models.PushToken(user_id=user.id, token="tok-a", platform="android"))
        db_session.add(models.PushToken(user_id=user.id, token="tok-b", platform="ios"))
        db_session.commit()

        batch = _fake_batch_response([True, True])
        with patch("firebase_admin.messaging.send_each_for_multicast", return_value=batch) as mock_send:
            with patch("app.push._firebase_app", return_value=None):
                sent = push_service.send_to_user(
                    db_session, user, PushCategory.MATCHES, "Совпадение!", "Текст",
                )
        assert sent == 2
        called_message = mock_send.call_args[0][0]
        assert sorted(called_message.tokens) == ["tok-a", "tok-b"]

    def test_logs_every_send_for_the_scheduled_scripts_idempotency_check(
        self, db_session, register_user, with_firebase_configured
    ):
        alice = register_user()
        user = db_session.query(models.User).filter(models.User.id == alice.id).first()
        db_session.add(models.PushToken(user_id=user.id, token="tok-a", platform="android"))
        db_session.commit()

        batch = _fake_batch_response([True])
        with patch("firebase_admin.messaging.send_each_for_multicast", return_value=batch):
            with patch("app.push._firebase_app", return_value=None):
                push_service.send_to_user(db_session, user, PushCategory.STREAK_REMINDERS, "T", "B")

        logs = db_session.query(models.PushLog).filter(models.PushLog.user_id == user.id).all()
        assert len(logs) == 1
        assert logs[0].category == "streak_reminders"
        assert logs[0].title == "T"

    def test_unregistered_token_is_deleted_other_failures_are_kept(
        self, db_session, register_user, with_firebase_configured
    ):
        from firebase_admin import messaging

        alice = register_user()
        user = db_session.query(models.User).filter(models.User.id == alice.id).first()
        db_session.add(models.PushToken(user_id=user.id, token="tok-dead", platform="android"))
        db_session.add(models.PushToken(user_id=user.id, token="tok-quota", platform="android"))
        db_session.add(models.PushToken(user_id=user.id, token="tok-good", platform="android"))
        db_session.commit()

        # Order must match the order PushService queries tokens in
        # (insertion order here, id-ordered in practice) — the test
        # builds tokens+results as parallel lists to stay in sync
        # rather than relying on that.
        tokens_in_db = [
            t.token for t in db_session.query(models.PushToken).filter(models.PushToken.user_id == user.id)
        ]
        results = []
        for t in tokens_in_db:
            if t == "tok-dead":
                results.append(messaging.UnregisteredError("gone"))
            elif t == "tok-quota":
                results.append(messaging.QuotaExceededError("slow down"))
            else:
                results.append(True)
        batch = _fake_batch_response(results)

        with patch("firebase_admin.messaging.send_each_for_multicast", return_value=batch):
            with patch("app.push._firebase_app", return_value=None):
                push_service.send_to_user(db_session, user, PushCategory.MATCHES, "T", "B")

        remaining = {
            t.token for t in db_session.query(models.PushToken).filter(models.PushToken.user_id == user.id)
        }
        assert remaining == {"tok-quota", "tok-good"}, (
            "only the UnregisteredError token should be gone — a quota error is transient"
        )

    def test_a_failed_send_call_does_not_raise(self, db_session, register_user, with_firebase_configured):
        """A Firebase outage, a bad credential that only fails once used
        — none of this should ever propagate up into whatever triggered
        the notification (a diary log, a match)."""
        alice = register_user()
        user = db_session.query(models.User).filter(models.User.id == alice.id).first()
        db_session.add(models.PushToken(user_id=user.id, token="tok-a", platform="android"))
        db_session.commit()

        with patch("firebase_admin.messaging.send_each_for_multicast", side_effect=RuntimeError("network blip")):
            with patch("app.push._firebase_app", return_value=None):
                sent = push_service.send_to_user(db_session, user, PushCategory.MATCHES, "T", "B")
        assert sent == 0

    def test_no_tokens_registered_is_a_cheap_noop(self, db_session, register_user, with_firebase_configured):
        alice = register_user()
        user = db_session.query(models.User).filter(models.User.id == alice.id).first()
        with patch("firebase_admin.messaging.send_each_for_multicast") as mock_send:
            sent = push_service.send_to_user(db_session, user, PushCategory.MATCHES, "T", "B")
        assert sent == 0
        assert not mock_send.called


class TestPreferenceGating:
    def test_opted_out_category_is_never_sent(self, db_session, register_user, with_firebase_configured):
        alice = register_user()
        user = db_session.query(models.User).filter(models.User.id == alice.id).first()
        user.notification_prefs = {"matches": False}
        db_session.add(models.PushToken(user_id=user.id, token="tok-a", platform="android"))
        db_session.commit()

        with patch("firebase_admin.messaging.send_each_for_multicast") as mock_send:
            sent = push_service.send_to_user(db_session, user, PushCategory.MATCHES, "T", "B")
        assert sent == 0
        assert not mock_send.called

    def test_missing_key_defaults_to_enabled(self, db_session, register_user, with_firebase_configured):
        """Opt-out model — see models.User.notification_prefs's own
        docstring. An account that never touched the settings screen has
        notification_prefs = None, and every category should still be on."""
        alice = register_user()
        user = db_session.query(models.User).filter(models.User.id == alice.id).first()
        assert user.notification_prefs is None
        db_session.add(models.PushToken(user_id=user.id, token="tok-a", platform="android"))
        db_session.commit()

        batch = _fake_batch_response([True])
        with patch("firebase_admin.messaging.send_each_for_multicast", return_value=batch):
            with patch("app.push._firebase_app", return_value=None):
                sent = push_service.send_to_user(db_session, user, PushCategory.MATCHES, "T", "B")
        assert sent == 1

    def test_one_category_off_does_not_affect_another(self, db_session, register_user, with_firebase_configured):
        alice = register_user()
        user = db_session.query(models.User).filter(models.User.id == alice.id).first()
        user.notification_prefs = {"matches": False}
        db_session.add(models.PushToken(user_id=user.id, token="tok-a", platform="android"))
        db_session.commit()

        batch = _fake_batch_response([True])
        with patch("firebase_admin.messaging.send_each_for_multicast", return_value=batch):
            with patch("app.push._firebase_app", return_value=None):
                sent = push_service.send_to_user(db_session, user, PushCategory.LEVEL_UPS, "T", "B")
        assert sent == 1


class TestSendToUsers:
    def test_sends_to_each_person_independently(self, db_session, register_user, with_firebase_configured):
        alice = register_user()
        bob = register_user()
        alice_user = db_session.query(models.User).filter(models.User.id == alice.id).first()
        bob_user = db_session.query(models.User).filter(models.User.id == bob.id).first()
        bob_user.notification_prefs = {"matches": False}  # bob opted out
        db_session.add(models.PushToken(user_id=alice_user.id, token="tok-alice", platform="android"))
        db_session.add(models.PushToken(user_id=bob_user.id, token="tok-bob", platform="android"))
        db_session.commit()

        batch = _fake_batch_response([True])
        with patch("firebase_admin.messaging.send_each_for_multicast", return_value=batch) as mock_send:
            with patch("app.push._firebase_app", return_value=None):
                total = push_service.send_to_users(
                    db_session, [alice_user, bob_user], PushCategory.MATCHES, "Match!", "Body",
                )
        # Only alice's token should ever have been sent to.
        assert total == 1
        assert mock_send.call_count == 1
        assert mock_send.call_args[0][0].tokens == ["tok-alice"]


class TestPushRouter:
    def test_register_then_get_preferences_shows_all_categories_on(self, client, register_user):
        alice = register_user()
        resp = client.post(
            "/push/tokens",
            json={"token": "tok-abc-long-enough", "platform": "android", "timezone": "Europe/Moscow"},
            headers=alice.headers,
        )
        assert resp.status_code == 200

        resp = client.get("/push/preferences", headers=alice.headers)
        assert resp.status_code == 200
        categories = resp.json()["categories"]
        assert len(categories) == len(CATEGORY_COPY)
        assert all(c["enabled"] for c in categories)

    def test_register_is_idempotent_for_the_same_token(self, client, register_user):
        alice = register_user()
        for _ in range(3):
            resp = client.post(
                "/push/tokens", json={"token": "tok-dup-long-enough", "platform": "ios"}, headers=alice.headers,
            )
            assert resp.status_code == 200

    def test_registering_an_existing_token_under_a_new_user_moves_ownership(
        self, client, register_user, db_session
    ):
        """A shared/reset device: alice signs out, bob signs in, Firebase
        hands the client the same token it already had. See
        register_token's own docstring for why this is correct rather
        than a collision."""
        alice = register_user()
        bob = register_user()
        client.post("/push/tokens", json={"token": "shared-tok", "platform": "android"}, headers=alice.headers)
        client.post("/push/tokens", json={"token": "shared-tok", "platform": "android"}, headers=bob.headers)

        row = db_session.query(models.PushToken).filter(models.PushToken.token == "shared-tok").first()
        assert row.user_id == bob.id
        assert db_session.query(models.PushToken).filter(models.PushToken.token == "shared-tok").count() == 1

    def test_unknown_platform_string_does_not_500(self, client, register_user):
        alice = register_user()
        resp = client.post(
            "/push/tokens", json={"token": "tok-weird", "platform": "smart-fridge"}, headers=alice.headers,
        )
        assert resp.status_code == 200

    def test_unregister_only_removes_the_callers_own_token(self, client, register_user, db_session):
        alice = register_user()
        bob = register_user()
        client.post("/push/tokens", json={"token": "alice-tok", "platform": "ios"}, headers=alice.headers)

        # bob tries to delete alice's token by guessing its value
        resp = client.delete("/push/tokens/alice-tok", headers=bob.headers)
        assert resp.status_code == 200  # no error, but...
        assert db_session.query(models.PushToken).filter(models.PushToken.token == "alice-tok").count() == 1, (
            "bob has no such token registered to him, so nothing should have been deleted"
        )

        resp = client.delete("/push/tokens/alice-tok", headers=alice.headers)
        assert resp.status_code == 200
        assert db_session.query(models.PushToken).filter(models.PushToken.token == "alice-tok").count() == 0

    def test_patch_preferences_only_changes_named_categories(self, client, register_user):
        alice = register_user()
        client.patch("/push/preferences", json={"categories": {"matches": False}}, headers=alice.headers)
        resp = client.get("/push/preferences", headers=alice.headers)
        by_cat = {c["category"]: c["enabled"] for c in resp.json()["categories"]}
        assert by_cat["matches"] is False
        assert by_cat["friend_activity"] is True  # untouched

    def test_patch_preferences_ignores_unknown_category_keys(self, client, register_user):
        alice = register_user()
        resp = client.patch(
            "/push/preferences", json={"categories": {"not_a_real_category": False}}, headers=alice.headers,
        )
        assert resp.status_code == 200
        # Nothing should have blown up, and no real category was affected.
        assert all(c["enabled"] for c in resp.json()["categories"])

    def test_requires_auth(self, client):
        assert client.post("/push/tokens", json={"token": "t", "platform": "ios"}).status_code == 401
        assert client.get("/push/preferences").status_code == 401
        assert client.patch("/push/preferences", json={"categories": {}}).status_code == 401
