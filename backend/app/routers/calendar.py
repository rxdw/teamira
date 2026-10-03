"""GET /calendar/releases and GET /calendar/watching — the Home screen's
two "what's coming out" blocks (see mobile's home_screen.dart:
_ReleaseCalendarSection / _NewReleasesSection).

/calendar/releases is a shared discovery calendar, same "public data, one
fetch serves everyone within the cache window" shape as GET
/feed/collections: date-sorted anime (Shikimori's own /api/calendar),
games (IGDB, first_release_date-scoped) and movies (TMDB, /discover/movie
sorted by release date) merged into one list. Not personalized at all —
nothing here reads this user's diary/watchlist.

/calendar/watching is the opposite: strictly this user's own
watching/watch-later shelf, checked per-title against its own source for
whether a new episode/release is out or coming up. Series and anime are
both checked against **TMDB only**, never Shikimori — every series/anime
title in this app's library came in through TMDB (see
app/adapters/shikimori.py's own module docstring: TMDB is the primary
catalog, Shikimori only ever overlays Russian text onto it), so
WatchlistEntry.media_id is always a real tmdb id here and
TmdbAdapter.next_episode can look it up directly. Re-matching a
watching-list title back to a Shikimori anime by title, just to read
*its* calendar instead, would reintroduce exactly the same-name/remake
ambiguity ShikimoriAdapter.calendar's own docstring warns about — wrong
for a personal to-do list, fine for the anonymous discovery grid above
where a stray mismatch is just one wrong poster in a big scroll.
"""
import asyncio
import json
import logging
from datetime import date, timedelta
from typing import List, Optional

from fastapi import APIRouter, Depends
from pydantic import TypeAdapter
from sqlalchemy.orm import Session

from app import cache, models
from app.database import get_db
from app.deps import get_current_user
from app.schemas import LocalizedText, MediaDetailOut, ReleaseCalendarItem, WatchingReleaseItem
from app.adapters.igdb import IgdbAdapter
from app.adapters.shikimori import ShikimoriAdapter
from app.adapters.tmdb import TmdbAdapter

logger = logging.getLogger("seenly.routers.calendar")

router = APIRouter(prefix="/calendar", tags=["calendar"])

_tmdb = TmdbAdapter()
_igdb = IgdbAdapter()
_shikimori = ShikimoriAdapter()

# Same cadence as Collections (see cache.COLLECTIONS_TTL) — this is
# exactly as "shared, moderately fresh" as that shelf, not as
# aggressively-cached as a 24h feed nor as live as a per-request call.
# v2: rows now carry `genres` — a v1 payload has none, and would make the
# genre filter drop everything until the old entry expired.
_RELEASES_CACHE_KEY = "calendar:releases-v2"
_RELEASES_TTL = cache.COLLECTIONS_TTL

# How stale a per-title "when's the next episode" answer is allowed to
# get before /calendar/watching pays for a fresh TMDB call — shared
# across every user watching that title (see _tmdb_next_episode_cached),
# so this is a per-*title* cost, not a per-user one.
_NEXT_EPISODE_TTL = timedelta(hours=3)

# A game that released more than this many days ago no longer counts as
# "news" on the watching strip — same grace window IgdbAdapter.calendar
# gives the discovery grid, for the same reason (so a release lands on
# the strip at least once rather than needing perfect timing to catch it
# exactly on its day).
_GAME_NEWS_WINDOW = timedelta(days=3)


async def _fetch_release_calendar() -> List[ReleaseCalendarItem]:
    """The actual fan-out behind GET /calendar/releases — see
    cached_dynamic below for why this is a bare function, not a method:
    it's handed to cache.cached_dynamic as `fetch`, called at most once
    per _RELEASES_TTL window regardless of how many people are looking
    at Home right now."""
    shikimori_rows, igdb_items, tmdb_items = await asyncio.gather(
        _shikimori.calendar(),
        _igdb.calendar(),
        _tmdb.upcoming_movies_calendar(),
        return_exceptions=True,
    )

    items: List[ReleaseCalendarItem] = []

    if isinstance(shikimori_rows, Exception):
        logger.warning("Shikimori calendar failed: %s", shikimori_rows)
    else:
        for row in shikimori_rows:
            title_ru, title_en = row.get("title_ru"), row.get("title_en")
            if not title_ru and not title_en:
                continue
            items.append(ReleaseCalendarItem(
                source="shikimori",
                media_type="anime",
                release_date=row["air_at"],
                title=LocalizedText(ru=title_ru, en=title_en),
                poster_url=row.get("poster_url"),
                episode=row.get("episode"),
                item=None,
                external_url=row.get("url"),
                genres=list(row.get("genres") or []),
            ))

    if isinstance(igdb_items, Exception):
        logger.warning("IGDB calendar failed: %s", igdb_items)
    else:
        for game in igdb_items:
            if not game.release_date:
                continue
            items.append(ReleaseCalendarItem(
                source="igdb",
                media_type="game",
                release_date=game.release_date,
                title=game.title,
                poster_url=game.poster_url,
                year=game.year,
                item=game,
                genres=list(game.genres or []),
            ))

    if isinstance(tmdb_items, Exception):
        logger.warning("TMDB upcoming movies calendar failed: %s", tmdb_items)
    else:
        for movie in tmdb_items:
            if not movie.release_date:
                continue
            items.append(ReleaseCalendarItem(
                source="tmdb",
                media_type="movie",
                release_date=movie.release_date,
                title=movie.title,
                poster_url=movie.poster_url,
                year=movie.year,
                item=movie,
                genres=list(movie.genres or []),
            ))

    items.sort(key=lambda i: i.release_date)
    return items


