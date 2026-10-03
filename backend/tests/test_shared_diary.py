"""Tests for routers/shared_diary.py — the "наш дневник" shared view over
two linked accounts' personal diaries. Scoped to the three things worth
being precise about, per that router's own module docstring: whether an
evening lands in the shared diary at all (auto_share_logs vs
watched_together), whether each person's rating/note is visible to the
*other* person according to their own prefs (never the viewer's), and
that unsharing a together-watched evening is refused rather than
silently allowed."""


def _link_two_users(client, register_user):
    a = register_user()
    b = register_user()
    code = client.post("/partner/pair", headers=a.headers).json()["pending_code"]
    client.post("/partner/join", json={"code": code}, headers=b.headers)
    return a, b


def _log(client, headers, sample_media_item, **overrides):
    payload = {"item": sample_media_item(), **overrides}
    resp = client.post("/diary", json=payload, headers=headers)
    assert resp.status_code == 201, resp.text
    return resp.json()


class TestPrefs:
    def test_defaults_for_an_unlinked_account(self, client, register_user):
        alice = register_user()
        resp = client.get("/partner/shared/prefs", headers=alice.headers)
        assert resp.status_code == 200
        body = resp.json()
        assert body == {"auto_share_logs": True, "share_ratings": True, "share_notes": False}

    def test_unlinked_account_cannot_update_prefs(self, client, register_user):
        alice = register_user()
        resp = client.patch("/partner/shared/prefs", json={"share_notes": True}, headers=alice.headers)
        assert resp.status_code == 409

    def test_linked_account_can_update_prefs(self, client, register_user):
        alice, _bob = _link_two_users(client, register_user)
        resp = client.patch(
            "/partner/shared/prefs", json={"share_notes": True, "auto_share_logs": False}, headers=alice.headers
        )
        assert resp.status_code == 200
        body = resp.json()
        assert body["share_notes"] is True
        assert body["auto_share_logs"] is False
        assert body["share_ratings"] is True  # untouched field keeps its default

    def test_unset_fields_are_left_alone(self, client, register_user):
        alice, _bob = _link_two_users(client, register_user)
        client.patch("/partner/shared/prefs", json={"share_notes": True}, headers=alice.headers)
        again = client.patch("/partner/shared/prefs", json={"auto_share_logs": False}, headers=alice.headers)
        assert again.json()["share_notes"] is True  # survived the second, unrelated update


class TestGatingWhenUnlinked:
    def test_shared_diary_requires_a_link(self, client, register_user):
        alice = register_user()
        assert client.get("/partner/shared/diary", headers=alice.headers).status_code == 409

    def test_shared_planned_requires_a_link(self, client, register_user):
        alice = register_user()
        assert client.get("/partner/shared/planned", headers=alice.headers).status_code == 409

    def test_shared_stats_requires_a_link(self, client, register_user):
        alice = register_user()
        assert client.get("/partner/shared/stats", headers=alice.headers).status_code == 409


class TestAutoShare:
    def test_a_solo_log_shares_by_default(self, client, register_user, sample_media_item):
        alice, bob = _link_two_users(client, register_user)
        _log(client, alice.headers, sample_media_item)

        shared = client.get("/partner/shared/diary", headers=bob.headers)
        assert len(shared.json()["items"]) == 1

    def test_turning_auto_share_off_keeps_new_solo_logs_private(self, client, register_user, sample_media_item):
        alice, bob = _link_two_users(client, register_user)
        client.patch("/partner/shared/prefs", json={"auto_share_logs": False}, headers=alice.headers)
        _log(client, alice.headers, sample_media_item)

        shared = client.get("/partner/shared/diary", headers=bob.headers)
        assert shared.json()["items"] == []

    def test_watched_together_shares_even_with_auto_share_off(self, client, register_user, sample_media_item):
        alice, bob = _link_two_users(client, register_user)
        client.patch("/partner/shared/prefs", json={"auto_share_logs": False}, headers=alice.headers)
        _log(client, alice.headers, sample_media_item, watched_with_partner=True)

        shared = client.get("/partner/shared/diary", headers=bob.headers)
        assert len(shared.json()["items"]) == 1

    def test_unlinking_stops_new_logs_from_ever_reaching_the_other_side(
        self, client, register_user, sample_media_item
    ):
        alice, bob = _link_two_users(client, register_user)
        client.delete("/partner", headers=alice.headers)
        # Logging now, unlinked — shared_link_id_for_log returns None
        # since get_active_link finds nothing.
        _log(client, alice.headers, sample_media_item)
        # bob is unlinked too now (unlink is symmetric), so this 409s
        # rather than returning an empty list — either way, nothing leaked.
        resp = client.get("/partner/shared/diary", headers=bob.headers)
        assert resp.status_code == 409


