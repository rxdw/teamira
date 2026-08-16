"""
TMDB (and other adapter) response cache, backed by the two tables in
models.py.

Why this exists: TMDB's API has rate limits, and most of what we ask it
for doesn't change from one request to the next within a day (or, for a
single title's own detail, basically ever). Two tiers:

- Static (`get_static_title` / `set_static_title`): one title's detail —
  synopsis, genres, runtime, ratings, similar titles. Cached forever once
  answered for a given (media_id, source). If a title's ratings drift
  slightly over months, that's an accepted tradeoff for the point of this
  cache — burning a fresh TMDB call every time someone opens a title page
  defeats the purpose.
- Dynamic (`cached_dynamic`): collections, the discover feed, the movies
  feed — genuinely time-varying, but only worth re-fetching once every 24h.
  Whichever request finds the cache missing/stale pays for the upstream
  calls; every other request in that window reads the cached JSON back out.

Concurrency note: `cached_dynamic`'s per-key `asyncio.Lock` makes
concurrent requests *within this process* share one fetch instead of each
independently hitting the upstream API when the cache is stale — i.e. "the
first request pays, the rest wait and then read the same result" holds within a
single running API process. It does NOT coordinate across multiple
replicas of the API (there's no cross-process lock here, e.g. via Postgres
advisory locks) — if you ever scale `api` beyond one replica, two replicas
could both refresh the same stale key at nearly the same moment. Fine for
this project's current single-container docker-compose setup; worth
revisiting with a DB-level lock if that changes.
"""

import asyncio
import json
from datetime import datetime, timedelta
from typing import Awaitable, Callable, Optional, TypeVar

from pydantic import BaseModel, TypeAdapter
from sqlalchemy.orm import Session

from app import models

T = TypeVar("T")

DYNAMIC_TTL = timedelta(hours=24)

# /feed/collections backs Home's "picked for tonight" / "more for tonight"
# and the Collections tab. This used to be a 30s "anti-spam cooldown" on
# the theory that pull-to-refresh should always hit these sources live —
# but TMDB/IGDB's own chart-style sources (best/premieres/trending/dvd)
# only refresh on THEIR schedule. Polling more often than that doesn't get
# fresher titles — it just re-fetches the identical chart that hasn't
# recomputed yet, for real cost against the ~19-shelf fan-out this endpoint
# does. A few hours is the right balance: frequent enough to pick up the
# upstream refresh well within the same day, not so frequent it burns
# requests re-asking for data that provably hasn't changed yet. The
# within-day feel of variety comes from get_collections() reshuffling shelf
# order and item order on every read of the cached pool (see
# routers/feed.py) — genuinely different combinations from the ~200+ items
# across all shelves, not a fake progress bar.
COLLECTIONS_TTL = timedelta(hours=3)

# /feed/teamira (hand-curated shelves, see app/routers/teamira.py) changes
# only when we edit it through the admin endpoints — nowhere near as often
# as the charts above — so a much longer TTL is fine here. Still
# not "forever": a tmdb_collection-kind shelf can grow (a new film added to
# a franchise), and we'd rather that show up within a day than require a
# manual cache-buster every time.
TEAMIRA_TTL = timedelta(hours=24)


# /media/search — deliberately much shorter than the other dynamic TTLs
# above: a search query is arbitrary user input, so this isn't a "the
# whole catalog reads one shared cache" tier the way collections/teamira
# are. It exists purely to collapse near-duplicate requests for the exact
# same (q, lang, include_*) combination that happen within a few seconds
# of each other — a debounced keystroke pair ("narut" then "naruto" typed
# with a pause in between), a filter-tab UI re-triggering the same query,
# a user re-opening the same search — into a single round trip to TMDB
# instead of one each. Long enough to absorb that kind of burst, short
# enough that a genuinely new search a minute later still hits live data
# rather than reading something stale.
SEARCH_TTL = timedelta(seconds=45)

_locks: dict[str, asyncio.Lock] = {}


def _lock_for(cache_key: str) -> asyncio.Lock:
    lock = _locks.get(cache_key)
    if lock is None:
        lock = asyncio.Lock()
        _locks[cache_key] = lock
    return lock


def _dump_json(value) -> str:
    # context={"raw": True} tells ImageFieldsModel's field_serializers
    # (schemas.py) to store poster_url/backdrop_url/etc. untouched rather
    # than resolving them against whatever PUBLIC_API_BASE_URL is
    # configured right now — see that mixin's docstring for why baking a
    # resolved (possibly proxied) URL into a cache row that can outlive
    # the current setting is exactly the bug this avoids.
    _RAW = {"raw": True}
    if isinstance(value, BaseModel):
        return value.model_dump_json(context=_RAW)
    if isinstance(value, list):
        if not value:
            return "[]"
        # Every item in one of our lists is the same Pydantic model type
        # (List[MediaItem], List[Collection], ...) — use the first item's
        # type to build the right TypeAdapter rather than assuming.
        item_type = type(value[0])
        return TypeAdapter(list[item_type]).dump_json(value, context=_RAW).decode("utf-8")
    return json.dumps(value)


