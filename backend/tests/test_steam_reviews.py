"""Steam reviews for games — parsing, request shape, outage handling, the
"don't cache a failure" rule, and how the list reaches /media/reviews and the
title screen's rating row.

The sample payload mirrors a real answer captured from
store.steampowered.com/appreviews/1245620?language=russian (fields kept as
they come; text shortened). No network: the adapter's HTTP client is swapped
for httpx.MockTransport. Cache tests use the real Postgres-backed cache and
clean up their rows.
"""

import asyncio

import httpx
import pytest
from sqlalchemy import text

from app import game_reviews
from app.adapters import steam_reviews as sr
from app.database import engine
from app.routers import reviews as reviews_router

LONG = "Отличная игра, очень атмосферная, огромный открытый мир, ни капли не жалею о потраченном времени. "

REVIEW = {
    "recommendationid": "234685081",
    "author": {
        "steamid": "76561198075594785", "personaname": "PinkieSmiler",
        "playtime_forever": 10252, "playtime_at_review": 10252,
        "avatar": "1f74f17d63a3f539430cb2b962582b24cc22021c",
    },
    "language": "russian", "review": LONG, "voted_up": True, "votes_up": 20,
    "timestamp_created": 1788773428, "refunded": False,
}
SUMMARY = {"success": 1, "query_summary": {"num_reviews": 1, "total_positive": 42571, "total_negative": 6163}, "reviews": []}


def _texts(*reviews):
    return {"success": 1, "query_summary": {"num_reviews": len(reviews)}, "reviews": list(reviews)}


@pytest.fixture(autouse=True)
def _guard():
    sr._guard.reset()
    yield
    sr._guard.reset()


@pytest.fixture()
def clean_cache():
    yield
    with engine.begin() as conn:
        conn.execute(text(
            "DELETE FROM cached_feed_snapshots WHERE cache_key LIKE 'steam:appid:9990%' "
            "OR cache_key LIKE 'steam:reviews:9990%'"
        ))


def _mock_http(monkeypatch, handler):
    real = httpx.AsyncClient
    monkeypatch.setattr(sr.httpx, "AsyncClient", lambda **kw: real(transport=httpx.MockTransport(handler), **kw))


class TestParsing:
    def test_review_fields(self):
        [r] = sr.parse_reviews("1245620", _texts(REVIEW))
        assert r.author == "PinkieSmiler" and r.voted_up is True and r.votes_up == 20
        assert r.playtime_hours == 170.9  # 10252 minutes
        assert r.url == "https://steamcommunity.com/profiles/76561198075594785/recommended/1245620/"
        assert r.avatar_url.endswith("1f74f17d63a3f539430cb2b962582b24cc22021c_full.jpg")
        assert r.created_at.year == 2026

    def test_short_and_refunded_reviews_are_dropped(self):
        short = {**REVIEW, "review": "норм"}
        refunded = {**REVIEW, "refunded": True}
        assert sr.parse_reviews("1", _texts(short, refunded)) == []

    def test_markup_and_spoilers_are_stripped(self):
        raw = "[h1]Итог[/h1] [b]Хорошая[/b] игра, [spoiler]финал грустный[/spoiler] " + LONG
        text_ = sr.clean_review_text(raw)
        assert "[" not in text_ and "финал грустный" not in text_
        assert text_.startswith("Итог Хорошая игра")

    def test_long_review_is_cut_at_a_word_boundary(self):
        out = sr.clean_review_text("слово " * 1000)
        assert len(out) <= sr.MAX_CHARS + 1 and out.endswith("…")

    def test_author_without_name_falls_back(self):
        noname = {**REVIEW, "author": {**REVIEW["author"], "personaname": ""}}
        assert sr.parse_reviews("1", _texts(noname))[0].author == "Steam"

    def test_positive_share(self):
        m = sr.SteamReviews(total_positive=42571, total_negative=6163)
        assert m.positive_pct == 87 and m.total == 48734
        assert sr.SteamReviews().positive_pct is None