class TestPerPersonPrivacy:
    def test_own_rating_and_note_are_always_visible_to_self(self, client, register_user, sample_media_item):
        alice, _bob = _link_two_users(client, register_user)
        _log(client, alice.headers, sample_media_item, rating=8, note="loved it")

        mine = client.get("/partner/shared/diary", headers=alice.headers).json()["items"][0]
        me = next(p for p in mine["people"] if p["is_me"])
        assert me["rating"] == 8
        assert me["note"] == "loved it"

    def test_partners_rating_visible_by_default_note_is_not(self, client, register_user, sample_media_item):
        alice, bob = _link_two_users(client, register_user)
        item = sample_media_item()
        client.post("/diary", json={"item": item, "rating": 8, "note": "loved it"}, headers=alice.headers)

        bobs_view = client.get("/partner/shared/diary", headers=bob.headers).json()["items"][0]
        alice_as_seen_by_bob = next(p for p in bobs_view["people"] if not p["is_me"])
        # share_ratings defaults True, but bob hasn't rated this title
        # himself yet, so the rating_hidden veil (app/sincerity.py's
        # spoiler_unlock/formed_own_opinion pair) applies on top of that —
        # visible-by-default and revealed-yet are two different things now.
        assert alice_as_seen_by_bob["rating"] is None
        assert alice_as_seen_by_bob["rating_hidden"] is True
        assert alice_as_seen_by_bob["note"] is None      # share_notes defaults False

        # Once bob rates the same title himself, the veil lifts on its own.
        client.post("/diary", json={"item": item, "rating": 6}, headers=bob.headers)
        bobs_view_after = client.get("/partner/shared/diary", headers=bob.headers).json()["items"][0]
        alice_as_seen_by_bob_after = next(p for p in bobs_view_after["people"] if not p["is_me"])
        assert alice_as_seen_by_bob_after["rating"] == 8
        assert alice_as_seen_by_bob_after["rating_hidden"] is False

    def test_turning_off_share_ratings_hides_the_rating_from_the_partner_only(
        self, client, register_user, sample_media_item
    ):
        alice, bob = _link_two_users(client, register_user)
        client.patch("/partner/shared/prefs", json={"share_ratings": False}, headers=alice.headers)
        _log(client, alice.headers, sample_media_item, rating=8)

        bobs_view = client.get("/partner/shared/diary", headers=bob.headers).json()["items"][0]
        alice_as_seen_by_bob = next(p for p in bobs_view["people"] if not p["is_me"])
        assert alice_as_seen_by_bob["rating"] is None

        # And alice still sees her own rating regardless of her own setting.
        alices_view = client.get("/partner/shared/diary", headers=alice.headers).json()["items"][0]
        me = next(p for p in alices_view["people"] if p["is_me"])
        assert me["rating"] == 8

    def test_turning_on_share_notes_reveals_the_note_to_the_partner(
        self, client, register_user, sample_media_item
    ):
        alice, bob = _link_two_users(client, register_user)
        client.patch("/partner/shared/prefs", json={"share_notes": True}, headers=alice.headers)
        _log(client, alice.headers, sample_media_item, note="visible now")

        bobs_view = client.get("/partner/shared/diary", headers=bob.headers).json()["items"][0]
        alice_as_seen_by_bob = next(p for p in bobs_view["people"] if not p["is_me"])
        assert alice_as_seen_by_bob["note"] == "visible now"


class TestGrouping:
    def test_both_logging_the_same_title_makes_one_card_with_two_people(
        self, client, register_user, sample_media_item
    ):
        alice, bob = _link_two_users(client, register_user)
        item = sample_media_item()
        client.post("/diary", json={"item": item, "rating": 6}, headers=alice.headers)
        client.post("/diary", json={"item": item, "rating": 9}, headers=bob.headers)

        items = client.get("/partner/shared/diary", headers=alice.headers).json()["items"]
        assert len(items) == 1
        assert len(items[0]["people"]) == 2
        assert items[0]["rating_gap"] == 3

    def test_two_different_titles_stay_as_two_cards(self, client, register_user, sample_media_item):
        alice, bob = _link_two_users(client, register_user)
        _log(client, alice.headers, sample_media_item)
        _log(client, bob.headers, sample_media_item)

        items = client.get("/partner/shared/diary", headers=alice.headers).json()["items"]
        assert len(items) == 2
        assert all(item["rating_gap"] is None for item in items)


class TestSetEntryShared:
    def test_unsharing_a_solo_shared_entry(self, client, register_user, sample_media_item):
        alice, bob = _link_two_users(client, register_user)
        entry = _log(client, alice.headers, sample_media_item)
        assert len(client.get("/partner/shared/diary", headers=bob.headers).json()["items"]) == 1

        resp = client.post(
            f"/partner/shared/diary/{entry['id']}/share", json={"shared": False}, headers=alice.headers
        )
        assert resp.status_code == 200
        assert client.get("/partner/shared/diary", headers=bob.headers).json()["items"] == []

    def test_cannot_unshare_a_watched_together_entry(self, client, register_user, sample_media_item):
        alice, _bob = _link_two_users(client, register_user)
        entry = _log(client, alice.headers, sample_media_item, watched_with_partner=True)

        resp = client.post(
            f"/partner/shared/diary/{entry['id']}/share", json={"shared": False}, headers=alice.headers
        )
        assert resp.status_code == 400

    def test_cannot_share_or_unshare_someone_elses_entry(self, client, register_user, sample_media_item):
        alice, bob = _link_two_users(client, register_user)
        client.patch("/partner/shared/prefs", json={"auto_share_logs": False}, headers=alice.headers)
        entry = _log(client, alice.headers, sample_media_item)  # private, not shared

        resp = client.post(
            f"/partner/shared/diary/{entry['id']}/share", json={"shared": True}, headers=bob.headers
        )
        assert resp.status_code == 404
        # Provably still private, not shared by bob's attempt.
        assert client.get("/partner/shared/diary", headers=bob.headers).json()["items"] == []

    def test_nonexistent_entry_is_404(self, client, register_user):
        alice, _bob = _link_two_users(client, register_user)
        resp = client.post(
            "/partner/shared/diary/00000000-0000-0000-0000-000000000000/share",
            json={"shared": True},
            headers=alice.headers,
        )
        assert resp.status_code == 404
