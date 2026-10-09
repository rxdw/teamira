"""Written reviews for a title — TMDB + Trakt.

Of the rating sources this app already touches (IMDB, TMDB), only TMDB
used to hand back review *text* over a public API. Problem: TMDB's
/reviews is thin for a lot of titles — a couple of entries, often none. So
this now also pulls Trakt's /comments (see app/adapters/trakt.py), which
covers the same movies/shows with a much bigger, more active user base,
and merges the two into one list. IMDB still has no public API for this
at all; their review pages are web-only and scraping them would violate
IMDB's terms.

Games and manga use the same list shape but their own sources, looked up by
the title's own id instead of a TMDB id: games -> Steam (app/game_reviews.py),
manga -> AniList (app/manga_reviews.py). Books have no review text anywhere
we may legally show (see app/adapters/hardcover.py).
"""

import asyncio
import logging
from datetime import timedelta
from typing import List, Optional

from fastapi import APIRouter, Depends, Query, Request

from app import cache, game_reviews, kinopoisk, manga_reviews
from app.adapters.tmdb import TmdbAdapter
from app.adapters.trakt import TraktAdapter
from app.deps import get_current_user_id
from app.rate_limit import client_key, reviews_limiter
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
    normal TMDB image path — this unwraps that case. A real TMDB-hosted
    path is returned bare (no base, no proxying) — see
    TmdbReviewOut.avatar_url's own field_serializer in app/schemas.py,
    which resolves it at response time, same as every other TMDB image
    field (app/image_urls.py has the full reasoning)."""
    if not path:
        return None
    if path.startswith("/http"):
        return path[1:]
    return path


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


_KP_ATTRIBUTION = "Отзывы предоставлены TMDB, Trakt и Кинопоиск (через ПоискКино)"


async def _with_kinopoisk(base: TmdbReviewsOut, tmdb_id: str, is_series: bool) -> TmdbReviewsOut:
    """Kinopoisk reviews go first for Russian-language callers — they're
    the longest, written in Russian, and the source this audience came
    for — followed by the TMDB/Trakt list in its own newest-first order.

    Kept out of fetch_reviews on purpose: that result is cached for days
    even when a source merely failed, which is wrong for a quota-limited,
    sometimes-unreachable source (see app/kinopoisk.py). Here a Kinopoisk
    miss just means this one response has no Kinopoisk section."""
    kp_reviews = await kinopoisk.get_reviews(tmdb_id, is_series)
    if not kp_reviews:
        return base
    title = await kinopoisk.get_title(tmdb_id, is_series)
    url = kinopoisk.page_url(title.kp_id, is_series) if title and title.kp_id else ""
    mapped = [
        TmdbReviewOut(
            author=r.author,
            avatar_url=None,
            rating=r.rating,
            content=r.text,
            created_at=r.created_at,
            url=url,
            source="kinopoisk",
            title=r.title,
            tone=r.tone,
            likes=r.likes,
        )
        for r in kp_reviews
    ]
    return TmdbReviewsOut(reviews=mapped + base.reviews, attribution=_KP_ATTRIBUTION)


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


_STEAM_ATTRIBUTION = "Отзывы предоставлены Steam"
_ANILIST_ATTRIBUTION = "Отзывы предоставлены AniList"


def _anilist_tone(score10: Optional[float]) -> Optional[str]:
    """AniList reviews carry a 0-100 score but no tone; the card's tape tag
    is derived from the score (7 and up reads positive, under 5 negative)."""
    if score10 is None:
        return None
    if score10 >= 7:
        return "positive"
    if score10 < 5:
        return "negative"
    return "neutral"


def steam_review_list(result: game_reviews.SteamReviews) -> List[TmdbReviewOut]:
    """Kept in Steam's own order (most helpful first) — not re-sorted by
    date like the TMDB/Trakt list, since "helpful" is why these are shown."""
    return [
        TmdbReviewOut(
            author=r.author,
            avatar_url=r.avatar_url,
            rating=None,
            content=r.content,
            created_at=r.created_at,
            url=r.url,
            source="steam",
            tone="positive" if r.voted_up else "negative",
            likes=r.votes_up or None,
            playtime_hours=r.playtime_hours,
        )
        for r in result.reviews
    ]


def anilist_review_list(manga: manga_reviews.AniListManga) -> List[TmdbReviewOut]:
    return [
        TmdbReviewOut(
            author=r.author,
            avatar_url=r.avatar_url,
            rating=r.score,
            content=r.content,
            created_at=r.created_at,
            url=r.url or (manga.url or ""),
            source="anilist",
            title=r.title,
            tone=_anilist_tone(r.score),
            likes=r.helpful or None,
        )
        for r in manga.reviews
    ]


async def game_reviews_out(media_id: Optional[str], lang: str) -> TmdbReviewsOut:
    """Steam reviews for an `igdb-<id>` game; empty when it has no Steam
    page, none in this language, or Steam can't be asked right now."""
    if not media_id or not media_id.startswith("igdb-"):
        return TmdbReviewsOut(reviews=[])
    raw_id = media_id[len("igdb-"):]
    result = await game_reviews.get_reviews(raw_id, lang) if raw_id.isdigit() else None
    if result is None or not result.reviews:
        return TmdbReviewsOut(reviews=[])
    return TmdbReviewsOut(reviews=steam_review_list(result), attribution=_STEAM_ATTRIBUTION)


