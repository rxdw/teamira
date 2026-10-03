"""Co-view rooms (routers/co_view_room.py, app/co_view_room.py).

What is worth pinning down is what the feature promises: it is free (no
premium anywhere), the clock is the server's, everyone in a circle of up to
four can be in the same room, and what the save switch says at the moment of
finishing is exactly what gets written.
"""

from datetime import datetime, timedelta, timezone

import pytest

from app import co_view_room as rules
from app import models


def _link(client, a, b):
    code = client.post("/partner/pair", headers=a.headers).json()["pending_code"]
    assert client.post("/partner/join", json={"code": code}, headers=b.headers).status_code == 200


def _invite(client, owner, other):
    assert client.post("/partner/invite", json={"user_id": other.id}, headers=owner.headers).status_code == 201
    inv = client.get("/partner/invites", headers=other.headers).json()["incoming"][0]["id"]
    assert client.post(f"/partner/invites/{inv}/accept", headers=other.headers).status_code == 200


def _buy(db_session, user):
    state = db_session.get(models.UserPremiumState, user.id) or models.UserPremiumState(user_id=user.id, is_premium=False, ai_asks_used=0)
    state.is_premium = True
    state.plan_kind = models.PremiumPlanKind.couple
    state.plan_duration = models.PremiumDuration.month
    state.purchased_at = datetime.now(timezone.utc)
    db_session.add(state)
    db_session.commit()


@pytest.fixture
def pair(client, register_user):
    a, b = register_user(), register_user()
    _link(client, a, b)
    return a, b


@pytest.fixture
def company(client, register_user):
    a, b, c = register_user(), register_user(), register_user()
    _link(client, a, b)
    _invite(client, a, c)
    return a, b, c


def _create(client, user, **over):
    body = {
        "media_id": "dQw4w9WgXcQ", "media_type": "video", "source": "youtube",
        "title_ru": "Ролик", "title_en": "Clip", "player_kind": "youtube",
        "player_ref": "https://youtu.be/dQw4w9WgXcQ", "duration_ms": 600_000,
    }
    body.update(over)
    return client.post("/partner/rooms", json=body, headers=user.headers)


def _ctl(client, user, room_id, action, pos=None):
    body = {"action": action}
    if pos is not None:
        body["position_ms"] = pos
    return client.post(f"/partner/rooms/{room_id}/control", json=body, headers=user.headers)


def _join(client, user, room_id):
    r = client.post(f"/partner/rooms/{room_id}/join", headers=user.headers)
    assert r.status_code == 200, r.text
    return r.json()


class TestRules:
    def test_position_advances_only_while_playing(self):
        t0 = datetime(2026, 1, 1, tzinfo=timezone.utc)
        later = t0 + timedelta(seconds=10)
        assert rules.current_position_ms(True, 5_000, t0, later) == 15_000
        assert rules.current_position_ms(False, 5_000, t0, later) == 5_000

    def test_position_never_negative_even_with_a_future_timestamp(self):
        t0 = datetime(2026, 1, 1, tzinfo=timezone.utc)
        assert rules.current_position_ms(True, 1_000, t0 + timedelta(seconds=5), t0) == 1_000
        assert rules.clamp_position(-5) == 0
        assert rules.clamp_position(9_999_999, 1_000) == 1_000

    def test_abandonment_limits_differ_for_lobby_and_live(self):
        now = datetime(2026, 1, 1, 12, tzinfo=timezone.utc)
        old = now - timedelta(hours=1)
        assert rules.is_abandoned("lobby", old, now) is True
        assert rules.is_abandoned("live", old, now) is False
        assert rules.is_abandoned("live", now - timedelta(hours=5), now) is True
        assert rules.is_abandoned("ended", now - timedelta(days=9), now) is False

    def test_presence_needs_a_fresh_heartbeat(self):
        now = datetime(2026, 1, 1, tzinfo=timezone.utc)
        assert rules.is_present(None, now - timedelta(seconds=30), now) is True
        assert rules.is_present(None, now - timedelta(minutes=5), now) is False
        assert rules.is_present(now, now, now) is False

    def test_guest_slots_follow_the_three_guest_and_six_person_caps(self):
        assert rules.guest_slots_left(2, 0) == 3
        assert rules.guest_slots_left(2, 3) == 0
        assert rules.guest_slots_left(3, 1) == 2
        assert rules.guest_slots_left(4, 0) == 2
        assert rules.guest_slots_left(4, 2) == 0
        assert rules.guest_slots_left(6, 0) == 0
        assert rules.guest_slots_left(2, 9) == 0

    def test_player_references(self):
        assert rules.normalize_player("youtube", "https://www.youtube.com/watch?v=dQw4w9WgXcQ") == ("youtube", "dQw4w9WgXcQ")
        assert rules.normalize_player("twitch", "https://www.twitch.tv/videos/123456789") == ("twitch", "123456789")
        assert rules.normalize_player("parallel", "ignored") == ("parallel", None)
        with pytest.raises(ValueError):
            rules.normalize_player("youtube", "https://example.com/x")
        with pytest.raises(ValueError):
            rules.normalize_player("direct", "http://insecure.example/v.mp4")
        with pytest.raises(ValueError):
            rules.normalize_player("direct", "javascript:alert(1)")
        with pytest.raises(ValueError):
            rules.normalize_player("hologram", None)


