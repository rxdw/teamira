"""Kinopoisk (ПоискКино) source — parsing, quota/outage handling, the
"don't cache a failure" rule, and how it reaches /media/reviews and
/media/detail.

Fixture payloads are trimmed copies of real responses from
api.poiskkino.dev/v1.5 (Interstellar), including the awkward parts: an
empty review `title`, `userRating` of 0, long multi-paragraph text with
\\r\\n, and a rating with three decimals.

Nothing here touches the network — the adapter's HTTP client is swapped
for httpx.MockTransport. The cache tests use the real Postgres-backed
cache (cache.cached_dynamic opens its own sessions), so they clean up
the `kp:` rows they create.
"""

import asyncio
from datetime import datetime, timezone

import httpx
import pytest
from sqlalchemy import text

from app import cache, kinopoisk
from app.adapters import poiskkino as pk
from app.config import settings
from app.database import engine
from app.routers import media as media_router
from app.routers import reviews as reviews_router
from app.schemas import ExternalIds, LocalizedText, MediaDetailOut, MediaItem, RatingsOut
from app.schemas import TmdbReviewOut, TmdbReviewsOut

MOVIE_DOC = {
    "id": 258687,
    "year": 2014,
    "isSeries": False,
    "type": "movie",
    "name": "Интерстеллар",
    "rating": {"filmCritics": 7.1, "imdb": 8.7, "kp": 8.685, "russianFilmCritics": 80.6452},
    "votes": {"filmCritics": 373, "imdb": 2500000, "kp": 1198020, "russianFilmCritics": 31},
}
SERIES_DOC_SAME_TMDB_ID = {
    "id": 999001,
    "isSeries": True,
    "type": "tv-series",
    "rating": {"kp": 7.4, "imdb": 0},
    "votes": {"kp": 5100, "imdb": 0},
}

LONG_PARAGRAPH = "Нолан снял это так, что космос ощущается физически. " * 40
REVIEW_DOCS = [
    {  # long, positive, no headline, reviewer gave no score
        "id": 3701227, "author": "Ерошкин Владислав", "title": "", "type": "Позитивный",
        "userRating": 0, "reviewLikes": 7, "reviewDislikes": 1,
        "review": "Первый абзац.\r\n\r\n\r\n\r\n" + LONG_PARAGRAPH,
        "date": "2026-08-29T13:43:56.000Z", "createdAt": "2026-09-03T17:58:29.278Z",
    },
    {  # has a headline and likes
        "id": 3662294, "author": "Vera Iurieva", "title": "Движение — это суть жизни",
        "type": "Позитивный", "userRating": 0, "reviewLikes": 16, "reviewDislikes": 0,
        "review": "Недавно я ходила на концерт симфонического оркестра и пересмотрела фильм.",
        "date": "2026-05-26T06:47:23.000Z",
    },
    {  # too short to be a review
        "id": 1, "author": "x", "title": "", "type": "Негативный", "review": "ну такое",
        "date": "2026-01-01T00:00:00.000Z",
    },
    {  # negative, reviewer score present
        "id": 2, "author": "Дарья", "title": "Красиво, но затянуто", "type": "Негативный",
        "userRating": 5, "reviewLikes": 2, "reviewDislikes": 9,
        "review": "Визуально потрясающе, но три часа пояснений про гравитацию — это испытание.",
        "date": "2026-02-01T00:00:00.000Z",
    },
]


@pytest.fixture(autouse=True)
def _kp_env(monkeypatch):
    monkeypatch.setattr(settings, "poiskkino_api_key", "test-key")
    monkeypatch.setattr(settings, "poiskkino_daily_budget", 180)
    pk._guard.reset()
    yield
    pk._guard.reset()


@pytest.fixture()
def clean_kp_cache():
    yield
    with engine.begin() as conn:
        conn.execute(text("DELETE FROM cached_feed_snapshots WHERE cache_key LIKE 'kp:%' OR cache_key LIKE 'reviews:kptest%'"))


def _mock_http(monkeypatch, handler):
    real = httpx.AsyncClient
    monkeypatch.setattr(pk.httpx, "AsyncClient", lambda **kw: real(transport=httpx.MockTransport(handler), **kw))


# --- parsing ---------------------------------------------------------------

