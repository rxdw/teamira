import asyncio
import difflib
import json
import logging
import re
from typing import List, Optional

from fastapi import APIRouter, Query, HTTPException, Depends, Request
from pydantic import TypeAdapter
from sqlalchemy.orm import Session

from app import book_extras, book_ratings, cache, extras_merge, game_reviews, game_store, kinopoisk, manga_reviews
from app.database import get_db
from app.deps import get_current_user_id
from app.rate_limit import media_read_limiter, client_key
from app.schemas import (
    MediaItem, MediaDetailOut, EpisodesOut, PersonDetailOut, RatingsOut, TitleExtras,
)
from app.adapters.igdb import IgdbAdapter
from app.adapters.google_books import GoogleBooksAdapter
from app.adapters.hardcover import book_url as hardcover_book_url
from app.adapters.tmdb import TmdbAdapter
from app.adapters.shikimori import ShikimoriAdapter, ShikimoriMangaAdapter, SHIKIMORI_ATTRIBUTION
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
_SHIKIMORI_SUPPLEMENT_SOURCE = "shikimori-supplement-anime-v2"

# GET /media/detail's own forever-cache row version. Bumped whenever the
# cached MediaDetailOut shape changes in a way an old cached row wouldn't
# validate against — most recently, RatingsOut dropping every
# IMDB-specific field down to just tmdb_rating/tmdb_votes/
# reviews_count. A version bump means old rows are simply never looked up
# again (TMDB is re-fetched once, same as any other cache miss) rather
# than needing an actual migration.
#
# Bumped v1 -> v2 for the title_ru/overview_ru fallback-to-English fix in
# TmdbAdapter.full_detail (the guard used to compare against
# original_title, which only catches TMDB's silent English fallback for
# titles whose original_language is itself English — anything else could
# get cached with a plain English string sitting in title.ru/
# overview.ru, displayed as if genuinely Russian). Without this bump,
# every title already opened once before the fix would keep serving that
# same wrong cached row forever; the version bump makes those rows a
# plain cache miss so they get re-fetched under the corrected guard.
_DETAIL_CACHE_SOURCE = "tmdb-detail-v2"

# GET /media/episodes' own forever-cache row version — same reasoning as
# _DETAIL_CACHE_SOURCE, kept as its own constant/version since the two
# endpoints' cached shapes change independently.
_EPISODES_CACHE_SOURCE = "tmdb-episodes-v1"

# GET /media/person's own forever-cache row version — same reasoning as
# _DETAIL_CACHE_SOURCE/_EPISODES_CACHE_SOURCE.
_PERSON_CACHE_SOURCE = "tmdb-person-v1"


async def _apply_shikimori_ru(db: Optional[Session], item: MediaItem, match_title: str) -> bool:
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
            item.extras = TitleExtras(complete=False)
            return False
        # A supplement whose sub-requests partly failed is used this once
        # but not remembered, so the next open asks again.
        if supplement is None or supplement.get("extras_complete", True):
            cache.set_static_title(db, item.id, _SHIKIMORI_SUPPLEMENT_SOURCE, supplement)

    # Extras (studios, episodes, staff, characters, related). A supplement
    # cached by an older build has no "extras" key at all — v2 of the cache
    # key makes that a miss, so this only ever sees the new shape.
    extras_raw = (supplement or {}).get("extras")
    if extras_raw:
        try:
            item.extras = TitleExtras.model_validate(extras_raw)
        except Exception as exc:  # noqa: BLE001 — a malformed extras must not cost the ru text
            logger.warning("Shikimori anime extras unreadable [%s] -> %s", item.id, exc)
    if item.extras is None:
        # Asked, and Shikimori had nothing / no match: an empty object marks
        # that as final (None is how a row cached before extras existed
        # looks, and is rebuilt once — see media_detail).
        item.extras = TitleExtras()
    if supplement and supplement.get("shikimori_id"):
        await _apply_anime_passport(item, supplement["shikimori_id"])

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


