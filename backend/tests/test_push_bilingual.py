"""Pushes worded for the device that receives them (app/bi.py, push_tokens.locale).

The server writes every push in Russian AND English (`Bi`); the token says
which one the phone wants. The rules pinned here: a token with no language is
Russian (what every push used to be), devices are grouped by language so one
send never mixes them, the PushLog keeps the Russian text, registering a token
stores a normalised language, and the notify_* helpers really do carry an
English version (a Bi with a different `.en`).
"""

from __future__ import annotations

from unittest.mock import patch

import pytest

from app import models
from app.bi import Bi, normalize_lang, pick, years_en
from app.config import settings
from app.push import PushCategory, push_service


@pytest.fixture()
def with_firebase_configured():
    original = settings.firebase_credentials_json
    settings.firebase_credentials_json = '{"type": "service_account", "project_id": "fake"}'
    yield
    settings.firebase_credentials_json = original


class TestBi:
    def test_is_the_russian_text_everywhere_a_str_is_expected(self):
        t = Bi("Совпадение!", "It's a match!")
        assert t == "Совпадение!" and isinstance(t, str) and t.en == "It's a match!"
        assert f"{t}" == "Совпадение!"

    def test_pick(self):
        t = Bi("ру", "en")
        assert pick(t, "en") == "en"
        assert pick(t, "ru") == "ру" and pick(t, None) == "ру"
        assert pick("plain", "en") == "plain"  # a text that was never bilingual

    def test_normalize_lang(self):
        assert [normalize_lang(x) for x in ("en", "en-US", " EN_gb", "ru", "ru-RU", "de", "", None)] == [
            "en", "en", "en", "ru", "ru", "ru", "ru", "ru",
        ]

    def test_years_en(self):
        assert years_en(1) == "1 year" and years_en(5) == "5 years"


class TestSendByDeviceLanguage:
    def _user(self, db_session, register_user, tokens):
        alice = register_user()
        user = db_session.query(models.User).filter(models.User.id == alice.id).first()
        for name, locale in tokens:
            db_session.add(models.PushToken(user_id=user.id, token=name, platform="android", locale=locale))
        db_session.commit()
        return user

    def test_each_language_gets_its_own_send(self, db_session, register_user, with_firebase_configured):
        user = self._user(db_session, register_user, [("t-en", "en"), ("t-ru", "ru"), ("t-old", None)])
        title, body = Bi("Привет", "Hello"), Bi("Мир", "World")
        with patch.object(push_service, "_send", return_value=1) as send:
            sent = push_service.send_to_user(db_session, user, PushCategory.MATCHES, title, body)
        calls = {tuple(c.args[1]): (c.args[2], c.args[3]) for c in send.call_args_list}
        assert calls[("t-en",)] == ("Hello", "World")
        # the token that never reported a language is Russian, same as "ru"
        assert calls[("t-ru", "t-old")] == ("Привет", "Мир")
        assert sent == 2

    def test_log_keeps_the_russian_text(self, db_session, register_user, with_firebase_configured):
        user = self._user(db_session, register_user, [("t-en", "en")])
        with patch.object(push_service, "_send", return_value=1):
            push_service.send_to_user(db_session, user, PushCategory.MATCHES, Bi("Привет", "Hello"), Bi("Мир", "World"))
        row = db_session.query(models.PushLog).one()
        assert (row.title, row.body) == ("Привет", "Мир")

    def test_plain_strings_still_work_and_go_to_everyone(self, db_session, register_user, with_firebase_configured):
        user = self._user(db_session, register_user, [("t-en", "en"), ("t-ru", "ru")])
        with patch.object(push_service, "_send", return_value=1) as send:
            push_service.send_to_user(db_session, user, PushCategory.MATCHES, "T", "B")
        assert {(c.args[2], c.args[3]) for c in send.call_args_list} == {("T", "B")}


class TestRegisterTokenLocale:
    def test_locale_is_stored_normalised_and_updated(self, client, register_user, db_session):
        user = register_user()
        body = {"token": "abc", "platform": "android", "locale": "en-US"}
        assert client.post("/push/tokens", json=body, headers=user.headers).status_code in (200, 201)
        row = db_session.query(models.PushToken).filter_by(token="abc").one()
        assert row.locale == "en"
        client.post("/push/tokens", json={**body, "locale": "ru"}, headers=user.headers)
        db_session.expire_all()
        assert db_session.query(models.PushToken).filter_by(token="abc").one().locale == "ru"

    def test_old_clients_send_no_locale(self, client, register_user, db_session):
        user = register_user()
        client.post("/push/tokens", json={"token": "old", "platform": "ios"}, headers=user.headers)
        assert db_session.query(models.PushToken).filter_by(token="old").one().locale is None


class TestCopiesCarryEnglish:
    """The notify_* helpers are the wording; what matters here is that each one
    hands send_to_user(s) a Bi whose English really is different text."""

    def _capture(self):
        seen = []

        def fake(*args, **kwargs):
            # send_to_user(db, user, category, title, body, data) and
            # send_to_users(db, users, category, title=..., body=..., data=...)
            title = kwargs.get("title", args[3] if len(args) > 3 else None)
            body = kwargs.get("body", args[4] if len(args) > 4 else None)
            seen.append((title, body))
            return 0

        return seen, fake

    def test_match_friend_request_and_level_up(self, register_user):
        from app import push

        alice = register_user()
        seen, fake = self._capture()
        with patch.object(push_service, "send_to_user", fake), patch.object(push_service, "send_to_users", fake):
            push.notify_match([alice.id], "Дюна", "tmdb-1", "tmdb", "movie")
            push.notify_friend_request(alice.id, "Маша")
            push.notify_level_up(alice.id, 7)
        assert len(seen) == 3
        for title, body in seen:
            assert isinstance(title, Bi) and isinstance(body, Bi)
            assert title.en != str(title) and body.en != str(body)  # a real English version
        assert seen[0][1].en == "You both picked “Дюна” — you can watch it tonight"
        assert seen[2][0].en == "Level 7! 🎬"

    def test_trial_and_subscription_copy_have_english(self):
        from datetime import datetime, timedelta, timezone

        from app import subscription

        now = datetime.now(timezone.utc)
        copy = subscription.pause_ending_copy(now + timedelta(days=3), now)
        assert isinstance(copy.title, Bi) and "Your pause ends in 3 days" == copy.title.en
        assert copy.title.startswith("Пауза заканчивается")