class TestParsing:
    def test_title_rounds_rating_and_keeps_votes(self):
        t = pk.parse_title(MOVIE_DOC)
        assert (t.kp_id, t.year, t.kp_rating, t.kp_votes) == (258687, 2014, 8.7, 1198020)
        assert (t.imdb_rating, t.imdb_votes) == (8.7, 2500000)

    def test_zero_rating_means_unknown(self):
        t = pk.parse_title(SERIES_DOC_SAME_TMDB_ID)
        assert t.kp_rating == 7.4
        assert t.imdb_rating is None and t.imdb_votes is None

    def test_reviews_clean_filter_and_map(self):
        reviews = {r.id: r for r in pk.parse_reviews(REVIEW_DOCS)}
        assert 1 not in reviews  # too short
        first = reviews[3701227]
        assert first.title is None  # "" -> None
        assert first.rating is None  # userRating 0 -> no score
        assert first.tone == "positive"
        assert "\r" not in first.text and "\n\n\n" not in first.text
        assert len(first.text) <= pk.MAX_REVIEW_CHARS + 1 and first.text.endswith("…")
        assert reviews[2].rating == 5.0 and reviews[2].tone == "negative"
        assert reviews[3662294].title == "Движение — это суть жизни"
        assert first.created_at == datetime(2026, 8, 29, 13, 43, 56, tzinfo=timezone.utc)

    def test_ranking_prefers_useful_over_new(self):
        ranked = pk.rank_reviews(pk.parse_reviews(REVIEW_DOCS))
        assert [r.id for r in ranked] == [3662294, 3701227, 2]  # net likes 16, 6, -7

    def test_truncate_prefers_sentence_end_and_never_cuts_mid_word(self):
        text_ = ("Слово " * 200).strip()
        cut = pk.truncate(text_, 100)
        assert cut.endswith("…") and not cut[:-1].endswith("Сло")
        sentence = ("Это предложение. " * 20).strip()
        assert pk.truncate(sentence, 100).endswith("предложение.…")
        assert pk.truncate("коротко", 100) == "коротко"


# --- adapter: HTTP behaviour -----------------------------------------------

class TestAdapter:
    def test_find_title_picks_the_matching_kind(self, monkeypatch):
        seen = {}

        def handler(request: httpx.Request):
            seen["key"] = request.headers.get("x-api-key")
            seen["params"] = dict(request.url.params)
            return httpx.Response(200, json={"docs": [SERIES_DOC_SAME_TMDB_ID, MOVIE_DOC]})

        _mock_http(monkeypatch, handler)
        adapter = pk.PoiskKinoAdapter()
        movie = asyncio.run(adapter.find_title("157336", is_series=False))
        series = asyncio.run(adapter.find_title("157336", is_series=True))
        assert movie.kp_id == 258687 and series.kp_id == 999001
        assert seen["key"] == "test-key"  # header, never in the URL
        assert seen["params"]["externalId.tmdb"] == "157336"

    def test_unknown_title_is_missing_not_an_error(self, monkeypatch):
        _mock_http(monkeypatch, lambda r: httpx.Response(200, json={"docs": []}))
        assert asyncio.run(pk.PoiskKinoAdapter().find_title("1", False)).missing is True

    def test_no_key_means_unavailable_and_no_request(self, monkeypatch):
        monkeypatch.setattr(settings, "poiskkino_api_key", "")
        _mock_http(monkeypatch, lambda r: pytest.fail("must not call out without a key"))
        with pytest.raises(pk.KpUnavailable):
            asyncio.run(pk.PoiskKinoAdapter().find_title("1", False))

    @pytest.mark.parametrize("status", [429, 401, 403, 500, 503])
    def test_errors_raise_and_pause_further_calls(self, monkeypatch, status):
        calls = []

        def handler(request):
            calls.append(1)
            return httpx.Response(status, json={})

        _mock_http(monkeypatch, handler)
        adapter = pk.PoiskKinoAdapter()
        with pytest.raises(pk.KpUnavailable):
            asyncio.run(adapter.find_title("1", False))
        with pytest.raises(pk.KpUnavailable):  # paused: no second request
            asyncio.run(adapter.find_title("2", False))
        assert len(calls) == 1

    def test_network_failure_raises_and_pauses(self, monkeypatch):
        def handler(request):
            raise httpx.ConnectError("Connection was reset")

        _mock_http(monkeypatch, handler)
        adapter = pk.PoiskKinoAdapter()
        with pytest.raises(pk.KpUnavailable):
            asyncio.run(adapter.find_title("1", False))
        assert pk._guard.allow() is False

    def test_daily_budget_stops_requests(self, monkeypatch):
        monkeypatch.setattr(settings, "poiskkino_daily_budget", 2)
        calls = []

        def handler(request):
            calls.append(1)
            return httpx.Response(200, json={"docs": []})

        _mock_http(monkeypatch, handler)
        adapter = pk.PoiskKinoAdapter()
        asyncio.run(adapter.find_title("1", False))
        asyncio.run(adapter.find_title("2", False))
        with pytest.raises(pk.KpUnavailable):
            asyncio.run(adapter.find_title("3", False))
        assert len(calls) == 2