async def _apply_kinopoisk(result: MediaDetailOut, lang: str) -> None:
    """Russian-language callers also get Kinopoisk/IMDb ratings, and the
    review badge counts Kinopoisk's reviews too (so it matches the list
    the reviews sheet opens). Applied after the cache read/write like
    _apply_review_count — these numbers are never stored in the forever
    detail cache — and any miss just leaves them unset. Costs nothing
    extra for a title Kinopoisk already answered for (see
    app/kinopoisk.py)."""
    if lang != "ru" or not kinopoisk.enabled():
        return
    tmdb_id = result.item.external_ids.tmdb
    if not tmdb_id or result.item.media_type not in ("movie", "series", "anime"):
        return
    is_series = result.item.media_type != "movie"
    title = await kinopoisk.get_title(tmdb_id, is_series)
    if title is None:
        return
    if result.ratings is None:
        result.ratings = RatingsOut()
    ratings = result.ratings
    ratings.kp_rating = title.kp_rating
    ratings.kp_votes = title.kp_votes
    ratings.imdb_rating = title.imdb_rating
    ratings.imdb_votes = title.imdb_votes
    kp_reviews = await kinopoisk.get_reviews(tmdb_id, is_series)
    if kp_reviews:
        ratings.reviews_count = (ratings.reviews_count or 0) + len(kp_reviews)


async def _apply_hardcover(result: MediaDetailOut) -> None:
    """A book's Hardcover community rating (and the link to its page there)
    for the title screen. Like _apply_kinopoisk: applied after the cache
    read/write, never stored in the forever detail cache, and any miss —
    no token, no ISBN, not on Hardcover, API unreachable — just leaves the
    book without a rating. Aggregate only; see app/adapters/hardcover.py
    for why review text is not used."""
    if not book_ratings.enabled():
        return
    item = result.item
    if item.media_type != "book" or not item.id.startswith(_books.id_prefix):
        return
    book = await book_ratings.get_rating(item.id[len(_books.id_prefix):])
    if book is None or book.rating is None:
        return
    if result.ratings is None:
        result.ratings = RatingsOut()
    result.ratings.hc_rating = book.rating
    result.ratings.hc_votes = book.ratings_count
    result.ratings.hc_url = hardcover_book_url(book.slug) if book.slug else None


# A game or manga title screen must not hang on a slow review source: the
# first open of a never-seen title makes up to three outbound requests
# (IGDB link -> Steam totals -> Steam texts). Past this, the screen just goes
# without the numbers this once; whatever finished is cached already, so the
# next open is instant.
_REVIEW_SOURCE_TIMEOUT_SEC = 7.0


async def _apply_steam(result: MediaDetailOut, lang: str) -> None:
    """A game's Steam score ("94% positive · N reviews") and the review
    count for the badge that opens the reviews sheet. Applied after the
    cache read/write like _apply_hardcover: never stored in the forever
    detail cache, and any miss — no Steam page, Steam unreachable, slow —
    leaves the game without them."""
    item = result.item
    if item.media_type != "game" or not item.id.startswith("igdb-"):
        return
    raw_id = item.id[len("igdb-"):]
    if not raw_id.isdigit():
        return
    try:
        steam = await asyncio.wait_for(
            game_reviews.get_reviews(raw_id, lang), timeout=_REVIEW_SOURCE_TIMEOUT_SEC,
        )
    except Exception as exc:  # noqa: BLE001 — a review source must never break the title screen
        logger.warning("Steam reviews lookup failed [%s] -> %s", item.id, type(exc).__name__)
        return
    if steam is None:
        return
    if result.ratings is None:
        result.ratings = RatingsOut()
    result.ratings.steam_pct = steam.positive_pct
    result.ratings.steam_votes = steam.total or None
    result.ratings.reviews_count = len(steam.reviews) or None


