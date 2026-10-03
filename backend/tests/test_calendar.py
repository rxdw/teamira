"""app/routers/calendar.py — the Home screen's two release-calendar
blocks. Every adapter call is patched (AsyncMock) rather than hitting
TMDB/IGDB/Shikimori for real, same "no live network call in this suite"
convention test_media_detail.py's own module docstring follows.

GET /calendar/releases itself is not exercised through the live
TestClient anywhere below, deliberately — it caches via
cache.cached_dynamic(db=None, ...), the same "opens its own real,
independent session" shape GET /feed/collections and GET /feed/movies
already use, and no test in this suite calls those two directly either
(see tests/README.md on this). A db=None cache write commits for real,
straight to Postgres, outside this suite's per-test SAVEPOINT rollback
(see conftest.py::db_session's own docstring) — so hitting the live
endpoint here would leak a real "calendar:releases-v2" row that
outlives this test and silently short-circuits every later test in the
same run. _fetch_release_calendar (the merge/sort logic
cache.cached_dynamic wraps) is plain, cache-free `async def`, so it's
tested directly instead, the same way any other pure function would be.
"""
from __future__ import annotations

import asyncio
from datetime import date, timedelta
from unittest.mock import AsyncMock, patch

from app import models
from app.routers import calendar as calendar_module
from app.schemas import ExternalIds, LocalizedText, MediaItem


def _watchlist_entry(db_session, user_id: str, **overrides) -> models.WatchlistEntry:
    fields = dict(
        user_id=user_id,
        media_id="tmdb-100",
        media_type=models.MediaType.series,
        source="tmdb",
        title_ru="Тестовый сериал",
        title_en="Test Show",
        status=models.WatchStatus.watching,
    )
    fields.update(overrides)
    entry = models.WatchlistEntry(**fields)
    db_session.add(entry)
    db_session.commit()
    return entry


def _diary_entry(db_session, user_id: str, **overrides) -> models.DiaryEntry:
    fields = dict(
        user_id=user_id,
        media_id="tmdb-100",
        media_type=models.MediaType.series,
        source="tmdb",
        title_en="Test Show",
    )
    fields.update(overrides)
    entry = models.DiaryEntry(**fields)
    db_session.add(entry)
    db_session.commit()
    return entry


class TestWatchingReleasesSeries:
    def test_aired_unlogged_episode_is_out(self, client, register_user, db_session):
        """last_episode_to_air already aired and the user's diary hasn't
        reached it yet -> shows up with is_out=True."""
        user = register_user()
        _watchlist_entry(db_session, user.id)
        yesterday = (date.today() - timedelta(days=1)).isoformat()

        with patch(
            "app.routers.calendar._tmdb.next_episode",
            new_callable=AsyncMock,
            return_value={
                "last": {"air_date": yesterday, "season_number": 2, "episode_number": 5, "name": "Ep 5"},
                "next": None,
            },
        ):
            resp = client.get("/calendar/watching", headers=user.headers)
        assert resp.status_code == 200
        body = resp.json()
        assert len(body) == 1
        assert body[0]["is_out"] is True
        assert body[0]["season"] == 2
        assert body[0]["episode"] == 5
        assert body[0]["media_id"] == "tmdb-100"

    def test_already_logged_episode_is_excluded(self, client, register_user, db_session):
        """The user's own DiaryEntry is already at/past the aired
        episode -> not "news" to them, so it's left off the strip."""
        user = register_user()
        _watchlist_entry(db_session, user.id)
        _diary_entry(db_session, user.id, season=2, episode=5)
        yesterday = (date.today() - timedelta(days=1)).isoformat()

        with patch(
            "app.routers.calendar._tmdb.next_episode",
            new_callable=AsyncMock,
            return_value={
                "last": {"air_date": yesterday, "season_number": 2, "episode_number": 5, "name": "Ep 5"},
                "next": None,
            },
        ):
            resp = client.get("/calendar/watching", headers=user.headers)
        assert resp.status_code == 200
        assert resp.json() == []

    def test_upcoming_episode_is_not_out(self, client, register_user, db_session):
        user = register_user()
        _watchlist_entry(db_session, user.id)
        tomorrow = (date.today() + timedelta(days=1)).isoformat()

        with patch(
            "app.routers.calendar._tmdb.next_episode",
            new_callable=AsyncMock,
            return_value={
                "last": None,
                "next": {"air_date": tomorrow, "season_number": 2, "episode_number": 6, "name": "Ep 6"},
            },
        ):
            resp = client.get("/calendar/watching", headers=user.headers)
        assert resp.status_code == 200
        body = resp.json()
        assert len(body) == 1
        assert body[0]["is_out"] is False
        assert body[0]["episode"] == 6

    def test_watch_later_series_is_not_checked(self, client, register_user, db_session):
        """Only status == watching is checked for series/anime — see
        this module's own module docstring in app/routers/calendar.py."""
        user = register_user()
        _watchlist_entry(db_session, user.id, status=models.WatchStatus.watch_later)

        with patch(
            "app.routers.calendar._tmdb.next_episode", new_callable=AsyncMock,
        ) as mock_next:
            resp = client.get("/calendar/watching", headers=user.headers)
        assert resp.status_code == 200
        assert resp.json() == []
        assert not mock_next.called


