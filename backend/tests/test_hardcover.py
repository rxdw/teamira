"""Hardcover book rating — parsing, quota/outage handling, the "don't cache
a failure" rule, and how it reaches /media/detail for a Google Books title.

Aggregate only (rating, number of raters, link): Hardcover's API policy
forbids showing its users' review text in a public product — see
app/adapters/hardcover.py. The response shapes below follow the schema in
Hardcover's docs (editions -> book { slug rating ratings_count users_count },
rating on a 0-5 scale); they have not been captured from the live API yet,
so run one real request when a token is available and compare.

No network: the adapter's HTTP client is swapped for httpx.MockTransport.
Cache tests use the real Postgres-backed cache and clean up their rows.
"""

import asyncio
from datetime import timedelta

import httpx
import pytest
from sqlalchemy import text

from app import book_ratings
from app.adapters import hardcover as hc
from app.config import settings
from app.database import engine
from app.routers import media as media_router
from app.schemas import ExternalIds, LocalizedText, MediaDetailOut, MediaItem, RatingsOut

BOOK = {"slug": "dune", "rating": 4.3126, "ratings_count": 18234, "users_count": 52110}
ISBN13 = "9780441172719"
ISBN10 = "0441172717"


def _ok(book=BOOK):
    editions = [{"book": book}] if book else []
    return httpx.Response(200, json={"data": {"editions": editions}})


@pytest.fixture(autouse=True)
def _hc_env(monkeypatch):
    monkeypatch.setattr(settings, "hardcover_api_token", "test-token")
    monkeypatch.setattr(settings, "hardcover_daily_budget", 4000)
    hc._guard.reset()
    yield
    hc._guard.reset()


@pytest.fixture()
def clean_cache():
    yield
    with engine.begin() as conn:
        conn.execute(text("DELETE FROM cached_feed_snapshots WHERE cache_key LIKE 'hc:%' OR cache_key LIKE 'gb:isbn:hctest%'"))


def _mock_http(monkeypatch, handler):
    real = httpx.AsyncClient
    monkeypatch.setattr(hc.httpx, "AsyncClient", lambda **kw: real(transport=httpx.MockTransport(handler), **kw))


# --- parsing ---------------------------------------------------------------

class TestParsing:
    def test_book_fields(self):
        book = hc.parse_book(BOOK)
        assert (book.slug, book.rating, book.ratings_count, book.users_count) == ("dune", 4.3, 18234, 52110)
        assert hc.book_url(book.slug) == "https://hardcover.app/books/dune"

    def test_unrated_book_has_no_rating(self):
        book = hc.parse_book({"slug": "new-book", "rating": None, "ratings_count": 0, "users_count": 3})
        assert book.rating is None and book.ratings_count is None and book.slug == "new-book"

    def test_no_book_is_missing(self):
        assert hc.parse_book(None).missing is True

    def test_isbn_cleaning(self):
        assert hc.clean_isbn("978-0-441-17271-9") == ISBN13
        assert hc.clean_isbn("0 441 17271 7") == ISBN10
        assert hc.clean_isbn("080442957x") == "080442957X"
        assert hc.clean_isbn("12345") is None
        assert hc.clean_isbn(None) is None


# --- adapter: HTTP behaviour -----------------------------------------------

