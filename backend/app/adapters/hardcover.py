"""Hardcover (hardcover.app) — the community rating for a book, looked up by
ISBN. Shown on the title screen as "hardcover 4.3 · N ratings" with a link
to the book's page there. Nothing else from Hardcover is used.

Why only the aggregate, never review text: Hardcover's API policy
(docs.hardcover.app/api/getting-started, "Commercial API Use") forbids a
commercial or publicly accessible product from using data its users own —
reviews, ratings by individual users, lists, journals. Aggregate figures
(readers count, average rating) are allowed *if credited to Hardcover*,
which is why the label on screen says "hardcover". Keep it that way: don't
add review text here without re-reading that policy.

The API is GraphQL, authenticated with a personal access token
(hardcover.app/account/api), free tier 60 requests/minute and 5,000/day,
and explicitly in beta ("anything you build on it could break", tokens
may be reset). So, as with ПоискКино, every failure raises HcUnavailable
and callers just skip the rating for that request.

Schema used (docs.hardcover.app/api/graphql/schemas/books, .../editions):
    editions(where: {isbn_13: {_eq: $isbn}}, limit: 1) {
        book { slug rating ratings_count users_count }
    }
`rating` is on a 0-5 scale. Only `_eq` is used — the `_like`/regex
operators are disabled by the API.
"""

import logging
import re
from typing import Optional

import httpx
from pydantic import BaseModel

from app.adapters.quota_guard import QuotaGuard
from app.config import settings

logger = logging.getLogger("seenly.adapters.hardcover")

HARDCOVER_URL = "https://api.hardcover.app/v1/graphql"
BOOK_PAGE_URL = "https://hardcover.app/books/{slug}"

# The docs recommend a descriptive User-Agent for scripts.
_USER_AGENT = "Seenly/1.0 (book ratings; hardcover.app attribution shown in-app)"
_TIMEOUT = httpx.Timeout(6.0, connect=3.0)

_PAUSE_NETWORK_SEC = 120
_PAUSE_RATE_LIMITED_SEC = 900
_PAUSE_DENIED_SEC = 3600
_MAX_RETRY_AFTER_SEC = 3600

_ISBN13_RE = re.compile(r"^\d{13}$")
_ISBN10_RE = re.compile(r"^\d{9}[\dXx]$")

_QUERY = """
query BookByIsbn($isbn: String!) {
  editions(where: {%s: {_eq: $isbn}}, limit: 1) {
    book { slug rating ratings_count users_count }
  }
}
"""


class HcUnavailable(Exception):
    """Couldn't get an answer right now (no token, over budget, paused
    after an error, network failure, bad response). Distinct from
    "answered: Hardcover doesn't have this ISBN"."""


class HcBook(BaseModel):
    """What we keep. `missing=True` is the cached "not on Hardcover"."""
    missing: bool = False
    slug: Optional[str] = None
    rating: Optional[float] = None  # 0-5
    ratings_count: Optional[int] = None
    users_count: Optional[int] = None


_guard = QuotaGuard(lambda: settings.hardcover_daily_budget)


def clean_isbn(raw: Optional[str]) -> Optional[str]:
    isbn = re.sub(r"[\s-]", "", raw or "")
    if _ISBN13_RE.match(isbn) or _ISBN10_RE.match(isbn):
        return isbn.upper()
    return None


def _positive_float(value) -> Optional[float]:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return round(number, 1) if number > 0 else None


def _positive_int(value) -> Optional[int]:
    try:
        number = int(value)
    except (TypeError, ValueError):
        return None
    return number if number > 0 else None


def parse_book(book: Optional[dict]) -> HcBook:
    if not book:
        return HcBook(missing=True)
    slug = book.get("slug")
    return HcBook(
        slug=slug if isinstance(slug, str) and slug else None,
        rating=_positive_float(book.get("rating")),
        ratings_count=_positive_int(book.get("ratings_count")),
        users_count=_positive_int(book.get("users_count")),
    )


