"""Trakt.tv comments — the second review-text source alongside TMDB (see
app/routers/reviews.py for how the two get merged).

TMDB's own /reviews endpoint is thin for a lot of titles — a handful of
entries, often none at all. Trakt's /comments endpoints cover the same
movies/shows with a much larger, more active user base, and Trakt already
documents a lookup-by-any-id search (GET /search/tmdb/{id}) so no extra ID
mapping table is needed beyond the tmdb_id this app already has on hand.

Public GETs here only need the app's Client ID (trakt-api-key header) — no
user OAuth — the same "read-only, app-level key" shape TMDB
already uses elsewhere in this codebase. Free to register at
https://app.trakt.tv/settings/apps/api (click the + in the top right).
"""

import asyncio
from typing import List, Optional

import httpx

from app.config import settings

TRAKT_BASE = "https://api.trakt.tv"
TRAKT_ATTRIBUTION = "Отзывы предоставлены Trakt"

# 100/page is the commonly-documented safe ceiling for Trakt's
# unauthenticated, app-level pagination (their own docs only guarantee a
# per-method max where one's explicitly listed; 100 is the same "sane
# default" third-party Trakt clients converge on for methods without one).
# _TRAKT_COMMENTS_MAX_PAGES caps the total page walk — 5 pages * 100 = up
# to 500 raw comments considered before app/routers/reviews.py filters
# down to substantial, non-spoiler ones — for the same "don't turn one
# very-active title into unbounded calls" reason TmdbAdapter.reviews caps
# its own page walk.
_PAGE_LIMIT = 100
_TRAKT_COMMENTS_MAX_PAGES = 5

# Trakt's own split is "movies"/"shows" (plural, in the URL) and
# "movie"/"show" (singular, as the `type` param and the JSON key on a
# search hit) — neither matches TMDB's "movie"/"tv" naming used elsewhere
# in this app, so callers pass this app's segment ("movie"/"tv") and this
# adapter does its own translation internally rather than leaking Trakt's
# vocabulary into app/routers/reviews.py.
_SINGULAR = {"movie": "movie", "tv": "show"}
_PLURAL = {"movie": "movies", "tv": "shows"}


class TraktAdapter:
    source_name = "trakt"

    def _headers(self) -> dict:
        return {
            "Content-Type": "application/json",
            "trakt-api-version": "2",
            "trakt-api-key": settings.trakt_client_id,
        }

    async def _trakt_id(self, client: httpx.AsyncClient, tmdb_id: str, kind: str) -> Optional[str]:
        """kind is Trakt's singular "movie"/"show". Returns a slug (stabler
        for a one-off lookup than the numeric id) or None if TMDB's id
        doesn't resolve to anything Trakt knows about — an ordinary case,
        not an error."""
        resp = await client.get(
            f"{TRAKT_BASE}/search/tmdb/{tmdb_id}",
            params={"type": kind},
            headers=self._headers(),
        )
        if resp.status_code != 200:
            return None
        hits = resp.json()
        if not hits:
            return None
        item = (hits[0] or {}).get(kind) or {}
        ids = item.get("ids") or {}
        trakt_num = ids.get("trakt")
        return ids.get("slug") or (str(trakt_num) if trakt_num else None)

    async def comments(self, tmdb_id: str, segment: str) -> List[dict]:
        """segment: this app's "movie"/"tv" (same as TmdbAdapter.reviews).
        Returns raw Trakt comment objects sorted by likes (their proxy for
        "most useful first"), walking every page Trakt reports via
        X-Pagination-Page-Count rather than stopping at the first one —
        a single page of 25 was quietly capping how many Trakt comments
        ever made it into the merged reviews list. Capped at
        _TRAKT_COMMENTS_MAX_PAGES for the same reason TmdbAdapter.reviews
        caps its own page walk: this is cached for REVIEWS_TTL (see
        app/routers/reviews.py), so the cost is paid once per cache
        window, not per request.

        Empty list for any lookup miss — no TRAKT_CLIENT_ID configured,
        title not on Trakt, no comments yet — same "just hide the
        section" convention as the rest of this file."""
        if not settings.trakt_client_id:
            return []
        kind = _SINGULAR.get(segment)
        if not kind:
            return []
        async with httpx.AsyncClient(timeout=10.0) as client:
            trakt_id = await self._trakt_id(client, tmdb_id, kind)
            if not trakt_id:
                return []
            base_url = f"{TRAKT_BASE}/{_PLURAL[segment]}/{trakt_id}/comments/likes"
            resp = await client.get(
                base_url,
                params={"page": 1, "limit": _PAGE_LIMIT, "extended": "full"},
                headers=self._headers(),
            )
            if resp.status_code != 200:
                return []
            results = list(resp.json() or [])
            try:
                page_count = min(int(resp.headers.get("X-Pagination-Page-Count", 1)), _TRAKT_COMMENTS_MAX_PAGES)
            except (TypeError, ValueError):
                page_count = 1
            if page_count > 1:
                more = await asyncio.gather(
                    *[
                        client.get(
                            base_url,
                            params={"page": page, "limit": _PAGE_LIMIT, "extended": "full"},
                            headers=self._headers(),
                        )
                        for page in range(2, page_count + 1)
                    ],
                    return_exceptions=True,
                )
                for page_resp in more:
                    if isinstance(page_resp, Exception):
                        continue
                    if page_resp.status_code == 200:
                        results += page_resp.json() or []
            return results
