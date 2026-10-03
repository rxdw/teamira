"""Integration tests for the admin endpoints in app/routers/teamira.py
(routers/teamira.py's own docstring on TeamiraCollection explains what
these curated shelves are for). Scoped to the admin CRUD itself, not
GET /feed/teamira or /feed/today-pick — both of those, and the
franchise half of this module, pull live from TMDB/IGDB/Google
Books/Shikimori and aren't mocked here.

admin_add_item is testable without a real adapter call because
_resolve_manual_item checks the cache (app/cache.py::get_static_title)
before ever reaching out — so a cached row makes for a fully offline,
deterministic test of the same "warm cache" path production takes on
every add after the first."""

from app import cache, models
from app.schemas import ExternalIds, LocalizedText, MediaItem


def _make_admin(db_session, user_id: str) -> None:
    user = db_session.get(models.User, user_id)
    user.is_admin = True
    db_session.commit()


def _seed_cached_tmdb_item(db_session, raw_id: str, **overrides) -> MediaItem:
    fields = {
        "id": f"tmdb-{raw_id}",
        "media_type": "movie",
        "external_ids": ExternalIds(tmdb=raw_id),
        "title": LocalizedText(en="Cached Test Movie"),
        "description": LocalizedText(en="Pre-seeded so admin_add_item never has to call a real adapter."),
        "source": "tmdb",
    }
    fields.update(overrides)
    item = MediaItem(**fields)
    # Mirrors exactly what _resolve_manual_item itself caches on a real
    # (cold-cache) adapter hit — a MediaItem instance, not a pre-dumped
    # JSON string; cache.set_static_title does its own serialization
    # (see app/cache.py::_dump_json), so double-encoding it here would
    # leave cache.get_static_title returning a JSON string *of* a JSON
    # string instead of the object MediaItem.model_validate_json expects.
    cache.set_static_title(db_session, raw_id, "tmdb-v2", item)
    return item


class TestAdminGating:
    def test_non_admin_gets_403(self, client, register_user):
        someone = register_user()
        resp = client.get("/teamira/admin/collections", headers=someone.headers)
        assert resp.status_code == 403

    def test_unauthenticated_gets_401_not_403(self, client):
        # get_current_user runs first (require_admin_user depends on it)
        # — no token should fail on "who are you", not "you're not an
        # admin".
        resp = client.get("/teamira/admin/collections")
        assert resp.status_code == 401

    def test_admin_flag_grants_access(self, client, register_user, db_session):
        admin = register_user()
        _make_admin(db_session, admin.id)
        resp = client.get("/teamira/admin/collections", headers=admin.headers)
        assert resp.status_code == 200


class TestCollectionCrud:
    def test_create_then_list(self, client, register_user, db_session):
        admin = register_user()
        _make_admin(db_session, admin.id)

        created = client.post(
            "/teamira/admin/collections", json={"title": "Top 10 of 2020"}, headers=admin.headers
        )
        assert created.status_code == 201
        body = created.json()
        assert body["title"] == "Top 10 of 2020"
        assert body["items"] == []

        listed = client.get("/teamira/admin/collections", headers=admin.headers)
        assert any(c["id"] == body["id"] for c in listed.json())

    def test_rename(self, client, register_user, db_session):
        admin = register_user()
        _make_admin(db_session, admin.id)
        created = client.post(
            "/teamira/admin/collections", json={"title": "Working Title"}, headers=admin.headers
        ).json()

        renamed = client.patch(
            f"/teamira/admin/collections/{created['id']}",
            json={"title": "Final Title", "title_en": "Final Title (EN)"},
            headers=admin.headers,
        )
        assert renamed.status_code == 200
        assert renamed.json()["title"] == "Final Title"
        assert renamed.json()["title_en"] == "Final Title (EN)"

    def test_rename_nonexistent_collection_is_404(self, client, register_user, db_session):
        admin = register_user()
        _make_admin(db_session, admin.id)
        resp = client.patch(
            "/teamira/admin/collections/00000000-0000-0000-0000-000000000000",
            json={"title": "x"},
            headers=admin.headers,
        )
        assert resp.status_code == 404

    def test_delete_removes_it_from_the_list(self, client, register_user, db_session):
        admin = register_user()
        _make_admin(db_session, admin.id)
        created = client.post(
            "/teamira/admin/collections", json={"title": "Temporary"}, headers=admin.headers
        ).json()

        deleted = client.delete(f"/teamira/admin/collections/{created['id']}", headers=admin.headers)
        assert deleted.status_code == 204

        listed = client.get("/teamira/admin/collections", headers=admin.headers).json()
        assert all(c["id"] != created["id"] for c in listed)


