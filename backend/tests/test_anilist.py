"""AniList reviews and score for manga — parsing (including the cleaning of
AniList's markdown and the cut of very long bodies), request shape, outage
handling, the "don't cache a failure" rule, and the router mapping.

Field names follow a real answer captured for Berserk (idMal 2): `score`
0-100, `rating` helpful votes, `body` markdown that can run to ~75 KB.
No network: httpx.MockTransport. Cache tests use the real Postgres-backed
cache and clean up their rows.
"""

import asyncio
import json

import httpx
import pytest
from sqlalchemy import text

from app import manga_reviews
from app.adapters import anilist as al
from app.database import engine
from app.routers import reviews as reviews_router

BODY = (
    "# ~~~___A Timeless Masterpiece___~~~\n\n___\n\n"
    "The first part of this review, __“Why should you read Berserk?”__, is spoiler free. "
    "~!Secret plot twist!~ It is the highest rated manga almost everywhere.\n"
    "~~~img(https://i.imgur.com/wgyFDEB.jpg)~~~\n___\n"
    "See [my other review](https://anilist.co/review/1) for more. " + "More words about art and themes. " * 4
)
NODE = {
    "summary": "A Timeless Masterpiece", "score": 100, "rating": 697, "ratingAmount": 744,
    "siteUrl": "https://anilist.co/review/11421", "createdAt": 1646000000, "body": BODY,
    "user": {"name": "c4e", "avatar": {"medium": "https://s4.anilist.co/a.png"}},
}
MEDIA = {"id": 30002, "meanScore": 92, "siteUrl": "https://anilist.co/manga/30002", "reviews": {"nodes": [NODE]}}


def _ok(media=MEDIA):
    return httpx.Response(200, json={"data": {"Media": media}})


@pytest.fixture(autouse=True)
def _guard():
    al._guard.reset()
    yield
    al._guard.reset()


@pytest.fixture()
def clean_cache():
    yield
    with engine.begin() as conn:
        conn.execute(text("DELETE FROM cached_feed_snapshots WHERE cache_key LIKE 'al:manga:9990%'"))


def _mock_http(monkeypatch, handler):
    real = httpx.AsyncClient
    monkeypatch.setattr(al.httpx, "AsyncClient", lambda **kw: real(transport=httpx.MockTransport(handler), **kw))


class TestParsing:
    def test_manga_fields(self):
        m = al.parse_manga(MEDIA)
        assert m.score == 9.2 and m.url == "https://anilist.co/manga/30002" and len(m.reviews) == 1
        r = m.reviews[0]
        assert (r.author, r.score, r.helpful, r.title) == ("c4e", 10.0, 697, "A Timeless Masterpiece")
        assert r.url == "https://anilist.co/review/11421" and r.created_at.year == 2022

    def test_markdown_spoilers_and_media_are_cleaned(self):
        content = al.parse_manga(MEDIA).reviews[0].content
        assert "Secret plot twist" not in content
        assert "img(" not in content and "~~~" not in content and "___" not in content and "__" not in content
        assert "https://" not in content and "my other review" in content
        # the headline is shown on its own, so it isn't repeated as the first line
        assert not content.lower().startswith("a timeless masterpiece")

    def test_very_long_body_is_cut(self):
        node = {**NODE, "body": "Слово и ещё слово. " * 5000}
        content = al.parse_manga({**MEDIA, "reviews": {"nodes": [node]}}).reviews[0].content
        assert len(content) <= al.MAX_CHARS + 1 and content.endswith("…")

    def test_short_reviews_are_dropped(self):
        node = {**NODE, "body": "Great."}
        assert al.parse_manga({**MEDIA, "reviews": {"nodes": [node]}}).reviews == []

    def test_at_most_max_reviews_in_given_order(self):
        nodes = [{**NODE, "user": {"name": f"u{i}"}, "summary": f"s{i}"} for i in range(8)]
        out = al.parse_manga({**MEDIA, "reviews": {"nodes": nodes}}).reviews
        assert [r.author for r in out] == [f"u{i}" for i in range(al.MAX_REVIEWS)]

    def test_unscored_manga_has_no_score(self):
        assert al.parse_manga({"id": 1, "meanScore": None, "reviews": {"nodes": []}}).score is None

    def test_no_media_is_missing(self):
        assert al.parse_manga(None).missing is True


