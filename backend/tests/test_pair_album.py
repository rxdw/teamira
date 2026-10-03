"""Pair album (routers/pair_album.py, app/pair_album.py).

The properties worth pinning down are the promises the feature makes:
a partner's note is never readable before the evening is watched, a
capsule is never readable before its date (and the *server's* date is the
one that counts), unlimited writing needs premium but a free couple still
gets a small taste and reading never costs anything, and the whole album
goes with the link.
"""

from datetime import date, datetime, timedelta, timezone

import pytest

from app import models, pair_album


def _link(client, a, b):
    code = client.post("/partner/pair", headers=a.headers).json()["pending_code"]
    resp = client.post("/partner/join", json={"code": code}, headers=b.headers)
    assert resp.status_code == 200, resp.text


def _buy(db_session, user):
    state = db_session.get(models.UserPremiumState, user.id)
    if state is None:
        state = models.UserPremiumState(user_id=user.id, is_premium=False, ai_asks_used=0)
        db_session.add(state)
    state.is_premium = True
    state.plan_kind = models.PremiumPlanKind.couple
    state.plan_duration = models.PremiumDuration.month
    state.purchased_at = datetime.now(timezone.utc)
    db_session.commit()


@pytest.fixture
def pair(client, db_session, register_user):
    """A linked couple where alice holds the couple plan (so both write)."""
    alice, bob = register_user(), register_user()
    _buy(db_session, alice)
    _link(client, alice, bob)
    return alice, bob


def _put_note(client, user, item, body="Купи попкорн", mood=None):
    return client.put(
        "/partner/album/notes",
        json={"item": item, "body": body, "mood": mood},
        headers=user.headers,
    )


def _plan_and_watch(client, user, item):
    planned = client.post("/partner/co-viewing/plan", json={"item": item}, headers=user.headers)
    assert planned.status_code in (200, 201), planned.text
    return client.post(f"/partner/co-viewing/{planned.json()['id']}/watched", headers=user.headers)


class TestNotesSealing:
    def test_partner_cannot_read_my_note_before_the_evening(self, client, pair, sample_media_item):
        alice, bob = pair
        item = sample_media_item()
        assert _put_note(client, alice, item, body="секрет").status_code == 200

        page = client.get("/partner/album/notes/waiting", headers=bob.headers).json()
        assert len(page) == 1
        assert page[0]["partner_sealed"] is True
        assert page[0]["partner"] is None
        assert page[0]["mine"] is None
        assert "секрет" not in str(page)

    def test_author_sees_their_own_text_and_that_partner_has_not_written(
        self, client, pair, sample_media_item
    ):
        alice, bob = pair
        item = sample_media_item()
        page = _put_note(client, alice, item, body="мой текст").json()
        assert page["state"] == "waiting"
        assert page["mine"]["body"] == "мой текст"
        assert page["partner_sealed"] is False

    def test_each_person_has_their_own_note_and_rewriting_edits_it(
        self, client, pair, sample_media_item
    ):
        alice, bob = pair
        item = sample_media_item()
        _put_note(client, alice, item, body="v1")
        _put_note(client, alice, item, body="v2")
        _put_note(client, bob, item, body="bob")

        mine = client.get("/partner/album/notes/waiting", headers=alice.headers).json()[0]
        assert mine["mine"]["body"] == "v2"
        assert mine["partner_sealed"] is True
        status = client.get("/partner/album", headers=alice.headers).json()
        assert status["waiting_mine"] == 1 and status["waiting_partner"] == 1

    def test_author_can_take_back_a_sealed_note(self, client, pair, sample_media_item):
        alice, bob = pair
        page = _put_note(client, alice, sample_media_item()).json()
        assert client.delete(f"/partner/album/notes/{page['mine']['id']}", headers=alice.headers).status_code == 204
        assert client.get("/partner/album/notes/waiting", headers=bob.headers).json() == []

    def test_partner_cannot_delete_my_note(self, client, pair, sample_media_item):
        alice, bob = pair
        page = _put_note(client, alice, sample_media_item()).json()
        resp = client.delete(f"/partner/album/notes/{page['mine']['id']}", headers=bob.headers)
        assert resp.status_code == 404

    def test_rejects_empty_and_overlong_and_unknown_mood(self, client, pair, sample_media_item):
        alice, _ = pair
        item = sample_media_item()
        assert _put_note(client, alice, item, body="   ").status_code == 400
        assert _put_note(client, alice, item, body="а" * (pair_album.NOTE_MAX_CHARS + 1)).status_code == 400
        assert _put_note(client, alice, item, body="ok", mood="🦄").status_code == 400
        assert _put_note(client, alice, item, body="ok", mood="💌").status_code == 200


