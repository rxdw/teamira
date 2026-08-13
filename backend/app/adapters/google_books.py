"""Books — search, browse, and detail, backed by the Google Books API
(developers.google.com/books). Free, no OAuth: a single API key on the
query string (not even a secret), and it works without a key at all on
Google's shared anonymous quota (1,000 requests/day, per-IP) — a key just
raises that ceiling and is what you'd want for anything beyond local dev.
Get one at console.cloud.google.com: create a project, enable the
"Books API", then Credentials -> Create Credentials -> API key.

No client-credentials dance like IGDB/Twitch — every request is just:
    GET https://www.googleapis.com/books/v1/volumes?q=...&key=...

No key configured just means requests go out unauthenticated instead of
being skipped — unlike TMDB/IGDB, Google Books doesn't hard-require a
key, so books don't quietly disappear the way games do when IGDB_CLIENT_ID
is empty. They just become more likely to hit the shared rate limit under
real traffic.
"""
import asyncio
import logging
import re
from typing import List, Optional

import httpx

from app.config import settings
from app.schemas import MediaItem, ExternalIds, LocalizedText
from app.adapters.base import MediaAdapter

logger = logging.getLogger("seenly.adapters.google_books")

BOOKS_BASE = "https://www.googleapis.com/books/v1/volumes"

# Requested every call — averageRating/ratingsCount are what let us filter
# shelf results down to books that actually have a meaningful score,
# instead of every random self-published title Google indexes.
_FIELDS = (
    "items(id,volumeInfo(title,authors,description,categories,"
    "imageLinks,publishedDate,averageRating,ratingsCount,pageCount,language))"
)

_TAG_RE = re.compile(r"<[^>]+>")

# Subject-scoped shelves for the Collections tab — Google Books has no
# "top rated" browse endpoint like IGDB's sort=total_rating, so each shelf
# pulls a wider pool via subject search and is re-sorted by averageRating
# here, same "real data, filtered and ranked, not synthetic" approach as
# the IGDB genre shelves.
_SUBJECT_SHELVES = [
    ("Popular Fiction", "subject:fiction"),
    ("Sci-Fi & Fantasy", "subject:science+fiction+OR+subject:fantasy"),
    ("Mystery & Thriller", "subject:mystery+OR+subject:thriller"),
    ("Non-Fiction Picks", "subject:nonfiction"),
    ("Biographies & Memoirs", "subject:biography"),
    ("Self-Help & Growth", "subject:self-help"),
]

_MIN_RATINGS_COUNT = 5  # filters out books with a single stray 5-star rating


def _clean_description(raw: Optional[str]) -> Optional[str]:
    """Google's description field is HTML (<p>, <b>, <br> ...); strip tags
    for a plain-text synopsis matching what TMDB/IGDB already return."""
    if not raw:
        return None
    text = _TAG_RE.sub("", raw).replace("&nbsp;", " ").replace("&amp;", "&")
    return text.strip() or None


def _cover_url(image_links: Optional[dict]) -> Optional[str]:
    """Google returns http:// thumbnails at a small default zoom, plus a
    "page curl" decoration (edge=curl) meant for their own reader UI —
    upgraded to https, a bigger zoom, and stripped of the curl here."""
    if not image_links:
        return None
    raw = image_links.get("thumbnail") or image_links.get("smallThumbnail")
    if not raw:
        return None
    url = raw.replace("http://", "https://")
    url = url.replace("zoom=1", "zoom=2").replace("&edge=curl", "")
    return url


def _year(published_date: Optional[str]) -> Optional[int]:
    if not published_date:
        return None
    try:
        return int(published_date[:4])
    except ValueError:
        return None


def _reading_minutes(page_count: Optional[int]) -> Optional[int]:
    """A real (if approximate) per-book estimate from its actual page
    count, at ~1.2 min/page (roughly 250 wpm over a ~300-word page) —
    used for Wrapped hour totals when present; profile.py's flat 6h
    default for MediaType.book still covers books with no pageCount."""
    if not page_count or page_count <= 0:
        return None
    return round(page_count * 1.2)


