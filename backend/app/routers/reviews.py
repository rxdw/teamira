"""Written reviews for a title — TMDB + Trakt.

Of the rating sources this app already touches (IMDB, TMDB), only TMDB
used to hand back review *text* over a public API. Problem: TMDB's
/reviews is thin for a lot of titles — a couple of entries, often none. So
this now also pulls Trakt's /comments (see app/adapters/trakt.py), which
covers the same movies/shows with a much bigger, more active user base,
and merges the two into one list. IMDB still has no public API for this
at all; their review pages are web-only and scraping them would violate
IMDB's terms.
"""

import asyncio
import logging
from datetime import timedelta
from typing import List, Optional

from fastapi import APIRouter, Query, Depends
from sqlalchemy.orm import Session

from app import cache
from app.database import get_db
from app.adapters.tmdb import TmdbAdapter, TMDB_PROFILE_BASE
from app.adapters.trakt import TraktAdapter
from app.schemas import TmdbReviewOut, TmdbReviewsOut

logger = logging.getLogger("seenly.routers.reviews")

router = APIRouter(prefix="/media", tags=["reviews"])
_tmdb = TmdbAdapter()
_trakt = TraktAdapter()

# Reviews trickle in slowly and don't need to be near-realtime — a few
# days stale is unnoticeable, same tradeoff as watch-providers' 3-day TTL.
REVIEWS_TTL = timedelta(days=3)

# Trakt comments are short-form chat as often as they're a real review —
# this filters out the driveby one-liners ("lol so good") so the merged
# list stays closer to "written review" than "comment section". TMDB's
# reviews don't need this: everything TMDB returns already went through
# their own "write a review" flow, not a comment box.
_TRAKT_MIN_CHARS = 40


def _avatar_url(path: Optional[str]) -> Optional[str]:
    """TMDB's `author_details.avatar_path` is occasionally a full
    external (Gravatar) URL prefixed with "/https://..." rather than a
    normal TMDB image path — this unwraps that case; a real TMDB-hosted
    path just gets the usual base prepended."""
    if not path:
        return None
    if path.startswith("/http"):
        return path[1:]
    return f"{TMDB_PROFILE_BASE}{path}"


def _tmdb_reviews(raw: list) -> List[TmdbReviewOut]:
    return [
        TmdbReviewOut(
            author=r.get("author") or (r.get("author_details") or {}).get("username") or "Anonymous",
            avatar_url=_avatar_url((r.get("author_details") or {}).get("avatar_path")),
            rating=(r.get("author_details") or {}).get("rating"),
            content=r.get("content") or "",
            created_at=r.get("created_at"),
            url=r.get("url") or "",
            source="tmdb",
        )
        for r in raw
        if r.get("content")
    ]


def _trakt_reviews(raw: list) -> List[TmdbReviewOut]:
    out = []
    for c in raw:
        if c.get("spoiler"):
            continue
        content = (c.get("comment") or "").strip()
        if len(content) < _TRAKT_MIN_CHARS:
            continue
        user = c.get("user") or {}
        avatar = (((user.get("images") or {}).get("avatar")) or {}).get("full")
        comment_id = c.get("id")
        out.append(
            TmdbReviewOut(
                author=user.get("username") or "Anonymous",
                avatar_url=avatar,
                rating=c.get("user_rating"),
                content=content,
                created_at=c.get("created_at"),
                url=f"https://trakt.tv/comments/{comment_id}" if comment_id else "",
                source="trakt",
            )
        )
    return out


def _sort_key(r: TmdbReviewOut) -> float:
    """Newest first, across both sources combined. A missing timestamp
    (rare) just sinks to the bottom instead of crashing the sort — avoids
    comparing None/naive/aware datetimes against each other directly."""
    if r.created_at is None:
        return 0.0
    try:
        return r.created_at.timestamp()
    except (OverflowError, OSError, ValueError):
        return 0.0


async def fetch_reviews(tmdb_id: str, segment: str) -> TmdbReviewsOut:
    """segment is this app's "movie"/"tv" split. Fetches both sources
    concurrently; either one failing (missing key, network hiccup, 404)
    just contributes an empty list rather than failing the whole request —
    same "hide, don't error" convention the rest of this file uses.
    Public (no leading underscore) because app/routers/media.py reuses
    this — plus its cache entry — to back the review-count badge on the
    title screen."""
    tmdb_task = _tmdb.reviews(tmdb_id, segment)
    trakt_task = _trakt.comments(tmdb_id, segment)
    tmdb_raw, trakt_raw = await asyncio.gather(tmdb_task, trakt_task, return_exceptions=True)

    if isinstance(tmdb_raw, Exception):
        logger.warning("TMDB reviews fetch failed for %s/%s: %s", segment, tmdb_id, tmdb_raw)
        tmdb_raw = []
    if isinstance(trakt_raw, Exception):
        logger.warning("Trakt comments fetch failed for %s/%s: %s", segment, tmdb_id, trakt_raw)
        trakt_raw = []

    reviews = _tmdb_reviews(tmdb_raw) + _trakt_reviews(trakt_raw)
    reviews.sort(key=_sort_key, reverse=True)
    return TmdbReviewsOut(reviews=reviews)


@router.get("/reviews", response_model=TmdbReviewsOut)
async def media_reviews(
    media_type: str = Query(...),
    tmdb_id: Optional[str] = Query(None),
    db: Session = Depends(get_db),
):
    """Empty (not an error) whenever there's nothing to show: no tmdb_id
    (games, books, or manga), or neither TMDB nor Trakt has written
    reviews for this title — both ordinary, same "hide the section"
    convention as /media/watch-providers."""
    if not tmdb_id or media_type not in ("movie", "series", "anime"):
        return TmdbReviewsOut(reviews=[])

    segment = "movie" if media_type == "movie" else "tv"
    cache_key = f"reviews:{tmdb_id}:{segment}"
    payload_json = await cache.cached_dynamic(
        db, cache_key, lambda: fetch_reviews(tmdb_id, segment), ttl=REVIEWS_TTL,
    )
    return TmdbReviewsOut.model_validate_json(payload_json)