# --- service: how long things are cached ----------------------------------

class TestCacheLifetimes:
    NOW = datetime(2026, 10, 5, tzinfo=timezone.utc)

    def test_recent_means_less_than_a_year_old(self):
        # years are taken as 1 July of that year
        assert kinopoisk.is_recent(2026, self.NOW)       # ~3 months
        assert not kinopoisk.is_recent(2025, self.NOW)   # ~15 months
        assert not kinopoisk.is_recent(2014, self.NOW)
        assert kinopoisk.is_recent(2027, self.NOW)       # announced, not out yet
        assert kinopoisk.is_recent(None, self.NOW)       # unknown -> fresher side
        # the cut-off moves with the calendar
        assert kinopoisk.is_recent(2026, datetime(2027, 6, 1, tzinfo=timezone.utc))
        assert not kinopoisk.is_recent(2026, datetime(2027, 8, 1, tzinfo=timezone.utc))

    def test_ttl_follows_age_and_missing(self):
        new = pk.KpTitle(kp_id=1, year=datetime.now(timezone.utc).year).model_dump_json()
        old = pk.KpTitle(kp_id=2, year=2014).model_dump_json()
        missing = pk.KpTitle(missing=True).model_dump_json()
        assert kinopoisk._title_ttl(new).days == 21
        assert kinopoisk._title_ttl(old).days == 120
        assert kinopoisk._title_ttl(missing).days == 7
        assert kinopoisk._title_ttl(None).days == 21          # nothing stored yet
        assert kinopoisk._title_ttl("not json").days == 21    # unreadable copy
        assert kinopoisk._reviews_ttl(pk.KpTitle(kp_id=1, year=datetime.now(timezone.utc).year)).days == 14
        assert kinopoisk._reviews_ttl(pk.KpTitle(kp_id=2, year=2014)).days == 90


# --- service: what gets cached ---------------------------------------------