async def manga_reviews_out(media_id: Optional[str]) -> TmdbReviewsOut:
    """AniList reviews for a `shikimanga-<id>` manga (Shikimori's id is the
    MyAnimeList id AniList looks up by)."""
    mal_id = manga_reviews.mal_id_from_media_id(media_id or "")
    if mal_id is None:
        return TmdbReviewsOut(reviews=[])
    manga = await manga_reviews.get_manga(mal_id)
    if manga is None or not manga.reviews:
        return TmdbReviewsOut(reviews=[])
    return TmdbReviewsOut(reviews=anilist_review_list(manga), attribution=_ANILIST_ATTRIBUTION)


@router.get("/reviews", response_model=TmdbReviewsOut)
async def media_reviews(
    request: Request,
    media_type: str = Query(...),
    tmdb_id: Optional[str] = Query(None),
    media_id: Optional[str] = Query(None),  # games ("igdb-…") and manga ("shikimanga-…")
    lang: str = Query("en"),  # "en" | "ru" — client's content-language setting
    _user_id: str = Depends(get_current_user_id),
):
    """`lang=ru` additionally includes Kinopoisk reviews (see
    _with_kinopoisk); anything else is TMDB + Trakt exactly as before.

    `media_type=game` (with `media_id=igdb-…`) returns Steam reviews in the
    caller's language; `media_type=manga` (with `media_id=shikimanga-…`)
    returns AniList reviews (mostly English).

    Empty (not an error) whenever there's nothing to show: no tmdb_id
    (books), no Steam page / AniList entry, or neither TMDB nor Trakt has written
    reviews for this title — both ordinary, same "hide the section"
    convention as /media/watch-providers.

    No `db: Session = Depends(get_db)` here — same reasoning as
    routers/media.py::search_media: this endpoint's only DB use is the
    cache read/write below, and the underlying fetch (fetch_reviews) is
    a concurrent TMDB+Trakt round trip. This one's hit on every title
    detail screen open, same traffic shape as search, so it gets the
    same fix.

    Requires a logged-in caller (get_current_user_id — DB-free, see its
    own docstring) and an IP rate limit (reviews_limiter, `db=None` for
    the same pool-exhaustion reason as above) — an uncached call here is
    a real TMDB+Trakt round trip, and this was previously reachable by
    anyone who knew this server's address."""
    reviews_limiter.check(None, client_key(request))
    if media_type == "game":
        return await game_reviews_out(media_id, lang)
    if media_type == "manga":
        return await manga_reviews_out(media_id)
    if not tmdb_id or media_type not in ("movie", "series", "anime"):
        return TmdbReviewsOut(reviews=[])

    segment = "movie" if media_type == "movie" else "tv"
    cache_key = f"reviews:{tmdb_id}:{segment}"
    payload_json = await cache.cached_dynamic(
        None, cache_key, lambda: fetch_reviews(tmdb_id, segment), ttl=REVIEWS_TTL,
    )
    base = TmdbReviewsOut.model_validate_json(payload_json)
    if lang == "ru" and kinopoisk.enabled():
        return await _with_kinopoisk(base, tmdb_id, is_series=(segment == "tv"))
    return base