@router.get("/releases", response_model=List[ReleaseCalendarItem])
async def release_calendar():
    """The Steam-style discovery grid on Home — same shelf for everyone.
    No `db: Session = Depends(get_db)` here, same reasoning as
    routers/feed.py's get_movies_feed: this endpoint's only DB use is the
    cache read/write, and cache.cached_dynamic(db=None, ...) opens its
    own short-lived session just for that, never holding one for the
    TMDB/IGDB/Shikimori round trips in between."""
    payload_json = await cache.cached_dynamic(None, _RELEASES_CACHE_KEY, _fetch_release_calendar, ttl=_RELEASES_TTL)
    return TypeAdapter(List[ReleaseCalendarItem]).validate_json(payload_json)


async def _tmdb_next_episode_cached(db: Session, tmdb_id: str) -> Optional[dict]:
    """cache.cached_dynamic wraps TmdbAdapter.next_episode with a shared,
    per-*title* TTL (see _NEXT_EPISODE_TTL) — a show five different users
    are all watching gets looked up once per window, not once per user
    per Home load. Returns the same {"next": ..., "last": ...} shape (or
    None) next_episode() itself returns; cache.cached_dynamic's own
    _dump_json falls back to plain json.dumps for a non-Pydantic value
    like this dict, so nothing extra is needed to make it cacheable."""
    async def _fetch():
        return await _tmdb.next_episode(tmdb_id)

    payload_json = await cache.cached_dynamic(
        db, f"calendar:next-episode:{tmdb_id}", _fetch, ttl=_NEXT_EPISODE_TTL,
    )
    return json.loads(payload_json)


def _entry_title(entry: models.WatchlistEntry) -> LocalizedText:
    return LocalizedText(ru=entry.title_ru, en=entry.title_en)


async def _series_releases(
    db: Session, user_id: str, entries: List[models.WatchlistEntry],
) -> List[WatchingReleaseItem]:
    """Series/anime entries on the watching shelf — see this module's own
    docstring for why every one of these is looked up on TMDB regardless
    of whether media_type is "series" or "anime"."""
    episode_infos = await asyncio.gather(
        *[_tmdb_next_episode_cached(db, e.media_id) for e in entries],
        return_exceptions=True,
    )

    # The latest season/episode this user has actually logged for each
    # title (see models.DiaryEntry's own docstring: a series keeps a
    # single row, season/episode holding the latest point reached) —
    # fetched once for the whole batch rather than once per entry.
    media_ids = [e.media_id for e in entries]
    diary_by_media_id = {
        d.media_id: d
        for d in db.query(models.DiaryEntry).filter(
            models.DiaryEntry.user_id == user_id,
            models.DiaryEntry.source == "tmdb",
            models.DiaryEntry.media_id.in_(media_ids),
        )
    }

    today = date.today()
    out: List[WatchingReleaseItem] = []

    for entry, info in zip(entries, episode_infos):
        if isinstance(info, Exception) or not info:
            continue
        diary = diary_by_media_id.get(entry.media_id)
        watched_key = (
            (diary.season, diary.episode)
            if diary and diary.season is not None and diary.episode is not None
            else None
        )

        def _already_logged(season: Optional[int], episode: Optional[int]) -> bool:
            if watched_key is None or season is None or episode is None:
                return False
            return watched_key >= (season, episode)

        last = info.get("last") or {}
        last_air_date = last.get("air_date")
        if last_air_date:
            try:
                already_aired = date.fromisoformat(last_air_date) <= today
            except ValueError:
                already_aired = False
            if already_aired and not _already_logged(last.get("season_number"), last.get("episode_number")):
                out.append(WatchingReleaseItem(
                    media_id=entry.media_id,
                    source="tmdb",
                    media_type=entry.media_type,
                    title=_entry_title(entry),
                    poster_url=entry.poster_url,
                    release_date=last_air_date,
                    is_out=True,
                    season=last.get("season_number"),
                    episode=last.get("episode_number"),
                    episode_name=last.get("name"),
                ))
                continue  # already have a "new episode" row for this title — skip the "coming up" one below

        nxt = info.get("next") or {}
        next_air_date = nxt.get("air_date")
        if next_air_date:
            try:
                still_upcoming = date.fromisoformat(next_air_date) >= today
            except ValueError:
                still_upcoming = False
            if still_upcoming:
                out.append(WatchingReleaseItem(
                    media_id=entry.media_id,
                    source="tmdb",
                    media_type=entry.media_type,
                    title=_entry_title(entry),
                    poster_url=entry.poster_url,
                    release_date=next_air_date,
                    is_out=False,
                    season=nxt.get("season_number"),
                    episode=nxt.get("episode_number"),
                    episode_name=nxt.get("name"),
                ))

    return out