def _normalize(volume_id: Optional[str], info: dict) -> Optional[MediaItem]:
    title = info.get("title")
    if not volume_id or not title:
        return None

    authors = info.get("authors") or []
    rating = info.get("averageRating")  # Google's own scale is 0-5
    rating10 = round(rating * 2, 1) if rating else None

    return MediaItem(
        id=f"gbooks-{volume_id}",
        media_type="book",
        external_ids=ExternalIds(tmdb=None, imdb=None),
        title=LocalizedText(ru=None, en=title),
        description=LocalizedText(ru=None, en=_clean_description(info.get("description"))),
        poster_url=_cover_url(info.get("imageLinks")),
        backdrop_url=None,  # no wide art from Google Books; UI falls back to the cover
        year=_year(info.get("publishedDate")),
        genres=info.get("categories") or [],
        rating=rating10,
        # Reused as a free-text subtitle (see schemas.MediaItem.tagline) —
        # not shown anywhere yet, but the natural place for "by X, Y" until
        # the client grows a dedicated authors field.
        source="google_books",
        runtime_minutes=_reading_minutes(info.get("pageCount")),
        tagline=("By " + ", ".join(authors)) if authors else None,
    )


class GoogleBooksAdapter(MediaAdapter):
    source_name = "google_books"

    def __init__(self):
        self.api_key = settings.google_books_api_key

    def _params(self, **extra) -> dict:
        params = {**extra}
        if self.api_key:
            params["key"] = self.api_key
        return params

    async def _query(self, params: dict) -> List[dict]:
        try:
            async with httpx.AsyncClient(timeout=8.0) as client:
                resp = await client.get(BOOKS_BASE, params=self._params(**params))
                resp.raise_for_status()
                data = resp.json()
        except httpx.HTTPError as exc:
            status = getattr(getattr(exc, "response", None), "status_code", "?")
            logger.warning("Google Books query failed [%s]: %s", status, exc)
            return []
        return data.get("items") or []

    async def search(self, query: str) -> List[MediaItem]:
        if not query:
            return []
        raw = await self._query({
            "q": query,
            "maxResults": 20,
            "printType": "books",
            "fields": _FIELDS,
        })
        items = [
            item for r in raw
            if (item := _normalize(r.get("id"), r.get("volumeInfo") or {})) is not None
        ]
        return items

    async def _shelf(self, title: str, subject_query: str) -> tuple:
        raw = await self._query({
            "q": subject_query,
            "maxResults": 40,  # Google's per-request cap; over-fetch, then rank/trim below
            "printType": "books",
            "orderBy": "relevance",
            "fields": _FIELDS,
        })
        candidates = []
        for r in raw:
            info = r.get("volumeInfo") or {}
            if (info.get("ratingsCount") or 0) < _MIN_RATINGS_COUNT:
                continue
            item = _normalize(r.get("id"), info)
            if item is not None:
                candidates.append(item)
        candidates.sort(key=lambda m: m.rating or 0, reverse=True)
        return (title, candidates[:12])

    async def discover(self) -> List[MediaItem]:
        """A flat pool for GET /feed — there's no single "trending books"
        endpoint here, so this reuses the
        same subject shelves as named_collections() and flattens them,
        de-duplicated by id since a book can legitimately match more than
        one subject shelf (e.g. a mystery/thriller crossover)."""
        shelves = await self.named_collections()
        seen: set = set()
        pool: List[MediaItem] = []
        for _title, items in shelves:
            for item in items:
                if item.id not in seen:
                    seen.add(item.id)
                    pool.append(item)
        return pool

    async def named_collections(self) -> List[tuple]:
        """Subject-scoped shelves for the Collections tab — see
        _SUBJECT_SHELVES. Same fan-out-concurrently, drop-what-fails
        pattern as IGDB's named_collections()."""
        results = await asyncio.gather(
            *[self._shelf(title, q) for title, q in _SUBJECT_SHELVES],
            return_exceptions=True,
        )
        return [r for r in results if isinstance(r, tuple) and r[1]]

    async def full_detail(self, raw_id: str) -> Optional[MediaItem]:
        try:
            async with httpx.AsyncClient(timeout=8.0) as client:
                resp = await client.get(
                    f"{BOOKS_BASE}/{raw_id}", params=self._params()
                )
                resp.raise_for_status()
                data = resp.json()
        except httpx.HTTPError as exc:
            status = getattr(getattr(exc, "response", None), "status_code", "?")
            logger.warning("Google Books detail query failed [%s]: %s", status, exc)
            return None
        return _normalize(data.get("id"), data.get("volumeInfo") or {})
