"""Reading together: a book or a manga in a co-view room
(routers/co_view_room.py, app/co_reading.py).

What is worth pinning down is what the feature promises: the room never
carries the text (only where people are, and a fingerprint of the file), a
place is a canonical string that means the same thing on every device, the
shared place in "together" mode belongs to the circle, a margin note is
pinned to a place and goes through the same filter as chat, and the moments
timeline works for an evening of reading with no code of its own.
"""

from datetime import datetime, timezone

import pytest

from app import circle_review
from app import co_reading as rules
from app import co_view_room as room_rules
from app import models, pair_album

HASH_A = "a" * 64
HASH_B = "b" * 64


def _link(client, a, b):
    code = client.post("/partner/pair", headers=a.headers).json()["pending_code"]
    assert client.post("/partner/join", json={"code": code}, headers=b.headers).status_code == 200


@pytest.fixture
def pair(client, register_user):
    a, b = register_user(), register_user()
    _link(client, a, b)
    return a, b


def _create(client, user, **over):
    body = {
        "media_id": "file:aaaa", "media_type": "book", "source": "file",
        "title_ru": "Мастер и Маргарита", "title_en": "The Master and Margarita",
        "activity": "read", "read_kind": "epub", "content_hash": HASH_A, "read_units": 32,
    }
    body.update(over)
    return client.post("/partner/rooms", json=body, headers=user.headers)


def _join(client, user, room_id):
    r = client.post(f"/partner/rooms/{room_id}/join", headers=user.headers)
    assert r.status_code == 200, r.text
    return r.json()


def _here(client, user, room_id, locator, progress=0, **extra):
    return client.post(
        f"/partner/rooms/{room_id}/locator",
        json={"locator": locator, "progress": progress, **extra},
        headers=user.headers,
    )


def _patch(client, user, room_id, **body):
    return client.patch(f"/partner/rooms/{room_id}", json=body, headers=user.headers)


def _event(client, user, room_id, **body):
    return client.post(f"/partner/rooms/{room_id}/events", json=body, headers=user.headers)


def _person(room, user):
    return next(p for p in room["participants"] if p["user_id"] == user.id)


def _buy(db_session, user):
    state = db_session.get(models.UserPremiumState, user.id) or models.UserPremiumState(user_id=user.id, is_premium=False, ai_asks_used=0)
    state.is_premium = True
    state.plan_kind = models.PremiumPlanKind.couple
    state.plan_duration = models.PremiumDuration.month
    state.purchased_at = datetime.now(timezone.utc)
    db_session.add(state)
    db_session.commit()


def _marks(room, kind=None):
    return [m for m in room["marks"] if kind is None or m["kind"] == kind]


def _highlight(client, user, room_id, locator, on=True, **extra):
    return _event(client, user, room_id, kind="highlight", key="on" if on else "off", locator=locator, **extra)


def _album_quote(client, user, room_id, quote):
    return client.post(f"/partner/rooms/{room_id}/album-quote", json={"quote": quote}, headers=user.headers)


class TestLocators:
    def test_an_epub_place_is_canonical(self):
        assert rules.normalize_locator("epub", "c3") == "c3:p0"
        assert rules.normalize_locator("epub", "C03:P007") == "c3:p7"
        assert rules.normalize_locator("epub", " c12:p0 ") == "c12:p0"

    def test_each_kind_only_accepts_its_own_shape(self):
        for kind, bad in (("epub", "p3"), ("cbz", "c3"), ("cbz", "c3:p1"), ("parallel", "c3:p1"), ("parallel", "p2")):
            with pytest.raises(ValueError):
                rules.normalize_locator(kind, bad)
        assert rules.normalize_locator("cbz", "p012") == "p12"
        assert rules.normalize_locator("parallel", "c5") == "c5"

    def test_limits_and_garbage_are_refused(self):
        for kind, bad in (
            ("epub", "c10000"), ("epub", "c1:p100000"), ("cbz", "p100000"),
            ("epub", ""), ("epub", None), ("epub", "c-1"), ("epub", "c1:p"), ("nope", "c1"),
        ):
            with pytest.raises(ValueError):
                rules.normalize_locator(kind, bad)

    def test_places_sort_in_reading_order(self):
        assert rules.locator_key("epub", "c2:p9") < rules.locator_key("epub", "c3:p0")
        assert rules.locator_key("epub", "c3:p1") < rules.locator_key("epub", "c3:p10")
        assert rules.locator_key("cbz", "p4") < rules.locator_key("cbz", "p40")
        assert rules.locator_key("epub", "garbage") < rules.locator_key("epub", "c0:p0")