class TestLifecycle:
    def test_free_users_can_open_and_fill_a_room(self, client, pair):
        alice, bob = pair  # nobody is premium here
        created = _create(client, alice)
        assert created.status_code == 201, created.text
        room = created.json()
        assert room["status"] == "lobby"
        assert room["player_ref"] == "dQw4w9WgXcQ"
        assert room["save_to_shared"] is True
        assert [p["present"] for p in room["participants"]] == [True, False]

        joined = _join(client, bob, room["id"])
        assert all(p["present"] for p in joined["participants"])

    def test_one_open_room_per_circle(self, client, pair):
        alice, bob = pair
        first = _create(client, alice).json()
        again = _create(client, bob, media_id="other", title_ru="Другое")
        assert again.status_code == 200
        assert again.json()["id"] == first["id"]
        assert client.get("/partner/rooms/active", headers=bob.headers).json()["id"] == first["id"]

    def test_no_circle_no_room(self, client, register_user):
        solo = register_user()
        assert _create(client, solo).status_code == 409
        assert client.get("/partner/rooms/active", headers=solo.headers).json() is None

    def test_outsider_cannot_see_the_room(self, client, pair, register_user):
        alice, _ = pair
        room = _create(client, alice).json()
        stranger = register_user()
        # a room's existence isn't something an outsider learns: plain 404
        assert client.get(f"/partner/rooms/{room['id']}", headers=stranger.headers).status_code == 404
        other_a, other_b = register_user(), register_user()
        _link(client, other_a, other_b)
        assert client.get(f"/partner/rooms/{room['id']}", headers=other_a.headers).status_code == 404

    def test_bad_player_reference_is_rejected(self, client, pair):
        alice, _ = pair
        assert _create(client, alice, player_ref="https://example.com/not-youtube").status_code == 400
        assert _create(client, alice, player_kind="direct", player_ref="http://x.test/a.mp4").status_code == 400
        assert _create(client, alice, media_type="hologram").status_code == 400

    def test_last_person_out_closes_a_lobby(self, client, pair):
        alice, _ = pair
        room = _create(client, alice).json()
        out = client.post(f"/partner/rooms/{room['id']}/leave", headers=alice.headers).json()
        assert out["status"] == "ended"
        assert client.get("/partner/rooms/active", headers=alice.headers).json() is None

    def test_abandoned_lobby_is_closed_on_next_look(self, client, pair, db_session):
        alice, _ = pair
        room = _create(client, alice).json()
        row = db_session.get(models.CoViewRoom, room["id"])
        row.last_activity_at = datetime.now(timezone.utc) - timedelta(hours=2)
        db_session.commit()
        assert client.get("/partner/rooms/active", headers=alice.headers).json() is None
        assert client.get(f"/partner/rooms/{room['id']}", headers=alice.headers).json()["status"] == "ended"
        # and a new one can be opened straight away
        assert _create(client, alice).status_code == 201


class TestClock:
    def test_play_starts_the_room_and_control_seq_moves(self, client, pair):
        alice, bob = pair
        room = _create(client, alice).json()
        _join(client, bob, room["id"])
        played = _ctl(client, bob, room["id"], "play", 0).json()
        assert played["status"] == "live" and played["is_playing"] is True
        assert played["started_at"] is not None
        assert played["control_seq"] == 1
        paused = _ctl(client, alice, room["id"], "pause", 42_000).json()
        assert paused["is_playing"] is False and paused["position_ms"] == 42_000
        assert paused["control_seq"] == 2

    def test_seek_keeps_playing_state_and_is_clamped_to_the_video(self, client, pair):
        alice, _ = pair
        room = _create(client, alice, duration_ms=100_000).json()
        _ctl(client, alice, room["id"], "play", 0)
        sought = _ctl(client, alice, room["id"], "seek", 9_999_999).json()
        assert sought["is_playing"] is True
        assert sought["position_ms"] >= 100_000 and sought["position_ms"] < 100_000 + 5_000

    def test_position_advances_on_the_server_clock_while_playing(self, client, pair, db_session):
        alice, _ = pair
        room = _create(client, alice).json()
        _ctl(client, alice, room["id"], "play", 10_000)
        row = db_session.get(models.CoViewRoom, room["id"])
        row.position_updated_at = datetime.now(timezone.utc) - timedelta(seconds=30)
        db_session.commit()
        state = client.get(f"/partner/rooms/{room['id']}", headers=alice.headers).json()
        assert 39_000 <= state["position_ms"] <= 42_000

    def test_control_needs_entering_first(self, client, pair):
        alice, bob = pair
        room = _create(client, alice).json()
        assert _ctl(client, bob, room["id"], "play").status_code == 409
        assert _ctl(client, alice, room["id"], "dance").status_code == 400

    def test_last_person_leaving_pauses_a_running_film(self, client, pair):
        alice, _ = pair
        room = _create(client, alice).json()
        _ctl(client, alice, room["id"], "play", 5_000)
        out = client.post(f"/partner/rooms/{room['id']}/leave", headers=alice.headers).json()
        assert out["is_playing"] is False
        assert out["status"] == "live"  # a paused film can wait


