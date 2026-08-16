import asyncio
import json
import logging
import random
from datetime import datetime, timedelta
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import TypeAdapter
from sqlalchemy.orm import Session

from app import cache
from app.database import get_db
from app import models
from app.deps import get_current_user
from app.schemas import MediaItem, FeedReaction, Collection
from app.adapters.igdb import IgdbAdapter
from app.adapters.google_books import GoogleBooksAdapter
from app.adapters.shikimori import ShikimoriMangaAdapter
from app.adapters.tmdb import TmdbAdapter

router = APIRouter(prefix="/feed", tags=["feed"])
logger = logging.getLogger(__name__)

_games = IgdbAdapter()
_books = GoogleBooksAdapter()
_manga = ShikimoriMangaAdapter()
_tmdb = TmdbAdapter()

# How many liked titles we're willing to fan out to TMDB's genre-scoped
# /discover (via _tmdb.similar_by_genre) for — one call each. Kept small:
# this is a synchronous per-user endpoint, not a background job, and the
# marginal value of a 7th or 8th seed title is low once the pool already
# has a few dozen candidates.
_FOR_YOU_SEED_LIMIT = 6
# How many of the ranked pool actually get a trailer looked up. Every trailer
# lookup is its own TMDB round-trip, so this is the real cost control on the
# endpoint — the rest of the ranked pool still comes back, just without a
# trailer_youtube_id (client falls back to a plain poster card for those).
_FOR_YOU_TRAILER_LIMIT = 12
_FOR_YOU_TTL = timedelta(hours=6)

# get_collections' own forever-cache row version for the ru-supplement
# overlay below — bumped independently of _DETAIL_CACHE_SOURCE-style
# constants in media.py since this cache stores a thinner payload (title/
# overview/poster only, no cast/director/trailers). Bumped from the old
# poster-only "tmdb-poster-ru-v1" since the cached payload shape changed
# (now also carries title_ru/overview_ru) — an old poster-only row would
# otherwise look like a permanent "no title/overview" miss forever.
#
# Bumped v2 -> v3 for the same title_ru/overview_ru fallback-to-English
# fix as media.py's _DETAIL_CACHE_SOURCE bump — TmdbAdapter.
# shelf_ru_supplement used to guard title_ru against original_title,
# which silently let an English fallback string through as "Russian"
# for any title whose original_language isn't itself English. Without
# this bump, shelves would keep serving already-cached wrong rows
# forever even after the adapter fix.
_RU_SUPPLEMENT_CACHE_SOURCE = "tmdb-ru-supplement-v3"
# How many shelf_ru_supplement lookups run at once while enriching a cold
# Collections fetch — a real cap, not just politeness: a full shelf pass
# is a few hundred titles, and firing them all at TMDB simultaneously is
# the kind of burst that gets an API key rate-limited. Paid once per
# title, ever (see _apply_ru_supplement below) — only a genuinely cold
# cache (a title that's never shown up in a Russian Collections fetch
# before) pays this at all; from then on it's a single cached-row read.
_RU_SUPPLEMENT_CONCURRENCY = 8