class TestReadingRules:
    def test_a_file_needs_its_fingerprint_and_a_parallel_room_drops_it(self):
        assert rules.normalize_reading("epub", HASH_A.upper(), 10) == ("epub", HASH_A, 10)
        assert rules.normalize_reading("parallel", HASH_A, None) == ("parallel", None, None)
        for kind in ("epub", "cbz"):
            with pytest.raises(ValueError):
                rules.normalize_reading(kind, None, None)
            with pytest.raises(ValueError):
                rules.normalize_reading(kind, "not-a-hash", None)
        with pytest.raises(ValueError):
            rules.normalize_reading("pdf", HASH_A, None)

    def test_the_length_must_be_sane(self):
        for bad in (0, -3, rules.MAX_UNITS + 1):
            with pytest.raises(ValueError):
                rules.normalize_reading("cbz", HASH_A, bad)

    def test_progress_is_scaled_so_the_moments_timeline_works(self):
        assert rules.progress_to_ms(0) == 0
        assert rules.progress_to_ms(1000) == rules.READ_DURATION_MS == 1_000_000
        assert rules.progress_to_ms(5000) == rules.READ_DURATION_MS
        assert rules.progress_to_ms(-4) == 0
        assert rules.ms_to_progress(340_000) == 340
        assert rules.ms_to_progress(None) == 0

    def test_an_evening_of_reading_yields_moments_without_code_of_its_own(self):
        """Two people reacting within three per cent of the book is one shared moment."""
        events = [
            {"user_id": "a", "kind": "reaction", "emoji": "😂", "position_ms": rules.progress_to_ms(400)},
            {"user_id": "b", "kind": "reaction", "emoji": "😂", "position_ms": rules.progress_to_ms(410)},
            {"user_id": "a", "kind": "reaction", "emoji": "😭", "position_ms": rules.progress_to_ms(900)},
        ]
        moments = circle_review.build_moments(events)
        shared = [m for m in moments if m["shared"]]
        assert len(moments) == 2 and len(shared) == 1
        assert shared[0]["top"] == "😂" and shared[0]["people"] == 2

    def test_the_same_edition_is_known_only_when_both_sides_are(self):
        assert rules.same_edition(HASH_A, HASH_A) is True
        assert rules.same_edition(HASH_A, HASH_B) is False
        assert rules.same_edition(HASH_A, None) is None
        assert rules.same_edition(None, HASH_A) is None

    def test_a_quote_is_a_line_or_two_never_the_text(self):
        assert rules.clean_quote("  много   пробелов \n тут ") == "много пробелов тут"
        assert rules.clean_quote("   ") is None and rules.clean_quote(None) is None
        long = " ".join(["слово"] * 200)
        cut = rules.clean_quote(long)
        assert len(cut) <= rules.QUOTE_MAX_CHARS and cut.endswith("…")

    def test_the_end_of_the_book(self):
        assert rules.reached_the_end(980) and not rules.reached_the_end(500)


class TestMarksAndQuotes:
    def test_the_modes_and_what_each_kind_allows(self):
        assert rules.normalize_mode("aloud", "epub") == "aloud"
        assert rules.normalize_mode("ALOUD") == "aloud"
        for kind in ("cbz", "parallel"):
            with pytest.raises(ValueError):
                rules.normalize_mode("aloud", kind)
        assert rules.has_shared_place("together") and rules.has_shared_place("aloud")
        assert not rules.has_shared_place("own") and not rules.has_shared_place(None)

    def test_a_highlight_is_on_or_off(self):
        assert rules.normalize_highlight(" ON ") == "on"
        assert rules.normalize_highlight("off") == "off"
        for bad in (None, "", "yes", "toggle"):
            with pytest.raises(ValueError):
                rules.normalize_highlight(bad)

    def test_marks_keep_every_note_and_the_latest_word_on_each_highlight(self):
        ledger = [
            {"seq": 1, "user_id": "a", "kind": "highlight", "emoji": "on", "locator": "c1:p1"},
            {"seq": 2, "user_id": "b", "kind": "highlight", "emoji": "on", "locator": "c1:p1"},
            {"seq": 3, "user_id": "a", "kind": "margin", "body": "вот это да", "quote": "строка", "locator": "c1:p1"},
            {"seq": 4, "user_id": "a", "kind": "highlight", "emoji": "off", "locator": "c1:p1"},
            {"seq": 5, "user_id": "a", "kind": "highlight", "emoji": "on", "locator": "c2:p0"},
            {"seq": 6, "user_id": "a", "kind": "highlight", "emoji": "on", "locator": "c2:p0"},
            {"seq": 7, "user_id": "a", "kind": "reaction", "emoji": "😂", "locator": "c2:p0"},
            {"seq": 8, "user_id": "a", "kind": "margin", "body": "без места", "locator": None},
        ]
        marks = rules.reduce_marks(list(reversed(ledger)))  # any order in
        assert [(m["seq"], m["kind"], m["user_id"]) for m in marks] == [
            (2, "highlight", "b"), (3, "margin", "a"), (6, "highlight", "a"),
        ]
        assert rules.reduce_marks([]) == []

    def test_marks_are_capped_at_the_newest(self):
        ledger = [{"seq": i, "user_id": "a", "kind": "margin", "body": "x", "locator": "c0:p0"} for i in range(1, rules.MARKS_LIMIT + 6)]
        marks = rules.reduce_marks(ledger)
        assert len(marks) == rules.MARKS_LIMIT and marks[-1]["seq"] == rules.MARKS_LIMIT + 5

    def test_an_album_quote_is_short_and_never_cut_mid_sentence_of_the_note(self):
        assert rules.clean_album_quote("  один   два \n три ") == "один два три"
        long = rules.clean_album_quote(" ".join(["слово"] * 100))
        assert len(long) <= rules.ALBUM_QUOTE_MAX_CHARS and long.endswith("…")
        for bad in (None, "", "   "):
            with pytest.raises(ValueError):
                rules.clean_album_quote(bad)

    def test_quotes_pile_up_in_one_note_without_repeating_or_overflowing(self):
        one = rules.add_quote_to_note(None, "первая", max_chars=400)
        assert one == "«первая»"
        two = rules.add_quote_to_note(one, "вторая", max_chars=400)
        assert two == "«первая»\n\n«вторая»"
        assert rules.add_quote_to_note(two, "первая", max_chars=400) == two
        with pytest.raises(ValueError):
            rules.add_quote_to_note(two, "ещё одна", max_chars=len(two) + 3)

    def test_moments_count_notes_and_highlights_and_name_the_place(self):
        events = [
            {"user_id": "a", "kind": "highlight", "emoji": "on", "position_ms": rules.progress_to_ms(400), "locator": "c3:p4"},
            {"user_id": "b", "kind": "margin", "emoji": None, "position_ms": rules.progress_to_ms(410), "locator": "c3:p9"},
            {"user_id": "a", "kind": "highlight", "emoji": "off", "position_ms": rules.progress_to_ms(700), "locator": "c6:p1"},
            {"user_id": "a", "kind": "margin", "emoji": None, "position_ms": None, "locator": "c7:p1"},
        ]
        moments = circle_review.build_moments(events)
        assert len(moments) == 1  # the "off" and the placeless note are not moments
        m = moments[0]
        assert m["shared"] and m["people"] == 2 and m["count"] == 2
        assert m["keys"] == {circle_review.HIGHLIGHT_KEY: 1, circle_review.MARGIN_KEY: 1}
        assert m["locator"] == "c3:p4"

    def test_a_film_moment_carries_no_place(self):
        m = circle_review.build_moments([{"user_id": "a", "kind": "reaction", "emoji": "😂", "position_ms": 5_000}])[0]
        assert "locator" not in m