class TestEvents:
    def test_chat_reactions_signals_and_emotions_land_in_order_with_positions(self, client, db_session, pair):
        alice, bob = pair
        _buy(db_session, alice)  # emotions are Zen's input: the circle needs a subscriber
        room = _create(client, alice).json()
        _join(client, bob, room["id"])
        _ctl(client, alice, room["id"], "play", 61_000)
        post = lambda u, **b: client.post(f"/partner/rooms/{room['id']}/events", json=b, headers=u.headers)
        assert post(alice, kind="chat", body="ого!").status_code == 200
        assert post(bob, kind="reaction", key="😂", position_ms=62_000).status_code == 200
        assert post(bob, kind="signal", key="pulse").status_code == 200
        assert post(alice, kind="emotion", key="touching").status_code == 200
        events = client.get(f"/partner/rooms/{room['id']}/events?after=0", headers=alice.headers).json()
        assert [e["seq"] for e in events] == list(range(1, len(events) + 1))
        kinds = [e["kind"] for e in events]
        assert kinds[:4] == ["join", "join", "control", "chat"]
        assert kinds[-3:] == ["reaction", "signal", "emotion"]
        reaction = next(e for e in events if e["kind"] == "reaction")
        assert reaction["position_ms"] == 62_000 and reaction["emoji"] == "😂"
        later = client.get(f"/partner/rooms/{room['id']}/events?after={events[-2]['seq']}", headers=bob.headers).json()
        assert [e["kind"] for e in later] == ["emotion"]

    def test_only_allow_listed_keys_and_clean_text(self, client, pair):
        alice, _ = pair
        room = _create(client, alice).json()
        post = lambda **b: client.post(f"/partner/rooms/{room['id']}/events", json=b, headers=alice.headers)
        assert post(kind="reaction", key="💩").status_code == 400
        assert post(kind="signal", key="slap").status_code == 400
        assert post(kind="emotion", key="rage").status_code == 400
        assert post(kind="control", key="x").status_code == 400
        assert post(kind="chat", body="   ").status_code == 400
        assert post(kind="chat", body="я" * (rules.CHAT_MAX_CHARS + 1)).status_code == 400

    def test_flood_is_slowed_down(self, client, pair):
        alice, _ = pair
        room = _create(client, alice).json()
        codes = [
            client.post(f"/partner/rooms/{room['id']}/events", json={"kind": "reaction", "key": "❤️"}, headers=alice.headers).status_code
            for _ in range(rules.EVENT_RATE_MAX + 5)
        ]
        assert 429 in codes and codes[0] == 200

    def test_nothing_can_be_posted_after_the_end(self, client, pair):
        alice, _ = pair
        room = _create(client, alice).json()
        _ctl(client, alice, room["id"], "play", 0)
        client.post(f"/partner/rooms/{room['id']}/finish", headers=alice.headers)
        r = client.post(f"/partner/rooms/{room['id']}/events", json={"kind": "chat", "body": "эй"}, headers=alice.headers)
        assert r.status_code == 409


def _befriend(client, a, b):
    assert client.post("/friends/request", json={"username": b.username}, headers=a.headers).status_code == 201
    rid = client.get("/friends", headers=b.headers).json()["incoming_requests"][0]["id"]
    assert client.post(f"/friends/requests/{rid}/accept", headers=b.headers).status_code == 200


def _invite_guest(client, host, room_id, guest):
    return client.post(f"/partner/rooms/{room_id}/guests", json={"user_id": guest.id}, headers=host.headers)