class TestAdapter:
    def test_request_shape(self, monkeypatch):
        seen = {}

        def handler(request: httpx.Request):
            import json
            body = json.loads(request.content)
            seen["auth"] = request.headers.get("authorization")
            seen["ua"] = request.headers.get("user-agent")
            seen["vars"] = body["variables"]
            seen["query"] = body["query"]
            return _ok()

        _mock_http(monkeypatch, handler)
        book = asyncio.run(hc.HardcoverAdapter().find_by_isbn(ISBN13))
        assert book.rating == 4.3
        assert seen["auth"] == "Bearer test-token"
        assert "Seenly" in seen["ua"]
        assert seen["vars"] == {"isbn": ISBN13}
        assert "isbn_13" in seen["query"] and "_eq" in seen["query"] and "isbn_10" not in seen["query"]

    def test_isbn10_uses_the_isbn10_field(self, monkeypatch):
        seen = {}

        def handler(request):
            import json
            seen["query"] = json.loads(request.content)["query"]
            return _ok()

        _mock_http(monkeypatch, handler)
        asyncio.run(hc.HardcoverAdapter().find_by_isbn(ISBN10))
        assert "isbn_10" in seen["query"] and "isbn_13" not in seen["query"]

    def test_token_with_bearer_prefix_is_not_doubled(self, monkeypatch):
        monkeypatch.setattr(settings, "hardcover_api_token", "Bearer abc")
        seen = {}

        def handler(request):
            seen["auth"] = request.headers.get("authorization")
            return _ok()

        _mock_http(monkeypatch, handler)
        asyncio.run(hc.HardcoverAdapter().find_by_isbn(ISBN13))
        assert seen["auth"] == "Bearer abc"

    def test_unknown_isbn_is_missing_not_an_error(self, monkeypatch):
        _mock_http(monkeypatch, lambda r: _ok(None))
        assert asyncio.run(hc.HardcoverAdapter().find_by_isbn(ISBN13)).missing is True

    def test_invalid_isbn_makes_no_request(self, monkeypatch):
        _mock_http(monkeypatch, lambda r: pytest.fail("must not call out for a malformed ISBN"))
        assert asyncio.run(hc.HardcoverAdapter().find_by_isbn("nope")).missing is True

    def test_no_token_means_unavailable_and_no_request(self, monkeypatch):
        monkeypatch.setattr(settings, "hardcover_api_token", "")
        _mock_http(monkeypatch, lambda r: pytest.fail("must not call out without a token"))
        with pytest.raises(hc.HcUnavailable):
            asyncio.run(hc.HardcoverAdapter().find_by_isbn(ISBN13))

    @pytest.mark.parametrize("status", [429, 401, 403, 500, 503])
    def test_errors_raise_and_pause_further_calls(self, monkeypatch, status):
        calls = []

        def handler(request):
            calls.append(1)
            return httpx.Response(status, json={"error": "insufficient_scope", "scope": "books:read"})

        _mock_http(monkeypatch, handler)
        adapter = hc.HardcoverAdapter()
        with pytest.raises(hc.HcUnavailable):
            asyncio.run(adapter.find_by_isbn(ISBN13))
        with pytest.raises(hc.HcUnavailable):
            asyncio.run(adapter.find_by_isbn(ISBN10))
        assert len(calls) == 1

    def test_retry_after_sets_the_pause(self, monkeypatch):
        _mock_http(monkeypatch, lambda r: httpx.Response(429, headers={"Retry-After": "5"}, json={}))
        with pytest.raises(hc.HcUnavailable):
            asyncio.run(hc.HardcoverAdapter().find_by_isbn(ISBN13))
        assert hc._guard.allow() is False

    def test_graphql_errors_in_a_200_are_unavailable_and_pause(self, monkeypatch):
        _mock_http(monkeypatch, lambda r: httpx.Response(200, json={"errors": [{"message": "field not found"}]}))
        with pytest.raises(hc.HcUnavailable):
            asyncio.run(hc.HardcoverAdapter().find_by_isbn(ISBN13))
        assert hc._guard.allow() is False

    def test_network_failure_raises_and_pauses(self, monkeypatch):
        def handler(request):
            raise httpx.ConnectError("unreachable")

        _mock_http(monkeypatch, handler)
        with pytest.raises(hc.HcUnavailable):
            asyncio.run(hc.HardcoverAdapter().find_by_isbn(ISBN13))
        assert hc._guard.allow() is False

    def test_daily_budget_stops_requests(self, monkeypatch):
        monkeypatch.setattr(settings, "hardcover_daily_budget", 1)
        calls = []

        def handler(request):
            calls.append(1)
            return _ok()

        _mock_http(monkeypatch, handler)
        adapter = hc.HardcoverAdapter()
        asyncio.run(adapter.find_by_isbn(ISBN13))
        with pytest.raises(hc.HcUnavailable):
            asyncio.run(adapter.find_by_isbn(ISBN10))
        assert len(calls) == 1


# --- service: ISBN lookup, caching, fallbacks --------------------------------

@pytest.fixture()
def google(monkeypatch):
    """Stand-in for Google Books' ISBN lookup. `state['isbns']` is what it
    returns (None = the lookup failed); `state['calls']` counts asks."""
    state = {"isbns": {"isbn_13": ISBN13, "isbn_10": ISBN10}, "calls": 0}

    async def fake_isbns(self, raw_id):
        state["calls"] += 1
        return state["isbns"]

    monkeypatch.setattr(book_ratings.GoogleBooksAdapter, "isbns", fake_isbns)
    return state