class TestCreate:
    def test_a_reading_room_is_a_room_with_no_player(self, client, pair):
        a, _ = pair
        r = _create(client, a)
        assert r.status_code == 201, r.text
        room = r.json()
        assert room["activity"] == "read" and room["read_kind"] == "epub"
        assert room["player_kind"] == "parallel" and room["player_ref"] is None
        assert room["duration_ms"] == rules.READ_DURATION_MS
        assert room["content_hash"] == HASH_A and room["read_units"] == 32
        assert room["read_mode"] == "own" and room["lead_locator"] is None
        # the host's own file is, by definition, the room's edition
        assert _person(room, a)["same_edition"] is True

    def test_a_film_room_is_still_a_film_room(self, client, pair):
        a, _ = pair
        r = client.post("/partner/rooms", json={
            "media_id": "dQw4w9WgXcQ", "media_type": "video", "source": "youtube",
            "title_ru": "Ролик", "player_kind": "youtube", "player_ref": "https://youtu.be/dQw4w9WgXcQ",
            "duration_ms": 600_000,
        }, headers=a.headers)
        assert r.status_code == 201
        room = r.json()
        assert room["activity"] == "watch" and room["read_kind"] is None and room["read_mode"] == "own"

    def test_only_books_and_manga_can_be_read(self, client, pair):
        a, _ = pair
        assert _create(client, a, media_type="movie").status_code == 400
        assert _create(client, a, media_type="video").status_code == 400

    def test_a_file_room_needs_a_fingerprint_but_a_parallel_room_does_not(self, client, pair):
        a, _ = pair
        assert _create(client, a, content_hash=None).status_code == 400
        assert _create(client, a, content_hash="nope").status_code == 400
        assert _create(client, a, read_kind="pdf").status_code == 400
        assert _create(client, a, read_units=0).status_code == 422
        ok = _create(client, a, media_type="manga", read_kind="parallel", content_hash=None, read_units=None)
        assert ok.status_code == 201, ok.text
        assert ok.json()["content_hash"] is None

    def test_together_mode_can_be_chosen_up_front(self, client, pair):
        a, _ = pair
        # (checked first: an open room answers any further "create" with itself)
        assert _create(client, a, read_mode="sideways").status_code == 400
        room = _create(client, a, media_type="manga", read_kind="cbz", read_mode="together").json()
        assert room["read_mode"] == "together" and room["lead_locator"] == "p0" and room["lead_user_id"] == a.id

    def test_a_film_clock_does_not_apply_to_reading(self, client, pair):
        a, _ = pair
        room = _create(client, a).json()
        for action in ("play", "pause", "seek"):
            r = client.post(f"/partner/rooms/{room['id']}/control", json={"action": action, "position_ms": 5}, headers=a.headers)
            assert r.status_code == 409


