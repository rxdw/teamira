"""Integration tests for app/routers/partner.py — scoped to the core
pairing lifecycle (code-based pairing and direct invites), that only
the two actual link members can act on it, and the co-viewing "mark
watched" endpoint's already_logged branch. The rest of the co-viewing
suggestion/plan/bulk-add endpoints past that are still untested — see
tests/README.md."""


def _link(client, register_user):
    alice = register_user()
    bob = register_user()
    code = client.post("/partner/pair", headers=alice.headers).json()["pending_code"]
    client.post("/partner/join", json={"code": code}, headers=bob.headers)
    return alice, bob


def _media_ids(diary_json):
    return [row["media_id"] for row in diary_json]


class TestCodePairing:
    def test_pair_then_join_links_both_accounts(self, client, register_user):
        alice = register_user()
        bob = register_user()

        started = client.post("/partner/pair", headers=alice.headers)
        assert started.status_code == 201
        code = started.json()["pending_code"]
        assert code

        joined = client.post("/partner/join", json={"code": code}, headers=bob.headers)
        assert joined.status_code == 200
        assert joined.json()["linked"] is True

        alices_status = client.get("/partner", headers=alice.headers).json()
        assert alices_status["linked"] is True
        assert alices_status["partner_username"] == bob.username

    def test_join_schedules_a_push_to_both_sides(self, client, register_user):
        from unittest.mock import patch

        alice = register_user()
        bob = register_user()
        code = client.post("/partner/pair", headers=alice.headers).json()["pending_code"]

        with patch("app.routers.partner.push.notify_partner_linked") as mock_notify:
            client.post("/partner/join", json={"code": code}, headers=bob.headers)

        assert mock_notify.called
        (member_ids, names_by_id) = mock_notify.call_args[0]
        assert set(member_ids) == {alice.id, bob.id}
        # Each side's push needs *the other* person's name, not their own.
        assert names_by_id[alice.id] == bob.username
        assert names_by_id[bob.id] == alice.username

    def test_calling_pair_again_reuses_the_same_pending_code(self, client, register_user):
        alice = register_user()
        first = client.post("/partner/pair", headers=alice.headers).json()["pending_code"]
        second = client.post("/partner/pair", headers=alice.headers).json()["pending_code"]
        assert first == second

    def test_cannot_join_your_own_code(self, client, register_user):
        alice = register_user()
        code = client.post("/partner/pair", headers=alice.headers).json()["pending_code"]
        resp = client.post("/partner/join", json={"code": code}, headers=alice.headers)
        assert resp.status_code == 400

    def test_unknown_code_is_404(self, client, register_user):
        alice = register_user()
        # Right shape (PartnerJoinRequest.code requires exactly 6 chars,
        # matching _gen_code's alphabet) but not one anything generated.
        resp = client.post("/partner/join", json={"code": "ZZZZZZ"}, headers=alice.headers)
        assert resp.status_code == 404

    def test_code_cannot_be_reused_once_active(self, client, register_user):
        alice = register_user()
        bob = register_user()
        mallory = register_user()
        code = client.post("/partner/pair", headers=alice.headers).json()["pending_code"]
        client.post("/partner/join", json={"code": code}, headers=bob.headers)

        resp = client.post("/partner/join", json={"code": code}, headers=mallory.headers)
        assert resp.status_code == 409

    def test_already_linked_user_cannot_start_a_new_pairing(self, client, register_user):
        alice = register_user()
        bob = register_user()
        code = client.post("/partner/pair", headers=alice.headers).json()["pending_code"]
        client.post("/partner/join", json={"code": code}, headers=bob.headers)

        resp = client.post("/partner/pair", headers=alice.headers)
        assert resp.status_code == 409


class TestUnlink:
    def test_unlink_is_symmetric(self, client, register_user):
        alice = register_user()
        bob = register_user()
        code = client.post("/partner/pair", headers=alice.headers).json()["pending_code"]
        client.post("/partner/join", json={"code": code}, headers=bob.headers)

        unlinked = client.delete("/partner", headers=alice.headers)
        assert unlinked.status_code == 204

        assert client.get("/partner", headers=alice.headers).json()["linked"] is False
        assert client.get("/partner", headers=bob.headers).json()["linked"] is False

    def test_unlink_with_no_partner_is_a_no_op_not_an_error(self, client, register_user):
        alice = register_user()
        resp = client.delete("/partner", headers=alice.headers)
        assert resp.status_code == 204


