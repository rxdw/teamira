"""Author biography and reader counts for a book — the cached layer between
the routers and app/adapters/open_library.py::OpenLibraryAdapter.book_info.
Same rules as app/book_ratings.py and app/manga_reviews.py (see
app/source_cache.py): a real answer, including "Open Library has no confident
match", is cached; "couldn't ask" is not, and the last known copy is served
when a refresh fails.

An author's biography barely changes and reader counts only drift, so the
answer is kept 30 days ("no match": 7). Keyed by the Google Books volume id so
two editions of the same novel don't share a row they shouldn't.
"""

import logging
from datetime import timedelta
from typing import Optional

from app import cache, source_cache
from app.adapters.open_library import OlBookInfo, OlUnavailable, OpenLibraryAdapter

logger = logging.getLogger("seenly.book_extras")

INFO_TTL = timedelta(days=30)
INFO_MISSING_TTL = timedelta(days=7)

_adapter = OpenLibraryAdapter()


def _ttl(raw: Optional[str]) -> timedelta:
    if raw is None:
        return INFO_TTL
    try:
        return INFO_MISSING_TTL if OlBookInfo.model_validate_json(raw).missing else INFO_TTL
    except Exception:  # noqa: BLE001
        return INFO_MISSING_TTL


async def get_book_info(volume_id: str, title: str, author: str) -> Optional[OlBookInfo]:
    """Open Library's author bio / reader counts for a book, or None when
    there's no confident match or it can't be asked right now."""
    key = f"ol:bookinfo:{volume_id}"
    try:
        ttl = _ttl(cache.get_dynamic_stale(None, key))
    except Exception:  # noqa: BLE001
        ttl = INFO_MISSING_TTL
    info = await source_cache.load(
        key, lambda: _adapter.book_info(title, author), ttl,
        OlBookInfo, OlUnavailable, logger, "Open Library book info",
    )
    return None if info is None or info.missing else info