class TestGuests:
    """A friend of someone in the circle can be invited into one room: they
    watch, chat, react and talk, but the room's playback, saving and the
    circle's own data stay with the circle."""

    @pytest.fixture
    def room_with_friend(self, client, pair, register_user):
        alice, bob = pair
        guest = register_user()
        _befriend(client, alice, guest)
        room = _create(client, alice).json()
        return alice, bob, guest, room

    def test_invite_join_and_see_the_room(self, client, room_with_friend):
        alice, bob, guest, room = room_with_friend
        invited = _invite_guest(client, alice, room["id"], guest)
        assert invited.status_code == 200, invited.text
        out = invited.json()
        assert out["guest_slots_left"] == 2
        listed = next(p for p in out["participants"] if p["user_id"] == guest.id)
        assert listed["is_guest"] is True and listed["joined"] is False

        mine = client.get("/partner/rooms/invites", headers=guest.headers).json()
        assert [i["room_id"] for i in mine] == [room["id"]]
        assert mine[0]["inviter_username"] == alice.username

        joined = _join(client, guest, room["id"])
        assert joined["me_is_guest"] is True and joined["review_id"] is None
        me = next(p for p in joined["participants"] if p["is_you"])
        assert me["is_guest"] is True and me["present"] is True
        assert client.get("/partner/rooms/active", headers=guest.headers).json() is None

    def test_a_guest_can_chat_react_signal_and_talk_but_not_steer(self, client, room_with_friend, monkeypatch):
        alice, bob, guest, room = room_with_friend
        _invite_guest(client, alice, room["id"], guest)
        _join(client, guest, room["id"])
        post = lambda **b: client.post(f"/partner/rooms/{room['id']}/events", json=b, headers=guest.headers)
        assert post(kind="chat", body="привет всем").status_code == 200
        assert post(kind="reaction", key="😂").status_code == 200
        assert post(kind="signal", key="hold").status_code == 200

        assert _ctl(client, guest, room["id"], "play", 0).status_code == 403
        assert client.patch(f"/partner/rooms/{room['id']}", json={"save_to_shared": False}, headers=guest.headers).status_code == 403
        assert client.post(f"/partner/rooms/{room['id']}/finish", headers=guest.headers).status_code == 403
        assert client.delete(f"/partner/rooms/{room['id']}", headers=guest.headers).status_code == 403
        assert _invite_guest(client, guest, room["id"], alice).status_code == 403

        from app.config import settings
        monkeypatch.setattr(settings, "livekit_url", "wss://rtc.example.test")
        monkeypatch.setattr(settings, "livekit_api_key", "devkey")
        monkeypatch.setattr(settings, "livekit_api_secret", "s" * 40)
        assert client.post(f"/partner/rooms/{room['id']}/voice-token", headers=guest.headers).status_code == 200

    def test_the_circle_sees_the_guests_chat_and_the_guest_sees_the_circles(self, client, room_with_friend):
        alice, bob, guest, room = room_with_friend
        _invite_guest(client, alice, room["id"], guest)
        _join(client, guest, room["id"])
        client.post(f"/partner/rooms/{room['id']}/events", json={"kind": "chat", "body": "я гость"}, headers=guest.headers)
        _join(client, bob, room["id"])
        client.post(f"/partner/rooms/{room['id']}/events", json={"kind": "chat", "body": "добро пожаловать"}, headers=bob.headers)
        for viewer in (alice, guest):
            events = client.get(f"/partner/rooms/{room['id']}/events?after=0", headers=viewer.headers).json()
            chat = [(e["username"], e["body"]) for e in events if e["kind"] == "chat"]
            assert chat == [(guest.username, "я гость"), (bob.username, "добро пожаловать")]

    def test_only_a_friend_and_only_someone_in_the_circle_can_invite(self, client, pair, register_user):
        alice, bob = pair
        stranger = register_user()
        room = _create(client, alice).json()
        assert _invite_guest(client, alice, room["id"], stranger).status_code == 403  # not a friend
        assert _invite_guest(client, alice, room["id"], bob).status_code == 409        # already in the circle
        friend = register_user()
        _befriend(client, alice, friend)
        outsider = register_user()
        assert _invite_guest(client, outsider, room["id"], friend).status_code == 404
        assert client.post(f"/partner/rooms/{room['id']}/guests", json={"user_id": "nope"}, headers=alice.headers).status_code == 404

    def test_a_circle_member_can_invite_their_own_friend_too(self, client, pair, register_user):
        alice, bob = pair
        bobs_friend = register_user()
        _befriend(client, bob, bobs_friend)
        room = _create(client, alice).json()
        assert _invite_guest(client, bob, room["id"], bobs_friend).status_code == 200

    def test_slots_are_limited_to_three_and_six_in_total(self, client, pair, register_user):
        alice, _ = pair
        room = _create(client, alice).json()
        friends = [register_user() for _ in range(4)]
        for f in friends:
            _befriend(client, alice, f)
        for f in friends[:3]:
            assert _invite_guest(client, alice, room["id"], f).status_code == 200
        full = _invite_guest(client, alice, room["id"], friends[3])
        assert full.status_code == 409
        state = client.get(f"/partner/rooms/{room['id']}", headers=alice.headers).json()
        assert state["guest_slots_left"] == 0
        # inviting the same person twice is harmless
        assert _invite_guest(client, alice, room["id"], friends[0]).status_code == 200

    def test_blocks_keep_people_out(self, client, pair, register_user):
        alice, bob = pair
        guest = register_user()
        _befriend(client, alice, guest)
        room = _create(client, alice).json()
        assert client.post("/moderation/blocks", json={"user_id": guest.id}, headers=bob.headers).status_code == 201
        refused = _invite_guest(client, alice, room["id"], guest)
        assert refused.status_code == 409

    def test_removing_a_guest_ends_their_access_at_once(self, client, room_with_friend):
        alice, bob, guest, room = room_with_friend
        _invite_guest(client, alice, room["id"], guest)
        _join(client, guest, room["id"])
        assert client.delete(f"/partner/rooms/{room['id']}/guests/{guest.id}", headers=bob.headers).status_code == 204
        assert client.get(f"/partner/rooms/{room['id']}", headers=guest.headers).status_code == 404
        assert client.get("/partner/rooms/invites", headers=guest.headers).json() == []
        state = client.get(f"/partner/rooms/{room['id']}", headers=alice.headers).json()
        assert all(p["user_id"] != guest.id for p in state["participants"])
        assert state["guest_slots_left"] == 3
        # a removed guest can be asked again
        assert _invite_guest(client, alice, room["id"], guest).status_code == 200

    def test_a_guest_who_says_no_is_not_asked_again_for_that_room(self, client, room_with_friend):
        alice, bob, guest, room = room_with_friend
        _invite_guest(client, alice, room["id"], guest)
        assert client.delete(f"/partner/rooms/{room['id']}/guests/{guest.id}", headers=guest.headers).status_code == 204
        assert client.get("/partner/rooms/invites", headers=guest.headers).json() == []
        assert _invite_guest(client, alice, room["id"], guest).status_code == 409

    def test_a_guest_can_decline_with_me_as_the_id(self, client, room_with_friend):
        alice, bob, guest, room = room_with_friend
        _invite_guest(client, alice, room["id"], guest)
        assert client.delete(f"/partner/rooms/{room['id']}/guests/me", headers=guest.headers).status_code == 204
        assert client.get("/partner/rooms/invites", headers=guest.headers).json() == []

    def test_a_guest_cannot_remove_other_guests_or_circle_members(self, client, room_with_friend, register_user):
        alice, bob, guest, room = room_with_friend
        other = register_user()
        _befriend(client, alice, other)
        _invite_guest(client, alice, room["id"], guest)
        _invite_guest(client, alice, room["id"], other)
        assert client.delete(f"/partner/rooms/{room['id']}/guests/{other.id}", headers=guest.headers).status_code == 403

    def test_an_uninvited_friend_cannot_join_or_read(self, client, room_with_friend):
        alice, bob, guest, room = room_with_friend
        assert client.post(f"/partner/rooms/{room['id']}/join", headers=guest.headers).status_code == 404
        assert client.get(f"/partner/rooms/{room['id']}", headers=guest.headers).status_code == 404

    def test_finishing_writes_the_evening_to_the_guests_diary_but_not_the_circles_review(self, client, room_with_friend):
        alice, bob, guest, room = room_with_friend
        _invite_guest(client, alice, room["id"], guest)
        _join(client, bob, room["id"])
        _join(client, guest, room["id"])
        _ctl(client, alice, room["id"], "play", 0)
        out = client.post(f"/partner/rooms/{room['id']}/finish", headers=alice.headers).json()
        assert out["review_id"]
        diary = client.get("/diary", headers=guest.headers).json()
        assert len(diary) == 1 and diary[0]["rating"] is None
        names = set(diary[0]["watched_with_username"].split(", "))
        assert names == {alice.username, bob.username}
        review = client.get(f"/partner/reviews/{out['review_id']}", headers=alice.headers).json()
        assert {p["username"] for p in review["people"]} == {alice.username, bob.username}
        assert client.get(f"/partner/reviews/{out['review_id']}", headers=guest.headers).status_code == 409
        after = client.get(f"/partner/rooms/{room['id']}", headers=guest.headers).json()
        assert after["status"] == "ended" and after["review_id"] is None and after["my_diary_entry_id"]

    def test_a_guest_alone_does_not_keep_a_film_running(self, client, room_with_friend):
        alice, bob, guest, room = room_with_friend
        _invite_guest(client, alice, room["id"], guest)
        _join(client, guest, room["id"])
        _ctl(client, alice, room["id"], "play", 5_000)
        out = client.post(f"/partner/rooms/{room['id']}/leave", headers=alice.headers).json()
        assert out["is_playing"] is False

    def test_the_invite_list_forgets_rooms_that_have_ended(self, client, room_with_friend):
        alice, bob, guest, room = room_with_friend
        _invite_guest(client, alice, room["id"], guest)
        assert len(client.get("/partner/rooms/invites", headers=guest.headers).json()) == 1
        client.delete(f"/partner/rooms/{room['id']}", headers=alice.headers)
        assert client.get("/partner/rooms/invites", headers=guest.headers).json() == []

    def test_zen_follows_the_circles_subscription_for_guests_too(self, client, db_session, room_with_friend):
        alice, bob, guest, room = room_with_friend
        _buy(db_session, bob)
        _invite_guest(client, alice, room["id"], guest)
        _join(client, guest, room["id"])
        state = client.get(f"/partner/rooms/{room['id']}", headers=guest.headers).json()
        assert state["zen_available"] is True
        r = client.post(f"/partner/rooms/{room['id']}/events", json={"kind": "emotion", "key": "warm"}, headers=guest.headers)
        assert r.status_code == 200


