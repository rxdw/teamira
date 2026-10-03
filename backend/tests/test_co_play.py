"""Playing together: a real game, each on their own machine
(routers/co_view_room.py, app/co_play.py).

What is worth pinning down is what the feature promises: the room carries
nothing of the game (only an evening around it), the room's clock is the
session timer and can't be jumped around, a game speaks its own signals, rounds
are one tap each and make the tally and the review's moments, and the ready
check is a courtesy rather than a gate.
"""

import pytest

from app import circle_review
from app import co_play as rules
from app import models

STEAM = {"media_id": "1942", "media_type": "game", "source": "igdb", "title_ru": "It Takes Two", "title_en": "It Takes Two"}


def _link(client, a, b):
    code = client.post("/partner/pair", headers=a.headers).json()["pending_code"]
    assert client.post("/partner/join", json={"code": code}, headers=b.headers).status_code == 200


@pytest.fixture
def pair(client, register_user):
    a, b = register_user(), register_user()
    _link(client, a, b)
    return a, b


def _create(client, user, **over):
    body = {**STEAM, "activity": "play", "platform": "pc"}
    body.update(over)
    return client.post("/partner/rooms", json=body, headers=user.headers)


def _join(client, user, room_id):
    r = client.post(f"/partner/rooms/{room_id}/join", headers=user.headers)
    assert r.status_code == 200, r.text
    return r.json()


def _control(client, user, room_id, action, **extra):
    return client.post(f"/partner/rooms/{room_id}/control", json={"action": action, **extra}, headers=user.headers)


def _event(client, user, room_id, **body):
    return client.post(f"/partner/rooms/{room_id}/events", json=body, headers=user.headers)


def _round(client, user, room_id, key):
    return _event(client, user, room_id, kind="round", key=key)


def _ready(client, user, room_id, ready=True):
    return client.post(f"/partner/rooms/{room_id}/ready", json={"ready": ready}, headers=user.headers)


def _person(room, user):
    return next(p for p in room["participants"] if p["user_id"] == user.id)


class TestRules:
    def test_platforms_are_an_allow_list_and_none_is_fine(self):
        assert rules.normalize_platform(" PS ") == "ps"
        assert rules.normalize_platform("switch") == "switch"
        assert rules.normalize_platform(None) is None and rules.normalize_platform("  ") is None
        with pytest.raises(ValueError):
            rules.normalize_platform("amiga")

    def test_a_game_speaks_its_own_signals(self):
        film = ("pause", "rewind", "pulse", "hold")
        assert rules.signal_keys("play", film) == rules.GAME_SIGNAL_KEYS
        assert rules.signal_keys("watch", film) == film
        assert rules.signal_keys("read", film) == film
        assert not set(rules.GAME_SIGNAL_KEYS) & set(film)

    def test_the_tally_always_has_every_key_and_ignores_the_rest(self):
        assert rules.tally([]) == {"win": 0, "loss": 0, "draw": 0, "checkpoint": 0}
        got = rules.tally(["win", "win", "loss", None, "nonsense", "checkpoint"])
        assert got == {"win": 2, "loss": 1, "draw": 0, "checkpoint": 1}

    def test_everyone_ready_needs_somebody_and_all_of_them(self):
        assert rules.everyone_ready([True, True]) is True
        assert rules.everyone_ready([True, False]) is False
        assert rules.everyone_ready([]) is False

    def test_every_round_counts_as_a_moment(self):
        assert set(rules.ROUND_MOMENT_KEYS) == set(rules.ROUND_KEYS)

    def test_moments_count_rounds_and_a_film_still_counts_what_it_did(self):
        events = [
            {"user_id": "a", "kind": "round", "emoji": "win", "position_ms": 10 * 60_000},
            {"user_id": "b", "kind": "reaction", "emoji": "😂", "position_ms": 10 * 60_000 + 5_000},
            {"user_id": "a", "kind": "round", "emoji": "nonsense", "position_ms": 50 * 60_000},
        ]
        moments = circle_review.build_moments(events)
        assert len(moments) == 1  # an unknown round isn't a moment
        m = moments[0]
        assert m["shared"] and m["people"] == 2 and m["count"] == 2
        assert m["keys"] == {"🏆": 1, "😂": 1}