async def _apply_anilist(result: MediaDetailOut) -> None:
    """A manga's AniList score and review count, same rules as _apply_steam."""
    item = result.item
    if item.media_type != "manga":
        return
    mal_id = manga_reviews.mal_id_from_media_id(item.id)
    if mal_id is None:
        return
    try:
        manga = await asyncio.wait_for(
            manga_reviews.get_manga(mal_id), timeout=_REVIEW_SOURCE_TIMEOUT_SEC,
        )
    except Exception as exc:  # noqa: BLE001
        logger.warning("AniList lookup failed [%s] -> %s", item.id, type(exc).__name__)
        return
    if manga is None:
        return
    if manga.score is None and not manga.reviews:
        return
    if result.ratings is None:
        result.ratings = RatingsOut()
    result.ratings.al_rating = manga.score
    result.ratings.reviews_count = len(manga.reviews) or None


async def _apply_anime_passport(item: MediaItem, mal_id) -> None:
    """AniList's tags and source material (manga / light novel / original)
    for an anime. Best-effort and bounded, like every other optional source
    on this screen. Runs while the title is first built, so what it adds
    lands in the forever cache with the rest of the card."""
    try:
        info = await asyncio.wait_for(
            manga_reviews.get_info(int(mal_id), "anime"), timeout=_REVIEW_SOURCE_TIMEOUT_SEC,
        )
    except Exception as exc:  # noqa: BLE001
        logger.warning("AniList anime info failed [%s] -> %s", item.id, type(exc).__name__)
        return
    if info is not None:
        extras_merge.merge_anilist_info(item, info)


async def _apply_game_store(result: MediaDetailOut, lang: str) -> None:
    """A game's price, Metacritic, achievements, controller support and — when
    IGDB had few — Steam's languages and screenshots. Applied after the cache
    read/write like _apply_steam: never stored in the forever detail cache
    (a price must not outlive its week), any miss leaves the game without."""
    item = result.item
    if item.media_type != "game" or not item.id.startswith("igdb-"):
        return
    raw_id = item.id[len("igdb-"):]
    if not raw_id.isdigit():
        return
    try:
        store = await asyncio.wait_for(
            game_store.get_store(raw_id, lang), timeout=_REVIEW_SOURCE_TIMEOUT_SEC,
        )
    except Exception as exc:  # noqa: BLE001
        logger.warning("Steam store lookup failed [%s] -> %s", item.id, type(exc).__name__)
        return
    if store is not None:
        extras_merge.merge_steam_store(item, store)


async def _apply_book_extras(result: MediaDetailOut) -> None:
    """A book's author biography and reader counts (Open Library). Same
    rules as the other overlays: after the cache, bounded, best-effort."""
    item = result.item
    if item.media_type != "book" or not item.id.startswith("gbooks-"):
        return
    creators = item.extras.creators if item.extras else []
    author = creators[0].name if creators else ""
    title = item.title.en or item.title.ru or ""
    if not author or not title:
        return
    try:
        info = await asyncio.wait_for(
            book_extras.get_book_info(item.id[len("gbooks-"):], title, author),
            timeout=_REVIEW_SOURCE_TIMEOUT_SEC,
        )
    except Exception as exc:  # noqa: BLE001
        logger.warning("Open Library book info failed [%s] -> %s", item.id, type(exc).__name__)
        return
    if info is not None:
        extras_merge.merge_book_info(item, info)


async def _apply_manga_info(result: MediaDetailOut) -> None:
    """A manga's AniList passport: weighted tags, popularity, banner, legal
    places to read. Separate from _apply_anilist (score/reviews) on purpose —
    its own query, its own cache row."""
    item = result.item
    if item.media_type != "manga":
        return
    mal_id = manga_reviews.mal_id_from_media_id(item.id)
    if mal_id is None:
        return
    try:
        info = await asyncio.wait_for(
            manga_reviews.get_info(mal_id, "manga"), timeout=_REVIEW_SOURCE_TIMEOUT_SEC,
        )
    except Exception as exc:  # noqa: BLE001
        logger.warning("AniList info lookup failed [%s] -> %s", item.id, type(exc).__name__)
        return
    if info is not None:
        extras_merge.merge_anilist_info(item, info)


