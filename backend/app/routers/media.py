import asyncio
import difflib
import json
import logging
import re
from typing import List

from fastapi import APIRouter, Query, HTTPException, Depends
from pydantic import TypeAdapter
from sqlalchemy.orm import Session

from app import cache
from app.database import get_db
from app.schemas import (
    MediaItem, MediaDetailOut, EpisodesOut, PersonDetailOut,
)
from app.adapters.igdb import IgdbAdapter
from app.adapters.open_library import OpenLibraryAdapter, _MANGA_SHELVES
from app.adapters.tmdb import TmdbAdapter
from app.adapters.shikimori import ShikimoriAdapter, SHIKIMORI_ATTRIBUTION
from app.routers.reviews import fetch_reviews as _fetch_merged_reviews, REVIEWS_TTL as _REVIEWS_TTL
from app.schemas import TmdbReviewsOut

logger = logging.getLogger("seenly.routers.media")

router = APIRouter(prefix="/media", tags=["media"])

_tmdb = TmdbAdapter()
_shikimori = ShikimoriAdapter()

# Anime-only Russian-text source (see app/adapters/shikimori.py's module
# docstring for why TMDB's own ru-RU translation alone isn't enough here —
# it's frequently thin or missing for anime specifically). Keyed by the
# item's own id ("tmdb-<id>") rather than a separate Shikimori id — this
# app has no id in common with Shikimori's catalog at all, so the item id
# is the only stable key available regardless of which title it is.
# "-v1" so the shape can be bumped later the same way TMDB's own cached
# rows are versioned (see app/adapters/tmdb.py).
_SHIKIMORI_SUPPLEMENT_SOURCE = "shikimori-supplement-anime-v1"

# GET /media/detail's own forever-cache row version. Bumped whenever the
# cached MediaDetailOut shape changes in a way an old cached row wouldn't
# validate against — most recently, RatingsOut dropping every
# IMDB-specific field down to just tmdb_rating/tmdb_votes/
# reviews_count. A version bump means old rows are simply never looked up
# again (TMDB is re-fetched once, same as any other cache miss) rather
# than needing an actual migration.
_DETAIL_CACHE_SOURCE = "tmdb-detail-v1"

# GET /media/episodes' own forever-cache row version — same reasoning as
# _DETAIL_CACHE_SOURCE, kept as its own constant/version since the two
# endpoints' cached shapes change independently.
_EPISODES_CACHE_SOURCE = "tmdb-episodes-v1"

# GET /media/person's own forever-cache row version — same reasoning as
# _DETAIL_CACHE_SOURCE/_EPISODES_CACHE_SOURCE.
_PERSON_CACHE_SOURCE = "tmdb-person-v1"


async def _apply_shikimori_ru(db: Session, item: MediaItem, match_title: str) -> bool:
    """Overlays title.ru/description.ru/poster_url_ru on an anime `item`
    from Shikimori, overriding whatever TMDB's own (usually thinner, for
    anime) ru text already set — see app/adapters/shikimori.py's module
    docstring for why anime gets a second, Russian-native source instead of
    just trusting TMDB's ru-RU translation. Matched by title/year (Shikimori
    has no id in common with this app's catalog), cached forever, keyed by
    the item's own id.

    `match_title` is the romaji/original title to search Shikimori with —
    callers must pass this explicitly (TMDB's own `original_title`/
    `original_name`, captured by app/adapters/tmdb.py's catalog_search/
    full_detail alongside the item itself) rather than this helper reading
    item.title.en, because item.title.en is already TMDB's real English
    title by the time this runs (TMDB is the primary catalog now — see
    this module's own docstring at the top). Shikimori's own catalog is
    romaji-native, so searching it with a real English title ("Attack on
    Titan" instead of "Shingeki no Kyojin") would just fail to match at all.

    Returns whether anything was actually overlaid, so callers know whether
    to also set shikimori_attribution — a miss (no confident Shikimori
    match, or nothing configured/reachable) just leaves TMDB's ru text (or
    English, if TMDB had none either) exactly as it already was, same
    "degrade to what we already had" convention as everywhere else in this
    file.
    """
    cached = cache.get_static_title(db, item.id, _SHIKIMORI_SUPPLEMENT_SOURCE)
    if cached is not None:
        supplement = json.loads(cached)
    else:
        try:
            supplement = await _shikimori.anime_supplement(match_title or "", item.year)
        except Exception as exc:  # a Shikimori hiccup should never break the title screen
            logger.warning("Shikimori supplement fetch failed [%s] -> %s", item.id, exc)
            return False
        cache.set_static_title(db, item.id, _SHIKIMORI_SUPPLEMENT_SOURCE, supplement)

    if not supplement:
        return False
    applied = False
    if supplement.get("title_ru"):
        item.title.ru = supplement["title_ru"]
        applied = True
    if supplement.get("overview_ru"):
        item.description.ru = supplement["overview_ru"]
        applied = True
    if supplement.get("poster_ru"):
        item.poster_url_ru = supplement["poster_ru"]
        applied = True
    return applied