class TestCollectionItems:
    def test_add_a_cached_item_and_see_it_in_the_collection(self, client, register_user, db_session):
        admin = register_user()
        _make_admin(db_session, admin.id)
        _seed_cached_tmdb_item(db_session, "603")
        collection = client.post(
            "/teamira/admin/collections", json={"title": "Sci-Fi Picks"}, headers=admin.headers
        ).json()

        added = client.post(
            f"/teamira/admin/collections/{collection['id']}/items",
            json={"media_id": "tmdb-603", "media_type": "movie", "source": "tmdb"},
            headers=admin.headers,
        )
        assert added.status_code == 200
        items = added.json()["items"]
        assert len(items) == 1
        assert items[0]["media_id"] == "tmdb-603"

    def test_invalid_media_type_is_rejected(self, client, register_user, db_session):
        admin = register_user()
        _make_admin(db_session, admin.id)
        collection = client.post(
            "/teamira/admin/collections", json={"title": "x"}, headers=admin.headers
        ).json()

        resp = client.post(
            f"/teamira/admin/collections/{collection['id']}/items",
            json={"media_id": "tmdb-603", "media_type": "not-a-real-type", "source": "tmdb"},
            headers=admin.headers,
        )
        assert resp.status_code == 400

    def test_unreachable_adapter_is_a_clean_502_not_a_crash(self, client, register_user, db_session):
        # No cache row seeded, and this sandbox has no route to the real
        # TMDB API — so _tmdb.item_detail() raises httpx.HTTPError, which
        # main.py's own app-wide httpx_error_handler turns into a clean
        # 502 rather than a bare 500. (A genuine "TMDB says no such id"
        # 404 needs real network access to provoke — not something this
        # sandboxed test run can exercise — but this at least proves an
        # unreachable adapter fails safely rather than crashing.)
        admin = register_user()
        _make_admin(db_session, admin.id)
        collection = client.post(
            "/teamira/admin/collections", json={"title": "x"}, headers=admin.headers
        ).json()

        resp = client.post(
            f"/teamira/admin/collections/{collection['id']}/items",
            json={"media_id": "tmdb-999999999-not-cached", "media_type": "movie", "source": "tmdb"},
            headers=admin.headers,
        )
        assert resp.status_code == 502

    def test_duplicate_item_in_the_same_collection_is_409(self, client, register_user, db_session):
        admin = register_user()
        _make_admin(db_session, admin.id)
        _seed_cached_tmdb_item(db_session, "603")
        collection = client.post(
            "/teamira/admin/collections", json={"title": "x"}, headers=admin.headers
        ).json()
        payload = {"media_id": "tmdb-603", "media_type": "movie", "source": "tmdb"}
        client.post(f"/teamira/admin/collections/{collection['id']}/items", json=payload, headers=admin.headers)

        dup = client.post(f"/teamira/admin/collections/{collection['id']}/items", json=payload, headers=admin.headers)
        assert dup.status_code == 409

    def test_remove_an_item(self, client, register_user, db_session):
        admin = register_user()
        _make_admin(db_session, admin.id)
        _seed_cached_tmdb_item(db_session, "603")
        collection = client.post(
            "/teamira/admin/collections", json={"title": "x"}, headers=admin.headers
        ).json()
        with_item = client.post(
            f"/teamira/admin/collections/{collection['id']}/items",
            json={"media_id": "tmdb-603", "media_type": "movie", "source": "tmdb"},
            headers=admin.headers,
        ).json()
        item_id = with_item["items"][0]["id"]

        removed = client.delete(
            f"/teamira/admin/collections/{collection['id']}/items/{item_id}", headers=admin.headers
        )
        assert removed.status_code == 200
        assert removed.json()["items"] == []

    def test_removing_an_item_from_the_wrong_collection_is_404(self, client, register_user, db_session):
        admin = register_user()
        _make_admin(db_session, admin.id)
        _seed_cached_tmdb_item(db_session, "603")
        collection_a = client.post(
            "/teamira/admin/collections", json={"title": "A"}, headers=admin.headers
        ).json()
        collection_b = client.post(
            "/teamira/admin/collections", json={"title": "B"}, headers=admin.headers
        ).json()
        with_item = client.post(
            f"/teamira/admin/collections/{collection_a['id']}/items",
            json={"media_id": "tmdb-603", "media_type": "movie", "source": "tmdb"},
            headers=admin.headers,
        ).json()
        item_id = with_item["items"][0]["id"]

        # item_id genuinely exists, just not under collection_b.
        resp = client.delete(
            f"/teamira/admin/collections/{collection_b['id']}/items/{item_id}", headers=admin.headers
        )
        assert resp.status_code == 404