def _extras_stale(item: MediaItem) -> bool:
    """A cached game/book/manga card built before extras existed (None), or
    whose sources were only partly reachable (complete=False), is rebuilt on
    the next open instead of served as final."""
    return item.extras is None or not item.extras.complete


async def _apply_overlays(result: MediaDetailOut, source: str, lang: str) -> None:
    """Everything refreshed per request, after the forever cache. The
    sources are independent, so they run side by side — the screen waits for
    the slowest, not the sum."""
    if source == "igdb":
        await asyncio.gather(_apply_steam(result, lang), _apply_game_store(result, lang))
    elif source == "google_books":
        await asyncio.gather(_apply_hardcover(result), _apply_book_extras(result))
    elif source == "shikimori_manga":
        await asyncio.gather(_apply_anilist(result), _apply_manga_info(result))


_games = IgdbAdapter()
_books = GoogleBooksAdapter()
_manga = ShikimoriMangaAdapter()

# search_media enriches at most this many anime hits with a Shikimori
# Russian-text overlay per request — same "bound the fan-out" convention
# as everywhere else in this app that fans out per-item lookups.
_SEARCH_ENRICH_LIMIT = 24

# Google Books' ru_supplement fan-out (_enrich_books_with_ru below) used
# to share _SEARCH_ENRICH_LIMIT=24 with the anime/Shikimori pass above —
# kept as its own, smaller limit instead: Google's shared anonymous quota
# is a modest 1,000 requests/day per IP (see
# app/adapters/google_books.py's module docstring), and a single popular
# search fanning out 24 concurrent ru_supplement() calls would burn a
# visible chunk of that on one request. Bounding how many hits get a
# Russian-text overlay keeps that cost predictable without holding up the
# rest of the (already-returned) results.
_GB_RU_ENRICH_LIMIT = 4

# Cyrillic-vs-Latin sniff so a query typed in Russian is searched against
# TMDB in ru-RU even when the person hasn't turned on "show titles in
# Russian" in Settings — that toggle only controls which language
# *display* prefers, it shouldn't gate whether a Russian query can find
# anything at all. \u0400-\u04FF covers the Cyrillic Unicode block.
_CYRILLIC_RE = re.compile(r"[\u0400-\u04FF]")


# Own forever-cache row per Google Books book search hit — separate from
# anything TMDB/Shikimori-shaped above (different adapter, different
# shape). Manga no longer needs an entry here: Shikimori's /mangas search
# already returns a native `russian` title directly on the list hit (see
# app/adapters/shikimori.py's module docstring), so there's no separate
# enrichment pass left to cache for it.
_GB_RU_SOURCE = "gb-ru-book-v1"