async def _apply_review_count(db: Session, result: MediaDetailOut) -> None:
    """Sets `ratings.reviews_count` from the merged TMDB+Trakt review list
    the title screen's "N reviews" badge is supposed to be describing —
    reuses the exact same cache entry app/routers/reviews.py already
    maintains (same key, same TTL), so opening the badge and opening the
    reviews sheet share one fetch, not two. A miss (no tmdb id, or the
    merged fetch itself failing) just leaves reviews_count unset — same
    "degrade to what we already had" convention as everywhere else here.
    """
    if result.ratings is None:
        return
    tmdb_id = result.item.external_ids.tmdb
    if not tmdb_id:
        return
    segment = "movie" if result.item.media_type == "movie" else "tv"
    cache_key = f"reviews:{tmdb_id}:{segment}"
    try:
        payload_json = await cache.cached_dynamic(
            db, cache_key, lambda: _fetch_merged_reviews(tmdb_id, segment), ttl=_REVIEWS_TTL,
        )
        count = len(TmdbReviewsOut.model_validate_json(payload_json).reviews)
    except Exception as exc:  # a TMDB/Trakt hiccup should never break the title screen
        logger.warning("Merged review count fetch failed [%s:%s] -> %s", tmdb_id, segment, exc)
        return
    # None (not 0) when there's genuinely nothing — same "hide the badge
    # entirely" convention the client already applies for a null count.
    result.ratings.reviews_count = count or None


_games = IgdbAdapter()
_books = OpenLibraryAdapter()
_manga = OpenLibraryAdapter(
    media_type="manga",
    id_prefix="olm-",
    source="open_library_manga",
    shelves=_MANGA_SHELVES,
    search_filter="subject:manga",
)

# search_media enriches at most this many anime hits with a Shikimori
# Russian-text overlay per request — same "bound the fan-out" convention
# as everywhere else in this app that fans out per-item lookups.
_SEARCH_ENRICH_LIMIT = 24

# Open Library's own ru_supplement fan-out (_enrich_books_with_ru below)
# used to share _SEARCH_ENRICH_LIMIT=24 with the anime/Shikimori pass
# above — fine when everything ran unthrottled, but now that
# OpenLibraryAdapter rate-limits itself to ~1 req/sec process-wide (see
# app/adapters/open_library.py's _rate_limiter — Open Library's own
# unidentified-caller cap), 24 queued-up requests at 1/sec means a single
# book/manga search with that many matches could take up to 24 seconds to
# respond. Kept much smaller here so the worst case is a handful of
# seconds instead: a search still returns every result immediately, this
# only bounds how many of them wait around for a Russian-text overlay
# before the response goes out.
_OL_RU_ENRICH_LIMIT = 4

# Cyrillic-vs-Latin sniff so a query typed in Russian is searched against
# TMDB in ru-RU even when the person hasn't turned on "show titles in
# Russian" in Settings — that toggle only controls which language
# *display* prefers, it shouldn't gate whether a Russian query can find
# anything at all. \u0400-\u04FF covers the Cyrillic Unicode block.
_CYRILLIC_RE = re.compile(r"[\u0400-\u04FF]")


# Own forever-cache row per Open Library adapter instance — separate from
# anything TMDB/Shikimori-shaped above (different adapter, different
# shape) and separate between books vs manga even though they share one
# adapter class, so the two catalogs don't collide in one cache row.
_OL_RU_SOURCE = {"open_library": "ol-ru-book-v1", "open_library_manga": "ol-ru-manga-v1"}