class TestReveal:
    def test_marking_watched_opens_both_notes_for_both_sides(self, client, pair, sample_media_item):
        alice, bob = pair
        item = sample_media_item()
        _put_note(client, alice, item, body="от Алисы")
        _put_note(client, bob, item, body="от Боба")

        resp = _plan_and_watch(client, alice, item)
        assert resp.status_code == 200, resp.text
        # Alice marked it: Bob's note is what just opened *for her*.
        assert resp.json()["album_reveal_count"] == 1

        for viewer, expected_other in ((alice, "от Боба"), (bob, "от Алисы")):
            pages = client.get("/partner/album/pages", headers=viewer.headers).json()["items"]
            assert len(pages) == 1
            assert pages[0]["state"] == "revealed"
            assert pages[0]["partner"]["body"] == expected_other
            assert pages[0]["unread"] is True

    def test_opened_and_react_are_per_reader_and_one_way(self, client, pair, sample_media_item):
        alice, bob = pair
        item = sample_media_item()
        _put_note(client, alice, item, body="hi")
        _plan_and_watch(client, alice, item)

        bob_page = client.get("/partner/album/pages", headers=bob.headers).json()["items"][0]
        note_id = bob_page["partner"]["id"]
        assert client.post(f"/partner/album/notes/{note_id}/opened", headers=bob.headers).status_code == 204
        assert client.post(
            f"/partner/album/notes/{note_id}/react", json={"emoji": "❤️"}, headers=bob.headers
        ).status_code == 204
        # Not an allowed reaction:
        assert client.post(
            f"/partner/album/notes/{note_id}/react", json={"emoji": "💩"}, headers=bob.headers
        ).status_code == 400
        # The author can't react to their own note.
        assert client.post(
            f"/partner/album/notes/{note_id}/react", json={"emoji": "❤️"}, headers=alice.headers
        ).status_code == 404

        after = client.get("/partner/album/pages", headers=bob.headers).json()["items"][0]
        assert after["unread"] is False
        alice_view = client.get("/partner/album/pages", headers=alice.headers).json()["items"][0]
        assert alice_view["mine"]["reaction"] == "❤️"

    def test_revealed_note_is_frozen(self, client, pair, sample_media_item):
        alice, _ = pair
        item = sample_media_item()
        page = _put_note(client, alice, item).json()
        _plan_and_watch(client, alice, item)
        resp = client.delete(f"/partner/album/notes/{page['mine']['id']}", headers=alice.headers)
        assert resp.status_code == 409

    def test_cannot_leave_a_note_on_an_already_watched_evening(self, client, pair, sample_media_item):
        alice, _ = pair
        item = sample_media_item()
        _plan_and_watch(client, alice, item)
        assert _put_note(client, alice, item).status_code == 409

    def test_replanning_a_watched_title_starts_a_fresh_sealed_round(
        self, client, pair, sample_media_item
    ):
        alice, bob = pair
        item = sample_media_item()
        _put_note(client, alice, item, body="раунд 1")
        _plan_and_watch(client, alice, item)

        # Watch it again: the old entry must be gone from "planned" first.
        entries = client.get("/partner/co-viewing", headers=alice.headers).json()
        for e in entries.get("watched", []):
            client.delete(f"/partner/co-viewing/{e['id']}", headers=alice.headers)

        second = _put_note(client, alice, item, body="раунд 2").json()
        assert second["round"] == 2
        assert second["state"] == "waiting"
        pages = client.get("/partner/album/pages", headers=bob.headers).json()["items"]
        assert [p["round"] for p in pages] == [1]

    def test_watched_without_notes_reveals_nothing(self, client, pair, sample_media_item):
        alice, _ = pair
        resp = _plan_and_watch(client, alice, sample_media_item())
        assert resp.json()["album_reveal_count"] == 0

    def test_reveal_is_scoped_to_the_title(self, client, pair, sample_media_item):
        alice, bob = pair
        a, b = sample_media_item(), sample_media_item()
        _put_note(client, alice, a, body="про A")
        _put_note(client, alice, b, body="про B")
        _plan_and_watch(client, bob, a)
        waiting = client.get("/partner/album/notes/waiting", headers=bob.headers).json()
        assert [w["media_id"] for w in waiting] == [b["id"]]