async def _game_release_date(db: Session, media_id: str) -> Optional[str]:
    """Reuses the exact same forever cache GET /media/detail already
    writes to for igdb ids (cache_source == "igdb" there — see
    routers/media.py::media_detail) rather than keeping a second, ad-hoc
    cache of the same data under a different key: a game already opened
    once from its title screen answers instantly here, and a game looked
    up here first populates that same cache for the title screen later.
    Only release_date is read off it; nothing else on the cached
    MediaItem is touched.

    First release_date can be None instead — accepted as a shipped
    tradeoff for the "IGDB has no exact date at all" case (rare, mostly
    ancient games), same as everywhere else this app reads it (see
    IgdbAdapter._normalize)."""
    raw_id = media_id[len("igdb-"):] if media_id.startswith("igdb-") else None
    if not raw_id:
        return None

    cached = cache.get_static_title(db, media_id, "igdb")
    if cached is not None:
        try:
            return MediaDetailOut.model_validate_json(cached).item.release_date
        except Exception:  # noqa: BLE001 — a corrupt/old-shape cache row shouldn't break this
            pass

    try:
        item = await _igdb.full_detail(raw_id)
    except RuntimeError:
        return None  # IGDB not configured — see IgdbAdapter's own module docstring
    if item is None:
        return None
    cache.set_static_title(db, media_id, "igdb", MediaDetailOut(item=item, ratings=None, similar=[]))
    return item.release_date


async def _game_releases(db: Session, entries: List[models.WatchlistEntry]) -> List[WatchingReleaseItem]:
    """Games on watch_later/watching whose IGDB release falls inside the
    same "recent past through today" news window release_calendar()
    itself uses for the discovery grid — a game released long ago just
    doesn't belong on a *new* releases strip, even if it's still sitting
    unplayed on this user's shelf."""
    release_dates = await asyncio.gather(
        *[_game_release_date(db, e.media_id) for e in entries],
        return_exceptions=True,
    )
    today = date.today()
    window_start = today - _GAME_NEWS_WINDOW

    out: List[WatchingReleaseItem] = []
    for entry, release_date_str in zip(entries, release_dates):
        if isinstance(release_date_str, Exception) or not release_date_str:
            continue
        try:
            release_date = date.fromisoformat(release_date_str)
        except ValueError:
            continue
        if release_date < window_start:
            continue
        out.append(WatchingReleaseItem(
            media_id=entry.media_id,
            source="igdb",
            media_type="game",
            title=_entry_title(entry),
            poster_url=entry.poster_url,
            release_date=release_date_str,
            is_out=release_date <= today,
        ))
    return out


@router.get("/watching", response_model=List[WatchingReleaseItem])
async def watching_releases(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The personal "new episodes" strip on Home — see this module's own
    docstring for the series/anime-vs-game split and why Shikimori is
    never involved here."""
    watching_shows = (
        db.query(models.WatchlistEntry)
        .filter(
            models.WatchlistEntry.user_id == current_user.id,
            models.WatchlistEntry.status == models.WatchStatus.watching,
            models.WatchlistEntry.media_type.in_([models.MediaType.series, models.MediaType.anime]),
            models.WatchlistEntry.source == "tmdb",
        )
        .all()
    )
    tracked_games = (
        db.query(models.WatchlistEntry)
        .filter(
            models.WatchlistEntry.user_id == current_user.id,
            models.WatchlistEntry.status.in_([models.WatchStatus.watch_later, models.WatchStatus.watching]),
            models.WatchlistEntry.media_type == models.MediaType.game,
            models.WatchlistEntry.source == "igdb",
        )
        .all()
    )

    results: List[WatchingReleaseItem] = []
    if watching_shows:
        results.extend(await _series_releases(db, current_user.id, watching_shows))
    if tracked_games:
        results.extend(await _game_releases(db, tracked_games))

    results.sort(key=lambda i: i.release_date)
    return results
