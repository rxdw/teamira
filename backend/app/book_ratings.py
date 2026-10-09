"""Hardcover's community rating for a book — the cached layer between
GET /media/detail and app/adapters/hardcover.py. Same rules as
app/kinopoisk.py (see app/source_cache.py): a real answer, including "not
on Hardcover", is cached; "couldn't ask" is not, and the last known copy is
served instead when a refresh fails.

Two lookups per never-seen book, both cached:
  1. Google Books volume -> ISBNs   (kept a year; an ISBN doesn't change)
  2. ISBN -> Hardcover rating       (30 days; a book's average barely moves)
Repeat opens cost nothing until those expire.
"""

import logging
from datetime import timedelta
from typing import Optional

from pydantic import BaseModel

from app import cache, source_cache
from app.adapters.google_books import GoogleBooksAdapter
from app.adapters.hardcover import HardcoverAdapter, HcBook, HcUnavailable, clean_isbn

logger = logging.getLogger("seenly.book_ratings")

ISBN_TTL = timedelta(days=365)
RATING_TTL = timedelta(days=30)
# Short, like Kinopoisk's "not found": a book Hardcover doesn't have yet may
# well be added soon.
RATING_MISSING_TTL = timedelta(days=7)

_books = GoogleBooksAdapter()
_hardcover = HardcoverAdapter()


class GbIsbns(BaseModel):
    isbn_13: Optional[str] = None
    isbn_10: Optional[str] = None


def enabled() -> bool:
    return _hardcover.configured()


def _rating_ttl(raw: Optional[str]) -> timedelta:
    if raw is None:
        return RATING_TTL  # nothing stored, nothing to expire
    try:
        return RATING_MISSING_TTL if HcBook.model_validate_json(raw).missing else RATING_TTL
    except Exception:  # noqa: BLE001 — unreadable copy: just refetch soon
        return RATING_MISSING_TTL


async def _fetch_isbns(volume_id: str) -> GbIsbns:
    found = await _books.isbns(volume_id)
    if found is None:
        # Google Books didn't answer — not the same as "no ISBN", so it
        # must not be cached as one.
        raise HcUnavailable("Google Books lookup failed")
    return GbIsbns(
        isbn_13=clean_isbn(found.get("isbn_13")),
        isbn_10=clean_isbn(found.get("isbn_10")),
    )


async def get_rating(volume_id: str) -> Optional[HcBook]:
    """The Hardcover book for a Google Books volume id, or None when there
    isn't one or it can't be asked right now — callers just show no rating."""
    isbns = await source_cache.load(
        f"gb:isbn:{volume_id}", lambda: _fetch_isbns(volume_id), ISBN_TTL,
        GbIsbns, HcUnavailable, logger, "Google Books ISBN",
    )
    if isbns is None:
        return None
    for isbn in (isbns.isbn_13, isbns.isbn_10):
        if not isbn:
            continue
        key = f"hc:isbn:{isbn}"
        try:
            ttl = _rating_ttl(cache.get_dynamic_stale(None, key))
        except Exception:  # noqa: BLE001
            ttl = RATING_MISSING_TTL
        book = await source_cache.load(
            key, lambda isbn=isbn: _hardcover.find_by_isbn(isbn), ttl,
            HcBook, HcUnavailable, logger, "Hardcover",
        )
        if book is None:
            return None  # couldn't ask — don't fall through to ISBN-10 and spend more
        if not book.missing:
            return book
    return None