async def _apply_ru_supplement(db: Session, items: List[MediaItem]) -> None:
    """Overlays title.ru/description.ru/poster_url_ru onto every TMDB-
    sourced item in a freshly-built Collections shelf set, so a Russian-
    content device (see LocaleService.contentPrefersRussian on mobile)
    shows real Russian text and key art immediately rather than only
    after opening a title's own detail screen. Needed because TMDB's
    list/discover endpoints (what shelves are built from — see
    TmdbAdapter._fetch_list) pass `language=ru-RU` through same as the
    per-title endpoint does, but resolve a title's actual translation far
    less reliably in practice — plenty of titles that come back
    untranslated from e.g. /discover/movie do have a genuine Russian
    translation one call away on /movie/{id}. (An earlier version of this
    function only backfilled the poster, on the assumption text was fine
    off the list call directly — it wasn't; this closes that same gap for
    title/overview too, off the identical per-title request.)

    This always overwrites title.ru/description.ru with what this lookup
    found (including clearing back to None if TMDB genuinely has nothing)
    rather than only filling gaps — the list call's own ru text has no
    guard against TMDB's "quietly return the original" fallback the way
    this per-title lookup does (see TmdbAdapter.shelf_ru_supplement's
    docstring), so it can't be trusted as a floor to fall back to.

    Cached forever per title (media_id), same pattern as
    app/routers/media.py::_apply_shikimori_ru — a title that keeps
    reappearing across shelves/refreshes (as chart-style shelves do)
    only ever pays for the extra TMDB call once. A genuine miss (TMDB
    responds, just has nothing in Russian for this title) is cached too,
    so it isn't re-attempted on every subsequent Collections refresh. A
    transient failure (rate limit, timeout) is NOT cached — see _one
    below — so it gets retried next time instead of being mistaken for a
    real miss forever.

    Best-effort: this whole pass sits behind get_collections' own
    try/except-per-source loop having already succeeded, so a slow or
    failing lookup for one title just leaves that item's ru fields as the
    list call already set them (falls back to English client-side, same
    as before this existed) rather than failing the endpoint.
    """
    semaphore = asyncio.Semaphore(_RU_SUPPLEMENT_CONCURRENCY)

    async def _one(item: MediaItem) -> None:
        if item.source != "tmdb" or not item.external_ids.tmdb:
            return
        cached = cache.get_static_title(db, item.id, _RU_SUPPLEMENT_CACHE_SOURCE)
        if cached is not None:
            supplement = json.loads(cached)
        else:
            segment = "tv" if item.media_type in ("series", "anime") else "movie"
            async with semaphore:
                try:
                    supplement = await _tmdb.shelf_ru_supplement(item.external_ids.tmdb, segment)
                except Exception as exc:
                    # A transient failure (429, timeout, 5xx — see
                    # TmdbAdapter.shelf_ru_supplement's own docstring) is
                    # NOT the same thing as TMDB genuinely having nothing
                    # in Russian for this title. Leave it uncached so the
                    # next Collections refresh actually retries it,
                    # instead of baking a false "nothing here" into the
                    # forever-cache off one bad request.
                    logger.warning("shelf_ru_supplement lookup failed [%s] -> %s", item.id, exc)
                    return
            cache.set_static_title(db, item.id, _RU_SUPPLEMENT_CACHE_SOURCE, supplement)
        item.title.ru = supplement.get("title_ru")
        item.description.ru = supplement.get("overview_ru")
        item.poster_url_ru = supplement.get("poster_ru")

    await asyncio.gather(*(_one(item) for item in items), return_exceptions=True)



async def _fetch_discover_pool() -> List[MediaItem]:
    pool: List[MediaItem] = []
    pool += await _tmdb.discover_mixed()
    pool += await _games.search("")
    pool += await _books.discover()
    pool += await _manga.discover()
    return pool


async def get_discover_pool(db: Session) -> List[MediaItem]:
    """The whole-app pool GET /feed serves — every movie/series/anime,
    game, book, and manga we know about, cached once every 24h (see
    app/cache.py) rather than rebuilt per request. Exposed as its own
    function so anything else that wants a genuinely "everything in the
    app" pool (e.g. co_view_vote's "catalog" pool source) can share this
    same cached fetch instead of re-hitting TMDB/IGDB/Open Library
    itself. Callers that want a fresh shuffle order do their own —
    this returns whatever order came out of the cache."""
    payload_json = await cache.cached_dynamic(db, "feed:discover", _fetch_discover_pool)
    return TypeAdapter(List[MediaItem]).validate_json(payload_json)