class TestZenIsPremium:
    """Zen mode is the one premium thing in a room, and the server holds the
    line: its input — the emotion tap — is refused for a circle where nobody
    subscribes. Everything else a room does stays free."""

    def _emotion(self, client, user, room_id, key="warm"):
        return client.post(f"/partner/rooms/{room_id}/events", json={"kind": "emotion", "key": key}, headers=user.headers)

    def test_a_free_circle_cannot_tap_emotions_but_everything_else_is_free(self, client, pair):
        alice, bob = pair
        room = _create(client, alice).json()
        _join(client, bob, room["id"])
        assert room["zen_available"] is False
        assert self._emotion(client, alice, room["id"]).status_code == 402
        post = lambda u, **b: client.post(f"/partner/rooms/{room['id']}/events", json=b, headers=u.headers)
        assert post(alice, kind="chat", body="привет").status_code == 200
        assert post(bob, kind="reaction", key="❤️").status_code == 200
        assert post(bob, kind="signal", key="hold").status_code == 200
        events = client.get(f"/partner/rooms/{room['id']}/events?after=0", headers=alice.headers).json()
        assert all(e["kind"] != "emotion" for e in events)

    def test_one_subscriber_opens_zen_for_the_whole_circle(self, client, db_session, pair):
        alice, bob = pair
        _buy(db_session, bob)
        room = _create(client, alice).json()
        _join(client, bob, room["id"])
        assert client.get(f"/partner/rooms/{room['id']}", headers=alice.headers).json()["zen_available"] is True
        assert self._emotion(client, alice, room["id"]).status_code == 200
        assert self._emotion(client, bob, room["id"], "funny").status_code == 200

    def test_a_circle_of_three_is_open_if_any_one_member_subscribes(self, client, db_session, company):
        alice, bob, carol = company
        _buy(db_session, carol)
        room = _create(client, alice).json()
        assert self._emotion(client, alice, room["id"]).status_code == 200

    def test_the_gate_checks_before_the_key_so_unknown_keys_are_still_400(self, client, pair):
        alice, _ = pair
        room = _create(client, alice).json()
        assert self._emotion(client, alice, room["id"], "rage").status_code == 400

    def test_a_lapsed_subscription_closes_zen_again(self, client, db_session, pair):
        alice, _ = pair
        _buy(db_session, alice)
        room = _create(client, alice).json()
        assert self._emotion(client, alice, room["id"]).status_code == 200
        state = db_session.get(models.UserPremiumState, alice.id)
        state.is_premium = False
        db_session.commit()
        assert self._emotion(client, alice, room["id"]).status_code == 402
        # what was tapped while subscribed stays on the record
        events = client.get(f"/partner/rooms/{room['id']}/events?after=0", headers=alice.headers).json()
        assert sum(1 for e in events if e["kind"] == "emotion") == 1