class TestDirectInvites:
    """send_invite takes a user_id (see SendPartnerInviteRequest), not a
    username — the alternative entry point to the same circle a /pair
    code creates, reached from a friend's own profile screen instead of
    a code changing hands."""

    def test_send_accept_links_both_accounts(self, client, register_user):
        alice = register_user()
        bob = register_user()

        sent = client.post("/partner/invite", json={"user_id": bob.id}, headers=alice.headers)
        assert sent.status_code == 201

        invite_id = client.get("/partner/invites", headers=bob.headers).json()["incoming"][0]["id"]
        accepted = client.post(f"/partner/invites/{invite_id}/accept", headers=bob.headers)
        assert accepted.status_code == 200
        assert accepted.json()["linked"] is True

        assert client.get("/partner", headers=alice.headers).json()["partner_username"] == bob.username

    def test_decline_does_not_pair_them(self, client, register_user):
        # send_invite creates the circle as *active* right away (see that
        # function) rather than waiting for a response the way /pair's
        # "pending_code" does — so the sender is already "linked" (to a
        # circle of just themselves) from the moment the invite goes out.
        # Declining doesn't undo that; it just means the invite, and
        # specifically pairing with *this* person, never happened.
        alice = register_user()
        bob = register_user()
        client.post("/partner/invite", json={"user_id": bob.id}, headers=alice.headers)
        invite_id = client.get("/partner/invites", headers=bob.headers).json()["incoming"][0]["id"]

        declined = client.post(f"/partner/invites/{invite_id}/decline", headers=bob.headers)
        assert declined.status_code == 204

        alices_status = client.get("/partner", headers=alice.headers).json()
        assert alices_status["partner_username"] != bob.username
        assert client.get("/partner", headers=bob.headers).json()["linked"] is False

    def test_stranger_cannot_accept_someone_elses_invite(self, client, register_user):
        alice = register_user()
        bob = register_user()
        mallory = register_user()
        client.post("/partner/invite", json={"user_id": bob.id}, headers=alice.headers)
        invite_id = client.get("/partner/invites", headers=bob.headers).json()["incoming"][0]["id"]

        resp = client.post(f"/partner/invites/{invite_id}/accept", headers=mallory.headers)
        assert resp.status_code == 404
        # And it's provably still pending, not silently consumed by mallory.
        still_pending = client.get("/partner/invites", headers=bob.headers).json()["incoming"]
        assert any(inv["id"] == invite_id and inv["status"] == "pending" for inv in still_pending)
        assert client.get("/partner", headers=bob.headers).json()["linked"] is False

    def test_stranger_cannot_decline_someone_elses_invite(self, client, register_user):
        alice = register_user()
        bob = register_user()
        mallory = register_user()
        client.post("/partner/invite", json={"user_id": bob.id}, headers=alice.headers)
        invite_id = client.get("/partner/invites", headers=bob.headers).json()["incoming"][0]["id"]

        resp = client.post(f"/partner/invites/{invite_id}/decline", headers=mallory.headers)
        assert resp.status_code == 404

    def test_cannot_invite_yourself(self, client, register_user):
        alice = register_user()
        resp = client.post("/partner/invite", json={"user_id": alice.id}, headers=alice.headers)
        assert resp.status_code == 400

    def test_unknown_user_id_is_404(self, client, register_user):
        alice = register_user()
        resp = client.post(
            "/partner/invite", json={"user_id": "00000000-0000-0000-0000-000000000000"}, headers=alice.headers
        )
        assert resp.status_code == 404

    def test_partner_endpoints_require_auth(self, client):
        assert client.get("/partner").status_code == 401


