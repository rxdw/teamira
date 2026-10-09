"""Steam reviews for a game — the cached layer between the routers and
app/adapters/steam_reviews.py. Same rules as app/kinopoisk.py and
app/book_ratings.py (see app/source_cache.py): a real answer, including "this
game has no Steam page" and "no reviews", is cached; "couldn't ask" is not,
and the last known copy is served instead when a refresh fails.

Lookups for a never-seen game, all cached:
  1. IGDB game id -> Steam appid        (a year; "no Steam page" 30 days)
  2. appid -> all-language totals plus review texts in the caller's
     language: one cache row, 2 Steam requests (14 days; "no reviews" 7)
Repeat opens cost nothing until those expire. Expiry is lazy: nothing is
refreshed in the background.

The reader's language picks the review language (Russian for lang=ru,
English otherwise) — Steam filters by language server-side, so a Russian
reader sees Russian reviews of the game, not a translated pile of English.
"""

import logging
from datetime import timedelta
from typing import Optional

from pydantic import BaseModel

from app import cache, source_cache
from app.adapters.igdb import IgdbAdapter
from app.adapters.steam_reviews import SteamReviews, SteamReviewsAdapter, SteamUnavailable

logger = logging.getLogger("seenly.game_reviews")

APPID_TTL = timedelta(days=365)
APPID_MISSING_TTL = timedelta(days=30)
REVIEWS_TTL = timedelta(days=14)
# Short, like Kinopoisk's "not found": a new game's reviews pile up fast.
REVIEWS_MISSING_TTL = timedelta(days=7)

_igdb = IgdbAdapter()
_steam = SteamReviewsAdapter()


class SteamApp(BaseModel):
    """IGDB game -> Steam. `appid=None` is the cached "no Steam page"."""
    appid: Optional[str] = None


def _norm_lang(lang: str) -> str:
    return "ru" if lang == "ru" else "en"


def _appid_ttl(raw: Optional[str]) -> timedelta:
    if raw is None:
        return APPID_TTL  # nothing stored, nothing to expire
    try:
        return APPID_TTL if SteamApp.model_validate_json(raw).appid else APPID_MISSING_TTL
    except Exception:  # noqa: BLE001 — unreadable copy: just refetch soon
        return APPID_MISSING_TTL


def _reviews_ttl(raw: Optional[str]) -> timedelta:
    if raw is None:
        return REVIEWS_TTL
    try:
        return REVIEWS_MISSING_TTL if SteamReviews.model_validate_json(raw).missing else REVIEWS_TTL
    except Exception:  # noqa: BLE001
        return REVIEWS_MISSING_TTL


async def _fetch_appid(igdb_id: str) -> SteamApp:
    try:
        return SteamApp(appid=await _igdb.steam_appid(igdb_id))
    except Exception as exc:  # IGDB down / not configured: not the same as "no Steam page"
        raise SteamUnavailable(f"IGDB lookup failed: {type(exc).__name__}") from exc


async def get_appid(igdb_id: str) -> Optional[str]:
    """The Steam appid for an IGDB game id (digits only, no "igdb-"
    prefix), or None when the game has no Steam page or IGDB can't be asked
    right now. Shared by the reviews below and by app/game_store.py (price,
    languages, screenshots) so one game costs one IGDB lookup, not two."""
    app_key = f"steam:appid:{igdb_id}"
    try:
        ttl = _appid_ttl(cache.get_dynamic_stale(None, app_key))
    except Exception:  # noqa: BLE001
        ttl = APPID_MISSING_TTL
    app = await source_cache.load(
        app_key, lambda: _fetch_appid(igdb_id), ttl,
        SteamApp, SteamUnavailable, logger, "Steam appid",
    )
    if app is None or not app.appid:
        return None
    return app.appid


async def get_reviews(igdb_id: str, lang: str) -> Optional[SteamReviews]:
    """The Steam reviews for an IGDB game id (digits only, no "igdb-"
    prefix), or None when the game has no Steam page or it can't be asked
    right now — callers just show no reviews."""
    lang = _norm_lang(lang)
    appid = await get_appid(igdb_id)
    if not appid:
        return None

    key = f"steam:reviews:{appid}:{lang}"
    try:
        ttl = _reviews_ttl(cache.get_dynamic_stale(None, key))
    except Exception:  # noqa: BLE001
        ttl = REVIEWS_MISSING_TTL
    result = await source_cache.load(
        key, lambda: _steam.fetch(appid, lang), ttl,
        SteamReviews, SteamUnavailable, logger, "Steam reviews",
    )
    if result is None or result.missing:
        return None
    return result
