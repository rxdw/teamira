"""Kinopoisk data for Russian-language users — the cached layer between the
routers and app/adapters/poiskkino.py.

Why this isn't just another entry in routers/reviews.py::fetch_reviews:
that merged TMDB+Trakt list is cached for days *including* an empty result
from a source that merely failed. Fine for sources that rarely fail; wrong
for one with a 200/day free quota and a habit of being unreachable from
some networks. So Kinopoisk lives in its own cache entries and follows one
rule:

    answered (found, or "not on Kinopoisk")  -> cached
    couldn't answer (quota, network, 429...) -> NOT cached; the last known
                                                copy is served if there is
                                                one, otherwise skipped

`cache.cached_dynamic` stores whatever its fetch returns and stores nothing
when the fetch raises, so the adapter's KpUnavailable is what keeps a bad
minute from being remembered for a week.

Cost per never-seen title: 1 request for the title match + ratings, 1 for
reviews. Repeat opens cost zero until the entries expire (21/14 days for
a release under a year old, 120/90 for older ones — see the TTL table
below). Expiry is lazy —
nothing is refreshed in the background, an entry is only re-fetched when
someone opens that title after it went stale — and an expired entry is not
thrown away: if the refresh can't happen (quota used up, API unreachable),
the old copy is shown instead of nothing.
"""

import logging
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from app import cache, source_cache
from app.adapters.poiskkino import KpReview, KpReviews, KpTitle, KpUnavailable, PoiskKinoAdapter

logger = logging.getLogger("seenly.kinopoisk")

# How long cached entries live depends on how old the title is. A recent
# release is still moving — its rating settles and reviews pile up over the
# first months — so it's refreshed more often; a classic's numbers and its
# most-liked reviews are effectively stable, so it's re-fetched rarely
# (still not "never": reviews do get deleted, and ratings drift).
#
#                      title match + ratings    reviews
#   released < 1 year          21 days           14 days
#   older                     120 days           90 days
#   "not on Kinopoisk"          7 days             —
#
# "Not found" is kept short on purpose: for a fresh release it usually
# means Kinopoisk just hasn't added the page yet.
KP_TITLE_TTL_RECENT = timedelta(days=21)
KP_REVIEWS_TTL_RECENT = timedelta(days=14)
KP_TITLE_TTL_CLASSIC = timedelta(days=120)
KP_REVIEWS_TTL_CLASSIC = timedelta(days=90)
KP_MISSING_TTL = timedelta(days=7)


def is_recent(year: Optional[int], now: Optional[datetime] = None) -> bool:
    """Released less than a year ago. The API only gives the year, so the
    release is taken to be mid-year (1 July): a 2026 title is "recent"
    until July 2027, a 2025 title stopped being recent in July 2026.
    Unknown year counts as recent — the safer side (fresher data)."""
    if not year:
        return True
    now = now or datetime.now(timezone.utc)
    return now - datetime(year, 7, 1, tzinfo=timezone.utc) < timedelta(days=365)


def _title_ttl(raw: Optional[str]) -> timedelta:
    """TTL for a title entry, from the copy already stored (the year is
    only known once we've fetched it once; with nothing stored there's
    nothing to expire, so the value is unused)."""
    if raw is None:
        return KP_TITLE_TTL_RECENT
    try:
        title = KpTitle.model_validate_json(raw)
    except Exception:  # noqa: BLE001 — unreadable copy: just refetch soon
        return KP_TITLE_TTL_RECENT
    if title.missing:
        return KP_MISSING_TTL
    return KP_TITLE_TTL_RECENT if is_recent(title.year) else KP_TITLE_TTL_CLASSIC


def _reviews_ttl(title: KpTitle) -> timedelta:
    return KP_REVIEWS_TTL_RECENT if is_recent(title.year) else KP_REVIEWS_TTL_CLASSIC


_adapter = PoiskKinoAdapter()


def enabled() -> bool:
    return _adapter.configured()


def _segment(is_series: bool) -> str:
    return "tv" if is_series else "movie"


def page_url(kp_id: int, is_series: bool) -> str:
    """The title's reviews page on kinopoisk.ru — where "read the whole
    review" goes (the API gives no per-review permalink)."""
    return f"https://www.kinopoisk.ru/{'series' if is_series else 'film'}/{kp_id}/reviews/"


async def _load(key: str, fetch, ttl: timedelta, model):
    return await source_cache.load(key, fetch, ttl, model, KpUnavailable, logger, "Kinopoisk")


async def get_title(tmdb_id: str, is_series: bool) -> Optional[KpTitle]:
    """None for "unknown or unavailable" — callers just don't show the
    Kinopoisk bits."""
    key = f"kp:title:{_segment(is_series)}:{tmdb_id}"
    try:
        ttl = _title_ttl(cache.get_dynamic_stale(None, key))
    except Exception:  # noqa: BLE001
        ttl = KP_TITLE_TTL_RECENT
    title = await _load(key, lambda: _adapter.find_title(tmdb_id, is_series), ttl, KpTitle)
    return None if title is None or title.missing else title


async def get_reviews(tmdb_id: str, is_series: bool) -> List[KpReview]:
    title = await get_title(tmdb_id, is_series)
    if title is None or not title.kp_id:
        return []
    kp_id = title.kp_id

    async def _fetch() -> KpReviews:
        return KpReviews(reviews=await _adapter.reviews(kp_id))

    loaded = await _load(f"kp:reviews:{kp_id}", _fetch, _reviews_ttl(title), KpReviews)
    return loaded.reviews if loaded else []