class TestPremiumGate:
    def test_reading_survives_a_lapse_and_unlimited_writing_does_not(
        self, client, db_session, register_user, sample_media_item
    ):
        alice, bob = register_user(), register_user()
        _buy(db_session, alice)
        _link(client, alice, bob)
        # Premium lets alice write well past the free allowance.
        first = sample_media_item()
        _put_note(client, alice, first, body="пока есть подписка")
        for _ in range(pair_album.FREE_NOTES_PER_AUTHOR):
            assert _put_note(client, alice, sample_media_item()).status_code == 200
        _plan_and_watch(client, alice, first)

        # Premium lapses.
        state = db_session.get(models.UserPremiumState, alice.id)
        state.is_premium = False
        db_session.commit()

        # Alice is already over the free allowance, so a new note is refused...
        assert _put_note(client, alice, sample_media_item()).status_code == 402
        status = client.get("/partner/album", headers=bob.headers).json()
        assert status["is_premium"] is False
        # ...but everything written stays readable.
        pages = client.get("/partner/album/pages", headers=bob.headers).json()["items"]
        assert pages[0]["partner"]["body"] == "пока есть подписка"

    def test_the_partner_of_the_payer_can_write_too(self, client, pair, sample_media_item):
        _, bob = pair
        assert _put_note(client, bob, sample_media_item()).status_code == 200

    def test_premium_circle_has_no_ceiling_in_the_status(self, client, pair):
        alice, _ = pair
        status = client.get("/partner/album", headers=alice.headers).json()
        assert status["is_premium"] is True
        assert status["notes_limit"] is None and status["capsules_limit"] is None

    def test_the_anniversary_date_is_still_premium_only(self, client, register_user):
        alice, bob = register_user(), register_user()
        _link(client, alice, bob)
        assert client.put(
            "/partner/album/together-since", json={"together_since": "2024-01-01"}, headers=alice.headers
        ).status_code == 402