class TestMarkCoViewingWatched:
    """POST /partner/co-viewing/{id}/watched — the co-viewing planned
    card's "watched" transition. Default (already_logged unset/False)
    behavior stays the instant, no-rating dual write every existing
    caller relies on; already_logged=True is the new branch the planned
    card's "смотрю" button uses once it's sent the caller through the
    normal per-title logging ritual (see WatchingChoiceScreen) first."""

    def test_default_logs_both_members_diaries_and_flips_status(
        self, client, register_user, sample_media_item
    ):
        alice, bob = _link(client, register_user)
        item = sample_media_item()
        planned = client.post(
            "/partner/co-viewing/plan", json={"item": item}, headers=alice.headers
        ).json()

        resp = client.post(
            f"/partner/co-viewing/{planned['id']}/watched", headers=alice.headers
        )
        assert resp.status_code == 200
        assert resp.json()["status"] == "watched"

        assert item["id"] in _media_ids(client.get("/diary", headers=alice.headers).json())
        assert item["id"] in _media_ids(client.get("/diary", headers=bob.headers).json())

    def test_already_logged_flips_status_without_writing_any_diary(
        self, client, register_user, sample_media_item
    ):
        alice, bob = _link(client, register_user)
        item = sample_media_item()
        planned = client.post(
            "/partner/co-viewing/plan", json={"item": item}, headers=alice.headers
        ).json()

        resp = client.post(
            f"/partner/co-viewing/{planned['id']}/watched",
            json={"already_logged": True},
            headers=alice.headers,
        )
        assert resp.status_code == 200
        assert resp.json()["status"] == "watched"

        assert item["id"] not in _media_ids(client.get("/diary", headers=alice.headers).json())
        assert item["id"] not in _media_ids(client.get("/diary", headers=bob.headers).json())

    def test_already_logged_after_caller_rated_it_themselves_leaves_exactly_one_diary_row(
        self, client, register_user, sample_media_item
    ):
        """The actual planned-card flow: alice runs the normal logging
        ritual herself first (own rating, "watched with partner" on —
        exactly what WatchingChoiceScreen's themed screens already do),
        *then* this endpoint fires with already_logged=True just to drop
        the entry off "запланировано". Alice should end up with exactly
        the one rated row she made — never a second, bare one — and bob
        still gets none, same as any other evening nobody logged for him."""
        alice, bob = _link(client, register_user)
        item = sample_media_item()
        planned = client.post(
            "/partner/co-viewing/plan", json={"item": item}, headers=alice.headers
        ).json()

        logged = client.post(
            "/diary",
            json={"item": item, "rating": 5, "watched_with_partner": True},
            headers=alice.headers,
        )
        assert logged.status_code == 201

        resp = client.post(
            f"/partner/co-viewing/{planned['id']}/watched",
            json={"already_logged": True},
            headers=alice.headers,
        )
        assert resp.status_code == 200
        assert resp.json()["status"] == "watched"

        alice_rows = [
            row for row in client.get("/diary", headers=alice.headers).json()
            if row["media_id"] == item["id"]
        ]
        assert len(alice_rows) == 1
        assert alice_rows[0]["rating"] == 5
        assert item["id"] not in _media_ids(client.get("/diary", headers=bob.headers).json())

        # And it's genuinely shared — bob sees it on the shared diary
        # even though only alice has a row of her own.
        shared = client.get("/partner/shared/diary", headers=bob.headers).json()
        assert any(row["media_id"] == item["id"] for row in shared["items"])

    def test_already_watched_entry_is_a_no_op_either_way(
        self, client, register_user, sample_media_item
    ):
        alice, bob = _link(client, register_user)
        item = sample_media_item()
        planned = client.post(
            "/partner/co-viewing/plan", json={"item": item}, headers=alice.headers
        ).json()
        client.post(f"/partner/co-viewing/{planned['id']}/watched", headers=alice.headers)

        # Second call, now already watched — already_logged shouldn't
        # matter, and it must not write a second diary row for anyone.
        resp = client.post(
            f"/partner/co-viewing/{planned['id']}/watched",
            json={"already_logged": True},
            headers=alice.headers,
        )
        assert resp.status_code == 200
        alice_rows = [
            row for row in client.get("/diary", headers=alice.headers).json()
            if row["media_id"] == item["id"]
        ]
        assert len(alice_rows) == 1


class TestAcceptSuggestion:
    """POST /partner/suggestions/{id}/accept — approving a suggestion is
    itself "plan an evening" (see AcceptSuggestionRequest's own
    docstring), so this covers both the pre-existing bare-add behavior
    (no body, unaffected) and the new optional schedule."""

    def _suggest(self, client, sender, receiver, item):
        resp = client.post("/partner/suggest", json={"item": item}, headers=sender.headers)
        assert resp.status_code == 201
        suggestions = client.get("/partner/suggestions", headers=receiver.headers).json()
        return next(s for s in suggestions if s["media_id"] == item["id"])

    def test_accept_with_no_body_still_bare_adds_like_before(
        self, client, register_user, sample_media_item
    ):
        alice, bob = _link(client, register_user)
        item = sample_media_item()
        suggestion = self._suggest(client, alice, bob, item)

        resp = client.post(
            f"/partner/suggestions/{suggestion['id']}/accept", headers=bob.headers
        )
        assert resp.status_code == 201
        body = resp.json()
        assert body["status"] == "planned"
        assert body["scheduled_date"] is None

        # And it's off the inbox either way.
        assert client.get("/partner/suggestions", headers=bob.headers).json() == []

    def test_accept_with_a_schedule_stamps_it_onto_the_entry(
        self, client, register_user, sample_media_item
    ):
        alice, bob = _link(client, register_user)
        item = sample_media_item()
        suggestion = self._suggest(client, alice, bob, item)

        resp = client.post(
            f"/partner/suggestions/{suggestion['id']}/accept",
            json={"scheduled_date": "2030-01-15T00:00:00Z", "scheduled_hour": 20, "scheduled_minute": 30},
            headers=bob.headers,
        )
        assert resp.status_code == 201
        body = resp.json()
        assert body["status"] == "planned"
        assert body["scheduled_date"] is not None
        assert body["scheduled_hour"] == 20
        assert body["scheduled_minute"] == 30

        planned = client.get("/partner/shared/planned", headers=alice.headers).json()
        row = next(p for p in planned["planned"] if p["media_id"] == item["id"])
        assert row["scheduled_hour"] == 20