class TestSaving:
    def _diary(self, client, user):
        return client.get("/diary", headers=user.headers).json()

    def test_finish_with_the_switch_on_writes_shared_entry_and_both_diaries(self, client, pair):
        alice, bob = pair
        room = _create(client, alice).json()
        _join(client, bob, room["id"])
        _ctl(client, alice, room["id"], "play", 0)
        done = client.post(f"/partner/rooms/{room['id']}/finish", json={"position_ms": 590_000}, headers=bob.headers)
        assert done.status_code == 200, done.text
        out = done.json()
        assert out["status"] == "ended" and out["saved_entry_id"]
        assert out["my_diary_entry_id"]

        watched = client.get("/partner/co-viewing", headers=alice.headers).json()["watched"]
        assert [w["media_id"] for w in watched] == ["dQw4w9WgXcQ"]
        for user, other in ((alice, bob), (bob, alice)):
            rows = self._diary(client, user)
            assert len(rows) == 1
            assert rows[0]["watched_with_username"] == other.username
            assert rows[0]["rating"] is None

    def test_each_person_can_then_rate_their_own_entry(self, client, pair):
        alice, bob = pair
        room = _create(client, alice).json()
        _join(client, bob, room["id"])
        _ctl(client, alice, room["id"], "play", 0)
        out = client.post(f"/partner/rooms/{room['id']}/finish", headers=alice.headers).json()
        rated = client.patch(f"/diary/{out['my_diary_entry_id']}", json={"rating": 9}, headers=alice.headers)
        assert rated.status_code == 200 and rated.json()["rating"] == 9
        assert self._diary(client, bob)[0]["rating"] is None

    def test_switch_off_writes_nothing_anywhere(self, client, pair):
        alice, bob = pair
        room = _create(client, alice, save_to_shared=False).json()
        _join(client, bob, room["id"])
        _ctl(client, alice, room["id"], "play", 0)
        out = client.post(f"/partner/rooms/{room['id']}/finish", headers=alice.headers).json()
        assert out["status"] == "ended" and out["saved_entry_id"] is None and out["my_diary_entry_id"] is None
        assert client.get("/partner/co-viewing", headers=alice.headers).json()["watched"] == []
        assert self._diary(client, alice) == [] and self._diary(client, bob) == []

    def test_whatever_the_switch_says_at_the_end_wins(self, client, pair):
        alice, bob = pair
        room = _create(client, alice, save_to_shared=False).json()
        _join(client, bob, room["id"])
        flipped = client.patch(f"/partner/rooms/{room['id']}", json={"save_to_shared": True}, headers=bob.headers).json()
        assert flipped["save_to_shared"] is True
        assert any(e["kind"] == "system" and e["emoji"] is None and e["body"] == "save_on" for e in flipped["events"])
        _ctl(client, alice, room["id"], "play", 0)
        out = client.post(f"/partner/rooms/{room['id']}/finish", headers=alice.headers).json()
        assert out["saved_entry_id"]

    def test_only_people_who_were_there_get_the_evening(self, client, company):
        alice, bob, carol = company
        room = _create(client, alice).json()
        _join(client, bob, room["id"])  # carol never comes
        _ctl(client, alice, room["id"], "play", 0)
        client.post(f"/partner/rooms/{room['id']}/finish", headers=alice.headers)
        assert len(self._diary(client, alice)) == 1
        assert len(self._diary(client, bob)) == 1
        assert self._diary(client, carol) == []
        assert self._diary(client, alice)[0]["watched_with_username"] == bob.username

    def test_a_circle_of_three_shares_one_room(self, client, company):
        alice, bob, carol = company
        room = _create(client, alice).json()
        for u in (bob, carol):
            _join(client, u, room["id"])
        state = client.get(f"/partner/rooms/{room['id']}", headers=carol.headers).json()
        assert len(state["participants"]) == 3 and all(p["present"] for p in state["participants"])
        _ctl(client, carol, room["id"], "play", 0)
        client.post(f"/partner/rooms/{room['id']}/finish", headers=bob.headers)
        for u in (alice, bob, carol):
            assert len(self._diary(client, u)) == 1
        names = set(self._diary(client, alice)[0]["watched_with_username"].split(", "))
        assert names == {bob.username, carol.username}

    def test_cannot_finish_what_never_started_but_can_close_it(self, client, pair):
        alice, _ = pair
        room = _create(client, alice).json()
        assert client.post(f"/partner/rooms/{room['id']}/finish", headers=alice.headers).status_code == 409
        assert client.delete(f"/partner/rooms/{room['id']}", headers=alice.headers).status_code == 204
        assert client.get("/partner/rooms/active", headers=alice.headers).json() is None

    def test_finishing_twice_is_harmless_and_writes_one_diary_row(self, client, pair):
        alice, bob = pair
        room = _create(client, alice).json()
        _join(client, bob, room["id"])
        _ctl(client, alice, room["id"], "play", 0)
        first = client.post(f"/partner/rooms/{room['id']}/finish", headers=alice.headers).json()
        second = client.post(f"/partner/rooms/{room['id']}/finish", headers=bob.headers).json()
        assert second["status"] == "ended" and second["saved_entry_id"] == first["saved_entry_id"]
        assert second["my_diary_entry_id"]
        assert len(self._diary(client, alice)) == 1 and len(self._diary(client, bob)) == 1

    def test_finishing_opens_sealed_album_notes_for_a_couple(self, client, db_session, pair, sample_media_item):
        alice, bob = pair
        state = db_session.get(models.UserPremiumState, alice.id) or models.UserPremiumState(user_id=alice.id, is_premium=False, ai_asks_used=0)
        state.is_premium = True
        state.plan_kind = models.PremiumPlanKind.couple
        state.plan_duration = models.PremiumDuration.month
        state.purchased_at = datetime.now(timezone.utc)
        db_session.add(state)
        db_session.commit()
        item = sample_media_item(id="tt777", source="tmdb")
        assert client.put("/partner/album/notes", json={"item": item, "body": "секрет"}, headers=alice.headers).status_code == 200
        room = _create(client, alice, media_id="tt777", media_type="movie", source="tmdb", player_kind="parallel", player_ref=None).json()
        _join(client, bob, room["id"])
        _ctl(client, alice, room["id"], "play", 0)
        client.post(f"/partner/rooms/{room['id']}/finish", headers=alice.headers)
        notes = db_session.query(models.PairNote).filter_by(link_id=db_session.query(models.PartnerLink).first().id).all()
        assert notes and all(n.revealed_at is not None for n in notes)

    def test_a_planned_entry_becomes_watched_not_duplicated(self, client, pair, sample_media_item):
        alice, bob = pair
        item = sample_media_item(id="tt42", source="tmdb")
        planned = client.post("/partner/co-viewing/plan", json={"item": item}, headers=alice.headers).json()
        room = _create(client, alice, media_id="tt42", media_type="movie", source="tmdb", player_kind="parallel", player_ref=None, entry_id=planned["id"]).json()
        _join(client, bob, room["id"])
        _ctl(client, alice, room["id"], "play", 0)
        out = client.post(f"/partner/rooms/{room['id']}/finish", headers=alice.headers).json()
        assert out["saved_entry_id"] == planned["id"]
        co = client.get("/partner/co-viewing", headers=alice.headers).json()
        assert co["planned"] == [] and len(co["watched"]) == 1