class TestWhereYouAre:
    def test_the_first_page_turned_starts_the_evening(self, client, pair):
        a, _ = pair
        room = _create(client, a).json()
        assert room["status"] == "lobby" and room["started_at"] is None
        r = _here(client, a, room["id"], "c2", 125)
        assert r.status_code == 200, r.text
        out = r.json()
        assert out["status"] == "live" and out["started_at"] is not None
        me = _person(out, a)
        assert me["locator"] == "c2:p0" and me["progress"] == 125

    def test_the_other_person_sees_where_you_are(self, client, pair):
        a, b = pair
        room = _create(client, a).json()
        _join(client, b, room["id"])
        _here(client, a, room["id"], "c4:p17", 310)
        seen = client.get(f"/partner/rooms/{room['id']}", headers=b.headers).json()
        assert _person(seen, a)["locator"] == "c4:p17" and _person(seen, a)["progress"] == 310
        assert _person(seen, b)["locator"] is None

    def test_a_place_that_does_not_fit_the_kind_is_refused(self, client, pair):
        a, _ = pair
        room = _create(client, a).json()
        assert _here(client, a, room["id"], "p3", 10).status_code == 400
        assert _here(client, a, room["id"], "c1:p1", 10, content_hash="nope").status_code == 400
        assert _here(client, a, room["id"], "c1:p1", 5000).status_code == 422

    def test_a_film_room_has_no_places(self, client, pair):
        a, _ = pair
        film = client.post("/partner/rooms", json={
            "media_id": "m1", "media_type": "movie", "source": "tmdb", "title_ru": "Фильм",
        }, headers=a.headers).json()
        assert _here(client, a, film["id"], "c1", 10).status_code == 409

    def test_two_devices_tell_whether_they_hold_the_same_edition(self, client, pair):
        a, b = pair
        room = _create(client, a).json()
        _join(client, b, room["id"])
        same = _here(client, b, room["id"], "c0:p0", 0, content_hash=HASH_A).json()
        assert _person(same, b)["same_edition"] is True
        other = _here(client, b, room["id"], "c0:p0", 0, content_hash=HASH_B).json()
        assert _person(other, b)["same_edition"] is False
        # the host's own file is the room's edition, whatever the guest holds
        assert _person(other, a)["same_edition"] is True

    def test_someone_who_has_not_entered_cannot_report(self, client, pair):
        a, b = pair
        room = _create(client, a).json()
        r = _here(client, b, room["id"], "c1", 10)
        assert r.status_code == 409

    def test_an_outsider_learns_nothing(self, client, pair, register_user):
        a, _ = pair
        stranger = register_user()
        room = _create(client, a).json()
        assert _here(client, stranger, room["id"], "c1", 10).status_code == 404


class TestReadingTogether:
    def test_the_shared_place_exists_only_in_together_mode(self, client, pair):
        a, b = pair
        room = _create(client, a).json()
        _join(client, b, room["id"])
        r = client.post(f"/partner/rooms/{room['id']}/lead", json={"locator": "c1", "progress": 10}, headers=a.headers)
        assert r.status_code == 409

    def test_switching_on_together_starts_from_where_you_are(self, client, pair):
        a, b = pair
        room = _create(client, a).json()
        _join(client, b, room["id"])
        _here(client, a, room["id"], "c5:p3", 200)
        before = client.get(f"/partner/rooms/{room['id']}", headers=a.headers).json()["control_seq"]
        out = _patch(client, a, room["id"], read_mode="together").json()
        assert out["read_mode"] == "together"
        assert out["lead_locator"] == "c5:p3" and out["lead_user_id"] == a.id
        assert out["position_ms"] == rules.progress_to_ms(200)
        assert out["control_seq"] == before + 1
        assert any(e["kind"] == "system" and e["body"] == "read_together" for e in out["events"])

    def test_anyone_in_the_circle_turns_the_page_for_everybody(self, client, pair):
        a, b = pair
        room = _create(client, a, read_mode="together").json()
        _join(client, b, room["id"])
        r = client.post(f"/partner/rooms/{room['id']}/lead", json={"locator": "c2:p8", "progress": 90}, headers=b.headers)
        assert r.status_code == 200, r.text
        out = r.json()
        assert out["lead_locator"] == "c2:p8" and out["lead_user_id"] == b.id
        assert out["position_ms"] == 90_000
        assert _person(out, b)["locator"] == "c2:p8"
        seen = client.get(f"/partner/rooms/{room['id']}", headers=a.headers).json()
        assert seen["lead_locator"] == "c2:p8"

    def test_turning_to_the_same_page_again_is_quiet(self, client, pair):
        a, b = pair
        room = _create(client, a, read_mode="together").json()
        _join(client, b, room["id"])
        body = {"locator": "c1:p4", "progress": 40}
        first = client.post(f"/partner/rooms/{room['id']}/lead", json=body, headers=a.headers).json()
        again = client.post(f"/partner/rooms/{room['id']}/lead", json=body, headers=b.headers).json()
        assert again["control_seq"] == first["control_seq"]

    def test_a_bad_place_is_refused(self, client, pair):
        a, _ = pair
        room = _create(client, a, read_mode="together").json()
        r = client.post(f"/partner/rooms/{room['id']}/lead", json={"locator": "p9", "progress": 1}, headers=a.headers)
        assert r.status_code == 400

    def test_going_back_to_your_own_pace(self, client, pair):
        a, b = pair
        room = _create(client, a, read_mode="together").json()
        _join(client, b, room["id"])
        out = _patch(client, b, room["id"], read_mode="own").json()
        assert out["read_mode"] == "own"
        assert any(e["body"] == "read_own" for e in out["events"] if e["kind"] == "system")
        assert _patch(client, a, room["id"], read_mode="sideways").status_code == 400