class TestServiceCaching:
    def test_found_title_is_cached_and_costs_one_request(self, monkeypatch, clean_kp_cache):
        calls = []

        def handler(request):
            calls.append(request.url.path)
            return httpx.Response(200, json={"docs": [MOVIE_DOC]})

        _mock_http(monkeypatch, handler)
        first = asyncio.run(kinopoisk.get_title("kptest1", False))
        second = asyncio.run(kinopoisk.get_title("kptest1", False))
        assert first.kp_id == second.kp_id == 258687
        assert len(calls) == 1

    def test_not_on_kinopoisk_is_cached_too(self, monkeypatch, clean_kp_cache):
        calls = []

        def handler(request):
            calls.append(1)
            return httpx.Response(200, json={"docs": []})

        _mock_http(monkeypatch, handler)
        assert asyncio.run(kinopoisk.get_title("kptest2", False)) is None
        assert asyncio.run(kinopoisk.get_title("kptest2", False)) is None
        assert len(calls) == 1

    def test_a_failure_is_not_remembered(self, monkeypatch, clean_kp_cache):
        state = {"status": 500}

        def handler(request):
            if state["status"] != 200:
                return httpx.Response(state["status"], json={})
            return httpx.Response(200, json={"docs": [MOVIE_DOC]})

        _mock_http(monkeypatch, handler)
        assert asyncio.run(kinopoisk.get_title("kptest3", False)) is None  # outage
        pk._guard.reset()  # time passes, the pause ends
        state["status"] = 200
        recovered = asyncio.run(kinopoisk.get_title("kptest3", False))
        assert recovered is not None and recovered.kp_id == 258687

    def test_expired_copy_is_served_when_the_refresh_fails(self, monkeypatch, clean_kp_cache):
        from datetime import timedelta

        state = {"ok": True}

        def handler(request):
            if not state["ok"]:
                return httpx.Response(500, json={})
            return httpx.Response(200, json={"docs": [MOVIE_DOC]})

        _mock_http(monkeypatch, handler)
        assert asyncio.run(kinopoisk.get_title("kptest5", False)).kp_id == 258687
        # Everything cached is now older than its TTL, and the API is down.
        monkeypatch.setattr(kinopoisk, "KP_TITLE_TTL_CLASSIC", timedelta(seconds=-1))  # 2014 -> classic
        state["ok"] = False
        pk._guard.reset()
        stale = asyncio.run(kinopoisk.get_title("kptest5", False))
        assert stale is not None and stale.kp_id == 258687

    def test_reviews_reuse_the_cached_title_match(self, monkeypatch, clean_kp_cache):
        paths = []

        def handler(request):
            paths.append(request.url.path)
            if request.url.path.endswith("/movie"):
                return httpx.Response(200, json={"docs": [MOVIE_DOC]})
            assert request.url.params["movieId"] == "258687"
            return httpx.Response(200, json={"docs": REVIEW_DOCS})

        _mock_http(monkeypatch, handler)
        asyncio.run(kinopoisk.get_title("kptest4", False))
        reviews = asyncio.run(kinopoisk.get_reviews("kptest4", False))
        assert [r.id for r in reviews][0] == 3662294
        asyncio.run(kinopoisk.get_reviews("kptest4", False))
        assert paths.count("/v1.5/movie") == 1 and paths.count("/v1.5/review") == 1


# --- routers -----------------------------------------------------------------

def _kp_review(**kw):
    base = dict(id=7, author="Vera", title="Заголовок", text="Текст рецензии, достаточно длинный.",
                tone="positive", rating=None, likes=3, dislikes=0,
                created_at=datetime(2026, 5, 1, tzinfo=timezone.utc))
    base.update(kw)
    return pk.KpReview(**base)


def _trakt_only():
    return TmdbReviewsOut(reviews=[TmdbReviewOut(
        author="maple", content="Visually stunning, and the score does half the work.",
        url="https://trakt.tv/comments/1", source="trakt",
    )])


class TestReviewsEndpoint:
    @pytest.fixture()
    def patched(self, monkeypatch):
        async def fake_fetch(tmdb_id, segment):
            return _trakt_only()

        async def fake_title(tmdb_id, is_series):
            return pk.KpTitle(kp_id=258687, is_series=is_series, kp_rating=8.7)

        async def fake_reviews(tmdb_id, is_series):
            return [_kp_review()]

        monkeypatch.setattr(reviews_router, "fetch_reviews", fake_fetch)
        monkeypatch.setattr(kinopoisk, "get_title", fake_title)
        monkeypatch.setattr(kinopoisk, "get_reviews", fake_reviews)

    def test_ru_gets_kinopoisk_first_with_its_extras(self, client, register_user, patched, clean_kp_cache):
        user = register_user()
        resp = client.get("/media/reviews", params={"media_type": "movie", "tmdb_id": "kptest10", "lang": "ru"},
                          headers=user.headers)
        assert resp.status_code == 200
        body = resp.json()
        assert [r["source"] for r in body["reviews"]] == ["kinopoisk", "trakt"]
        kp = body["reviews"][0]
        assert (kp["title"], kp["tone"], kp["likes"]) == ("Заголовок", "positive", 3)
        assert kp["url"] == "https://www.kinopoisk.ru/film/258687/reviews/"
        assert "Кинопоиск" in body["attribution"]

    def test_series_link_uses_the_series_path(self, client, register_user, patched, clean_kp_cache):
        user = register_user()
        resp = client.get("/media/reviews", params={"media_type": "series", "tmdb_id": "kptest11", "lang": "ru"},
                          headers=user.headers)
        assert resp.json()["reviews"][0]["url"] == "https://www.kinopoisk.ru/series/258687/reviews/"

    def test_english_never_touches_kinopoisk(self, client, register_user, monkeypatch, clean_kp_cache):
        async def fake_fetch(tmdb_id, segment):
            return _trakt_only()

        async def boom(*a, **k):
            pytest.fail("English callers must not trigger Kinopoisk requests")

        monkeypatch.setattr(reviews_router, "fetch_reviews", fake_fetch)
        monkeypatch.setattr(kinopoisk, "get_title", boom)
        monkeypatch.setattr(kinopoisk, "get_reviews", boom)
        user = register_user()
        resp = client.get("/media/reviews", params={"media_type": "movie", "tmdb_id": "kptest12"},
                          headers=user.headers)
        assert [r["source"] for r in resp.json()["reviews"]] == ["trakt"]
        assert "Кинопоиск" not in resp.json()["attribution"]

    def test_ru_falls_back_cleanly_when_kinopoisk_has_nothing(self, client, register_user, monkeypatch, clean_kp_cache):
        async def fake_fetch(tmdb_id, segment):
            return _trakt_only()

        async def none_reviews(tmdb_id, is_series):
            return []

        monkeypatch.setattr(reviews_router, "fetch_reviews", fake_fetch)
        monkeypatch.setattr(kinopoisk, "get_reviews", none_reviews)
        user = register_user()
        resp = client.get("/media/reviews", params={"media_type": "movie", "tmdb_id": "kptest13", "lang": "ru"},
                          headers=user.headers)
        assert [r["source"] for r in resp.json()["reviews"]] == ["trakt"]