class TestFreeAllowance:
    """A free couple gets FREE_NOTES_PER_AUTHOR notes each and
    FREE_CAPSULES_PER_LINK capsule — enough for the habit to form."""

    @pytest.fixture
    def free(self, client, register_user):
        alice, bob = register_user(), register_user()
        _link(client, alice, bob)
        return alice, bob

    @staticmethod
    def _capsule(client, user, days=90, body="Привет из прошлого"):
        opens = (pair_album.utc_today() + timedelta(days=days)).isoformat()
        return client.post(
            "/partner/album/capsules", json={"opens_on": opens, "body": body}, headers=user.headers
        )

    def test_status_reports_the_allowance(self, client, free):
        alice, _ = free
        status = client.get("/partner/album", headers=alice.headers).json()
        assert status["is_premium"] is False
        assert status["notes_limit"] == pair_album.FREE_NOTES_PER_AUTHOR
        assert status["notes_used"] == 0
        assert status["capsules_limit"] == pair_album.FREE_CAPSULES_PER_LINK
        assert status["capsules_used"] == 0

    def test_notes_run_out_after_the_free_ones(self, client, free, sample_media_item):
        alice, _ = free
        for _ in range(pair_album.FREE_NOTES_PER_AUTHOR):
            assert _put_note(client, alice, sample_media_item()).status_code == 200
        assert _put_note(client, alice, sample_media_item()).status_code == 402
        status = client.get("/partner/album", headers=alice.headers).json()
        assert status["notes_used"] == pair_album.FREE_NOTES_PER_AUTHOR

    def test_notes_are_counted_per_person(self, client, free, sample_media_item):
        alice, bob = free
        for _ in range(pair_album.FREE_NOTES_PER_AUTHOR):
            _put_note(client, alice, sample_media_item())
        assert _put_note(client, alice, sample_media_item()).status_code == 402
        # Bob hasn't used any of his.
        assert _put_note(client, bob, sample_media_item()).status_code == 200
        assert client.get("/partner/album", headers=bob.headers).json()["notes_used"] == 1

    def test_rewriting_a_note_never_costs_a_slot(self, client, free, sample_media_item):
        alice, _ = free
        items = [sample_media_item() for _ in range(pair_album.FREE_NOTES_PER_AUTHOR)]
        for it in items:
            assert _put_note(client, alice, it, body="раз").status_code == 200
        # At the ceiling, but editing a note that's already there still works.
        assert _put_note(client, alice, items[0], body="переписано").status_code == 200
        assert client.get("/partner/album", headers=alice.headers).json()["notes_used"] == len(items)

    def test_taking_back_a_sealed_note_gives_the_slot_back(self, client, free, sample_media_item):
        alice, _ = free
        page = None
        for _ in range(pair_album.FREE_NOTES_PER_AUTHOR):
            page = _put_note(client, alice, sample_media_item()).json()
        assert _put_note(client, alice, sample_media_item()).status_code == 402
        assert client.delete(
            f"/partner/album/notes/{page['mine']['id']}", headers=alice.headers
        ).status_code == 204
        assert _put_note(client, alice, sample_media_item()).status_code == 200

    def test_a_revealed_note_keeps_its_slot(self, client, free, sample_media_item):
        alice, _ = free
        first = sample_media_item()
        _put_note(client, alice, first)
        for _ in range(pair_album.FREE_NOTES_PER_AUTHOR - 1):
            _put_note(client, alice, sample_media_item())
        _plan_and_watch(client, alice, first)
        # The revealed note is in the book now — it still counts.
        assert _put_note(client, alice, sample_media_item()).status_code == 402

    def test_one_free_capsule_then_the_paywall(self, client, free):
        alice, bob = free
        assert self._capsule(client, alice).status_code == 201
        assert self._capsule(client, alice).status_code == 402
        # The allowance is the couple's, not the person's.
        assert self._capsule(client, bob).status_code == 402
        status = client.get("/partner/album", headers=bob.headers).json()
        assert status["capsules_used"] == 1 and status["capsules_limit"] == 1

    def test_partner_can_always_add_a_letter_to_the_free_capsule(self, client, free):
        alice, bob = free
        cap = self._capsule(client, alice).json()
        added = client.post(
            f"/partner/album/capsules/{cap['id']}/letter", json={"body": "и моё"}, headers=bob.headers
        )
        assert added.status_code == 200, added.text
        assert added.json()["partner_letter_sealed"] and added.json()["my_letter_sealed"]

    def test_an_opened_capsule_still_counts(self, client, free, monkeypatch):
        alice, _ = free
        self._capsule(client, alice, days=40)
        later = pair_album.utc_today() + timedelta(days=41)
        monkeypatch.setattr(pair_album, "utc_today", lambda: later)
        # Not a queue depth: opening the capsule doesn't hand out a fresh one.
        assert self._capsule(client, alice, days=40).status_code == 402

    def test_taking_a_capsule_back_gives_the_slot_back(self, client, free):
        alice, _ = free
        cap = self._capsule(client, alice).json()
        assert self._capsule(client, alice).status_code == 402
        assert client.delete(f"/partner/album/capsules/{cap['id']}", headers=alice.headers).status_code == 204
        assert self._capsule(client, alice).status_code == 201

    def test_validation_still_comes_first_for_a_free_couple(self, client, free):
        alice, _ = free
        assert self._capsule(client, alice, days=5).status_code == 400
        assert self._capsule(client, alice, body="   ").status_code == 400
        assert client.get("/partner/album", headers=alice.headers).json()["capsules_used"] == 0

    def test_letter_into_a_capsule_survives_a_lapse(self, client, db_session, register_user):
        alice, bob = register_user(), register_user()
        _buy(db_session, alice)
        _link(client, alice, bob)
        cap = self._capsule(client, alice).json()
        state = db_session.get(models.UserPremiumState, alice.id)
        state.is_premium = False
        db_session.commit()
        added = client.post(
            f"/partner/album/capsules/{cap['id']}/letter", json={"body": "после подписки"}, headers=bob.headers
        )
        assert added.status_code == 200, added.text