class TestMarginNotes:
    def test_a_note_is_pinned_to_a_place_and_to_a_moment_of_the_book(self, client, pair):
        a, b = pair
        room = _create(client, a).json()
        _join(client, b, room["id"])
        _here(client, a, room["id"], "c3:p10", 300)
        r = _event(
            client, a, room["id"], kind="margin", body="ого, вот это поворот",
            locator="c3:p12", quote="  Никогда   не разговаривайте с неизвестными  ", progress=312,
        )
        assert r.status_code == 200, r.text
        note = [e for e in r.json()["events"] if e["kind"] == "margin"][-1]
        assert note["body"] == "ого, вот это поворот"
        assert note["locator"] == "c3:p12"
        assert note["quote"] == "Никогда не разговаривайте с неизвестными"
        assert note["position_ms"] == rules.progress_to_ms(312)

    def test_a_note_needs_text_and_a_place(self, client, pair):
        a, _ = pair
        room = _create(client, a).json()
        assert _event(client, a, room["id"], kind="margin", locator="c1:p1").status_code == 400
        assert _event(client, a, room["id"], kind="margin", body="тут").status_code == 400
        assert _event(client, a, room["id"], kind="margin", body="тут", locator="p3").status_code == 400
        assert _event(client, a, room["id"], kind="margin", body="x" * 401, locator="c1").status_code == 400

    def test_notes_exist_only_when_reading(self, client, pair):
        a, _ = pair
        film = client.post("/partner/rooms", json={
            "media_id": "m1", "media_type": "movie", "source": "tmdb", "title_ru": "Фильм",
        }, headers=a.headers).json()
        assert _event(client, a, film["id"], kind="margin", body="тут", locator="c1").status_code == 400

    def test_a_reaction_can_be_pinned_to_a_place(self, client, pair):
        a, _ = pair
        room = _create(client, a).json()
        _here(client, a, room["id"], "c1:p1", 50)
        out = _event(client, a, room["id"], kind="reaction", key="😂", locator="c1:p9", progress=70).json()
        e = [x for x in out["events"] if x["kind"] == "reaction"][-1]
        assert e["locator"] == "c1:p9" and e["position_ms"] == rules.progress_to_ms(70) and e["quote"] is None

    def test_without_a_stated_place_a_reaction_lands_where_you_are(self, client, pair):
        a, _ = pair
        room = _create(client, a).json()
        _here(client, a, room["id"], "c2:p2", 222)
        out = _event(client, a, room["id"], kind="reaction", key="❤️").json()
        e = [x for x in out["events"] if x["kind"] == "reaction"][-1]
        assert e["position_ms"] == rules.progress_to_ms(222)

    def test_feelings_are_zen_and_zen_is_premium_in_a_book_too(self, client, pair, db_session):
        a, b = pair
        room = _create(client, a).json()
        _join(client, b, room["id"])
        _here(client, a, room["id"], "c4:p2", 410)
        assert _event(client, a, room["id"], kind="emotion", key="touching").status_code == 402
        _buy(db_session, b)  # one subscription opens it for the whole circle
        out = _event(client, a, room["id"], kind="emotion", key="touching")
        assert out.status_code == 200, out.text
        e = [x for x in out.json()["events"] if x["kind"] == "emotion"][-1]
        # a feeling is about where you are
        assert e["locator"] == "c4:p2" and e["position_ms"] == rules.progress_to_ms(410)
        assert _event(client, a, room["id"], kind="emotion", key="nonsense").status_code == 400

    def test_chat_and_signals_work_as_in_any_room(self, client, pair):
        a, b = pair
        room = _create(client, a).json()
        _join(client, b, room["id"])
        assert _event(client, a, room["id"], kind="chat", body="читаешь?").status_code == 200
        assert _event(client, b, room["id"], kind="signal", key="hold").status_code == 200