class TestCreate:
    def test_a_game_room_is_a_room_with_a_clock_and_no_end(self, client, pair):
        a, _ = pair
        r = _create(client, a)
        assert r.status_code == 201, r.text
        room = r.json()
        assert room["activity"] == "play" and room["media_type"] == "game"
        assert room["player_kind"] == "parallel" and room["player_ref"] == "pc"
        assert room["duration_ms"] is None
        assert room["rounds"] == {"win": 0, "loss": 0, "draw": 0, "checkpoint": 0}
        assert room["all_ready"] is False and room["status"] == "lobby"

    def test_only_a_game_can_be_played(self, client, pair):
        a, _ = pair
        for kind in ("movie", "book", "anime"):
            assert _create(client, a, media_type=kind).status_code == 400

    def test_the_platform_is_optional_but_must_be_a_known_one(self, client, pair):
        a, _ = pair
        assert _create(client, a, platform="amiga").status_code == 400
        ok = _create(client, a, platform=None)
        assert ok.status_code == 201 and ok.json()["player_ref"] is None

    def test_an_unknown_kind_of_room_is_refused(self, client, pair):
        a, _ = pair
        assert _create(client, a, activity="dance").status_code == 400

    def test_the_other_kinds_of_room_are_untouched(self, client, pair):
        a, _ = pair
        film = client.post("/partner/rooms", json={
            "media_id": "m1", "media_type": "movie", "source": "tmdb", "title_ru": "Фильм",
        }, headers=a.headers)
        assert film.status_code == 201
        room = film.json()
        assert room["activity"] == "watch" and room["rounds"] == {} and room["all_ready"] is False

    def test_the_circle_hears_about_a_game(self, client, pair, monkeypatch):
        from app import push
        sent = []
        monkeypatch.setattr(push, "notify_room_invite", lambda *args, **kw: sent.append(args))
        a, b = pair
        _create(client, a)
        assert sent and sent[0][-1] == "play" and sent[0][2] == "It Takes Two"


class TestTheSessionClock:
    def test_the_first_play_opens_the_evening_and_pause_is_a_break(self, client, pair):
        a, b = pair
        room = _create(client, a).json()
        _join(client, b, room["id"])
        on = _control(client, b, room["id"], "play").json()
        assert on["status"] == "live" and on["is_playing"] is True and on["started_at"]
        off = _control(client, a, room["id"], "pause").json()
        assert off["is_playing"] is False and off["status"] == "live"

    def test_the_session_cannot_be_jumped_around(self, client, pair):
        a, _ = pair
        room = _create(client, a).json()
        r = _control(client, a, room["id"], "seek", position_ms=60_000)
        assert r.status_code == 409

    def test_a_film_can_still_be_sought(self, client, pair):
        a, _ = pair
        film = client.post("/partner/rooms", json={
            "media_id": "m2", "media_type": "movie", "source": "tmdb", "title_ru": "Фильм",
            "duration_ms": 600_000,
        }, headers=a.headers).json()
        assert _control(client, a, film["id"], "seek", position_ms=60_000).status_code == 200

    def test_the_last_person_to_leave_stops_the_clock(self, client, pair):
        a, b = pair
        room = _create(client, a).json()
        _join(client, b, room["id"])
        _control(client, a, room["id"], "play")
        client.post(f"/partner/rooms/{room['id']}/leave", headers=a.headers)
        still = client.get(f"/partner/rooms/{room['id']}", headers=b.headers).json()
        assert still["is_playing"] is True
        client.post(f"/partner/rooms/{room['id']}/leave", headers=b.headers)
        gone = client.get(f"/partner/rooms/{room['id']}", headers=a.headers).json()
        assert gone["is_playing"] is False