class TestWatchingReleasesGames:
    def test_recently_released_game_is_out(self, client, register_user, db_session):
        user = register_user()
        _watchlist_entry(
            db_session, user.id,
            media_id="igdb-42", media_type=models.MediaType.game, source="igdb",
            title_en="Test Game", status=models.WatchStatus.watch_later,
        )
        release_date = (date.today() - timedelta(days=1)).isoformat()

        with patch(
            "app.routers.calendar._game_release_date", new_callable=AsyncMock, return_value=release_date,
        ):
            resp = client.get("/calendar/watching", headers=user.headers)
        assert resp.status_code == 200
        body = resp.json()
        assert len(body) == 1
        assert body[0]["is_out"] is True
        assert body[0]["source"] == "igdb"

    def test_old_release_falls_outside_the_news_window(self, client, register_user, db_session):
        user = register_user()
        _watchlist_entry(
            db_session, user.id,
            media_id="igdb-42", media_type=models.MediaType.game, source="igdb",
            title_en="Test Game", status=models.WatchStatus.watch_later,
        )
        long_ago = (date.today() - timedelta(days=30)).isoformat()

        with patch(
            "app.routers.calendar._game_release_date", new_callable=AsyncMock, return_value=long_ago,
        ):
            resp = client.get("/calendar/watching", headers=user.headers)
        assert resp.status_code == 200
        assert resp.json() == []


class TestFetchReleaseCalendar:
    """_fetch_release_calendar directly — see this module's own
    docstring for why the live GET /calendar/releases endpoint isn't
    exercised here."""

    def test_merges_and_sorts_all_three_sources(self):
        game_item = MediaItem(
            id="igdb-1", media_type="game", external_ids=ExternalIds(tmdb=None, imdb=None),
            title=LocalizedText(en="Some Game"), description=LocalizedText(en=""),
            source="igdb", release_date="2026-10-05",
        )
        movie_item = MediaItem(
            id="tmdb-1", media_type="movie", external_ids=ExternalIds(tmdb="1", imdb=None),
            title=LocalizedText(en="Some Movie"), description=LocalizedText(en=""),
            source="tmdb", release_date="2026-10-10",
        )
        with patch(
            "app.routers.calendar._shikimori.calendar", new_callable=AsyncMock,
            return_value=[{
                "shikimori_id": 5, "title_ru": "Аниме", "title_en": "Anime",
                "poster_url": None, "episode": 3,
                "air_at": "2026-10-01T09:00:00+03:00", "url": "https://shikimori.io/animes/5",
            }],
        ), patch(
            "app.routers.calendar._igdb.calendar", new_callable=AsyncMock, return_value=[game_item],
        ), patch(
            "app.routers.calendar._tmdb.upcoming_movies_calendar", new_callable=AsyncMock, return_value=[movie_item],
        ):
            items = asyncio.run(calendar_module._fetch_release_calendar())

        assert [i.source for i in items] == ["shikimori", "igdb", "tmdb"]
        assert items[0].media_type == "anime"
        assert items[0].item is None
        assert items[0].external_url == "https://shikimori.io/animes/5"
        assert items[1].item.id == "igdb-1"
        assert items[2].item.id == "tmdb-1"

    def test_one_failing_source_does_not_break_the_others(self):
        movie_item = MediaItem(
            id="tmdb-1", media_type="movie", external_ids=ExternalIds(tmdb="1", imdb=None),
            title=LocalizedText(en="Some Movie"), description=LocalizedText(en=""),
            source="tmdb", release_date="2026-10-10",
        )
        with patch(
            "app.routers.calendar._shikimori.calendar", new_callable=AsyncMock, side_effect=RuntimeError("boom"),
        ), patch(
            "app.routers.calendar._igdb.calendar", new_callable=AsyncMock, return_value=[],
        ), patch(
            "app.routers.calendar._tmdb.upcoming_movies_calendar", new_callable=AsyncMock, return_value=[movie_item],
        ):
            items = asyncio.run(calendar_module._fetch_release_calendar())

        assert len(items) == 1
        assert items[0].source == "tmdb"

    def test_rows_missing_a_title_or_a_date_are_dropped(self):
        """A Shikimori row with neither title -- or an IGDB/TMDB item
        with no release_date -- shouldn't produce an unusable card."""
        untitled_anime = {
            "shikimori_id": 9, "title_ru": None, "title_en": None,
            "poster_url": None, "episode": 1,
            "air_at": "2026-10-01T09:00:00+03:00", "url": "https://shikimori.io/animes/9",
        }
        dateless_game = MediaItem(
            id="igdb-2", media_type="game", external_ids=ExternalIds(tmdb=None, imdb=None),
            title=LocalizedText(en="No Date Game"), description=LocalizedText(en=""),
            source="igdb", release_date=None,
        )
        with patch(
            "app.routers.calendar._shikimori.calendar", new_callable=AsyncMock, return_value=[untitled_anime],
        ), patch(
            "app.routers.calendar._igdb.calendar", new_callable=AsyncMock, return_value=[dateless_game],
        ), patch(
            "app.routers.calendar._tmdb.upcoming_movies_calendar", new_callable=AsyncMock, return_value=[],
        ):
            items = asyncio.run(calendar_module._fetch_release_calendar())

        assert items == []