class TestFinishing:
    def test_finishing_saves_the_evening_like_a_film_does(self, client, pair, db_session):
        a, b = pair
        room = _create(client, a).json()
        _join(client, b, room["id"])
        _here(client, a, room["id"], "c30:p5", 940)
        _here(client, b, room["id"], "c31:p1", 985)
        out = client.post(f"/partner/rooms/{room['id']}/finish", json={}, headers=a.headers)
        assert out.status_code == 200, out.text
        done = out.json()
        assert done["status"] == "ended" and done["saved_entry_id"] is not None
        finished = [e for e in done["events"] if e["kind"] == "system" and e["body"] == "finished"][-1]
        # nobody said where the book ended: the furthest anyone got
        assert finished["position_ms"] == rules.progress_to_ms(985)
        entry = db_session.get(models.CoViewEntry, done["saved_entry_id"])
        assert entry is not None and entry.media_type == models.MediaType.book
        assert entry.status == models.CoViewStatus.watched

    def test_the_save_switch_still_decides(self, client, pair):
        a, _ = pair
        room = _create(client, a, save_to_shared=False).json()
        _here(client, a, room["id"], "c1", 100)
        done = client.post(f"/partner/rooms/{room['id']}/finish", json={}, headers=a.headers).json()
        assert done["status"] == "ended" and done["saved_entry_id"] is None

    def test_a_book_nobody_opened_cannot_be_finished(self, client, pair):
        a, _ = pair
        room = _create(client, a).json()
        assert client.post(f"/partner/rooms/{room['id']}/finish", json={}, headers=a.headers).status_code == 409

    def test_a_finished_room_takes_no_more_places(self, client, pair):
        a, _ = pair
        room = _create(client, a).json()
        _here(client, a, room["id"], "c1", 100)
        client.post(f"/partner/rooms/{room['id']}/finish", json={}, headers=a.headers)
        assert _here(client, a, room["id"], "c2", 200).status_code == 409

    def test_the_manga_flavour_works_the_same(self, client, pair):
        a, b = pair
        room = _create(
            client, a, media_type="manga", read_kind="cbz", media_id="file:cbz1", read_units=180,
        ).json()
        _join(client, b, room["id"])
        out = _here(client, b, room["id"], "p42", 233).json()
        assert _person(out, b)["locator"] == "p42"
        assert _here(client, b, room["id"], "c4", 233).status_code == 400


class TestReadingAloud:
    def test_a_book_can_be_read_aloud_a_comic_cannot(self, client, pair):
        a, _ = pair
        assert _create(client, a, media_type="manga", read_kind="cbz", read_mode="aloud").status_code == 400
        assert _create(client, a, read_kind="parallel", content_hash=None, read_mode="aloud").status_code == 400
        room = _create(client, a, read_mode="aloud").json()
        assert room["read_mode"] == "aloud" and room["lead_user_id"] == a.id and room["lead_locator"] == "c0:p0"

    def test_switching_on_aloud_makes_you_the_reader_from_where_you_are(self, client, pair):
        a, b = pair
        room = _create(client, a).json()
        _join(client, b, room["id"])
        _here(client, b, room["id"], "c2:p6", 150)
        out = _patch(client, b, room["id"], read_mode="aloud").json()
        assert out["read_mode"] == "aloud" and out["lead_user_id"] == b.id
        assert out["lead_locator"] == "c2:p6" and out["position_ms"] == rules.progress_to_ms(150)
        assert any(e["kind"] == "system" and e["body"] == "read_aloud" for e in out["events"])

    def test_only_the_reader_moves_the_line(self, client, pair):
        a, b = pair
        room = _create(client, a, read_mode="aloud").json()
        _join(client, b, room["id"])
        r = client.post(f"/partner/rooms/{room['id']}/lead", json={"locator": "c0:p3", "progress": 5}, headers=b.headers)
        assert r.status_code == 409 and "читает вслух" in r.json()["detail"]
        ok = client.post(f"/partner/rooms/{room['id']}/lead", json={"locator": "c0:p3", "progress": 5}, headers=a.headers)
        assert ok.status_code == 200 and ok.json()["lead_locator"] == "c0:p3"

    def test_taking_over_carries_on_from_the_last_line_read(self, client, pair):
        a, b = pair
        room = _create(client, a, read_mode="aloud").json()
        _join(client, b, room["id"])
        _here(client, b, room["id"], "c9:p9", 900)  # b is far ahead on their own
        client.post(f"/partner/rooms/{room['id']}/lead", json={"locator": "c1:p4", "progress": 70}, headers=a.headers)
        out = _patch(client, b, room["id"], read_mode="aloud").json()
        assert out["lead_user_id"] == b.id
        assert out["lead_locator"] == "c1:p4" and out["position_ms"] == rules.progress_to_ms(70)
        # a is no longer the reader
        again = client.post(f"/partner/rooms/{room['id']}/lead", json={"locator": "c1:p5", "progress": 71}, headers=a.headers)
        assert again.status_code == 409

    def test_asking_again_as_the_reader_changes_nothing(self, client, pair):
        a, _ = pair
        room = _create(client, a, read_mode="aloud").json()
        seq = room["control_seq"]
        out = _patch(client, a, room["id"], read_mode="aloud").json()
        assert out["control_seq"] == seq and out["lead_user_id"] == a.id

    def test_a_comic_room_refuses_aloud_when_switching(self, client, pair):
        a, _ = pair
        room = _create(client, a, media_type="manga", read_kind="cbz", media_id="file:cbz2").json()
        assert _patch(client, a, room["id"], read_mode="aloud").status_code == 400

    def test_leaving_aloud_for_another_mode(self, client, pair):
        a, b = pair
        room = _create(client, a, read_mode="aloud").json()
        _join(client, b, room["id"])
        out = _patch(client, b, room["id"], read_mode="own").json()
        assert out["read_mode"] == "own"