class TestReadyCheck:
    def test_ready_shows_for_everyone_and_all_ready_needs_everyone_here(self, client, pair):
        a, b = pair
        room = _create(client, a).json()
        _join(client, b, room["id"])
        one = _ready(client, a, room["id"]).json()
        assert _person(one, a)["ready"] is True and _person(one, b)["ready"] is False
        assert one["all_ready"] is False
        both = _ready(client, b, room["id"]).json()
        assert both["all_ready"] is True
        undone = _ready(client, a, room["id"], ready=False).json()
        assert _person(undone, a)["ready"] is False and undone["all_ready"] is False

    def test_a_person_who_leaves_takes_their_tick_with_them(self, client, pair):
        a, b = pair
        room = _create(client, a).json()
        _join(client, b, room["id"])
        _ready(client, b, room["id"])
        client.post(f"/partner/rooms/{room['id']}/leave", headers=b.headers)
        out = client.get(f"/partner/rooms/{room['id']}", headers=a.headers).json()
        assert _person(out, b)["ready"] is False
        back = _join(client, b, room["id"])
        assert _person(back, b)["ready"] is False

    def test_it_is_a_courtesy_not_a_gate(self, client, pair):
        a, b = pair
        room = _create(client, a).json()
        _join(client, b, room["id"])
        assert _control(client, a, room["id"], "play").status_code == 200

    def test_only_game_rooms_have_it_and_only_people_in_the_room(self, client, pair, register_user):
        a, b = pair
        room = _create(client, a).json()
        assert _ready(client, b, room["id"]).status_code == 409  # b hasn't come in
        assert _ready(client, register_user(), room["id"]).status_code == 404
        film = client.post("/partner/rooms", json={
            "media_id": "m3", "media_type": "movie", "source": "tmdb", "title_ru": "Фильм",
        }, headers=a.headers).json()
        assert _ready(client, a, film["id"]).status_code == 409

    def test_a_finished_game_takes_no_more_ticks(self, client, pair):
        a, _ = pair
        room = _create(client, a).json()
        _control(client, a, room["id"], "play")
        client.post(f"/partner/rooms/{room['id']}/finish", json={}, headers=a.headers)
        assert _ready(client, a, room["id"]).status_code == 409


class TestSignalsAndRounds:
    def test_a_game_speaks_game_signals_and_not_a_films(self, client, pair):
        a, b = pair
        room = _create(client, a).json()
        _join(client, b, room["id"])
        for key in rules.GAME_SIGNAL_KEYS:
            assert _event(client, b, room["id"], kind="signal", key=key).status_code == 200, key
        r = _event(client, b, room["id"], kind="signal", key="rewind")
        assert r.status_code == 400

    def test_a_film_speaks_film_signals_and_not_a_games(self, client, pair):
        a, _ = pair
        film = client.post("/partner/rooms", json={
            "media_id": "m4", "media_type": "movie", "source": "tmdb", "title_ru": "Фильм",
        }, headers=a.headers).json()
        assert _event(client, a, film["id"], kind="signal", key="pause").status_code == 200
        assert _event(client, a, film["id"], kind="signal", key="gg").status_code == 400
        assert _event(client, a, film["id"], kind="signal", key="nonsense").status_code == 400

    def test_a_round_is_one_tap_stamped_with_the_session_time(self, client, pair):
        a, b = pair
        room = _create(client, a).json()
        _join(client, b, room["id"])
        _control(client, a, room["id"], "play")
        out = _round(client, b, room["id"], "win")
        assert out.status_code == 200, out.text
        room_out = out.json()
        e = [x for x in room_out["events"] if x["kind"] == "round"][-1]
        assert e["emoji"] == "win" and e["position_ms"] is not None and e["position_ms"] >= 0
        assert room_out["rounds"] == {"win": 1, "loss": 0, "draw": 0, "checkpoint": 0}

    def test_the_tally_counts_each_kind(self, client, pair):
        a, _ = pair
        room = _create(client, a).json()
        _control(client, a, room["id"], "play")
        out = None
        for key in ("win", "win", "loss", "draw", "checkpoint", "win"):
            out = _round(client, a, room["id"], key).json()
        assert out["rounds"] == {"win": 3, "loss": 1, "draw": 1, "checkpoint": 1}

    def test_a_round_is_a_known_kind_in_a_game_room(self, client, pair):
        a, _ = pair
        room = _create(client, a).json()
        assert _round(client, a, room["id"], "flawless").status_code == 400
        assert _event(client, a, room["id"], kind="round").status_code == 400
        film = client.post("/partner/rooms", json={
            "media_id": "m5", "media_type": "movie", "source": "tmdb", "title_ru": "Фильм",
        }, headers=a.headers).json()
        assert _round(client, a, film["id"], "win").status_code == 400

    def test_there_is_no_zen_and_no_margin_in_a_game(self, client, pair):
        a, _ = pair
        room = _create(client, a).json()
        assert _event(client, a, room["id"], kind="emotion", key="warm").status_code == 400
        assert _event(client, a, room["id"], kind="margin", body="тут", locator="c1").status_code == 400
        assert _event(client, a, room["id"], kind="highlight", key="on", locator="c1").status_code == 400

    def test_reactions_and_chat_work_as_in_any_room(self, client, pair):
        a, b = pair
        room = _create(client, a).json()
        _join(client, b, room["id"])
        assert _event(client, a, room["id"], kind="reaction", key="🔥").status_code == 200
        assert _event(client, b, room["id"], kind="chat", body="ещё один?").status_code == 200

    def test_a_reading_room_has_no_rounds(self, client, pair):
        a, _ = pair
        book = client.post("/partner/rooms", json={
            "media_id": "file:aaaa", "media_type": "book", "source": "file", "title_ru": "Книга",
            "activity": "read", "read_kind": "parallel",
        }, headers=a.headers).json()
        assert _round(client, a, book["id"], "win").status_code == 400
        assert book["rounds"] == {} and book["all_ready"] is False