async def _enrich_books_with_ru(db: Session, items: List[MediaItem]) -> None:
    """Fills in title.ru/description.ru/poster_url_ru on Open Library
    (books/manga) search hits — see OpenLibraryAdapter.ru_supplement's
    docstring for why this is meaningfully lower-coverage than the anime
    Shikimori overlay above (a real but separate Russian edition has to
    actually exist in Open Library's catalog, there's no translation call
    to fall back on). Cached forever per item id, so a repeat search for
    the same book costs nothing further here either.
    """
    eligible = [
        item for item in items
        if item.source in ("open_library", "open_library_manga") and item.title.en
    ][:_OL_RU_ENRICH_LIMIT]
    if not eligible:
        return
    adapter_by_source = {"open_library": _books, "open_library_manga": _manga}

    async def _apply(item: MediaItem) -> None:
        cache_source = _OL_RU_SOURCE[item.source]
        cached = cache.get_static_title(db, item.id, cache_source)
        if cached is not None:
            supplement = json.loads(cached) if cached != "null" else None
        else:
            try:
                supplement = await adapter_by_source[item.source].ru_supplement(item.title.en)
            except Exception as exc:  # noqa: BLE001 — a search card should never break over this
                logger.warning("Open Library ru enrichment failed [%s] -> %s", item.id, exc)
                return
            cache.set_static_title(db, item.id, cache_source, supplement)
        if not supplement:
            return
        if supplement.get("title_ru"):
            item.title.ru = supplement["title_ru"]
        if supplement.get("description_ru"):
            item.description.ru = supplement["description_ru"]
        if supplement.get("poster_ru"):
            item.poster_url_ru = supplement["poster_ru"]

    await asyncio.gather(*[_apply(item) for item in eligible], return_exceptions=True)


_TITLE_PUNCT_RE = re.compile(r"[^\w\s]", re.UNICODE)


def _normalize_for_match(text: str) -> str:
    """Casefold + strip punctuation, so \"Миньоны и монстры\" and a query
    of \"миньоны\" compare on words alone, not on colons/apostrophes/case.
    """
    return _TITLE_PUNCT_RE.sub("", text or "").strip().casefold()


def _match_score(query: str, item: MediaItem) -> float:
    """How well `item`'s title matches `query`, on a single 0-100 scale
    shared across every media type — used to sort the *whole* merged
    catalog (movies/series/anime + games + books/manga) by best match
    instead of leaving it grouped block-by-block in whatever order each
    source's results got appended in (see _fetch_search_results below).

    Checked against both title.en and title.ru (whichever the source
    populated) and the higher of the two wins, since a Russian query can
    still land squarely on an English-only title and vice versa.
    """
    q = _normalize_for_match(query)
    if not q:
        return 0.0
    best = 0.0
    for candidate in (item.title.en, item.title.ru):
        if not candidate:
            continue
        t = _normalize_for_match(candidate)
        if not t:
            continue
        if t == q:
            score = 100.0
        elif t.startswith(q):
            score = 90.0
        elif re.search(rf"(?:^|\s){re.escape(q)}(?:\s|$)", t):
            score = 75.0  # whole word match inside a longer title
        elif q in t:
            score = 60.0
        else:
            score = difflib.SequenceMatcher(None, q, t).ratio() * 50.0
        best = max(best, score)
    return best


@router.get("/search", response_model=List[MediaItem])
async def search_media(
    q: str = Query(..., min_length=1),
    include_games: bool = Query(True),
    include_books: bool = Query(True),
    include_manga: bool = Query(True),
    lang: str = Query("en"),  # "en" | "ru" — client's content-language setting
    db: Session = Depends(get_db),
):
    """
    Movies/series/anime all come straight from TMDB now (see
    app/adapters/tmdb.py::catalog_search) — TMDB is the primary catalog
    for this app. A query typed in Russian, or with
    `lang=ru`, is searched against TMDB in ru-RU directly — TMDB indexes
    per-language natively, so there's no separate "fallback search"
    machinery needed anymore for either a Russian query or an anime title
    whose English name isn't its romaji original; catalog_search just
    returns the right text the first time.

    Anime (detected off TMDB's own data — Animation genre + Japanese
    origin, see app/adapters/tmdb.py::_is_anime) gets a further Russian
    overlay from Shikimori on top of whatever TMDB returned — see
    _apply_shikimori_ru's docstring for why anime specifically still needs
    a second, more-native Russian source even with TMDB primary.

    Games always come from the games adapter, since TMDB doesn't cover
    them — no Russian pass for these: IGDB has no translated-text field
    to draw from, and there's no other free source wired up for it, so
    game cards stay English-only for now. Books and manga come from Open
    Library (manga rides the same book catalog, scoped to the "manga"
    subject — see app/adapters/open_library.py's module docstring for why
    it isn't on a manga-specific API); each gets a best-effort Russian
    overlay too, when Open Library happens to have a real Russian-language
    edition of the same work indexed (see OpenLibraryAdapter.ru_supplement).

    Cached for a short window per exact (q, lang, include_*) combination —
    see cache.SEARCH_TTL's docstring for why this exists (it's a burst-
    absorbing cache, not a "shared catalog" one): a debounced-but-still-
    multi-request keystroke, a filter-tab re-trigger, or a user re-opening
    the same search within a few seconds shouldn't mean paying for the
    exact same TMDB round trip more than once.
    """
    cache_key = (
        f"search:{lang}:{include_games}:{include_books}:{include_manga}:"
        f"{q.strip().casefold()}"
    )
    payload_json = await cache.cached_dynamic(
        db,
        cache_key,
        lambda: _fetch_search_results(db, q, include_games, include_books, include_manga, lang),
        ttl=cache.SEARCH_TTL,
    )
    return TypeAdapter(List[MediaItem]).validate_json(payload_json)