class TestHighlights:
    def test_a_highlight_shows_in_the_rooms_marks_for_everyone(self, client, pair):
        a, b = pair
        room = _create(client, a).json()
        _join(client, b, room["id"])
        out = _highlight(client, a, room["id"], "c2:p5", quote="  Рукописи   не горят ", progress=200)
        assert out.status_code == 200, out.text
        marks = _marks(client.get(f"/partner/rooms/{room['id']}", headers=b.headers).json(), "highlight")
        assert [(m["user_id"], m["locator"]) for m in marks] == [(a.id, "c2:p5")]
        assert marks[0]["quote"] == "Рукописи не горят"

    def test_switching_it_off_takes_it_off_the_page(self, client, pair):
        a, _ = pair
        room = _create(client, a).json()
        _highlight(client, a, room["id"], "c0:p1")
        out = _highlight(client, a, room["id"], "c0:p1", on=False).json()
        assert _marks(out, "highlight") == []

    def test_each_person_has_their_own_highlight_on_a_paragraph(self, client, pair):
        a, b = pair
        room = _create(client, a).json()
        _join(client, b, room["id"])
        _highlight(client, a, room["id"], "c1:p1")
        out = _highlight(client, b, room["id"], "c1:p1").json()
        assert sorted(m["user_id"] for m in _marks(out, "highlight")) == sorted([a.id, b.id])
        out = _highlight(client, a, room["id"], "c1:p1", on=False).json()
        assert [m["user_id"] for m in _marks(out, "highlight")] == [b.id]

    def test_marks_survive_the_events_tail(self, client, pair, db_session):
        """The state push carries only the last few events; the margins of a book read over days must not depend on them."""
        a, _ = pair
        room = _create(client, a).json()
        _event(client, a, room["id"], kind="margin", body="самая первая заметка", locator="c1:p1")
        _highlight(client, a, room["id"], "c1:p2")
        row = db_session.get(models.CoViewRoom, room["id"])
        seq = row.event_seq
        for i in range(room_rules.EVENT_TAIL + 10):  # a long evening of chat, written straight into the ledger
            seq += 1
            db_session.add(models.CoViewRoomEvent(room_id=row.id, seq=seq, user_id=a.id, kind="chat", body=f"сообщение {i}"))
        row.event_seq = seq
        db_session.commit()
        out = client.get(f"/partner/rooms/{room['id']}", headers=a.headers).json()
        assert not any(e["kind"] in ("margin", "highlight") for e in out["events"])  # long gone from the tail…
        assert [m["body"] for m in _marks(out, "margin")] == ["самая первая заметка"]  # …but still on the page
        assert [m["locator"] for m in _marks(out, "highlight")] == ["c1:p2"]

    def test_a_highlight_needs_a_valid_place_and_state(self, client, pair):
        a, _ = pair
        room = _create(client, a).json()
        assert _event(client, a, room["id"], kind="highlight", key="on").status_code == 400
        assert _event(client, a, room["id"], kind="highlight", key="maybe", locator="c1:p1").status_code == 400
        assert _highlight(client, a, room["id"], "p4").status_code == 400
        film = client.post("/partner/rooms", json={
            "media_id": "m9", "media_type": "movie", "source": "tmdb", "title_ru": "Фильм",
        }, headers=a.headers).json()
        assert _highlight(client, a, film["id"], "c1").status_code == 400

    def test_a_film_room_has_no_marks(self, client, pair):
        a, _ = pair
        film = client.post("/partner/rooms", json={
            "media_id": "m8", "media_type": "movie", "source": "tmdb", "title_ru": "Фильм",
        }, headers=a.headers).json()
        assert film["marks"] == []


