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

Concurrency note: `cached_dynamic` guards a stale key with two layers, an
in-process one and a cross-process one. The in-process `asyncio.Lock` per
key (`_lock_for`) is the cheap first gate — concurrent requests *within
this one worker* share a single fetch instead of each independently
hitting the upstream API, with no database round trip needed to get that
far. Behind that, `_advisory_lock` takes a Postgres advisory lock keyed
on the same cache key, so two *different* worker processes or replicas
racing to refresh the same stale key also serialize instead of both
paying for the upstream fetch at once — the loser just waits, then reads
back whatever the winner already wrote. This used to stop at the
in-process lock alone, with a comment here saying the cross-process case
was "fine for now, worth revisiting with a DB-level lock" — this is that
revisit, using the database this app already has rather than adding
Redis or similar just for this.

Connection-lifetime note: every function here takes `db: Optional[Session]`.
Pass a real session (the usual, still-supported way — every call site
outside media.py's search flow still does this) and it's used exactly as
before: read, maybe an awaited upstream fetch, write, all on that one
session, for as long as the caller holds it open. Pass `db=None` and
each function opens and closes its *own* short-lived session (see
`_session` below) for just the moment it's actually touching the
database — never held across an awaited upstream call. That matters
because `Depends(get_db)` (see database.py) checks out a pooled
connection for a route's *entire* request lifetime, including whatever
slow external I/O happens in between — database.py's own docstring
already flagged this as the cause of one real pool-exhaustion incident
(a burst of onboarding's concurrent /media/search calls). A route whose
only DB use is through these cache functions can drop
`db: Session = Depends(get_db)` from its signature entirely and pass
`db=None` everywhere instead — see routers/media.py's search_media for
the first example — so it never holds a pooled connection at all except
for the handful of brief moments it's actually reading or writing a
cache row.
"""

import asyncio
import json
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from typing import Awaitable, Callable, Optional, TypeVar

from pydantic import BaseModel, TypeAdapter
from sqlalchemy import text
from sqlalchemy.orm import Session

from app import models


@contextmanager
def _session(db: Optional[Session]):
    """Yields `db` if given, unmanaged — the caller opened it and the
    caller closes it, same as always. If `db` is None, opens a fresh,
    short-lived session of its own for just the `with` block, closing it
    on the way out. See this module's own docstring's "connection-
    lifetime note" for why a function would ever be called with `db=None`
    instead of just always requiring a real session."""
    if db is not None:
        yield db
        return
    from app.database import SessionLocal
    own_db = SessionLocal()
    try:
        yield own_db
    finally:
        own_db.close()


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

# The one place this literal lives. routers/teamira.py's GET handler (via
# cached_dynamic) and its admin write endpoints, plus the standalone
# seed_teamira_picks.py CLI/startup path, all need the *same* key — used
# to be hand-copied into two separate _invalidate_teamira_cache()
# functions that could silently drift apart if the key ever changed in
# only one of them. See invalidate_teamira_cache() below.
TEAMIRA_CACHE_KEY = "feed:teamira:v7"


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


class _advisory_lock:
    """Cross-process counterpart to `_lock_for` above — a Postgres
    advisory lock keyed on `cache_key` (via `hashtext()`, Postgres's own
    string→int4 hash), held on `db`'s own already-checked-out
    connection rather than opening a second one from the pool. Two
    worker processes (or replicas) both finding the same key stale at
    the same moment now actually take turns instead of both independently
    calling `fetch()`.

    Polls `pg_try_advisory_lock` (non-blocking) on a short interval
    rather than calling the blocking `pg_advisory_lock`, so waiting for
    the lock doesn't tie up this coroutine's turn on the event loop for
    however long the current holder's `fetch()` takes — same reasoning
    as everywhere else in this codebase that prefers polling a fast
    non-blocking check over one long blocking call inside `async def`.

    A no-op on non-Postgres binds (e.g. sqlite in tests), which don't
    have advisory locks at all — `_lock_for`'s in-process lock is the
    only guard there, same as before this existed. That's an accepted
    gap for tests, not for the real deployment target (see
    database.py: this app always runs on Postgres outside tests).
    """

    def __init__(self, db: Session, cache_key: str):
        self.db = db
        self.cache_key = cache_key
        self._is_postgres = db.get_bind().dialect.name == "postgresql"

    async def __aenter__(self):
        if not self._is_postgres:
            return self
        while True:
            got = self.db.execute(
                text("SELECT pg_try_advisory_lock(hashtext(:key)::bigint)"),
                {"key": self.cache_key},
            ).scalar()
            if got:
                return self
            await asyncio.sleep(0.05)

    async def __aexit__(self, exc_type, exc, tb):
        if self._is_postgres:
            self.db.execute(
                text("SELECT pg_advisory_unlock(hashtext(:key)::bigint)"),
                {"key": self.cache_key},
            )
        return False


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

def get_static_title(db: Optional[Session], media_id: str, source: str) -> Optional[str]:
    with _session(db) as s:
        row = s.get(models.CachedTitleDetail, (media_id, source))
        return row.payload_json if row else None


def set_static_title(db: Optional[Session], media_id: str, source: str, payload) -> None:
    payload_json = _dump_json(payload)
    with _session(db) as s:
        row = s.get(models.CachedTitleDetail, (media_id, source))
        if row is None:
            s.add(models.CachedTitleDetail(media_id=media_id, source=source, payload_json=payload_json))
        else:
            row.payload_json = payload_json
            row.cached_at = datetime.now(timezone.utc)
        s.commit()


def get_static_episodes(db: Optional[Session], media_id: str, source: str) -> Optional[str]:
    with _session(db) as s:
        row = s.get(models.CachedEpisodes, (media_id, source))
        return row.payload_json if row else None


def set_static_episodes(db: Optional[Session], media_id: str, source: str, payload) -> None:
    payload_json = _dump_json(payload)
    with _session(db) as s:
        row = s.get(models.CachedEpisodes, (media_id, source))
        if row is None:
            s.add(models.CachedEpisodes(media_id=media_id, source=source, payload_json=payload_json))
        else:
            row.payload_json = payload_json
            row.cached_at = datetime.now(timezone.utc)
        s.commit()


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


def get_embedding(db: Optional[Session], media_id: str, source: str) -> Optional[list[float]]:
    with _session(db) as s:
        row = s.get(models.CachedEmbedding, (media_id, source))
        if row is None:
            return None
        return json.loads(row.payload_json)


def set_embedding(db: Optional[Session], media_id: str, source: str, vector: list[float]) -> None:
    payload_json = json.dumps(vector)
    with _session(db) as s:
        row = s.get(models.CachedEmbedding, (media_id, source))
        if row is None:
            s.add(models.CachedEmbedding(media_id=media_id, source=source, payload_json=payload_json))
        else:
            row.payload_json = payload_json
            row.cached_at = datetime.now(timezone.utc)
        s.commit()


# --- dynamic: catalog-wide data, refreshed at most once a day ---------------

def _get_dynamic_raw(db: Optional[Session], cache_key: str, ttl: timedelta) -> Optional[str]:
    with _session(db) as s:
        row = s.get(models.CachedFeedSnapshot, cache_key)
        if row is None:
            return None
        if datetime.now(timezone.utc) - row.cached_at > ttl:
            return None
        return row.payload_json


def _set_dynamic_raw(db: Optional[Session], cache_key: str, payload_json: str) -> None:
    with _session(db) as s:
        row = s.get(models.CachedFeedSnapshot, cache_key)
        if row is None:
            s.add(models.CachedFeedSnapshot(cache_key=cache_key, payload_json=payload_json))
        else:
            row.payload_json = payload_json
            row.cached_at = datetime.now(timezone.utc)
        s.commit()


async def cached_dynamic(
    db: Optional[Session],
    cache_key: str,
    fetch: Callable[[], Awaitable[T]],
    ttl: timedelta = DYNAMIC_TTL,
) -> str:
    """Returns cached JSON for `cache_key` if it's still fresh; otherwise
    awaits `fetch()` (which should return a Pydantic model or a list of
    them), caches the result, and returns that instead. Concurrent callers
    for the same stale key share a single `fetch()` call — within this
    process via `_lock_for`, and across processes/replicas via
    `_advisory_lock` — see the module docstring.

    `db=None` (see the module docstring's "connection-lifetime note")
    means every step here opens/closes its own short-lived session
    instead of sharing one held by the caller for the whole request —
    except the advisory-lock-and-fetch step, which still needs exactly
    one session held for its own duration (advisory locks are
    connection-scoped in Postgres) — just a dedicated one opened right
    before it's needed and closed right after, not the caller's own
    request-long session."""
    cached = _get_dynamic_raw(db, cache_key, ttl)
    if cached is not None:
        return cached

    async with _lock_for(cache_key):
        # Another request in this same process may have refreshed this
        # key while we were waiting for the in-process lock — check
        # again before paying for the (comparatively expensive)
        # cross-process advisory lock below.
        cached = _get_dynamic_raw(db, cache_key, ttl)
        if cached is not None:
            return cached
        with _session(db) as s:
            async with _advisory_lock(s, cache_key):
                # And another *process* may have refreshed it while we
                # were waiting on the advisory lock — check once more
                # before actually calling fetch().
                cached = _get_dynamic_raw(s, cache_key, ttl)
                if cached is not None:
                    return cached
                result = await fetch()
                payload_json = _dump_json(result)
                _set_dynamic_raw(s, cache_key, payload_json)
                return payload_json


def invalidate_teamira_cache(db: Session) -> None:
    """Any write to the Teamira shelves — via the admin endpoints in
    routers/teamira.py, or via seed_teamira_picks.py's own CLI/startup
    seeding — makes the cached GET /feed/teamira snapshot stale. Clear it
    immediately rather than waiting out TEAMIRA_TTL, so the change shows
    up the next time someone opens the tab instead of up to a day later.

    Single definition shared by both callers, keyed on TEAMIRA_CACHE_KEY
    above — used to be two independent copies (one per caller) that both
    hardcoded the same key string, which meant bumping the key in one
    place and forgetting the other was one edit away.
    """
    row = db.get(models.CachedFeedSnapshot, TEAMIRA_CACHE_KEY)
    if row is not None:
        db.delete(row)
        db.commit()
