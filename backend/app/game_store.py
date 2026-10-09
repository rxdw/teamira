"""Steam store facts for a game — the cached layer between the routers and
app/adapters/steam_store.py. Same rules as app/game_reviews.py and
app/kinopoisk.py (see app/source_cache.py): a real answer, including "no
Steam store page", is cached; "couldn't ask" is not, and the last known copy
is served when a refresh fails.

Price is the reason this exists as its own refreshed layer: it must not sit
in the forever title-detail cache. A few days is short enough for a sale to
show up and long enough that a popular game costs a handful of requests a
week, not one per open.

Region: a Russian-language reader gets rubles, everyone else US dollars, so
the cache key carries the region.
"""

import logging
from datetime import timedelta
from typing import Optional

from app import cache, source_cache
from app import game_reviews
from app.adapters.steam_reviews import SteamUnavailable
from app.adapters.steam_store import SteamStore, SteamStoreAdapter

logger = logging.getLogger("seenly.game_store")

STORE_TTL = timedelta(days=3)
STORE_MISSING_TTL = timedelta(days=7)

_steam = SteamStoreAdapter()


def _region(lang: str) -> str:
    return "ru" if lang == "ru" else "us"


def _store_ttl(raw: Optional[str]) -> timedelta:
    if raw is None:
        return STORE_TTL
    try:
        return STORE_MISSING_TTL if SteamStore.model_validate_json(raw).missing else STORE_TTL
    except Exception:  # noqa: BLE001 — unreadable copy: just refetch soon
        return STORE_MISSING_TTL


async def get_store(igdb_id: str, lang: str) -> Optional[SteamStore]:
    """Steam store facts for an IGDB game id (digits only, no "igdb-"
    prefix), or None when the game has no Steam page or it can't be asked
    right now — callers just show the game without them."""
    appid = await game_reviews.get_appid(igdb_id)
    if not appid:
        return None
    region = _region(lang)
    # v2: rows cached before requirements/platforms/Deck existed lack them, and
    # would otherwise be served for up to STORE_TTL without them.
    key = f"steam:store:v2:{appid}:{region}"
    try:
        ttl = _store_ttl(cache.get_dynamic_stale(None, key))
    except Exception:  # noqa: BLE001
        ttl = STORE_MISSING_TTL
    store = await source_cache.load(
        key, lambda: _steam.fetch(appid, lang), ttl,
        SteamStore, SteamUnavailable, logger, "Steam store",
    )
    if store is None or store.missing:
        return None
    return store