class TestAdapter:
    def test_request_is_looked_up_by_mal_id(self, monkeypatch):
        seen = {}

        def handler(request: httpx.Request):
            body = json.loads(request.content)
            seen["vars"], seen["query"], seen["ua"] = body["variables"], body["query"], request.headers["user-agent"]
            return _ok()

        _mock_http(monkeypatch, handler)
        m = asyncio.run(al.AniListAdapter().manga(2))
        assert m.score == 9.2
        assert seen["vars"] == {"mal": 2} and "idMal: $mal" in seen["query"] and "MANGA" in seen["query"]
        assert "Seenly" in seen["ua"]

    def test_unknown_manga_is_a_normal_answer(self, monkeypatch):
        _mock_http(monkeypatch, lambda r: httpx.Response(404, json={"errors": [{"message": "Not Found.", "status": 404}], "data": {"Media": None}}))
        assert asyncio.run(al.AniListAdapter().manga(1)).missing is True

    def test_null_media_is_missing(self, monkeypatch):
        _mock_http(monkeypatch, lambda r: _ok(None))
        assert asyncio.run(al.AniListAdapter().manga(1)).missing is True

    @pytest.mark.parametrize("status", [429, 500, 503])
    def test_errors_are_unavailable_and_pause(self, monkeypatch, status):
        n = {"calls": 0}

        def handler(request):
            n["calls"] += 1
            return httpx.Response(status, headers={"Retry-After": "30"})

        _mock_http(monkeypatch, handler)
        with pytest.raises(al.AniListUnavailable):
            asyncio.run(al.AniListAdapter().manga(2))
        with pytest.raises(al.AniListUnavailable):  # paused: no second request
            asyncio.run(al.AniListAdapter().manga(2))
        assert n["calls"] == 1

    def test_network_error_is_unavailable(self, monkeypatch):
        def handler(request):
            raise httpx.ConnectError("down")

        _mock_http(monkeypatch, handler)
        with pytest.raises(al.AniListUnavailable):
            asyncio.run(al.AniListAdapter().manga(2))


class TestService:
    def test_media_id_to_mal_id(self):
        assert manga_reviews.mal_id_from_media_id("shikimanga-2") == 2
        assert manga_reviews.mal_id_from_media_id("shikimanga-x") is None
        assert manga_reviews.mal_id_from_media_id("igdb-2") is None

    def test_answer_is_cached_and_a_failure_is_not(self, monkeypatch, clean_cache):
        calls = []

        async def fake(mal_id):
            calls.append(mal_id)
            if len(calls) == 1:
                raise al.AniListUnavailable("down")
            return al.parse_manga(MEDIA)

        monkeypatch.setattr(manga_reviews._adapter, "manga", fake)
        assert asyncio.run(manga_reviews.get_manga(9990001)) is None
        assert asyncio.run(manga_reviews.get_manga(9990001)).score == 9.2
        asyncio.run(manga_reviews.get_manga(9990001))
        assert calls == [9990001, 9990001]  # failure not cached; success cached

    def test_manga_missing_on_anilist_is_cached_as_such(self, monkeypatch, clean_cache):
        calls = []

        async def fake(mal_id):
            calls.append(mal_id)
            return al.AniListManga(missing=True)

        monkeypatch.setattr(manga_reviews._adapter, "manga", fake)
        assert asyncio.run(manga_reviews.get_manga(9990002)) is None
        assert asyncio.run(manga_reviews.get_manga(9990002)) is None
        assert len(calls) == 1


class TestRouterMapping:
    def test_tone_follows_the_score(self):
        assert [reviews_router._anilist_tone(s) for s in (10.0, 7.0, 6.9, 5.0, 4.9, None)] == [
            "positive", "positive", "neutral", "neutral", "negative", None]

    def test_anilist_list_maps_fields(self):
        out = reviews_router.anilist_review_list(al.parse_manga(MEDIA))
        r = out[0]
        assert (r.source, r.author, r.rating, r.tone, r.likes, r.title) == (
            "anilist", "c4e", 10.0, "positive", 697, "A Timeless Masterpiece")
        assert r.url == "https://anilist.co/review/11421" and r.playtime_hours is None

    def test_endpoint_returns_anilist_reviews_for_a_manga(self, monkeypatch):
        async def fake_get(mal_id):
            assert mal_id == 2
            return al.parse_manga(MEDIA)

        monkeypatch.setattr(manga_reviews, "get_manga", fake_get)
        out = asyncio.run(reviews_router.manga_reviews_out("shikimanga-2"))
        assert out.attribution == "Отзывы предоставлены AniList" and len(out.reviews) == 1
        assert asyncio.run(reviews_router.manga_reviews_out("igdb-2")).reviews == []
        assert asyncio.run(reviews_router.manga_reviews_out(None)).reviews == []