class TestClosing:
    def test_a_guest_cannot_close_the_hosts_room_while_the_host_is_there(self, client, pair):
        alice, bob = pair
        room = _create(client, alice).json()
        _join(client, bob, room["id"])
        assert client.delete(f"/partner/rooms/{room['id']}", headers=bob.headers).status_code == 403
        assert client.delete(f"/partner/rooms/{room['id']}", headers=alice.headers).status_code == 204


class TestVoice:
    def test_voice_is_free_but_needs_a_configured_server(self, client, pair, monkeypatch):
        alice, _ = pair
        room = _create(client, alice).json()
        assert room["voice_available"] is False
        assert client.post(f"/partner/rooms/{room['id']}/voice-token", headers=alice.headers).status_code == 503

        from app.config import settings
        monkeypatch.setattr(settings, "livekit_url", "wss://rtc.example.test")
        monkeypatch.setattr(settings, "livekit_api_key", "devkey")
        monkeypatch.setattr(settings, "livekit_api_secret", "s" * 40)
        resp = client.post(f"/partner/rooms/{room['id']}/voice-token", headers=alice.headers)
        assert resp.status_code == 200, resp.text
        data = resp.json()
        assert data["url"] == "wss://rtc.example.test" and data["identity"] == alice.id

        from jose import jwt
        claims = jwt.decode(data["token"], "s" * 40, algorithms=["HS256"], options={"verify_aud": False})
        assert claims["iss"] == "devkey" and claims["sub"] == alice.id
        assert claims["video"]["room"] == f"co-view-{room['id']}" and claims["video"]["roomJoin"] is True

        state = client.get(f"/partner/rooms/{room['id']}", headers=alice.headers).json()
        assert state["participants"][0]["voice_on"] is True
        off = client.delete(f"/partner/rooms/{room['id']}/voice", headers=alice.headers).json()
        assert off["participants"][0]["voice_on"] is False

    def test_voice_token_needs_being_in_the_room(self, client, pair, monkeypatch):
        alice, bob = pair
        from app.config import settings
        monkeypatch.setattr(settings, "livekit_url", "wss://rtc.example.test")
        monkeypatch.setattr(settings, "livekit_api_key", "devkey")
        monkeypatch.setattr(settings, "livekit_api_secret", "s" * 40)
        room = _create(client, alice).json()
        assert client.post(f"/partner/rooms/{room['id']}/voice-token", headers=bob.headers).status_code == 409


class TestLinkBreak:
    def test_unlinking_takes_the_room_with_it(self, client, pair, db_session):
        alice, bob = pair
        room = _create(client, alice).json()
        assert client.delete("/partner", headers=bob.headers).status_code == 204
        db_session.expire_all()
        assert db_session.get(models.CoViewRoom, room["id"]) is None