@router.get("", response_model=List[MediaItem])
async def get_feed(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Cached once every 24h (see app/cache.py) — the underlying TMDB pool
    is what's cached; the shuffle happens fresh on every request so it
    doesn't look frozen in the same order all day for everyone."""
    pool = list(await get_discover_pool(db))
    random.shuffle(pool)
    return pool


@router.get("/movies", response_model=List[MediaItem])
async def get_movies_feed(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """A movies-only feed — same idea as GET /feed, but without games mixed
    in, for a screen that just wants a "movies feed". Cached once every 24h."""

    async def _fetch() -> List[MediaItem]:
        return await _tmdb.movies_pool()

    payload_json = await cache.cached_dynamic(db, "feed:movies", _fetch)
    return TypeAdapter(List[MediaItem]).validate_json(payload_json)


@router.get("/for-you", response_model=List[MediaItem])
async def get_for_you_feed(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """A personal, content-based recommendation feed — movies/series only
    (games/books/manga have no trailer to show, and the whole point of this
    shelf is the trailer preview). Built entirely from data we already have:

    - WatchlistEntry + DiaryEntry give us the user's own genres and their
      own ratings on them — no separate "taste profile" table needed.
    - For each of their better-loved, most-recent titles (a "seed"), we ask
      TMDB's genre-scoped /discover (`_tmdb.similar_by_genre`, already used
      by GET /media/detail's own similar-titles logic pattern) for more of
      the same combination of genres.
    - The combined pool is deduped against everything already on the
      user's shelves, then ranked by how well its genres line up with the
      user's own genre weights (not just "popular this month").
    - The top of that ranked pool gets a real trailer looked up from TMDB
      (see app/adapters/tmdb.py::videos) — capped, since that's a
      per-title network round-trip.

    Returns an empty list for a brand-new account with nothing logged yet
    (no seeds to work from) — the client's job is to fall back to the
    general "picked for tonight" shelf in that case, not to show an empty
    "for you" section.

    Cached per-user, keyed off that user's own last diary/watchlist write
    so a fresh log immediately busts the cache (unlike the shared feed
    caches above, which are time-only) — see the cache_key construction
    below. Falls back to a 6h TTL for users who haven't logged anything
    since their last fetch, so this never re-does the ranking/trailer work
    on every single Home load.
    """
    watch_entries = (
        db.query(models.WatchlistEntry)
        .filter(models.WatchlistEntry.user_id == current_user.id)
        .all()
    )
    diary_entries = (
        db.query(models.DiaryEntry)
        .filter(models.DiaryEntry.user_id == current_user.id)
        .all()
    )
    if not watch_entries and not diary_entries:
        return []

    last_activity = max(
        [e.updated_at or e.created_at for e in watch_entries]
        + [e.created_at for e in diary_entries]
        + [datetime.min]
    )
    cache_key = f"feed:foryou:{current_user.id}:{last_activity.isoformat()}"

    async def _fetch() -> List[MediaItem]:
        genre_weight: dict[str, float] = {}
        already_have: set[str] = set()
        # (media_id, media_type, source, genres) — recency-ordered below.
        seeds: list[tuple] = []

        for e in watch_entries:
            already_have.add(f"{e.source}:{e.media_id}")
            weight = (e.user_rating / 5) if e.user_rating else 0.6
            if e.status == models.WatchStatus.watched:
                weight *= 1.2
            for g in e.genres or []:
                genre_weight[g] = genre_weight.get(g, 0) + weight
            if e.media_type in (models.MediaType.movie, models.MediaType.series, models.MediaType.anime) and (
                e.user_rating is None or e.user_rating >= 3
            ):
                seeds.append((e.updated_at or e.created_at, e.media_id, e.media_type, e.genres or []))

        for d in diary_entries:
            already_have.add(f"{d.source}:{d.media_id}")
            weight = (d.rating / 10) if d.rating else 0.6
            for g in d.genres or []:
                genre_weight[g] = genre_weight.get(g, 0) + weight
            if d.media_type in (models.MediaType.movie, models.MediaType.series, models.MediaType.anime) and (
                d.rating is None or d.rating >= 6
            ):
                seeds.append((d.watched_at, d.media_id, d.media_type, d.genres or []))

        seeds.sort(key=lambda s: s[0] or datetime.min, reverse=True)

        pool: List[MediaItem] = []
        for _, media_id, media_type, genres in seeds[:_FOR_YOU_SEED_LIMIT]:
            if not genres:
                continue
            media_kind = "movie" if media_type == models.MediaType.movie else "tv"
            pool += await _tmdb.similar_by_genre(
                media_kind, genres,
                anime_only=(media_type == models.MediaType.anime),
                exclude_id=media_id,
            )

        deduped: List[MediaItem] = []
        seen_pool_keys: set[str] = set()
        for item in pool:
            key = f"{item.source}:{item.id}"
            if key in already_have or key in seen_pool_keys:
                continue
            seen_pool_keys.add(key)
            deduped.append(item)

        def _score(item: MediaItem) -> float:
            return sum(genre_weight.get(g, 0) for g in item.genres)

        deduped.sort(key=_score, reverse=True)
        ranked = deduped[:24]

        trailer_targets = [item for item in ranked[:_FOR_YOU_TRAILER_LIMIT] if item.external_ids.tmdb]

        async def _attach_trailer(item: MediaItem) -> None:
            segment = "movie" if item.media_type == "movie" else "tv"
            try:
                item.trailer_youtube_id = await _tmdb.videos(item.external_ids.tmdb, segment)
            except Exception:
                pass  # no trailer — the card just shows the poster instead

        await asyncio.gather(*(_attach_trailer(item) for item in trailer_targets))

        return ranked

    payload_json = await cache.cached_dynamic(db, cache_key, _fetch, ttl=_FOR_YOU_TTL)
    return TypeAdapter(List[MediaItem]).validate_json(payload_json)


@router.get("/collections", response_model=List[Collection])
async def get_collections(
    lang: Optional[str] = None,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Named shelves for the Collections tab — TMDB's own popular/top_rated/
    trending/discover shelves, plus IGDB-backed game shelves and Open
    Library-backed book/manga shelves. Every card in a shelf is real data
    from one of the three sources. If a source has no API key configured
    (TMDB/IGDB — Open Library needs no key at all), its shelves simply
    aren't available — no synthetic/mock data.

    `lang="ru"` (mobile sends this whenever LocaleService.preferRussian is
    on — see lib/services/feed_service.dart) fetches the TMDB-backed
    shelves' titles/overviews in Russian up front, the same way TMDB
    text elsewhere in the app already prefers Russian — rather than only
    after a title's own detail screen has been opened once. It also
    overlays real Russian title/overview/poster per title from TMDB's
    per-title endpoint (see _apply_ru_supplement below) — TMDB's list/
    discover endpoints pass `language=ru-RU` through same as the per-title
    endpoint, but resolve the actual translation far less reliably in
    practice (title/overview included, not just the poster), so this is a
    genuine second pass per title, capped and cached forever
    (_RU_SUPPLEMENT_CACHE_SOURCE) so it's only ever paid once per title,
    not once per Collections refresh. First cold Russian fetch after a
    cache miss is noticeably slower than the English one for this reason;
    every fetch after that (same COLLECTIONS_TTL) is a plain cache read
    like any other. Not every title has real Russian text/a TMDB-tagged
    Russian poster at all — that one is a data-availability gap, not
    something more engineering fixes; those fall back to the same English
    text/base poster. IGDB/Open Library shelves (games/books/manga) don't
    have a Russian catalog to switch to, so `lang` only affects the
    TMDB-sourced shelves.

    Cached for cache.COLLECTIONS_TTL (a few hours) — these are chart-style
    shelves that don't meaningfully change minute to minute, so polling
    more often than that doesn't surface newer titles, it just re-asks for
    a chart that hasn't moved. This endpoint alone fans out to ~19 shelf
    calls, so that's real cost for zero benefit. English and Russian are
    cached under separate keys (one full extra fetch/cache the first time
    each is asked for, same TTL) since they're genuinely different
    payloads, not a reshuffle of the same one.

    The felt sense of "this looks different every time I pull to refresh"
    comes from a different mechanism: every read of the cached pool
    reshuffles both the shelf order and the item order within each shelf
    (below). Across ~200+ items spread over ~19 shelves, that's genuine
    variety in what Home shows on any given pull — it's just drawn from
    the same day's snapshot rather than a fresh TMDB round-trip every
    time, because a fresh round-trip that often wouldn't return anything
    different anyway.

    Static per-title data — name, synopsis, poster, seasons/episodes — is
    a completely different cache (get_static_title / get_static_episodes)
    that's kept effectively forever, since that content doesn't change and
    re-fetching it buys nothing.
    """
    tmdb_language = "ru-RU" if lang == "ru" else None

    async def _fetch() -> List[Collection]:
        shelves: list = []
        # Each source gets its own try/except around *any* exception, not
        # just RuntimeError (missing key) — a bad/expired/revoked key, a
        # timeout, or the source being temporarily unreachable all raise
        # something else (httpx.HTTPStatusError, ConnectError,
        # TimeoutException…), and previously none of those were caught.
        # That meant one misconfigured or flaky source took down this
        # *entire* endpoint, which is what actually breaks Home's "picked
        # for tonight" and the Collections tab: they call this same
        # endpoint, and Diary loads separately (DB-only), so it looks fine
        # while this doesn't.
        for name, call in (
            ("tmdb", lambda: _tmdb.named_collections(language=tmdb_language)),
            ("igdb", _games.named_collections),
            ("google_books", _books.named_collections),
            ("shikimori_manga", _manga.named_collections),
        ):
            try:
                shelves += await call()
            except Exception:
                logger.warning("feed/collections: %s source failed, skipping its shelves", name, exc_info=True)
        # Each source's named_collections() now returns (title_ru, title_en,
        # items) — `title` on the Collection is always the Russian shelf
        # name, title_en the English fallback, same "title always Russian"
        # contract the Teamira franchise shelves already follow (see
        # schemas.Collection.title / mobile/lib/models/collection.dart::
        # displayTitle). Previously these adapters only ever returned an
        # English label with no title_en set, so the client's own ru/en
        # toggle had nothing to fall back *from* and the Collections tab's
        # shelf names stayed in English even once the cards on it were
        # showing Russian text/posters.
        collections_out = [
            Collection(title=title_ru, title_en=title_en, items=items)
            for title_ru, title_en, items in shelves
            if items
        ]
        if tmdb_language:
            all_items = [item for c in collections_out for item in c.items]
            await _apply_ru_supplement(db, all_items)
        return collections_out

    cache_key = "feed:collections:ru" if tmdb_language else "feed:collections"
    payload_json = await cache.cached_dynamic(db, cache_key, _fetch, ttl=cache.COLLECTIONS_TTL)
    collections = TypeAdapter(List[Collection]).validate_json(payload_json)
    for c in collections:
        random.shuffle(c.items)
    return collections


def add_watchlist_status(
    db: Session,
    user_id: str,
    item: MediaItem,
    status: "models.WatchStatus",
    verb: str,
) -> None:
    """Upserts one user's WatchlistEntry for `item` to `status` and logs
    the matching ActivityEvent — the exact write a "like" reaction makes
    (see react_to_feed_item below), pulled out so co-viewing matches can
    drop a title onto someone's "plan to watch" shelf the same way,
    without going through the /feed/react endpoint itself. Doesn't
    commit; callers batch this with their own write.
    """
    entry = (
        db.query(models.WatchlistEntry)
        .filter(
            models.WatchlistEntry.user_id == user_id,
            models.WatchlistEntry.media_id == item.id,
            models.WatchlistEntry.source == item.source,
        )
        .first()
    )
    if entry is None:
        db.add(models.WatchlistEntry(
            user_id=user_id,
            media_id=item.id,
            media_type=item.media_type,
            source=item.source,
            title_ru=item.title.ru,
            title_en=item.title.en,
            poster_url=item.poster_url,
            backdrop_url=item.backdrop_url,
            year=item.year,
            genres=item.genres,
            rating=item.rating,
            runtime_minutes=item.runtime_minutes,
            status=status,
        ))
    else:
        # Never downgrade something already mid-series or fully watched
        # back down to watch_later — same rule react_to_feed_item's own
        # "like" path follows.
        already_ahead = status == models.WatchStatus.watch_later and entry.status in (
            models.WatchStatus.watching,
            models.WatchStatus.watched,
        )
        if already_ahead:
            return
        entry.status = status

    display_title = item.title.en or item.title.ru or "—"
    db.add(models.ActivityEvent(
        user_id=user_id,
        verb=verb,
        media_title=display_title,
        media_type=item.media_type,
        media_id=item.id,
        source=item.source,
        poster_url=item.poster_url,
    ))


@router.post("/react", status_code=204)
def react_to_feed_item(
    payload: FeedReaction,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if payload.action not in ("like", "watched", "skip"):
        raise HTTPException(status_code=400, detail="action must be like | watched | skip")

    if payload.action == "skip":
        return None

    item = payload.item
    status_value = models.WatchStatus.watched if payload.action == "watched" else models.WatchStatus.watch_later
    verb = "marked as watched" if payload.action == "watched" else "added to watch later"
    add_watchlist_status(db, current_user.id, item, status_value, verb)

    db.commit()
    return None
