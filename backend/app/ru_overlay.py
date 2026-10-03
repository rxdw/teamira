"""Russian title / synopsis / poster for TMDB items in *list* responses.

The client shows `poster_url_ru` (and `title.ru`) whenever the device is set to
Russian and the item carries them — see mobile/lib/models/media_item.dart.
But TMDB's list/discover endpoints are queried in English (the shared pool is
cached once for everyone), so a list item only has the English poster until
someone opens the title itself: GET /media/detail makes the per-title
`language=ru-RU` call that finds the Russian art. That is the "posters are
English everywhere and only turn Russian on the card" report.

This module closes that gap for the list endpoints (GET /feed, /feed/movies,
/feed/for-you) without touching their shared 24h caches: the cached pool stays
language-neutral, and the Russian fields are overlaid per response, only when
the caller asks for `lang=ru`.

Where the Russian data comes from — the same per-title lookup and the same
forever-cache row Collections already uses (routers/feed.py::
_apply_ru_supplement, `tmdb-ru-supplement-v3`), so a title looked up for a shelf
is already warm here and vice versa:

  * cached titles are read back in one bulk query (a pool is hundreds of
    titles — one query each would be a lot of short sessions);
  * a handful of cold titles are looked up inline, in parallel, within a small
    time budget, so the first view is already Russian for most of the screen;
  * everything beyond that, or still running when the budget ends, finishes in
    the background and lands in the cache, so the next load has it.

Never raises: a failed or slow lookup just leaves that item on its English
poster, exactly as before.
"""
from __future__ import annotations

import asyncio
import json
import logging
from typing import Dict, Iterable, List, Optional

from sqlalchemy import select

from app import cache, models
from app.adapters.tmdb import TmdbAdapter
from app.schemas import MediaItem

logger = logging.getLogger("seenly.ru_overlay")

# Shared with routers/feed.py::_apply_ru_supplement — one forever-cache row per
# title, written by whichever of the two reaches the title first.
RU_SUPPLEMENT_CACHE_SOURCE = "tmdb-ru-supplement-v3"

# Cold titles looked up *during* the request. Each is one TMDB call, so this is
# the real cost cap on a cold feed; the rest go to the background.
INLINE_LOOKUP_LIMIT = 24
# Wall-clock budget for those inline lookups. Past it the response goes out
# with whatever has arrived; unfinished lookups keep running and cache.
INLINE_BUDGET_SECONDS = 4.0
# Parallel TMDB calls, across all requests — a burst guard, same idea as
# routers/feed.py::_RU_SUPPLEMENT_CONCURRENCY.
_CONCURRENCY = 8
# Upper bound for one background pass, so a big cold pool can't keep a worker
# hammering TMDB for minutes after the request is long gone.
_BACKGROUND_LOOKUP_LIMIT = 200
_BULK_CHUNK = 500

_tmdb = TmdbAdapter()
_semaphore: Optional[asyncio.Semaphore] = None
# Strong references so fire-and-forget tasks aren't garbage-collected mid-run.
_background: set = set()
# Titles with a lookup in flight in this process, so two overlapping responses
# don't both pay TMDB for the same title.
_in_flight: set = set()


def _sem() -> asyncio.Semaphore:
    global _semaphore
    if _semaphore is None:
        _semaphore = asyncio.Semaphore(_CONCURRENCY)
    return _semaphore


def _is_tmdb(item: MediaItem) -> bool:
    return item.source == "tmdb" and bool(item.external_ids.tmdb)


def _bulk_cached(media_ids: List[str]) -> Dict[str, dict]:
    """media_id -> cached supplement, for every id that already has a row."""
    found: Dict[str, dict] = {}
    if not media_ids:
        return found
    from app.database import SessionLocal

    with SessionLocal() as s:
        for i in range(0, len(media_ids), _BULK_CHUNK):
            chunk = media_ids[i : i + _BULK_CHUNK]
            rows = s.execute(
                select(models.CachedTitleDetail.media_id, models.CachedTitleDetail.payload_json).where(
                    models.CachedTitleDetail.source == RU_SUPPLEMENT_CACHE_SOURCE,
                    models.CachedTitleDetail.media_id.in_(chunk),
                )
            ).all()
            for media_id, payload_json in rows:
                try:
                    found[media_id] = json.loads(payload_json)
                except (TypeError, ValueError):
                    continue
    return found


def _apply(item: MediaItem, supplement: dict) -> None:
    """Fills only what the lookup actually found — never clears a value the
    item already carries (a genuine miss leaves the English fallback alone)."""
    if supplement.get("title_ru"):
        item.title.ru = supplement["title_ru"]
    if supplement.get("overview_ru"):
        item.description.ru = supplement["overview_ru"]
    if supplement.get("poster_ru"):
        item.poster_url_ru = supplement["poster_ru"]


async def _lookup(item: MediaItem) -> None:
    """One cold title: ask TMDB, cache the answer forever, apply it.

    A transient failure (429, timeout, 5xx) is NOT cached — same rule as
    routers/feed.py::_apply_ru_supplement — so it is retried next time rather
    than being mistaken for "TMDB has nothing in Russian" forever."""
    if item.id in _in_flight:
        return
    _in_flight.add(item.id)
    try:
        segment = "tv" if item.media_type in ("series", "anime") else "movie"
        async with _sem():
            supplement = await _tmdb.shelf_ru_supplement(item.external_ids.tmdb, segment)
        cache.set_static_title(None, item.id, RU_SUPPLEMENT_CACHE_SOURCE, supplement)
        _apply(item, supplement)
    except Exception as exc:  # noqa: BLE001 — best effort by design
        logger.warning("ru overlay lookup failed [%s] -> %s", item.id, exc)
    finally:
        _in_flight.discard(item.id)


async def _background_fill(items: List[MediaItem]) -> None:
    await asyncio.gather(*(_lookup(i) for i in items), return_exceptions=True)


def _spawn(coro) -> None:
    task = asyncio.ensure_future(coro)
    _background.add(task)
    task.add_done_callback(_background.discard)


async def overlay_ru(items: Iterable[MediaItem]) -> None:
    """Fills title.ru / description.ru / poster_url_ru on TMDB items in place.

    `items` must be this response's own objects (the list endpoints build them
    fresh from the cached JSON on every request), never a shared cached list."""
    try:
        tmdb_items = [i for i in items if _is_tmdb(i)]
        if not tmdb_items:
            return

        cached = _bulk_cached([i.id for i in tmdb_items])
        cold: List[MediaItem] = []
        for item in tmdb_items:
            supplement = cached.get(item.id)
            if supplement is not None:
                _apply(item, supplement)
            else:
                cold.append(item)
        if not cold:
            return

        inline, rest = cold[:INLINE_LOOKUP_LIMIT], cold[INLINE_LOOKUP_LIMIT:]
        tasks = [asyncio.ensure_future(_lookup(i)) for i in inline]
        _, pending = await asyncio.wait(tasks, timeout=INLINE_BUDGET_SECONDS)
        # Not cancelled: they finish in the background and fill the cache.
        for task in pending:
            _background.add(task)
            task.add_done_callback(_background.discard)
        if rest:
            _spawn(_background_fill(rest[:_BACKGROUND_LOOKUP_LIMIT]))
    except Exception as exc:  # noqa: BLE001
        logger.warning("ru overlay skipped: %s", exc)


def wants_ru(lang: Optional[str]) -> bool:
    return (lang or "").strip().lower().startswith("ru")