class TestNotACouple:
    def test_unlinked_user_gets_409(self, client, register_user):
        solo = register_user()
        assert client.get("/partner/album", headers=solo.headers).status_code == 409

    def test_requires_auth(self, client):
        assert client.get("/partner/album").status_code in (401, 403)


class TestUnlink:
    def test_album_goes_with_the_link(self, client, db_session, pair, sample_media_item):
        alice, bob = pair
        _put_note(client, alice, sample_media_item(), body="исчезнет")
        future = (pair_album.utc_today() + timedelta(days=60)).isoformat()
        client.post("/partner/album/capsules", json={"opens_on": future, "body": "письмо"}, headers=alice.headers)
        assert db_session.query(models.PairNote).count() == 1
        assert db_session.query(models.PairCapsule).count() == 1

        assert client.delete("/partner", headers=alice.headers).status_code == 204
        db_session.expire_all()
        assert db_session.query(models.PairNote).count() == 0
        assert db_session.query(models.PairCapsule).count() == 0
        assert db_session.query(models.PairCapsuleLetter).count() == 0


class TestCapsules:
    def _make(self, client, user, days=90, body="Привет из прошлого", title="Через год"):
        opens = (pair_album.utc_today() + timedelta(days=days)).isoformat()
        return client.post(
            "/partner/album/capsules",
            json={"opens_on": opens, "body": body, "title": title},
            headers=user.headers,
        )

    def test_sealed_capsule_never_exposes_text_to_anyone(self, client, pair):
        alice, bob = pair
        resp = self._make(client, alice, body="СЕКРЕТНОЕ-ПИСЬМО")
        assert resp.status_code == 201, resp.text
        for viewer in (alice, bob):
            body = client.get("/partner/album/capsules", headers=viewer.headers).json()
            assert "СЕКРЕТНОЕ-ПИСЬМО" not in str(body)
            cap = body["items"][0]
            assert cap["state"] == "sealed" and cap["letters"] == []
        assert client.get("/partner/album/capsules", headers=bob.headers).json()["items"][0]["partner_letter_sealed"] is True

    def test_date_bounds(self, client, pair):
        alice, _ = pair
        assert self._make(client, alice, days=5).status_code == 400
        assert self._make(client, alice, days=pair_album.CAPSULE_MAX_DAYS + 5).status_code == 400
        assert self._make(client, alice, days=pair_album.CAPSULE_MIN_DAYS).status_code == 201

    def test_cannot_open_early_and_server_clock_decides(self, client, pair, monkeypatch):
        alice, bob = pair
        cap = self._make(client, alice, days=40).json()
        assert client.post(f"/partner/album/capsules/{cap['id']}/open", headers=alice.headers).status_code == 409

        later = pair_album.utc_today() + timedelta(days=40)
        monkeypatch.setattr(pair_album, "utc_today", lambda: later)
        assert client.post(f"/partner/album/capsules/{cap['id']}/open", headers=alice.headers).status_code == 200

    def test_partner_adds_letter_then_both_read_after_opening(self, client, pair, monkeypatch):
        alice, bob = pair
        cap = self._make(client, alice, days=40, body="письмо Алисы").json()
        added = client.post(
            f"/partner/album/capsules/{cap['id']}/letter", json={"body": "письмо Боба"}, headers=bob.headers
        )
        assert added.status_code == 200, added.text
        assert added.json()["my_letter_sealed"] and added.json()["partner_letter_sealed"]
        # Only one letter per person.
        assert client.post(
            f"/partner/album/capsules/{cap['id']}/letter", json={"body": "ещё"}, headers=bob.headers
        ).status_code == 409

        later = pair_album.utc_today() + timedelta(days=41)
        monkeypatch.setattr(pair_album, "utc_today", lambda: later)
        opened = client.post(f"/partner/album/capsules/{cap['id']}/open", headers=bob.headers).json()
        assert opened["state"] == "open" and opened["opened_by_me"] is True
        assert {l["body"] for l in opened["letters"]} == {"письмо Алисы", "письмо Боба"}
        # Alice hasn't watched it open yet: it's "ready" for her, not for Bob.
        assert client.get("/partner/album", headers=alice.headers).json()["capsules_ready"] == 1
        assert client.get("/partner/album", headers=bob.headers).json()["capsules_ready"] == 0

    def test_no_letters_after_opening(self, client, pair, monkeypatch):
        alice, bob = pair
        cap = self._make(client, alice, days=40).json()
        later = pair_album.utc_today() + timedelta(days=41)
        monkeypatch.setattr(pair_album, "utc_today", lambda: later)
        resp = client.post(
            f"/partner/album/capsules/{cap['id']}/letter", json={"body": "поздно"}, headers=bob.headers
        )
        assert resp.status_code == 409

    def test_only_creator_deletes_and_only_while_alone_inside(self, client, pair):
        alice, bob = pair
        cap = self._make(client, alice).json()
        assert client.delete(f"/partner/album/capsules/{cap['id']}", headers=bob.headers).status_code == 403
        client.post(f"/partner/album/capsules/{cap['id']}/letter", json={"body": "моё"}, headers=bob.headers)
        assert client.delete(f"/partner/album/capsules/{cap['id']}", headers=alice.headers).status_code == 409

        cap2 = self._make(client, alice, title="вторая").json()
        assert cap2["can_delete"] is True
        assert client.delete(f"/partner/album/capsules/{cap2['id']}", headers=alice.headers).status_code == 204

    def test_limit_on_simultaneous_sealed_capsules(self, client, pair):
        alice, _ = pair
        for i in range(pair_album.MAX_SEALED_CAPSULES_PER_LINK):
            assert self._make(client, alice, title=f"c{i}").status_code == 201
        assert self._make(client, alice, title="лишняя").status_code == 409