class TestService:
    def test_found_book_is_cached_and_costs_one_hardcover_request(self, monkeypatch, google, clean_cache):
        calls = []

        def handler(request):
            calls.append(1)
            return _ok()

        _mock_http(monkeypatch, handler)
        first = asyncio.run(book_ratings.get_rating("hctest1"))
        second = asyncio.run(book_ratings.get_rating("hctest1"))
        assert first.rating == second.rating == 4.3
        assert len(calls) == 1 and google["calls"] == 1

    def test_falls_back_to_isbn10_when_isbn13_is_unknown(self, monkeypatch, google, clean_cache):
        import json
        asked = []

        def handler(request):
            isbn = json.loads(request.content)["variables"]["isbn"]
            asked.append(isbn)
            return _ok(BOOK if isbn == ISBN10 else None)

        _mock_http(monkeypatch, handler)
        book = asyncio.run(book_ratings.get_rating("hctest2"))
        assert book is not None and book.rating == 4.3
        assert asked == [ISBN13, ISBN10]

    def test_book_without_an_isbn_is_none_and_cached(self, monkeypatch, google, clean_cache):
        google["isbns"] = {"isbn_13": None, "isbn_10": None}
        _mock_http(monkeypatch, lambda r: pytest.fail("no ISBN, nothing to ask Hardcover"))
        assert asyncio.run(book_ratings.get_rating("hctest3")) is None
        assert asyncio.run(book_ratings.get_rating("hctest3")) is None
        assert google["calls"] == 1

    def test_google_books_failure_is_not_remembered(self, monkeypatch, google, clean_cache):
        google["isbns"] = None
        _mock_http(monkeypatch, lambda r: _ok())
        assert asyncio.run(book_ratings.get_rating("hctest4")) is None
        google["isbns"] = {"isbn_13": ISBN13, "isbn_10": None}
        assert asyncio.run(book_ratings.get_rating("hctest4")).rating == 4.3

    def test_hardcover_failure_is_not_remembered(self, monkeypatch, google, clean_cache):
        state = {"ok": False}

        def handler(request):
            return _ok() if state["ok"] else httpx.Response(500, json={})

        _mock_http(monkeypatch, handler)
        assert asyncio.run(book_ratings.get_rating("hctest5")) is None
        hc._guard.reset()  # time passes, the pause ends
        state["ok"] = True
        assert asyncio.run(book_ratings.get_rating("hctest5")).rating == 4.3

    def test_outage_does_not_fall_through_to_isbn10(self, monkeypatch, google, clean_cache):
        calls = []

        def handler(request):
            calls.append(1)
            return httpx.Response(500, json={})

        _mock_http(monkeypatch, handler)
        assert asyncio.run(book_ratings.get_rating("hctest6")) is None
        assert len(calls) == 1

    def test_expired_copy_is_served_when_the_refresh_fails(self, monkeypatch, google, clean_cache):
        state = {"ok": True}

        def handler(request):
            return _ok() if state["ok"] else httpx.Response(500, json={})

        _mock_http(monkeypatch, handler)
        assert asyncio.run(book_ratings.get_rating("hctest7")).rating == 4.3
        monkeypatch.setattr(book_ratings, "RATING_TTL", timedelta(seconds=-1))
        state["ok"] = False
        hc._guard.reset()
        stale = asyncio.run(book_ratings.get_rating("hctest7"))
        assert stale is not None and stale.rating == 4.3

    def test_ttl_is_shorter_for_a_book_hardcover_doesnt_have(self):
        found = hc.parse_book(BOOK).model_dump_json()
        missing = hc.HcBook(missing=True).model_dump_json()
        assert book_ratings._rating_ttl(found).days == 30
        assert book_ratings._rating_ttl(missing).days == 7
        assert book_ratings._rating_ttl(None).days == 30
        assert book_ratings._rating_ttl("not json").days == 7


# --- detail endpoint helper ---------------------------------------------------

def _book_detail(item_id="gbooks-hctest9", media_type="book", ratings=None):
    return MediaDetailOut(
        item=MediaItem(id=item_id, media_type=media_type, external_ids=ExternalIds(),
                       title=LocalizedText(en="Dune"), description=LocalizedText(en="x"), source="google_books"),
        ratings=ratings,
    )


class TestDetailRatings:
    @pytest.fixture()
    def patched(self, monkeypatch):
        seen = {}

        async def fake_rating(volume_id):
            seen["volume_id"] = volume_id
            return hc.HcBook(slug="dune", rating=4.3, ratings_count=18234)

        monkeypatch.setattr(book_ratings, "get_rating", fake_rating)
        return seen

    def test_book_gets_rating_votes_and_link(self, patched):
        result = _book_detail()
        asyncio.run(media_router._apply_hardcover(result))
        r = result.ratings
        assert (r.hc_rating, r.hc_votes, r.hc_url) == (4.3, 18234, "https://hardcover.app/books/dune")
        assert patched["volume_id"] == "hctest9"  # the Google Books id, prefix stripped

    def test_existing_ratings_block_is_kept(self, patched):
        result = _book_detail(ratings=RatingsOut(tmdb_rating=1.0))
        asyncio.run(media_router._apply_hardcover(result))
        assert result.ratings.tmdb_rating == 1.0 and result.ratings.hc_rating == 4.3

    def test_non_books_and_foreign_ids_are_untouched(self, patched):
        for item_id, media_type in (("gbooks-x", "game"), ("openlibrary-x", "book")):
            result = _book_detail(item_id=item_id, media_type=media_type)
            asyncio.run(media_router._apply_hardcover(result))
            assert result.ratings is None

    def test_no_token_means_no_lookup(self, monkeypatch):
        monkeypatch.setattr(settings, "hardcover_api_token", "")

        async def boom(volume_id):
            pytest.fail("without a token nothing should be looked up")

        monkeypatch.setattr(book_ratings, "get_rating", boom)
        result = _book_detail()
        asyncio.run(media_router._apply_hardcover(result))
        assert result.ratings is None

    def test_a_miss_or_an_unrated_book_adds_nothing(self, monkeypatch):
        async def none(volume_id):
            return None

        async def unrated(volume_id):
            return hc.HcBook(slug="new", rating=None)

        for fn in (none, unrated):
            monkeypatch.setattr(book_ratings, "get_rating", fn)
            result = _book_detail()
            asyncio.run(media_router._apply_hardcover(result))
            assert result.ratings is None