# --- static: one title's detail, cached forever -----------------------------

def get_static_title(db: Session, media_id: str, source: str) -> Optional[str]:
    row = db.get(models.CachedTitleDetail, (media_id, source))
    return row.payload_json if row else None


def set_static_title(db: Session, media_id: str, source: str, payload) -> None:
    payload_json = _dump_json(payload)
    row = db.get(models.CachedTitleDetail, (media_id, source))
    if row is None:
        db.add(models.CachedTitleDetail(media_id=media_id, source=source, payload_json=payload_json))
    else:
        row.payload_json = payload_json
        row.cached_at = datetime.utcnow()
    db.commit()


def get_static_episodes(db: Session, media_id: str, source: str) -> Optional[str]:
    row = db.get(models.CachedEpisodes, (media_id, source))
    return row.payload_json if row else None


def set_static_episodes(db: Session, media_id: str, source: str, payload) -> None:
    payload_json = _dump_json(payload)
    row = db.get(models.CachedEpisodes, (media_id, source))
    if row is None:
        db.add(models.CachedEpisodes(media_id=media_id, source=source, payload_json=payload_json))
    else:
        row.payload_json = payload_json
        row.cached_at = datetime.utcnow()
    db.commit()


# --- static: one title's semantic embedding, cached forever -----------------
#
# Same shape as get_static_title/set_static_title above, just its own table
# (models.CachedEmbedding) and JSON-list-of-floats payload instead of a
# serialized Pydantic model — see app/embeddings.py for what computes these
# and app/routers/ai.py for the only caller. Forever-cache is the right call
# here for the same reason as static titles: the text a vector is derived
# from (title/genres/description) essentially never changes for an existing
# title, so there's nothing to gain from re-embedding it on a schedule —
# only from computing it once instead of on every Ask Teamira request that
# happens to surface that title as a candidate again.


def get_embedding(db: Session, media_id: str, source: str) -> Optional[list[float]]:
    row = db.get(models.CachedEmbedding, (media_id, source))
    if row is None:
        return None
    return json.loads(row.payload_json)


def set_embedding(db: Session, media_id: str, source: str, vector: list[float]) -> None:
    payload_json = json.dumps(vector)
    row = db.get(models.CachedEmbedding, (media_id, source))
    if row is None:
        db.add(models.CachedEmbedding(media_id=media_id, source=source, payload_json=payload_json))
    else:
        row.payload_json = payload_json
        row.cached_at = datetime.utcnow()
    db.commit()


# --- dynamic: catalog-wide data, refreshed at most once a day ---------------

def _get_dynamic_raw(db: Session, cache_key: str, ttl: timedelta) -> Optional[str]:
    row = db.get(models.CachedFeedSnapshot, cache_key)
    if row is None:
        return None
    if datetime.utcnow() - row.cached_at > ttl:
        return None
    return row.payload_json


def _set_dynamic_raw(db: Session, cache_key: str, payload_json: str) -> None:
    row = db.get(models.CachedFeedSnapshot, cache_key)
    if row is None:
        db.add(models.CachedFeedSnapshot(cache_key=cache_key, payload_json=payload_json))
    else:
        row.payload_json = payload_json
        row.cached_at = datetime.utcnow()
    db.commit()


async def cached_dynamic(
    db: Session,
    cache_key: str,
    fetch: Callable[[], Awaitable[T]],
    ttl: timedelta = DYNAMIC_TTL,
) -> str:
    """Returns cached JSON for `cache_key` if it's still fresh; otherwise
    awaits `fetch()` (which should return a Pydantic model or a list of
    them), caches the result, and returns that instead. Concurrent callers
    for the same stale key share a single `fetch()` call — see the module
    docstring for the single-process caveat."""
    cached = _get_dynamic_raw(db, cache_key, ttl)
    if cached is not None:
        return cached

    async with _lock_for(cache_key):
        # Another request may have refreshed this key while we were
        # waiting for the lock — check again before paying for a fetch.
        cached = _get_dynamic_raw(db, cache_key, ttl)
        if cached is not None:
            return cached
        result = await fetch()
        payload_json = _dump_json(result)
        _set_dynamic_raw(db, cache_key, payload_json)
        return payload_json