class TestAnniversary:
    def test_set_read_and_clear(self, client, pair):
        alice, bob = pair
        d = (pair_album.utc_today() - timedelta(days=400)).isoformat()
        resp = client.put("/partner/album/together-since", json={"together_since": d}, headers=alice.headers)
        assert resp.status_code == 200, resp.text
        seen = client.get("/partner/album", headers=bob.headers).json()
        assert seen["together_since"] == d
        assert seen["together_set_by"] == alice.username

        cleared = client.put("/partner/album/together-since", json={"together_since": None}, headers=bob.headers)
        assert cleared.json()["together_since"] is None

    def test_future_and_ancient_dates_are_rejected(self, client, pair):
        alice, _ = pair
        tomorrow = (pair_album.utc_today() + timedelta(days=1)).isoformat()
        assert client.put(
            "/partner/album/together-since", json={"together_since": tomorrow}, headers=alice.headers
        ).status_code == 400
        assert client.put(
            "/partner/album/together-since", json={"together_since": "1900-01-01"}, headers=alice.headers
        ).status_code == 400

    def test_status_reports_first_evening_and_counts(self, client, pair, sample_media_item):
        alice, _ = pair
        item = sample_media_item()
        _plan_and_watch(client, alice, item)
        status = client.get("/partner/album", headers=alice.headers).json()
        assert status["is_couple"] is True
        assert status["evenings_together"] == 1
        assert status["first_evening"]["title_ru"] == "Тестовый фильм"
        assert [p["is_you"] for p in status["people"]] == [True, False]


class TestDateMath:
    def test_leap_day_anniversary_falls_on_feb_28_in_common_years(self):
        start = date(2024, 2, 29)
        assert pair_album.is_anniversary_today(start, date(2027, 2, 28))
        assert pair_album.is_anniversary_today(start, date(2028, 2, 29))
        assert pair_album.full_years(start, date(2027, 2, 27)) == 2
        assert pair_album.full_years(start, date(2027, 2, 28)) == 3

    def test_day_one_is_not_an_anniversary_but_day_100_is_a_milestone(self):
        start = date(2026, 1, 1)
        assert not pair_album.is_anniversary_today(start, start)
        assert pair_album.milestone_today(start, date(2026, 4, 10)) == 100
        assert pair_album.days_together(start, start) == 1

    def test_russian_plurals(self):
        assert pair_album.ru_years(1) == "1 год"
        assert pair_album.ru_years(3) == "3 года"
        assert pair_album.ru_years(11) == "11 лет"
        assert pair_album.ru_days(21) == "21 день"


