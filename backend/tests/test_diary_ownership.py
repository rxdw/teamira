"""app/routers/diary.py filters every read/update/delete by
`DiaryEntry.user_id == current_user.id`. These tests exist to prove
that in the one way that actually matters — by hitting the real HTTP
endpoints as two different logged-in users and confirming user B can't
read, edit, or delete user A's diary entry by guessing/reusing its id.
If a future change ever drops one of those filters, one of these should
turn red."""


def _log_entry(client, headers, sample_media_item, **overrides):
    payload = {"item": sample_media_item(), **overrides}
    resp = client.post("/diary", json=payload, headers=headers)
    assert resp.status_code == 201, resp.text
    return resp.json()


class TestDiaryOwnership:
    def test_owner_can_list_their_own_entry(self, client, register_user, sample_media_item):
        alice = register_user()
        entry = _log_entry(client, alice.headers, sample_media_item, note="alice's evening")

        listing = client.get("/diary", headers=alice.headers)
        assert listing.status_code == 200
        assert any(e["id"] == entry["id"] for e in listing.json())

    def test_other_user_does_not_see_it_in_their_list(self, client, register_user, sample_media_item):
        alice = register_user()
        bob = register_user()
        _log_entry(client, alice.headers, sample_media_item, note="alice's evening")

        bobs_list = client.get("/diary", headers=bob.headers)
        assert bobs_list.status_code == 200
        assert bobs_list.json() == []

    def test_other_user_cannot_update_it(self, client, register_user, sample_media_item):
        alice = register_user()
        bob = register_user()
        entry = _log_entry(client, alice.headers, sample_media_item, note="original note")

        resp = client.patch(f"/diary/{entry['id']}", json={"note": "hacked by bob"}, headers=bob.headers)
        assert resp.status_code == 404

        # And it's provably untouched, not just hidden from the response.
        still_alice_view = client.get("/diary", headers=alice.headers)
        assert still_alice_view.json()[0]["note"] == "original note"

    def test_other_user_cannot_delete_it(self, client, register_user, sample_media_item):
        alice = register_user()
        bob = register_user()
        entry = _log_entry(client, alice.headers, sample_media_item)

        resp = client.delete(f"/diary/{entry['id']}", headers=bob.headers)
        assert resp.status_code == 404

        still_there = client.get("/diary", headers=alice.headers)
        assert any(e["id"] == entry["id"] for e in still_there.json())

    def test_owner_can_update_and_delete_their_own_entry(self, client, register_user, sample_media_item):
        # The flip side of the two tests above — same route, same
        # shape of request, and it should just work for the actual owner.
        alice = register_user()
        entry = _log_entry(client, alice.headers, sample_media_item, note="before")

        updated = client.patch(f"/diary/{entry['id']}", json={"note": "after"}, headers=alice.headers)
        assert updated.status_code == 200
        assert updated.json()["note"] == "after"

        deleted = client.delete(f"/diary/{entry['id']}", headers=alice.headers)
        assert deleted.status_code == 204

        gone = client.get("/diary", headers=alice.headers)
        assert gone.json() == []

    def test_nonexistent_entry_id_is_404_not_500(self, client, register_user):
        alice = register_user()
        resp = client.patch(
            "/diary/00000000-0000-0000-0000-000000000000",
            json={"note": "doesn't matter"},
            headers=alice.headers,
        )
        assert resp.status_code == 404

    def test_diary_endpoints_require_auth(self, client):
        assert client.get("/diary").status_code == 401
        assert client.post("/diary", json={}).status_code == 401