def book_url(slug: str) -> str:
    return BOOK_PAGE_URL.format(slug=slug)


class HardcoverAdapter:
    source_name = "hardcover"

    @staticmethod
    def configured() -> bool:
        return bool(settings.hardcover_api_token.strip())

    @staticmethod
    def _auth_header() -> str:
        token = settings.hardcover_api_token.strip()
        # The account page shows the token with or without a "Bearer "
        # prefix depending on how it was copied — accept both.
        return token if token.lower().startswith("bearer ") else f"Bearer {token}"

    @staticmethod
    def _retry_after(resp: httpx.Response, default: float) -> float:
        try:
            return min(float(resp.headers.get("Retry-After", default)), _MAX_RETRY_AFTER_SEC)
        except (TypeError, ValueError):
            return default

    async def _post(self, query: str, variables: dict) -> dict:
        if not self.configured():
            raise HcUnavailable("HARDCOVER_API_TOKEN is not set")
        if not _guard.allow():
            raise HcUnavailable("paused or daily budget used up")
        _guard.spend()
        try:
            async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
                resp = await client.post(
                    HARDCOVER_URL,
                    json={"query": query, "variables": variables},
                    headers={
                        "authorization": self._auth_header(),
                        "content-type": "application/json",
                        "user-agent": _USER_AGENT,
                    },
                )
        except httpx.HTTPError as exc:
            _guard.pause(_PAUSE_NETWORK_SEC)
            logger.warning("Hardcover unreachable (%s), pausing %ss", type(exc).__name__, _PAUSE_NETWORK_SEC)
            raise HcUnavailable("network error") from exc

        status = resp.status_code
        if status == 429:
            wait = self._retry_after(resp, _PAUSE_RATE_LIMITED_SEC)
            _guard.pause(wait)
            logger.warning("Hardcover 429 — pausing %ss", wait)
            raise HcUnavailable("rate limited")
        if status in (401, 403):
            # 403 with `insufficient_scope` names the missing scope — log
            # that (never the token) so a wrongly-scoped token is obvious.
            detail = ""
            try:
                body = resp.json()
                detail = f"{body.get('error')} {body.get('scope') or ''}".strip()
            except ValueError:
                pass
            _guard.pause(_PAUSE_DENIED_SEC)
            logger.error("Hardcover refused the token (%s %s) — check HARDCOVER_API_TOKEN and its scopes", status, detail)
            raise HcUnavailable("token refused")
        if status in (408, 500, 502, 503, 504):
            _guard.pause(_PAUSE_NETWORK_SEC)
            logger.warning("Hardcover %s, pausing %ss", status, _PAUSE_NETWORK_SEC)
            raise HcUnavailable(f"server error {status}")
        if status != 200:
            logger.warning("Hardcover unexpected %s", status)
            raise HcUnavailable(f"unexpected status {status}")
        try:
            data = resp.json()
        except ValueError as exc:
            raise HcUnavailable("invalid JSON") from exc
        if not isinstance(data, dict):
            raise HcUnavailable("unexpected payload")
        if data.get("errors"):
            # A 200 carrying GraphQL errors means the query itself was
            # rejected (schema drift — it's a beta API). Retrying won't
            # help, so back off for a while instead of hammering it.
            _guard.pause(_PAUSE_DENIED_SEC)
            logger.error("Hardcover rejected the query: %s", str(data["errors"])[:300])
            raise HcUnavailable("query rejected")
        return data

    async def find_by_isbn(self, isbn: str) -> HcBook:
        """Not found (or not a valid ISBN) is a normal answer —
        HcBook(missing=True) — not an error."""
        isbn = clean_isbn(isbn)
        if not isbn:
            return HcBook(missing=True)
        field = "isbn_13" if len(isbn) == 13 else "isbn_10"
        data = await self._post(_QUERY % field, {"isbn": isbn})
        editions = ((data.get("data") or {}).get("editions")) or []
        book = (editions[0] or {}).get("book") if editions else None
        return parse_book(book)