class TestScheduledPushes:
    """scripts/send_scheduled_push.py::send_pair_album_pushes — the album's
    clock-driven moments. The script isn't a package module, so it's loaded
    by path; the timezone-window lookup is replaced with a fixed "it's
    morning for everyone" so the test doesn't depend on the wall clock."""

    @pytest.fixture
    def script(self, monkeypatch):
        import importlib.util
        from pathlib import Path

        path = Path(__file__).resolve().parents[1] / "scripts" / "send_scheduled_push.py"
        spec = importlib.util.spec_from_file_location("send_scheduled_push_under_test", path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod

    def _run(self, script, db_session, monkeypatch, users, today, sent_titles):
        from datetime import datetime as _dt

        local_now = _dt(today.year, today.month, today.day, 9, 0)
        monkeypatch.setattr(script, "_users_in_evening_window", lambda db, a, b: iter([(u, local_now) for u in users]))

        def fake_send(db, user, category, title, body, data=None):
            sent_titles.append((user.id, title, (data or {}).get("type")))
            db.add(models.PushLog(user_id=user.id, category=category.value, title=title, body=body))
            db.commit()
            return 1

        monkeypatch.setattr(script.push.push_service, "send_to_user", fake_send)
        return script.send_pair_album_pushes(db_session, dry_run=False)

    def _users(self, db_session, *ids):
        return [db_session.get(models.User, i) for i in ids]

    def test_anniversary_push_goes_to_both_once_per_day(self, client, db_session, pair, script, monkeypatch):
        alice, bob = pair
        today = pair_album.utc_today()
        start = date(today.year - 2, today.month, today.day) if not (today.month == 2 and today.day == 29) else date(2022, 2, 28)
        assert client.put(
            "/partner/album/together-since", json={"together_since": start.isoformat()}, headers=alice.headers
        ).status_code == 200

        sent = []
        users = self._users(db_session, alice.id, bob.id)
        assert self._run(script, db_session, monkeypatch, users, today, sent) == 2
        assert {t for _, t, _ in sent} == {"2 года вместе 💞"}
        assert {k for _, _, k in sent} == {"pair_album_anniversary"}
        # A second run the same day sends nothing new.
        assert self._run(script, db_session, monkeypatch, users, today, sent) == 0

    def test_round_day_count_pushes_and_ordinary_days_do_not(self, client, db_session, pair, script, monkeypatch):
        alice, bob = pair
        today = pair_album.utc_today()
        hundredth = today - timedelta(days=99)  # counting day one as day 1
        client.put("/partner/album/together-since", json={"together_since": hundredth.isoformat()}, headers=alice.headers)
        sent = []
        users = self._users(db_session, alice.id, bob.id)
        assert self._run(script, db_session, monkeypatch, users, today, sent) == 2
        assert sent[0][1] == "100 дней вместе ✨"

        # An ordinary day: nothing.
        client.put(
            "/partner/album/together-since",
            json={"together_since": (today - timedelta(days=50)).isoformat()},
            headers=alice.headers,
        )
        sent2 = []
        assert self._run(script, db_session, monkeypatch, users, today, sent2) == 0

    def test_capsule_day_pushes_only_to_whoever_hasnt_opened_it(
        self, client, db_session, pair, script, monkeypatch
    ):
        alice, bob = pair
        opens = pair_album.utc_today() + timedelta(days=40)
        cap = client.post(
            "/partner/album/capsules", json={"opens_on": opens.isoformat(), "body": "x"}, headers=alice.headers
        ).json()
        # Two days after it opened: too late to announce it as news.
        users = self._users(db_session, alice.id, bob.id)
        sent = []
        assert self._run(script, db_session, monkeypatch, users, opens + timedelta(days=2), sent) == 0
        # On the day itself, both are told...
        assert self._run(script, db_session, monkeypatch, users, opens, sent) == 2
        assert {k for _, _, k in sent} == {"pair_album_capsule"}
        # ...but not someone who already watched it open.
        db_session.add(models.PairCapsuleRead(capsule_id=cap["id"], user_id=bob.id))
        db_session.commit()
        db_session.query(models.PushLog).delete()
        db_session.commit()
        sent3 = []
        assert self._run(script, db_session, monkeypatch, users, opens, sent3) == 1
        assert sent3[0][0] == alice.id