class TestReleaseCalendarGenres:
    """Every row carries `genres` for the calendar's genre filter: copied
    from item.genres for tmdb/igdb, from the Shikimori overlay for anime."""

    def test_genres_ride_along_on_every_source(self):
        movie_item = MediaItem(
            id="tmdb-1", media_type="movie", external_ids=ExternalIds(tmdb="1", imdb=None),
            title=LocalizedText(en="Some Movie"), description=LocalizedText(en=""),
            source="tmdb", release_date="2026-10-10", genres=["Horror", "Thriller"],
        )
        game_item = MediaItem(
            id="igdb-1", media_type="game", external_ids=ExternalIds(tmdb=None, imdb=None),
            title=LocalizedText(en="Some Game"), description=LocalizedText(en=""),
            source="igdb", release_date="2026-10-05", genres=["Shooter"],
        )
        with patch(
            "app.routers.calendar._shikimori.calendar", new_callable=AsyncMock,
            return_value=[{
                "shikimori_id": 5, "title_ru": "Аниме", "title_en": "Anime",
                "poster_url": None, "episode": 3, "genres": ["Action", "Science Fiction"],
                "air_at": "2026-10-01T09:00:00+03:00", "url": "https://shikimori.io/animes/5",
            }],
        ), patch(
            "app.routers.calendar._igdb.calendar", new_callable=AsyncMock, return_value=[game_item],
        ), patch(
            "app.routers.calendar._tmdb.upcoming_movies_calendar", new_callable=AsyncMock, return_value=[movie_item],
        ):
            items = asyncio.run(calendar_module._fetch_release_calendar())

        by_source = {i.source: i for i in items}
        assert by_source["shikimori"].genres == ["Action", "Science Fiction"]
        assert by_source["igdb"].genres == ["Shooter"]
        assert by_source["tmdb"].genres == ["Horror", "Thriller"]

    def test_anime_without_genre_overlay_gets_empty_list(self):
        with patch(
            "app.routers.calendar._shikimori.calendar", new_callable=AsyncMock,
            return_value=[{
                "shikimori_id": 5, "title_ru": None, "title_en": "Anime",
                "poster_url": None, "episode": 1,
                "air_at": "2026-10-01T09:00:00+03:00", "url": "https://shikimori.io/animes/5",
            }],
        ), patch(
            "app.routers.calendar._igdb.calendar", new_callable=AsyncMock, return_value=[],
        ), patch(
            "app.routers.calendar._tmdb.upcoming_movies_calendar", new_callable=AsyncMock, return_value=[],
        ):
            items = asyncio.run(calendar_module._fetch_release_calendar())
        assert items[0].genres == []


class TestShikimoriGenreNormalizing:
    def test_aliases_and_skips(self):
        from app.adapters.shikimori import _normalize_genres

        assert _normalize_genres([
            {"name": "Sci-Fi", "kind": "genre"},
            {"name": "Shounen", "kind": "demographic"},
            {"name": "Hentai", "kind": "genre"},
            {"name": "Action", "kind": "genre"},
            {"name": "Action", "kind": "genre"},
            {"name": "", "kind": "genre"},
        ]) == ["Science Fiction", "Action"]