class TestFinishing:
    def test_finishing_saves_the_evening_like_a_film_does(self, client, pair, db_session):
        a, b = pair
        room = _create(client, a).json()
        _join(client, b, room["id"])
        _control(client, a, room["id"], "play")
        _round(client, a, room["id"], "win")
        done = client.post(f"/partner/rooms/{room['id']}/finish", json={}, headers=a.headers)
        assert done.status_code == 200, done.text
        out = done.json()
        assert out["status"] == "ended" and out["saved_entry_id"] is not None
        entry = db_session.get(models.CoViewEntry, out["saved_entry_id"])
        assert entry is not None and entry.media_type == models.MediaType.game
        assert entry.status == models.CoViewStatus.watched

    def test_a_session_nobody_started_cannot_be_finished(self, client, pair):
        a, _ = pair
        room = _create(client, a).json()
        assert client.post(f"/partner/rooms/{room['id']}/finish", json={}, headers=a.headers).status_code == 409

    def test_the_save_switch_still_decides(self, client, pair):
        a, _ = pair
        room = _create(client, a, save_to_shared=False).json()
        _control(client, a, room["id"], "play")
        done = client.post(f"/partner/rooms/{room['id']}/finish", json={}, headers=a.headers).json()
        assert done["status"] == "ended" and done["saved_entry_id"] is None

    def test_a_guest_can_tap_ready_and_signal_but_not_finish(self, client, pair, register_user):
        a, b = pair
        friend = register_user()
        assert client.post("/friends/request", json={"username": friend.username}, headers=a.headers).status_code == 201
        rid = client.get("/friends", headers=friend.headers).json()["incoming_requests"][0]["id"]
        assert client.post(f"/friends/requests/{rid}/accept", headers=friend.headers).status_code == 200
        room = _create(client, a).json()
        invited = client.post(f"/partner/rooms/{room['id']}/guests", json={"user_id": friend.id}, headers=a.headers)
        assert invited.status_code in (200, 201), invited.text
        _join(client, friend, room["id"])
        out = _ready(client, friend, room["id"])
        assert out.status_code == 200 and _person(out.json(), friend)["ready"] is True
        assert _event(client, friend, room["id"], kind="signal", key="gg").status_code == 200
        _control(client, a, room["id"], "play")
        assert client.post(f"/partner/rooms/{room['id']}/finish", json={}, headers=friend.headers).status_code == 403
