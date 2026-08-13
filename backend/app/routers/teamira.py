"""Подборки Teamira — hand-curated shelves for the Collections tab,
separate from both the TMDB/IGDB/Open Library editorial shelves in
app/routers/feed.py (algorithmic, no DB row) and a user's own UserList
(personal, per-user). See app/models.py::TeamiraCollection for the full
"why a third concept" reasoning.

Two sources feed GET /feed/teamira, on purpose kept apart rather than
forced into one mechanism:

- Franchises (Star Wars, Marvel, ...) — defined in code, see
  app/curated_franchises.py. TMDB already tracks franchise membership, so
  there's nothing to curate title-by-title here; each is just a (title,
  tmdb_collection_id) pair, resolved fresh from TMDB on every cache
  refresh, so a franchise that grows a new entry shows up automatically.
- Hand-picked shelves ("Top 10 Movies of 2020") — nothing on TMDB groups
  these, so they're added one title at a time through the API below,
  guarded by a single shared header key (see
  app/deps.py::require_teamira_admin), since there's no admin-flag/role
  system anywhere else in this app.
"""

import asyncio
import logging
from datetime import date
from typing import List

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import TypeAdapter
from sqlalchemy.orm import Session, selectinload

from app import cache, models
from app.curated_franchises import FRANCHISE_COLLECTIONS
from app.database import get_db
from app.deps import get_current_user, require_teamira_admin
from app.schemas import (
    Collection,
    MediaItem,
    TeamiraCollectionIn,
    TeamiraCollectionItemIn,
    TeamiraCollectionOut,
    TeamiraSearchResultOut,
    TodayPickOut,
)
from app.adapters.igdb import IgdbAdapter
from app.adapters.open_library import OpenLibraryAdapter, _MANGA_SHELVES
from app.adapters.tmdb import TmdbAdapter

router = APIRouter(tags=["teamira"])
logger = logging.getLogger(__name__)

_tmdb = TmdbAdapter()
# Same three non-TMDB catalogs /media/search and /media/detail draw from
# (see routers/media.py) — a Teamira shelf can now pull from any of them,
# not just TMDB movies/series.
_games = IgdbAdapter()
_books = OpenLibraryAdapter()
_manga = OpenLibraryAdapter(
    media_type="manga",
    id_prefix="olm-",
    source="open_library_manga",
    shelves=_MANGA_SHELVES,
    search_filter="subject:manga",
)


# ---------------------------------------------------------------------------
# Public read — powers the "подборки Teamira" tab on Collections.
# ---------------------------------------------------------------------------

# A shelf item's own lightweight resolve caches a bare MediaItem — not
# the richer MediaDetailOut /media/detail caches (item + ratings +
# similar) — so these need their own cache source tags, distinct from
# /media/detail's, even where they resolve the same underlying title.
_LITE_CACHE_SOURCE = {
    "tmdb": "tmdb-v2",
    "igdb": "igdb-lite-v1",
    "open_library": "ol-lite-v1",
    "open_library_manga": "olm-lite-v1",
}
_CATALOG_ADAPTERS = {"igdb": _games, "open_library": _books, "open_library_manga": _manga}


async def _resolve_manual_item(db: Session, media_id: str, media_type: str, source: str | None) -> MediaItem | None:
    """Resolves one hand-picked shelf item through whichever catalog it
    came from, cached forever the same way every other title on this app
    is (see app/cache.py) — just under this function's own cache tags
    rather than /media/detail's, since the payload shape differs (see
    _LITE_CACHE_SOURCE above).

    `source` is treated as "tmdb" when unset: every shelf item added
    before this generalized past TMDB movies/series has a NULL source
    column and a bare, unprefixed TMDB id (e.g. "603", not "tmdb-603") —
    see models.TeamiraCollectionItem's docstring. New items added through
    admin_add_item always carry both, in the same `{prefix}{raw_id}`
    shape /media/search and /media/detail already use everywhere else,
    so the prefix-stripping below is shared with that convention rather
    than inventing a second one.
    """
    source = source or "tmdb"
    cache_tag = _LITE_CACHE_SOURCE.get(source)
    if cache_tag is None:
        return None

    if source == "tmdb":
        raw_id = media_id[len("tmdb-"):] if media_id.startswith("tmdb-") else media_id
        cached = cache.get_static_title(db, raw_id, cache_tag)
        if cached is not None:
            return MediaItem.model_validate_json(cached)
        item = await _tmdb.item_detail(raw_id, media_type)
        if item is not None:
            cache.set_static_title(db, raw_id, cache_tag, item)
        return item

    adapter = _CATALOG_ADAPTERS[source]
    prefix = "igdb-" if source == "igdb" else adapter.id_prefix
    raw_id = media_id[len(prefix):] if media_id.startswith(prefix) else media_id
    cached = cache.get_static_title(db, raw_id, cache_tag)
    if cached is not None:
        return MediaItem.model_validate_json(cached)
    try:
        item = await adapter.full_detail(raw_id)
    except RuntimeError:
        # e.g. IGDB not configured — degrade to "this one just doesn't
        # resolve", same as any other per-title failure in this loop.
        return None
    if item is not None:
        cache.set_static_title(db, raw_id, cache_tag, item)
    return item


