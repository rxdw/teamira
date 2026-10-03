"""Integration tests for app/routers/media.py's GET /detail — the "single
most-visited screen after Home" per that route's own docstring. Testable
offline the same way teamira.py's admin_add_item is: media_detail checks
app/cache.py::get_static_title before ever calling out to TMDB/IGDB/etc.,
so a pre-seeded cache row exercises the exact same warm-cache path
production takes on every view after the first, with no live adapter
call. /media/search, /media/episodes, and /media/person, and a cold
(uncached) /media/detail call, all still need a real adapter and aren't
covered here — see tests/README.md.
"""

from app import cache
from app.schemas import ExternalIds, LocalizedText, MediaDetailOut, MediaItem, RatingsOut


def _seed_cached_detail(db_session, raw_tmdb_id: str, **item_overrides) -> MediaDetailOut:
    item_fields = {
        "id": f"tmdb-{raw_tmdb_id}",
        "media_type": "movie",
        "external_ids": ExternalIds(tmdb=raw_tmdb_id),
        "title": LocalizedText(en="Cached Detail Movie"),
        "description": LocalizedText(en="Pre-seeded for an offline /media/detail test."),
        "source": "tmdb",
    }
    item_fields.update(item_overrides)
    detail = MediaDetailOut(item=MediaItem(**item_fields), ratings=RatingsOut(tmdb_rating=8.1, tmdb_votes=4200))
    # Same cache row shape media_detail itself writes on a cold TMDB hit
    # — see that route's own "tmdb-detail-v2" cache_source constant.
    cache.set_static_title(db_session, f"tmdb-{raw_tmdb_id}", "tmdb-detail-v2", detail)
    return detail


class TestMediaDetailFromCache:
    def test_cached_tmdb_detail_is_served_without_a_live_call(self, client, register_user, db_session):
        user = register_user()
        _seed_cached_detail(db_session, "603")

        resp = client.get(
            "/media/detail",
            params={"media_id": "tmdb-603", "media_type": "movie", "source": "tmdb"},
            headers=user.headers,
        )
        assert resp.status_code == 200
        body = resp.json()
        assert body["item"]["id"] == "tmdb-603"
        assert body["item"]["title"]["en"] == "Cached Detail Movie"
        assert body["ratings"]["tmdb_rating"] == 8.1

    def test_unknown_source_is_404(self, client, register_user):
        user = register_user()
        resp = client.get(
            "/media/detail",
            params={"media_id": "x-1", "media_type": "movie", "source": "not-a-real-source"},
            headers=user.headers,
        )
        assert resp.status_code == 404

    def test_malformed_tmdb_id_is_400(self, client, register_user):
        user = register_user()
        # No "tmdb-" prefix on the id — same "can't even tell what to
        # look up" case media_detail itself special-cases.
        resp = client.get(
            "/media/detail",
            params={"media_id": "603", "media_type": "movie", "source": "tmdb"},
            headers=user.headers,
        )
        assert resp.status_code == 400

    def test_requires_auth(self, client, db_session):
        # media_detail proxies TMDB (a metered third-party API) on every
        # uncached call, so — unlike some purely-internal reads — it now
        # requires a logged-in caller (get_current_user_id) same as
        # /media/search, /media/episodes, /media/person, and
        # /media/reviews. No Authorization header at all -> 401, not a
        # served response, even for a title that's already cached.
        _seed_cached_detail(db_session, "42")
        resp = client.get("/media/detail", params={"media_id": "tmdb-42", "media_type": "movie", "source": "tmdb"})
        assert resp.status_code == 401