class TestAlbumQuotes:
    def test_a_quote_becomes_my_sealed_note_and_opens_when_you_finish(self, client, pair):
        a, b = pair
        room = _create(client, a).json()
        _join(client, b, room["id"])
        _here(client, a, room["id"], "c1", 100)
        r = _album_quote(client, a, room["id"], "  Рукописи   не горят.  ")
        assert r.status_code == 200, r.text
        assert r.json()["created"] is True and r.json()["added"] is True
        # sealed: the partner sees only that a note exists
        waiting = client.get("/partner/album/notes/waiting", headers=a.headers).json()
        assert len(waiting) == 1 and waiting[0]["mine"]["body"] == "«Рукописи не горят.»"
        # finishing the evening opens it for both
        _here(client, b, room["id"], "c2", 300)
        done = client.post(f"/partner/rooms/{room['id']}/finish", json={}, headers=a.headers)
        assert done.status_code == 200, done.text
        assert done.json()["album_reveal_count"] == 1

    def test_more_quotes_go_into_the_same_note_and_repeats_do_not(self, client, pair):
        a, _ = pair
        room = _create(client, a).json()
        one = _album_quote(client, a, room["id"], "первая")
        two = _album_quote(client, a, room["id"], "вторая")
        again = _album_quote(client, a, room["id"], "первая")
        assert (one.json()["created"], two.json()["created"], again.json()["created"]) == (True, False, False)
        assert again.json()["added"] is False
        note = client.get("/partner/album/notes/waiting", headers=a.headers).json()[0]["mine"]
        assert note["body"] == "«первая»\n\n«вторая»"
        assert two.json()["chars_left"] == pair_album.NOTE_MAX_CHARS - len("«первая»\n\n«вторая»")

    def test_a_full_note_refuses_rather_than_cuts(self, client, pair):
        a, _ = pair
        room = _create(client, a).json()
        for i in range(3):
            assert _album_quote(client, a, room["id"], f"цитата номер {i} " + "я" * 130).status_code == 200
        full = _album_quote(client, a, room["id"], "ещё одна цитата, которая уже не поместится " + "ю" * 100)
        assert full.status_code == 409
        note = client.get("/partner/album/notes/waiting", headers=a.headers).json()[0]["mine"]
        assert note["body"].count("«") == 3

    def test_only_a_couple_has_an_album(self, client, register_user):
        a, b, c = register_user(), register_user(), register_user()
        _link(client, a, b)
        code = client.post("/partner/invite", json={"user_id": c.id}, headers=a.headers)
        if code.status_code == 201:
            inv = client.get("/partner/invites", headers=c.headers).json()["incoming"][0]["id"]
            client.post(f"/partner/invites/{inv}/accept", headers=c.headers)
            room = _create(client, a).json()
            assert _album_quote(client, a, room["id"], "цитата").status_code == 409

    def test_needs_text_a_reading_room_and_a_seat_in_it(self, client, pair, register_user):
        a, b = pair
        room = _create(client, a).json()
        assert _album_quote(client, a, room["id"], "   ").status_code == 400
        assert _album_quote(client, b, room["id"], "я ещё не заходил").status_code == 409
        stranger = register_user()
        assert _album_quote(client, stranger, room["id"], "цитата").status_code == 404
        film = client.post("/partner/rooms", json={
            "media_id": "m7", "media_type": "movie", "source": "tmdb", "title_ru": "Фильм",
        }, headers=a.headers).json()
        assert _album_quote(client, a, film["id"], "цитата").status_code == 409

    def test_the_free_allowance_of_notes_is_the_albums_own(self, client, pair, db_session):
        a, _ = pair
        for i in range(pair_album.FREE_NOTES_PER_AUTHOR):
            r = client.put("/partner/album/notes", json={
                "item": {"id": f"t{i}", "media_type": "movie", "source": "tmdb", "title": {"ru": f"Фильм {i}"}, "description": {}},
                "body": "записка",
            }, headers=a.headers)
            assert r.status_code == 200, r.text
        room = _create(client, a).json()
        assert _album_quote(client, a, room["id"], "цитата").status_code == 402
        _buy(db_session, a)
        assert _album_quote(client, a, room["id"], "цитата").status_code == 200

    def test_a_finished_room_takes_no_more_quotes(self, client, pair):
        a, _ = pair
        room = _create(client, a).json()
        _here(client, a, room["id"], "c1", 100)
        client.post(f"/partner/rooms/{room['id']}/finish", json={}, headers=a.headers)
        assert _album_quote(client, a, room["id"], "поздно").status_code == 409


class TestMomentsOfABook:
    def test_notes_and_highlights_make_the_timeline_and_name_the_chapter(self, client, pair, db_session):
        a, b = pair
        _buy(db_session, a)  # the timeline is the one premium part of a review
        room = _create(client, a).json()
        _join(client, b, room["id"])
        _here(client, a, room["id"], "c3:p4", 400)
        _highlight(client, a, room["id"], "c3:p4", progress=400, quote="строчка")
        _event(client, b, room["id"], kind="margin", body="и мне тут понравилось", locator="c3:p6", progress=410)
        _here(client, b, room["id"], "c4", 900)
        done = client.post(f"/partner/rooms/{room['id']}/finish", json={}, headers=a.headers)
        assert done.status_code == 200, done.text
        rid = done.json()["review_id"]
        assert rid
        for who, rating in ((a, 9), (b, 8)):
            r = client.put(f"/partner/reviews/{rid}/mine", json={"rating": rating}, headers=who.headers)
            assert r.status_code == 200, r.text
        got = client.get(f"/partner/reviews/{rid}", headers=a.headers).json()
        assert got["moments_locked"] is False and got["moments"]
        m = got["moments"][0]
        assert m["shared"] is True and m["people"] == 2 and m["count"] == 2
        assert m["locator"] == "c3:p4"