class TestAdapter:
    def test_two_requests_totals_then_texts_in_the_readers_language(self, monkeypatch):
        calls = []

        def handler(request: httpx.Request):
            calls.append(dict(request.url.params))
            return httpx.Response(200, json=SUMMARY if request.url.params["language"] == "all" else _texts(REVIEW))

        _mock_http(monkeypatch, handler)
        got = asyncio.run(sr.SteamReviewsAdapter().fetch("1245620", "ru"))
        assert [c["language"] for c in calls] == ["all", "russian"]
        assert calls[0]["num_per_page"] == "1" and calls[0]["filter_offtopic_activity"] == "1"
        assert got.total_positive == 42571 and got.positive_pct == 87 and len(got.reviews) == 1

    def test_english_for_everything_but_ru(self, monkeypatch):
        langs = []

        def handler(request):
            langs.append(request.url.params["language"])
            return httpx.Response(200, json=SUMMARY if langs[-1] == "all" else _texts())

        _mock_http(monkeypatch, handler)
        asyncio.run(sr.SteamReviewsAdapter().fetch("1", "en"))
        assert langs == ["all", "english"]

    def test_game_without_reviews_is_a_normal_answer(self, monkeypatch):
        _mock_http(monkeypatch, lambda r: httpx.Response(200, json={"success": 1, "query_summary": {"total_positive": 0, "total_negative": 0}, "reviews": []}))
        assert asyncio.run(sr.SteamReviewsAdapter().fetch("1", "ru")).missing is True

    def test_unknown_app_is_missing(self, monkeypatch):
        _mock_http(monkeypatch, lambda r: httpx.Response(200, json={"success": 0}))
        assert asyncio.run(sr.SteamReviewsAdapter().fetch("1", "ru")).missing is True

    @pytest.mark.parametrize("status", [429, 500, 503])
    def test_errors_are_unavailable_and_pause(self, monkeypatch, status):
        n = {"calls": 0}

        def handler(request):
            n["calls"] += 1
            return httpx.Response(status)

        _mock_http(monkeypatch, handler)
        with pytest.raises(sr.SteamUnavailable):
            asyncio.run(sr.SteamReviewsAdapter().fetch("1", "ru"))
        with pytest.raises(sr.SteamUnavailable):  # paused: no second request
            asyncio.run(sr.SteamReviewsAdapter().fetch("1", "ru"))
        assert n["calls"] == 1

    def test_network_error_is_unavailable(self, monkeypatch):
        def handler(request):
            raise httpx.ConnectError("down")

        _mock_http(monkeypatch, handler)
        with pytest.raises(sr.SteamUnavailable):
            asyncio.run(sr.SteamReviewsAdapter().fetch("1", "ru"))


class TestService:
    def test_found_game_is_cached_and_a_failure_is_not(self, monkeypatch, clean_cache):
        appid_calls, steam_calls = [], []

        async def fake_appid(raw_id):
            appid_calls.append(raw_id)
            return "1245620"

        async def fake_fetch(appid, lang):
            steam_calls.append((appid, lang))
            if len(steam_calls) == 1:
                raise sr.SteamUnavailable("down")
            return sr.SteamReviews(appid=appid, total_positive=9, total_negative=1, reviews=sr.parse_reviews(appid, _texts(REVIEW)))

        monkeypatch.setattr(game_reviews._igdb, "steam_appid", fake_appid)
        monkeypatch.setattr(game_reviews._steam, "fetch", fake_fetch)

        assert asyncio.run(game_reviews.get_reviews("9990001", "ru")) is None  # Steam down, nothing stored yet
        got = asyncio.run(game_reviews.get_reviews("9990001", "ru"))
        assert got is not None and got.positive_pct == 90
        asyncio.run(game_reviews.get_reviews("9990001", "ru"))
        assert len(steam_calls) == 2 and len(appid_calls) == 1  # third call: cache; appid cached from the start

    def test_game_without_a_steam_page_is_cached_as_such(self, monkeypatch, clean_cache):
        calls = []

        async def fake_appid(raw_id):
            calls.append(raw_id)
            return None

        monkeypatch.setattr(game_reviews._igdb, "steam_appid", fake_appid)
        assert asyncio.run(game_reviews.get_reviews("9990002", "ru")) is None
        assert asyncio.run(game_reviews.get_reviews("9990002", "ru")) is None
        assert len(calls) == 1

    def test_igdb_failure_is_not_remembered_as_no_steam_page(self, monkeypatch, clean_cache):
        n = {"calls": 0}

        async def flaky_appid(raw_id):
            n["calls"] += 1
            raise RuntimeError("IGDB not configured")

        monkeypatch.setattr(game_reviews._igdb, "steam_appid", flaky_appid)
        assert asyncio.run(game_reviews.get_reviews("9990003", "ru")) is None
        assert asyncio.run(game_reviews.get_reviews("9990003", "ru")) is None
        assert n["calls"] == 2  # asked again, not cached as "no Steam page"


class TestRouterMapping:
    def test_steam_list_keeps_order_and_maps_fields(self):
        negative = {**REVIEW, "author": {**REVIEW["author"], "steamid": "2", "personaname": "Grump"}, "voted_up": False, "votes_up": 0}
        result = sr.SteamReviews(appid="1245620", total_positive=1, total_negative=1, reviews=sr.parse_reviews("1245620", _texts(REVIEW, negative)))
        out = reviews_router.steam_review_list(result)
        assert [r.author for r in out] == ["PinkieSmiler", "Grump"]
        assert [r.tone for r in out] == ["positive", "negative"]
        assert out[0].source == "steam" and out[0].likes == 20 and out[1].likes is None
        assert out[0].playtime_hours == 170.9 and out[0].rating is None

    def test_endpoint_returns_steam_reviews_for_a_game(self, monkeypatch):
        async def fake_get(raw_id, lang):
            return sr.SteamReviews(appid="1", total_positive=1, total_negative=0, reviews=sr.parse_reviews("1", _texts(REVIEW)))

        monkeypatch.setattr(game_reviews, "get_reviews", fake_get)
        out = asyncio.run(reviews_router.game_reviews_out("igdb-119133", "ru"))
        assert out.attribution == "Отзывы предоставлены Steam" and len(out.reviews) == 1
        assert asyncio.run(reviews_router.game_reviews_out("tmdb-1", "ru")).reviews == []
        assert asyncio.run(reviews_router.game_reviews_out(None, "ru")).reviews == []