@router.get("/feed/teamira", response_model=List[Collection])
async def get_teamira_collections(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Franchise shelves from app/curated_franchises.py first, then
    hand-picked shelves from the DB — both resolved into the same
    Collection(title, items) shape /feed/collections returns. Cached as
    one dynamic snapshot (cache.TEAMIRA_TTL): a handful of shelves, each
    up to a whole franchise's worth of TMDB calls, isn't something to redo
    on every single tab open."""

    async def _fetch() -> List[Collection]:
        out: List[Collection] = []

        for title, tmdb_collection_id, history, title_en in FRANCHISE_COLLECTIONS:
            try:
                overview_en, overview_ru, items = await _tmdb.collection(tmdb_collection_id)
            except Exception:
                logger.warning("feed/teamira: franchise %r failed to resolve, skipping it", title, exc_info=True)
                continue
            if not items:
                continue

            # Per-movie trailer (YouTube id) — same lookup/scoring as
            # GET /feed/for-you (see app/adapters/tmdb.py::videos), just
            # run across a whole franchise's worth of movies at once
            # rather than one item. Failures are per-title and silent:
            # "no trailer for this one" is ordinary, not an error.
            async def _attach_trailer(item: MediaItem) -> None:
                try:
                    item.trailer_youtube_id = await _tmdb.videos(item.external_ids.tmdb, "movie")
                except Exception:
                    pass
            await asyncio.gather(*(_attach_trailer(item) for item in items))

            # "How this franchise was made" — hand-written text from
            # app/curated_franchises.py now, not fetched from anywhere.
            # No history_url anymore either: that was only ever the
            # Wikipedia attribution link, and there's nothing to
            # attribute to once the text is our own.
            history_url = None

            # `items` comes back release-date sorted (see
            # app/adapters/tmdb.py::collection) — TMDB's own `parts` order
            # is just insertion order into their DB, not release or
            # in-universe order, so it's re-sorted there rather than
            # trusted as-is. This is what the "order to watch" sheet on
            # the client renders.
            out.append(Collection(
                title=title,
                title_en=title_en,
                items=items,
                is_franchise=True,
                description=overview_en,
                description_ru=overview_ru,
                history=history,
                history_url=history_url,
            ))

        rows = (
            db.query(models.TeamiraCollection)
            .options(selectinload(models.TeamiraCollection.items))
            .order_by(models.TeamiraCollection.position, models.TeamiraCollection.created_at)
            .all()
        )
        for row in rows:
            try:
                items = []
                for item in row.items:
                    media_item = await _resolve_manual_item(db, item.media_id, item.media_type, item.source)
                    if media_item is not None:
                        items.append(media_item)
            except Exception:
                logger.warning("feed/teamira: shelf %r failed to resolve, skipping it", row.title, exc_info=True)
                continue
            if items:
                out.append(Collection(title=row.title, title_en=row.title_en, items=items))

        return out

    # Versioned key — bumped to "...v7" because franchise items/posters/
    # overview used to be resolved from a single ru-RU TMDB request (see
    # app/adapters/tmdb.py::collection), which silently put Russian text
    # into the "en" fields regardless of any user's language setting.
    # Now that collection() does a proper dual-language fetch and
    # Collection carries title_en/description_ru, a snapshot cached
    # before this change would keep serving the old mislabeled payload
    # for up to TEAMIRA_TTL without the bump. Earlier bumps ("...v6",
    # "...v5", "...v4") were for the same reason: any time the cached
    # payload's shape or source changes, bump this so a stale snapshot
    # isn't served past the change. Bump again any time the cached
    # payload's shape changes.
    payload_json = await cache.cached_dynamic(db, "feed:teamira:v7", _fetch, ttl=cache.TEAMIRA_TTL)
    return TypeAdapter(List[Collection]).validate_json(payload_json)


@router.get("/feed/today-pick", response_model=TodayPickOut)
async def get_today_pick(
    offset: int = 0,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Home screen's \"today's pick\" card — one franchise shelf, plus how
    far this user already is into it. Franchise items themselves come from
    the same cached snapshot GET /feed/teamira uses (so this never repeats
    that endpoint's own TMDB work); only the "which franchise" pick and the
    watched-count are worked out here, per user, on every call — cheap: a
    handful of ids checked against this one user's own watchlist, not a
    TMDB round trip.

    "Which franchise" rotates by calendar date (UTC) — `date.today()` is
    the same for every user, so this genuinely is one shared "today's
    pick" and not a per-user shuffle, which matters for the client's
    "closes today, a new one tomorrow" framing (see mobile's
    TodayPickPrefsService) to actually mean something. Starting from
    today's rotated slot, this steps forward through the franchise list
    looking for the first one this user hasn't already finished — so
    someone who's already seen everything in today's default pick gets
    something to actually start instead of a 100%-done card; if every
    franchise is fully watched, today's plain rotated pick is used anyway.

    `offset` lets the client ask for a different franchise than the
    shared daily one without touching that rotation for anyone else —
    the card's own "shuffle" button increments a purely local, per-day
    counter (see mobile's TodayPickPrefsService.rerollCount) and resends
    it here. It's added to the shared day_index before the same
    skip-already-watched walk runs, so a reroll still never lands on
    something this user has fully finished, and still wraps around the
    franchise list rather than erroring past its end.

    404 (well — an empty items list on the returned collection) only if
    no franchise shelf resolves at all, e.g. TMDB unreachable; same
    "shelf isn't available right now" degradation GET /feed/teamira uses,
    just surfaced as a single empty collection here since the client only
    ever renders one at a time.
    """
    collections = await get_teamira_collections(current_user=current_user, db=db)
    franchises = [c for c in collections if c.is_franchise and c.items]

    today = date.today()
    empty = TodayPickOut(
        collection=Collection(title="", items=[], is_franchise=True),
        watched_count=0,
        total_count=0,
        pick_date=today.isoformat(),
    )
    if not franchises:
        return empty

    day_index = (today.toordinal() + offset) % len(franchises)

    def _watched_count(items: List[MediaItem]) -> int:
        tmdb_ids = [item.external_ids.tmdb for item in items if item.external_ids.tmdb]
        if not tmdb_ids:
            return 0
        return (
            db.query(models.WatchlistEntry)
            .filter(
                models.WatchlistEntry.user_id == current_user.id,
                models.WatchlistEntry.source == "tmdb",
                models.WatchlistEntry.media_type == models.MediaType.movie,
                models.WatchlistEntry.status == models.WatchStatus.watched,
                models.WatchlistEntry.media_id.in_(tmdb_ids),
            )
            .count()
        )

    chosen = None
    chosen_watched = 0
    for step in range(len(franchises)):
        candidate = franchises[(day_index + step) % len(franchises)]
        watched = _watched_count(candidate.items)
        if watched < len(candidate.items):
            chosen, chosen_watched = candidate, watched
            break
    if chosen is None:
        # Every franchise is fully watched — fall back to today's plain
        # rotated pick rather than showing nothing.
        chosen = franchises[day_index]
        chosen_watched = _watched_count(chosen.items)

    return TodayPickOut(
        collection=chosen,
        watched_count=chosen_watched,
        total_count=len(chosen.items),
        pick_date=today.isoformat(),
    )


# ---------------------------------------------------------------------------
# Admin — create/edit hand-picked shelves. Franchise shelves aren't managed
# here at all; add/remove them by editing app/curated_franchises.py.
# Not a public surface; see require_teamira_admin.
# ---------------------------------------------------------------------------

def _invalidate_teamira_cache(db: Session) -> None:
    """Any admin write makes the cached /feed/teamira snapshot stale —
    clear it immediately rather than waiting out cache.TEAMIRA_TTL, so an
    edit shows up the next time someone opens the tab, not up to a day
    later."""
    row = db.get(models.CachedFeedSnapshot, "feed:teamira:v7")
    if row is not None:
        db.delete(row)
        db.commit()


@router.get(
    "/teamira/admin/collections",
    response_model=List[TeamiraCollectionOut],
    dependencies=[Depends(require_teamira_admin)],
)
def admin_list_collections(db: Session = Depends(get_db)):
    return (
        db.query(models.TeamiraCollection)
        .options(selectinload(models.TeamiraCollection.items))
        .order_by(models.TeamiraCollection.position, models.TeamiraCollection.created_at)
        .all()
    )


@router.post(
    "/teamira/admin/collections",
    response_model=TeamiraCollectionOut,
    status_code=201,
    dependencies=[Depends(require_teamira_admin)],
)
def admin_create_collection(payload: TeamiraCollectionIn, db: Session = Depends(get_db)):
    max_position = db.query(models.TeamiraCollection).count()
    row = models.TeamiraCollection(title=payload.title, title_en=payload.title_en, position=max_position)
    db.add(row)
    db.commit()
    db.refresh(row)
    _invalidate_teamira_cache(db)
    return row


@router.patch(
    "/teamira/admin/collections/{collection_id}",
    response_model=TeamiraCollectionOut,
    dependencies=[Depends(require_teamira_admin)],
)
def admin_rename_collection(collection_id: str, payload: TeamiraCollectionIn, db: Session = Depends(get_db)):
    """Rename an existing hand-picked shelf (e.g. to add/fix its
    `title_en` on a shelf created before that field existed) without
    dropping and recreating it — that would also drop its items."""
    row = db.get(models.TeamiraCollection, collection_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    row.title = payload.title
    row.title_en = payload.title_en
    db.commit()
    db.refresh(row)
    _invalidate_teamira_cache(db)
    return row


@router.delete(
    "/teamira/admin/collections/{collection_id}",
    status_code=204,
    dependencies=[Depends(require_teamira_admin)],
)
def admin_delete_collection(collection_id: str, db: Session = Depends(get_db)):
    row = db.get(models.TeamiraCollection, collection_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    db.delete(row)
    db.commit()
    _invalidate_teamira_cache(db)
    return None


@router.post(
    "/teamira/admin/collections/{collection_id}/items",
    response_model=TeamiraCollectionOut,
    dependencies=[Depends(require_teamira_admin)],
)
async def admin_add_item(collection_id: str, payload: TeamiraCollectionItemIn, db: Session = Depends(get_db)):
    row = db.get(models.TeamiraCollection, collection_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    if payload.media_type not in ("movie", "series", "anime", "game", "book", "manga"):
        raise HTTPException(
            status_code=400, detail="media_type must be movie | series | anime | game | book | manga"
        )
    if payload.source not in ("tmdb", "igdb", "open_library", "open_library_manga"):
        raise HTTPException(
            status_code=400, detail="source must be tmdb | igdb | open_library | open_library_manga"
        )

    # Fail fast on a bad id rather than silently storing a reference that
    # will just come back empty from every future /feed/teamira read.
    resolved = await _resolve_manual_item(db, payload.media_id, payload.media_type, payload.source)
    if resolved is None:
        raise HTTPException(status_code=404, detail="No title at that media_id/media_type/source")

    next_position = len(row.items)
    item = models.TeamiraCollectionItem(
        collection_id=row.id,
        media_id=payload.media_id,
        media_type=payload.media_type,
        source=payload.source,
        position=next_position,
    )
    db.add(item)
    try:
        db.commit()
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=409, detail="That title is already in this collection") from exc
    db.refresh(row)
    _invalidate_teamira_cache(db)
    return row


@router.delete(
    "/teamira/admin/collections/{collection_id}/items/{item_id}",
    response_model=TeamiraCollectionOut,
    dependencies=[Depends(require_teamira_admin)],
)
def admin_remove_item(collection_id: str, item_id: str, db: Session = Depends(get_db)):
    row = db.get(models.TeamiraCollection, collection_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Collection not found")
    item = db.get(models.TeamiraCollectionItem, item_id)
    if item is None or item.collection_id != collection_id:
        raise HTTPException(status_code=404, detail="Item not found in this collection")
    db.delete(item)
    db.commit()
    db.refresh(row)
    _invalidate_teamira_cache(db)
    return row


@router.get(
    "/teamira/admin/search",
    response_model=List[TeamiraSearchResultOut],
    dependencies=[Depends(require_teamira_admin)],
)
async def admin_search_catalogs(q: str = Query(..., min_length=1)):
    """Convenience so adding a hand-picked item never requires leaving
    the API: search here across every catalog a shelf can now draw from
    — TMDB (movie/series/anime), IGDB (game), and Open Library
    (book/manga) — take a hit's media_id/media_type/source, and POST it
    straight to /teamira/admin/collections/{id}/items."""
    async def _safe(coro):
        try:
            return await coro
        except Exception:
            # One catalog being down (e.g. IGDB unconfigured) shouldn't
            # blank out results from the other three.
            return []

    tmdb_items, games, books, manga = await asyncio.gather(
        _safe(_tmdb_catalog_items(q)),
        _safe(_games.search(q)),
        _safe(_books.search(q)),
        _safe(_manga.search(q)),
    )
    results: List[MediaItem] = [*tmdb_items, *games, *books, *manga]
    return [
        TeamiraSearchResultOut(
            media_id=item.id,
            media_type=item.media_type,
            source=item.source,
            title=item.title.en or item.title.ru or "—",
            year=item.year,
            poster_url=item.poster_url,
        )
        for item in results
    ]


async def _tmdb_catalog_items(q: str) -> List[MediaItem]:
    items, _original_titles = await _tmdb.catalog_search(q)
    return items