async def _enrich_books_with_ru(db: Optional[Session], items: List[MediaItem]) -> None:
    """Fills in title.ru/description.ru/poster_url_ru on Google Books
    search hits — see GoogleBooksAdapter.ru_supplement's docstring for
    why this is still best-effort (a genuinely separate Russian edition
    has to be indexed for this exact title, there's no translation call
    to fall back on) even though Google Books' langRestrict makes it more
    reliable than Open Library's title-search-and-hope approach was.
    Cached forever per item id, so a repeat search for the same book costs
    nothing further here either.
    """
    eligible = [
        item for item in items if item.source == "google_books" and item.title.en
    ][:_GB_RU_ENRICH_LIMIT]
    if not eligible:
        return

    async def _apply(item: MediaItem) -> None:
        cached = cache.get_static_title(db, item.id, _GB_RU_SOURCE)
        if cached is not None:
            supplement = json.loads(cached) if cached != "null" else None
        else:
            try:
                supplement = await _books.ru_supplement(item.title.en)
            except Exception as exc:  # noqa: BLE001 — a search card should never break over this
                logger.warning("Google Books ru enrichment failed [%s] -> %s", item.id, exc)
                return
            cache.set_static_title(db, item.id, _GB_RU_SOURCE, supplement)
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
    request: Request,
    q: str = Query(..., min_length=1),
    include_games: bool = Query(True),
    include_books: bool = Query(True),
    include_manga: bool = Query(True),
    lang: str = Query("en"),  # "en" | "ru" — client's content-language setting
    _user_id: str = Depends(get_current_user_id),
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
    game cards stay English-only for now. Books come from Google Books
    (see app/adapters/google_books.py's module docstring); manga has its
    own dedicated Shikimori catalog instead (app/adapters/shikimori.py).
    Books get a best-effort Russian overlay too, when Google Books
    happens to have a real Russian-language edition of the same work
    indexed (see GoogleBooksAdapter.ru_supplement).

    Cached for a short window per exact (q, lang, include_*) combination —
    see cache.SEARCH_TTL's docstring for why this exists (it's a burst-
    absorbing cache, not a "shared catalog" one): a debounced-but-still-
    multi-request keystroke, a filter-tab re-trigger, or a user re-opening
    the same search within a few seconds shouldn't mean paying for the
    exact same TMDB round trip more than once.

    No `db: Session = Depends(get_db)` here on purpose, unlike most
    routes in this file — this endpoint's *only* database use is through
    cache.py's get_static_title/set_static_title/cached_dynamic, all
    called below with `db=None` so each cache touch opens and closes its
    own short-lived session instead. That matters specifically here: this
    is exactly the endpoint database.py's own docstring names as the
    cause of a real pool-exhaustion incident (a burst of ~26 concurrent
    onboarding searches), because the old `Depends(get_db)` pattern held
    one pooled connection per request for the *entire* fan-out below —
    TMDB, then Shikimori for every anime hit, then Google Books/IGDB —
    not just the moments actually touching Postgres. Dropping the
    dependency here means a burst of concurrent searches no longer eats
    into the pool at all beyond the brief, separate moments each cache
    read/write actually needs a connection.

    Requires a logged-in caller (get_current_user_id — DB-free token
    check, see its own docstring for why not the full get_current_user)
    and an IP rate limit (media_read_limiter, `db=None` for the same
    pool-exhaustion reason as above) — this endpoint fans out to TMDB,
    Shikimori, IGDB and Google Books on every uncached call, all paid/
    quota-limited third-party APIs; left open, anyone who finds this
    server's address gets a free, unmetered proxy to that quota.
    """
    media_read_limiter.check(None, client_key(request))
    cache_key = (
        f"search:{lang}:{include_games}:{include_books}:{include_manga}:"
        f"{q.strip().casefold()}"
    )
    payload_json = await cache.cached_dynamic(
        None,
        cache_key,
        lambda: _fetch_search_results(None, q, include_games, include_books, include_manga, lang),
        ttl=cache.SEARCH_TTL,
    )
    return TypeAdapter(List[MediaItem]).validate_json(payload_json)


async def _fetch_search_results(
    db: Optional[Session],
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
    request: Request,
    media_id: str = Query(...),
    media_type: str = Query(...),  # "movie" | "series" | "anime" | "game" | "book" | "manga"
    source: str = Query(...),
    lang: str = Query("en"),  # "en" | "ru" — client's content-language setting
    db: Session = Depends(get_db),
    _user_id: str = Depends(get_current_user_id),
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

    Requires a logged-in caller and an IP rate limit (media_read_limiter)
    — same reasoning as search_media above: an uncached call here is a
    real TMDB/IGDB/Google Books round trip, and this is otherwise the
    single most-visited screen after Home.
    """
    media_read_limiter.check(db, client_key(request))
    if source not in ("igdb", "google_books", "shikimori_manga", "tmdb"):
        raise HTTPException(status_code=404, detail="Extended detail is not available for this source")

    cache_source = _DETAIL_CACHE_SOURCE if source == "tmdb" else source

    cached = cache.get_static_title(db, media_id, cache_source)
    # A pre-extras copy that is about to be rebuilt. If the rebuild can't reach
    # its source (Google Books throttling, IGDB down ...), serving this beats
    # turning a title that used to open into a 404.
    stale_copy: Optional[MediaDetailOut] = None
    if cached is not None:
        result = MediaDetailOut.model_validate_json(cached)
        # A card cached before extras existed (or whose sources were only
        # partly reachable) is rebuilt below instead of served as final.
        # Movies/series never carry extras; anime does — see
        # _apply_shikimori_ru.
        stale = (
            _extras_stale(result.item)
            if source in ("igdb", "google_books", "shikimori_manga")
            or (source == "tmdb" and result.item.media_type == "anime")
            else False
        )
        if not stale:
            if source == "tmdb":
                await _apply_review_count(db, result)
                await _apply_kinopoisk(result, lang)
            else:
                await _apply_overlays(result, source, lang)
            return result
        if source != "tmdb":
            stale_copy = result

    if source == "igdb":
        raw_id = media_id[len("igdb-"):] if media_id.startswith("igdb-") else None
        if not raw_id:
            raise HTTPException(status_code=400, detail="Unrecognized media_id format")
        try:
            bundle = await _games.full_detail_bundle(raw_id)
        except RuntimeError as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        if bundle is None:
            if stale_copy is not None:
                await _apply_overlays(stale_copy, source, lang)
                return stale_copy
            raise HTTPException(status_code=404, detail="Title not found")
        item, trailers, similar = bundle
        result = MediaDetailOut(item=item, ratings=None, similar=similar, trailers=trailers)
        cache.set_static_title(db, media_id, source, result)
        await _apply_overlays(result, source, lang)
        return result

    if source in ("google_books", "shikimori_manga"):
        adapter = _books if source == "google_books" else _manga
        raw_id = media_id[len(adapter.id_prefix):] if media_id.startswith(adapter.id_prefix) else None
        if not raw_id:
            raise HTTPException(status_code=400, detail="Unrecognized media_id format")
        bundle = await adapter.full_detail_bundle(raw_id)
        if bundle is None:
            if stale_copy is not None:
                await _apply_overlays(stale_copy, source, lang)
                return stale_copy
            raise HTTPException(status_code=404, detail="Title not found")
        item, similar = bundle
        # No ratings round-trip here (those are the per-request overlays
        # below); `similar` is the "more from this author" / similar-manga
        # shelf the adapter built alongside the card.
        result = MediaDetailOut(item=item, ratings=None, similar=similar)
        # A card whose sources were only partly reachable is returned but not
        # remembered, so the next open asks again (see TitleExtras.complete).
        if not _extras_stale(item):
            cache.set_static_title(db, media_id, source, result)
        await _apply_overlays(result, source, lang)
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
    extras_ok = not (result.item.media_type == "anime" and _extras_stale(result.item))
    if ru_fetch_ok and extras_ok:
        cache.set_static_title(db, media_id, cache_source, result)
    else:
        logger.warning("TMDB ru-RU detail fetch failed [%s] — not caching, will retry next open", media_id)
    await _apply_review_count(db, result)
    await _apply_kinopoisk(result, lang)
    return result


@router.get("/episodes", response_model=EpisodesOut)
async def media_episodes(
    request: Request,
    media_id: str = Query(...),
    source: str = Query(...),
    db: Session = Depends(get_db),
    _user_id: str = Depends(get_current_user_id),
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
    Same auth + IP rate limit as /media/detail, same reasoning.
    """
    media_read_limiter.check(db, client_key(request))
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
    request: Request,
    person_id: str = Query(...),
    db: Session = Depends(get_db),
    _user_id: str = Depends(get_current_user_id),
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
    Same auth + IP rate limit as /media/detail, same reasoning.
    """
    media_read_limiter.check(db, client_key(request))
    cached = cache.get_static_title(db, person_id, _PERSON_CACHE_SOURCE)
    if cached is not None:
        return PersonDetailOut.model_validate_json(cached)

    result = await _tmdb.person_detail(person_id)
    if result is None:
        raise HTTPException(status_code=404, detail="Person not found")

    cache.set_static_title(db, person_id, _PERSON_CACHE_SOURCE, result)
    return result
