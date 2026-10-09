"""AniList reviews and score for a manga — the cached layer between the
routers and app/adapters/anilist.py. Same rules as app/game_reviews.py and
app/kinopoisk.py (see app/source_cache.py): a real answer, including "AniList
has no such manga", is cached; "couldn't ask" is not, and the last known copy
is served instead when a refresh fails.

One request per never-seen manga. A manga's best reviews and its mean score
barely move, so the answer is kept 30 days ("not on AniList": 7).
"""

import logging
from datetime import timedelta
from typing import Optional

from app import cache, source_cache
from app.adapters.anilist import AniListAdapter, AniListInfo, AniListManga, AniListUnavailable

logger = logging.getLogger("seenly.manga_reviews")

MANGA_TTL = timedelta(days=30)
MANGA_MISSING_TTL = timedelta(days=7)

_adapter = AniListAdapter()

# Our manga ids are `shikimanga-<id>`, and Shikimori's numeric manga id is
# the same number as the MyAnimeList id — which is what AniList looks up by.
SHIKIMORI_MANGA_PREFIX = "shikimanga-"


def mal_id_from_media_id(media_id: str) -> Optional[int]:
    if not media_id.startswith(SHIKIMORI_MANGA_PREFIX):
        return None
    raw = media_id[len(SHIKIMORI_MANGA_PREFIX):]
    return int(raw) if raw.isdigit() else None


def _ttl(raw: Optional[str]) -> timedelta:
    if raw is None:
        return MANGA_TTL
    try:
        return MANGA_MISSING_TTL if AniListManga.model_validate_json(raw).missing else MANGA_TTL
    except Exception:  # noqa: BLE001 — unreadable copy: just refetch soon
        return MANGA_MISSING_TTL


async def get_manga(mal_id: int) -> Optional[AniListManga]:
    """AniList's data for a manga, or None when AniList doesn't have it or
    can't be asked right now — callers just show no AniList score/reviews."""
    key = f"al:manga:{mal_id}"
    try:
        ttl = _ttl(cache.get_dynamic_stale(None, key))
    except Exception:  # noqa: BLE001
        ttl = MANGA_MISSING_TTL
    manga = await source_cache.load(
        key, lambda: _adapter.manga(mal_id), ttl,
        AniListManga, AniListUnavailable, logger, "AniList",
    )
    return None if manga is None or manga.missing else manga


# ---------------------------------------------------------------------------
# The title "passport" (weighted tags, popularity, banner, legal places to
# read, source material) — its own query and its own cache row, so a bad day
# for this newer query can never take the reviews above down with it. Used
# for manga and for anime: Shikimori's anime id is the MyAnimeList id too.
# ---------------------------------------------------------------------------

INFO_TTL = timedelta(days=30)
INFO_MISSING_TTL = timedelta(days=7)


def _info_ttl(raw: Optional[str]) -> timedelta:
    if raw is None:
        return INFO_TTL
    try:
        return INFO_MISSING_TTL if AniListInfo.model_validate_json(raw).missing else INFO_TTL
    except Exception:  # noqa: BLE001
        return INFO_MISSING_TTL


async def get_info(mal_id: int, kind: str = "manga") -> Optional[AniListInfo]:
    """AniList's passport of a manga (or anime) by MyAnimeList id, or None
    when AniList doesn't have it or can't be asked right now."""
    kind = "anime" if kind == "anime" else "manga"
    key = f"al:info:{kind}:{mal_id}"
    try:
        ttl = _info_ttl(cache.get_dynamic_stale(None, key))
    except Exception:  # noqa: BLE001
        ttl = INFO_MISSING_TTL
    info = await source_cache.load(
        key, lambda: _adapter.info(mal_id, kind), ttl,
        AniListInfo, AniListUnavailable, logger, "AniList info",
    )
    return None if info is None or info.missing else info