async def _fetch_search_results(
    db: Session,
    q: str,
    include_games: bool,
    include_books: bool,
    include_manga: bool,
    lang: str,
) -> List[MediaItem]:
    """The actual TMDB/Shikimori/IGDB/Open-Library fan-out search_media
    used to run inline — pulled out so it can sit behind
    cache.cached_dynamic above as a plain `fetch()` callable.
    """
    language = "ru-RU" if (lang == "ru" or _CYRILLIC_RE.search(q)) else None
    results, original_titles = await _tmdb.catalog_search(q, language=language)

    anime_hits = [item for item in results if item.media_type == "anime"][:_SEARCH_ENRICH_LIMIT]
    if anime_hits:
        await asyncio.gather(
            *[
                _apply_shikimori_ru(db, item, original_titles.get(item.id, item.title.en))
                for item in anime_hits
            ],
            return_exceptions=True,
        )

    if include_games:
        results += await _games.search(q)

    book_manga_results: List[MediaItem] = []
    if include_books:
        book_manga_results += await _books.search(q)

    if include_manga:
        book_manga_results += await _manga.search(q)

    await _enrich_books_with_ru(db, book_manga_results)
    results += book_manga_results

    # Everything above got appended in blocks — movies/series/anime, then
    # games, then books/manga — so left as-is the list reads as "grouped
    # by type" rather than "best match first" (see the search screen's
    # "all" tab). Re-sort the whole merged catalog by _match_score instead;
    # ties keep their original position (stable sort), which preserves
    # each source's own relevance ordering for equally-good matches.
    results.sort(key=lambda item: -_match_score(q, item))

    return results