def _detail(ratings=None, media_type="movie"):
    return MediaDetailOut(
        item=MediaItem(id="tmdb-157336", media_type=media_type, external_ids=ExternalIds(tmdb="157336"),
                       title=LocalizedText(en="Interstellar"), description=LocalizedText(en="x"), source="tmdb"),
        ratings=ratings,
    )


class TestDetailRatings:
    @pytest.fixture()
    def patched(self, monkeypatch):
        async def fake_title(tmdb_id, is_series):
            return pk.KpTitle(kp_id=258687, kp_rating=8.7, kp_votes=1198020, imdb_rating=8.7, imdb_votes=2500000)

        async def fake_reviews(tmdb_id, is_series):
            return [_kp_review(), _kp_review(id=8)]

        monkeypatch.setattr(kinopoisk, "get_title", fake_title)
        monkeypatch.setattr(kinopoisk, "get_reviews", fake_reviews)

    def test_ru_adds_ratings_and_counts_kinopoisk_reviews(self, patched):
        result = _detail(RatingsOut(tmdb_rating=8.5, tmdb_votes=38000, reviews_count=5))
        asyncio.run(media_router._apply_kinopoisk(result, "ru"))
        r = result.ratings
        assert (r.kp_rating, r.kp_votes, r.imdb_rating, r.imdb_votes) == (8.7, 1198020, 8.7, 2500000)
        assert r.reviews_count == 7 and r.tmdb_rating == 8.5

    def test_ratings_block_is_created_when_tmdb_had_none(self, patched):
        result = _detail(None)
        asyncio.run(media_router._apply_kinopoisk(result, "ru"))
        assert result.ratings.kp_rating == 8.7

    def test_english_and_non_video_are_untouched(self, patched):
        for lang, media_type in (("en", "movie"), ("ru", "game")):
            result = _detail(RatingsOut(tmdb_rating=8.5), media_type=media_type)
            asyncio.run(media_router._apply_kinopoisk(result, lang))
            assert result.ratings.kp_rating is None

    def test_a_miss_leaves_everything_as_it_was(self, monkeypatch):
        async def nothing(tmdb_id, is_series):
            return None

        monkeypatch.setattr(kinopoisk, "get_title", nothing)
        result = _detail(RatingsOut(tmdb_rating=8.5, reviews_count=5))
        asyncio.run(media_router._apply_kinopoisk(result, "ru"))
        assert result.ratings.kp_rating is None and result.ratings.reviews_count == 5

    def test_kinopoisk_numbers_never_reach_the_forever_cache(self, patched):
        """The cached copy is written before _apply_kinopoisk runs, so a
        serialized-then-reloaded detail has no Kinopoisk fields."""
        cached = _detail(RatingsOut(tmdb_rating=8.5))
        stored = MediaDetailOut.model_validate_json(cache._dump_json(cached))
        assert stored.ratings.kp_rating is None