@router.get("/detail", response_model=MediaDetailOut)
async def media_detail(
    media_id: str = Query(...),
    media_type: str = Query(...),  # "movie" | "series" | "anime" | "game" | "book" | "manga"
    source: str = Query(...),
    db: Session = Depends(get_db),
):
    """Everything the title screen needs beyond what search/feed already
    gave it: runtime/certification/status, ratings, cast/director,
    trailers, and a short "similar titles" shelf — all straight from TMDB
    now for movies/series/anime (see app/adapters/tmdb.py::full_detail).
    Games/books/manga get a lighter version of the same shape, unchanged
    from before.

    Cached forever per (media_id, source) once resolved — see
    app/cache.py — so a cache hit here means zero outbound calls at all
    for the single most-visited screen after Home.
    """
    if source not in ("igdb", "open_library", "open_library_manga", "tmdb"):
        raise HTTPException(status_code=404, detail="Extended detail is not available for this source")

    cache_source = _DETAIL_CACHE_SOURCE if source == "tmdb" else source

    cached = cache.get_static_title(db, media_id, cache_source)
    if cached is not None:
        result = MediaDetailOut.model_validate_json(cached)
        if source == "tmdb":
            await _apply_review_count(db, result)
        return result

    if source == "igdb":
        raw_id = media_id[len("igdb-"):] if media_id.startswith("igdb-") else None
        if not raw_id:
            raise HTTPException(status_code=400, detail="Unrecognized media_id format")
        try:
            item = await _games.full_detail(raw_id)
        except RuntimeError as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        if item is None:
            raise HTTPException(status_code=404, detail="Title not found")
        result = MediaDetailOut(item=item, ratings=None, similar=[])
        cache.set_static_title(db, media_id, source, result)
        return result

    if source in ("open_library", "open_library_manga"):
        adapter = _books if source == "open_library" else _manga
        raw_id = media_id[len(adapter.id_prefix):] if media_id.startswith(adapter.id_prefix) else None
        if not raw_id:
            raise HTTPException(status_code=400, detail="Unrecognized media_id format")
        item = await adapter.full_detail(raw_id)
        if item is None:
            raise HTTPException(status_code=404, detail="Title not found")
        # Same lighter shape as games — no ratings/similar round-trip.
        result = MediaDetailOut(item=item, ratings=None, similar=[])
        cache.set_static_title(db, media_id, source, result)
        return result

    # source == "tmdb" — the only movie/series/anime source now.
    raw_tmdb_id = media_id[len("tmdb-"):] if media_id.startswith("tmdb-") else None
    if not raw_tmdb_id:
        raise HTTPException(status_code=400, detail="Unrecognized media_id format")

    built = await _tmdb.full_detail(raw_tmdb_id, media_type)
    if built is None:
        raise HTTPException(status_code=404, detail="Title not found")
    result, original_title, ru_fetch_ok = built

    if result.item.media_type == "anime":
        if await _apply_shikimori_ru(db, result.item, original_title):
            result.shikimori_attribution = SHIKIMORI_ATTRIBUTION

    # This cache has no TTL (see app/cache.py::set_static_title) — only
    # persist it once the ru-RU side genuinely resolved (200 or a real
    # 404), not on a transient TMDB hiccup (429/5xx/timeout). Otherwise a
    # momentary rate-limit blip (e.g. while app/routers/feed.py's
    # collections poster backfill is running) would permanently stick
    # this title showing English-only, never retried. On a failed fetch
    # we still return what we have this one time, just don't persist it.
    if ru_fetch_ok:
        cache.set_static_title(db, media_id, cache_source, result)
    else:
        logger.warning("TMDB ru-RU detail fetch failed [%s] — not caching, will retry next open", media_id)
    await _apply_review_count(db, result)
    return result


@router.get("/episodes", response_model=EpisodesOut)
async def media_episodes(
    media_id: str = Query(...),
    source: str = Query(...),
    db: Session = Depends(get_db),
):
    """A series' season/episode structure, grouped for the title screen's
    tracker — straight from TMDB now (see
    app/adapters/tmdb.py::tv_episodes). Games, books/manga, and movies all
    get a clean empty result rather than a 404 — the client treats
    "no episodes" as "nothing to track", not an error state; a movie's
    tmdb id simply 404s inside tv_episodes since movie/tv are separate
    TMDB id namespaces, same as it would if we filtered on media_type
    ourselves.

    Cached forever per (media_id, source), same reasoning as /media/detail.
    """
    if source != "tmdb" or not media_id.startswith("tmdb-"):
        return EpisodesOut(seasons=[])

    cached = cache.get_static_episodes(db, media_id, _EPISODES_CACHE_SOURCE)
    if cached is not None:
        return EpisodesOut.model_validate_json(cached)

    raw_tmdb_id = media_id[len("tmdb-"):]
    seasons = await _tmdb.tv_episodes(raw_tmdb_id)
    result = EpisodesOut(seasons=seasons)
    cache.set_static_episodes(db, media_id, _EPISODES_CACHE_SOURCE, result)
    return result


@router.get("/person", response_model=PersonDetailOut)
async def media_person(
    person_id: str = Query(...),
    db: Session = Depends(get_db),
):
    """What a tapped cast tile or "directed by ___" name opens — bio,
    photo, and a filmography grid, straight from TMDB (see
    app/adapters/tmdb.py::person_detail). `person_id` is a CastMember's
    own `person_id` / a MediaItem's `director_id` — both are TMDB person
    ids, so there's exactly one id space to deal with here, not one per
    catalog source the way titles have.

    Cached forever per person_id, same reasoning as /media/detail — a
    person's bio/photo/filmography doesn't change meaningfully often
    enough to re-fetch past the first open.
    """
    cached = cache.get_static_title(db, person_id, _PERSON_CACHE_SOURCE)
    if cached is not None:
        return PersonDetailOut.model_validate_json(cached)

    result = await _tmdb.person_detail(person_id)
    if result is None:
        raise HTTPException(status_code=404, detail="Person not found")

    cache.set_static_title(db, person_id, _PERSON_CACHE_SOURCE, result)
    return result
