"""
TMDB's `watch/providers` endpoint — free, keyed off a TMDB API key
(themoviedb.org/settings/api), and itself sourced from JustWatch under a
data-sharing deal TMDB has with them. That parentage matters for two
reasons:

1. It's *availability* data only (which providers carry a title, in which
   country) plus one combined "watch" page link — not a per-provider deep
   link you can attach an affiliate tag to. That per-provider deep link is
   JustWatch's own product, and their terms don't allow scraping it out of
   the combined page. See app/routers/watch.py's module docstring for what
   this means for monetizing the feature.
2. TMDB's terms require attribution ("Powered by JustWatch") wherever this
   data is shown — already baked into WatchProvidersOut.attribution.
"""

import asyncio
import logging
import re
from datetime import date
from typing import List, Optional

import httpx

from app.config import settings
from app.schemas import (
    CastMember,
    EpisodeOut,
    ExternalIds,
    LocalizedText,
    MediaDetailOut,
    MediaItem,
    PersonDetailOut,
    RatingsOut,
    SeasonOut,
    TitleTrailer,
)

logger = logging.getLogger("seenly.adapters.tmdb")


TMDB_BASE = "https://api.themoviedb.org/3"

# NOTE: the image-size base URLs (w92/w185/w500/w780) and the
# image.tmdb.org -> /media/image-proxy rewrite used to live here, applied
# as soon as this adapter built a poster/backdrop/profile/logo URL. Both
# now live in app/image_urls.py instead, applied once at response-
# serialization time (see that module's docstring for why) — this
# adapter just hands back TMDB's own bare path unchanged (see
# poster_url()/profile_url()/logo_url() below, and the inline
# backdrop_path passthroughs further down).


# Attribution string for MediaDetailOut.tmdb_attribution — required by
# TMDB's API Terms of Use wherever their data/images are shown, same
# reasoning as WatchProvidersOut.attribution.
TMDB_ATTRIBUTION = "Данные предоставлены TMDB"

# reviews() walks up to this many pages (20 reviews/page) — a sane ceiling
# so an extremely-reviewed title doesn't turn one cache-refresh into an
# unbounded number of TMDB calls. 10 pages = ~200 reviews, comfortably
# more than any title-detail sheet needs to feel "complete".
_TMDB_REVIEWS_MAX_PAGES = 10

# Genre id -> name, hardcoded from TMDB's own (documented, effectively
# static) reference lists — https://developer.themoviedb.org/reference/
# genre-movie-list and .../genre-tv-list. Search hits (/search/multi,
# /discover, /similar) only carry `genre_ids` (bare ints), not the
# `genres: [{id,name}]` objects a full /movie or /tv detail call returns —
# so anywhere this app needs genre *names* off a thin search-style hit, it
# looks them up here instead of making an extra /genre/*/list call (or
# worse, a second detail call) just to get a name string. A full detail
# response's own `genres` array is used as-is instead (see
# _media_item_from_tmdb) since it's already got names.
_MOVIE_GENRES = {
    28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy", 80: "Crime",
    99: "Documentary", 18: "Drama", 10751: "Family", 14: "Fantasy",
    36: "History", 27: "Horror", 10402: "Music", 9648: "Mystery",
    10749: "Romance", 878: "Science Fiction", 10770: "TV Movie",
    53: "Thriller", 10752: "War", 37: "Western",
}
_TV_GENRES = {
    10759: "Action & Adventure", 16: "Animation", 35: "Comedy", 80: "Crime",
    99: "Documentary", 18: "Drama", 10751: "Family", 10762: "Kids",
    9648: "Mystery", 10763: "News", 10764: "Reality",
    10765: "Sci-Fi & Fantasy", 10766: "Soap", 10767: "Talk",
    10768: "War & Politics", 37: "Western",
}
_ANIME_GENRE_ID = 16  # "Animation" — same id in both tables above
_MOVIE_GENRE_IDS = {v: k for k, v in _MOVIE_GENRES.items()}
_TV_GENRE_IDS = {v: k for k, v in _TV_GENRES.items()}


def _franchise_key(title: Optional[str]) -> str:
    """Rough franchise fingerprint: the title text before the first colon/
    dash, with a trailing "Part 2" / roman numeral / number stripped, all
    lowercased — e.g. "Harry Potter and the Deathly Hallows: Part 2" and
    "Harry Potter and the Goblet of Fire" both collapse to "harry potter
    and the". Historical franchise-fingerprint helper — good enough to stop
    one multi-film franchise from filling an entire shelf, without real
    franchise metadata."""
    if not title:
        return ""
    base = re.split(r"[:\-–—]", title, maxsplit=1)[0].strip().lower()
    base = re.sub(r"\s+(part\s*)?\b([ivxlcdm]{1,4}|\d{1,2})\b\s*$", "", base)
    return base


def _diversify_with_cap(items: List[MediaItem], cap: int) -> List[MediaItem]:
    counts: dict = {}
    result = []
    for item in items:
        key = _franchise_key(item.title.en or item.title.ru)
        counts[key] = counts.get(key, 0) + 1
        if counts[key] <= cap:
            result.append(item)
    return result


def _diversify(items: List[MediaItem], max_per_franchise: int = 2, min_result: int = 8) -> List[MediaItem]:
    """Caps how many entries from the same apparent franchise can appear in
    one shelf — order-preserving, so it still favors the highest-ranked
    items overall.

    The cap is meant to stop one huge, currently-everywhere franchise
    (a dozen Demon Slayer entries, say) from crowding out everything
    else — not to starve a shelf whose raw candidate pool was thin to
    begin with. That combination bit hardest on the narrower
    genre-scoped shelves (anime ones especially: JP origin + one genre +
    vote_count>=20 is already a small slice of TMDB, and a couple of
    massively-popular franchises can fill most of a single results page
    on their own) — a shelf could come back with 2 items even though its
    raw pool had 15 perfectly good, just-differently-franchised ones.
    So: if capping at [max_per_franchise] would leave fewer than
    [min_result] items and the pool actually has more to offer, relax
    the cap a notch at a time until the shelf fills back up (or there's
    genuinely nothing left to add).
    """
    cap = max_per_franchise
    result = _diversify_with_cap(items, cap)
    target = min(min_result, len(items))
    while len(result) < target and cap < len(items):
        cap += 1
        result = _diversify_with_cap(items, cap)
    return result


def _is_anime(genre_ids, origin_country, original_language: Optional[str]) -> bool:
    """The heuristic this whole app uses to decide "anime" vs "series"/
    "movie" — TMDB itself has no "anime" category, it's
    just tv/movie content that happens to be Japanese animation. Standard
    two-part check: the Animation genre AND a Japanese origin (either
    signal alone over-fires — "Animation" alone catches Pixar/Disney,
    "Japanese origin" alone catches Japanese live-action). `genre_ids` may
    be either the thin int list a search/similar hit carries or a full
    `genres: [{id,...}]` object list off a detail call — both shapes are
    accepted so callers don't have to normalize first.
    """
    ids = set()
    for g in genre_ids or []:
        if isinstance(g, dict):
            gid = g.get("id")
            if gid is not None:
                ids.add(gid)
        elif g is not None:
            ids.add(g)
    is_animation = _ANIME_GENRE_ID in ids
    is_japanese = original_language == "ja" or "JP" in (origin_country or [])
    return is_animation and is_japanese


class TmdbAdapter:
    source_name = "tmdb"

    async def watch_providers(self, tmdb_id: str, segment: str, country: str) -> Optional[dict]:
        """`segment` is "movie" or "tv" — TMDB's catalog is divided this way, and anime
        rides the "tv" segment here too. Returns the raw per-country
        {link, flatrate, rent, buy} dict, or None if TMDB has nothing for
        this id/country (a very ordinary case — most of the world's
        catalog isn't listed for every country)."""
        if not settings.tmdb_api_key:
            raise RuntimeError("TMDB_API_KEY is not configured")
        url = f"{TMDB_BASE}/{segment}/{tmdb_id}/watch/providers"
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(url, params={"api_key": settings.tmdb_api_key})
            if resp.status_code == 404:
                return None
            resp.raise_for_status()
        data = resp.json()
        return (data.get("results") or {}).get(country)

    @staticmethod
    def logo_url(logo_path: Optional[str]) -> Optional[str]:
        """Returns TMDB's bare path unchanged (e.g. "/abc.png") — no base
        URL, no proxying. Resolving that into a full (optionally
        proxied) URL now happens once, at response-serialization time —
        see app/image_urls.py's module docstring for why that has to be
        deferred that late rather than done here."""
        return logo_path or None

    @staticmethod
    def profile_url(profile_path: Optional[str]) -> Optional[str]:
        return profile_path or None

    @staticmethod
    def poster_url(poster_path: Optional[str]) -> Optional[str]:
        return poster_path or None

    async def season_posters(self, tmdb_id: str) -> dict:
        """Poster path per season number, straight off /tv/{id}'s own
        `seasons` summary array — no extra per-season call needed, TMDB's
        main tv detail response already carries a poster_path (when it
        has one) for every season in one shot. Keyed by season_number;
        season 0 (specials) comes back in the raw response same as any
        other season but is never looked up since the episode grid
        itself drops specials (see this file's episodes() docstring) —
        harmless, just an unused dict entry.

        Anime rides this same "tv" endpoint on TMDB's side (same as
        watch_providers()/videos() above), so no separate anime path is
        needed here either.

        Empty dict on a 404, no configured key, or a title TMDB simply
        has no season data for — same "just show nothing extra" degrade
        as everywhere else in this adapter; callers already treat a
        season with no poster_url as an ordinary, expected case.
        """
        if not settings.tmdb_api_key:
            return {}
        url = f"{TMDB_BASE}/tv/{tmdb_id}"
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.get(url, params={"api_key": settings.tmdb_api_key})
            if resp.status_code == 404:
                return {}
            resp.raise_for_status()
        data = resp.json()
        posters: dict = {}
        for s in data.get("seasons") or []:
            number = s.get("season_number")
            path = s.get("poster_path")
            if number is not None and path:
                posters[int(number)] = self.poster_url(path)
        return posters

    async def shelf_ru_supplement(self, tmdb_id: str, segment: str) -> dict:
        """Backfills title_ru/overview_ru/poster_ru for one Collections-shelf
        item via TMDB's per-title endpoint — one `language=ru-RU` call with
        `append_to_response=images,translations` (no credits/videos, no
        second English call; cast/director/trailers still come from the
        full per-title detail call once someone actually opens the title).

        Why this exists at all: app/adapters/tmdb.py::_fetch_list already
        passes `language=ru-RU` straight through to every discover/list
        call Collections shelves are built from, and TMDB's docs say that
        should be enough — but in practice list/discover-shaped endpoints
        resolve a title's translation far less reliably than the per-title
        endpoint does (TMDB's own community-translation data appears to be
        indexed primarily against the single-item endpoint; the same title
        that comes back untranslated from /discover/movie often has a
        genuine Russian translation one call away on /movie/{id}). This was
        originally poster_ru()-only, on the assumption that only the
        poster needed this fallback and title/overview were fine off the
        list call directly — that assumption was wrong, this closes the
        same gap for text too, using the exact same request (title/
        overview are already in that response; we just weren't reading
        them).

        title_ru/overview_ru come from the `translations` block, NOT the
        top-level `title`/`overview` fields — TMDB's per-title endpoint
        quietly falls back to *English* (not the title's original
        language, and not a blank value) when it has no real Russian
        translation, so a same-language guard against `original_title`
        only catches the fallback for titles whose original_language
        already happens to be English; anything else (a French, Japanese,
        Korean, ... original) sails right through that guard with an
        English string sitting in title.ru, displayed as if it were
        genuinely Russian (this is the exact bug behind "poster's
        Russian, description's Russian, but the title's still in
        English" reports — TMDB's own community forum confirms the
        fallback-to-English behavior: a title/overview only appears in
        the main response body when the requested language actually has
        a translation, otherwise it silently substitutes the fallback
        language's text into the same field). The `translations` block
        sidesteps all of that: it lists every language TMDB actually has
        a submitted translation for, each with its own untouched
        `data.title`/`data.overview` — so reading the `ru` entry out of
        that list (or leaving both None when there isn't one) is a
        definitive presence check instead of a guess, and covers
        `overview_ru` too, which previously had no guard against this
        fallback at all.

        Returns {"title_ru", "overview_ru", "poster_ru"} — every key
        present, None where TMDB has nothing. Raises on a transient
        failure (network error, 429, 5xx) rather than folding it into
        that same "nothing here" result — see app/routers/feed.py::
        _apply_ru_supplement, which caches this forever; a rate-limit
        blip getting silently cached as a permanent miss would wrongly
        stick a title in English forever.
        """
        empty = {"title_ru": None, "overview_ru": None, "poster_ru": None}
        if not settings.tmdb_api_key:
            return empty
        url = f"{TMDB_BASE}/{segment}/{tmdb_id}"
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.get(url, params={
                "api_key": settings.tmdb_api_key,
                "language": "ru-RU",
                "append_to_response": "images,translations",
                "include_image_language": "ru,null",
            })
            if resp.status_code == 404:
                return empty
            resp.raise_for_status()
        data = resp.json()

        ru_translation = next(
            (
                t for t in ((data.get("translations") or {}).get("translations") or [])
                if t.get("iso_639_1") == "ru"
            ),
            None,
        )
        ru_data = (ru_translation or {}).get("data") or {}
        title_ru = (ru_data.get("title") or ru_data.get("name") or "").strip() or None
        overview_ru = (ru_data.get("overview") or "").strip() or None

        posters = [
            p for p in ((data.get("images") or {}).get("posters") or [])
            if p.get("iso_639_1") == "ru" and p.get("file_path")
        ]
        posters.sort(key=lambda p: p.get("vote_average") or 0, reverse=True)
        poster_ru = self.poster_url(posters[0]["file_path"]) if posters else None

        return {"title_ru": title_ru, "overview_ru": overview_ru, "poster_ru": poster_ru}

    # How many trailers the title screen's own shelf shows — a handful is
    # plenty for a horizontal shelf; TMDB can return a dozen+ (every
    # regional trailer/teaser/clip it has), and nobody's scrolling through
    # all of them.
    _TRAILERS_SHELF_LIMIT = 8

    @classmethod
    def _extract_trailers(cls, videos_block: dict) -> List[dict]:
        """Every worthwhile YouTube video TMDB has for this title, scored
        and deduped — the title screen's own "trailers" shelf, as opposed
        to videos() above (which only ever needs the single best one for
        the Home for-you feed / header play button). Same YouTube-only
        filter and official/Trailer/Teaser scoring as videos(), just kept
        as a short list instead of collapsed to one. Each entry carries
        enough to render a shelf card without a further TMDB call: the
        YouTube id, TMDB's own name for the video (e.g. "Official
        Trailer"), and a thumbnail built straight from the YouTube id.
        """
        results = videos_block.get("results") or []
        candidates = [v for v in results if v.get("site") == "YouTube" and v.get("key")]
        if not candidates:
            return []

        def _score(v: dict) -> tuple:
            return (
                1 if v.get("official") else 0,
                1 if v.get("type") == "Trailer" else 0,
                1 if v.get("type") == "Teaser" else 0,
            )

        candidates.sort(key=_score, reverse=True)
        trailers: List[dict] = []
        seen_keys: set = set()
        for v in candidates:
            key = v["key"]
            if key in seen_keys:
                continue
            seen_keys.add(key)
            trailers.append({
                "video_id": key,
                "name": v.get("name") or "Trailer",
                "thumbnail_url": f"https://img.youtube.com/vi/{key}/hqdefault.jpg",
            })
            if len(trailers) >= cls._TRAILERS_SHELF_LIMIT:
                break
        return trailers

    async def videos(self, tmdb_id: str, segment: str) -> Optional[str]:
        """A YouTube video id for this title's best available trailer, or
        None if there isn't one. `segment` is "movie" or "tv" — same split
        as watch_providers() above, anime included under "tv".

        TMDB returns every video it has (trailers, teasers, clips,
        featurettes, in various languages/sites) with no guaranteed order,
        so we score and pick: YouTube-hosted (the only site the mobile
        client can embed) > officially tagged > "Trailer" over "Teaser"/
        other types. Returns None rather than raising on a 404 or an empty
        list — "no trailer for this title" is an ordinary case, not an
        error, and callers (GET /feed/for-you) treat it as "just show the
        poster for this one".
        """
        if not settings.tmdb_api_key:
            return None
        url = f"{TMDB_BASE}/{segment}/{tmdb_id}/videos"
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.get(url, params={"api_key": settings.tmdb_api_key})
            if resp.status_code == 404:
                return None
            resp.raise_for_status()
        trailers = self._extract_trailers(resp.json())
        return trailers[0]["video_id"] if trailers else None

    async def reviews(self, tmdb_id: str, segment: str) -> List[dict]:
        """Written, user-submitted reviews from TMDB itself — the only one
        of the rating sources this app touches (IMDB/TMDB) that actually
        exposes review *text* over a public API; IMDB has no public API
        for this at all.

        `segment` is "movie" or "tv", same split as watch_providers()/
        videos() above. Returns the raw list of TMDB review objects
        (author_details.{name,username,avatar_path,rating}, content,
        created_at, url), walking every page TMDB reports rather than just
        page 1 — a title like Interstellar has well over 20 (TMDB's
        per-page size), and stopping at page 1 was quietly capping the
        merged reviews list at whatever a single page happened to hold.
        Capped at _TMDB_REVIEWS_MAX_PAGES total pages so one very-reviewed
        title can't turn every open into dozens of live TMDB calls; this
        result is cached for REVIEWS_TTL anyway (see
        app/routers/reviews.py), so the cost is paid once per cache
        window, not per request. Empty list (not an error) on a 404 or
        when TMDB simply has none for this title — both ordinary.
        """
        if not settings.tmdb_api_key:
            return []
        url = f"{TMDB_BASE}/{segment}/{tmdb_id}/reviews"
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.get(url, params={"api_key": settings.tmdb_api_key, "page": 1})
            if resp.status_code == 404:
                return []
            resp.raise_for_status()
            data = resp.json()
            results = list(data.get("results") or [])
            total_pages = min(data.get("total_pages") or 1, _TMDB_REVIEWS_MAX_PAGES)
            if total_pages > 1:
                more = await asyncio.gather(
                    *[
                        client.get(url, params={"api_key": settings.tmdb_api_key, "page": page})
                        for page in range(2, total_pages + 1)
                    ],
                    return_exceptions=True,
                )
                for page_resp in more:
                    if isinstance(page_resp, Exception):
                        continue
                    if page_resp.status_code == 200:
                        results += page_resp.json().get("results") or []
        return results

    # -----------------------------------------------------------------
    # Teamira picks (app/routers/teamira.py) — unlike everything above,
    # these build a standalone MediaItem straight from TMDB. Franchise
    # shelves (e.g. Star Wars) come from TMDB's own /collection endpoint,
    # and keeping *all* Teamira-picks items on one source (TMDB, movie/tv
    # only) means one lookup path for both kinds instead of two.
    # -----------------------------------------------------------------

    @staticmethod
    def _media_item_from_tmdb(
        data: dict,
        media_type: str,
        ru_overlay: Optional[dict] = None,
    ) -> Optional[MediaItem]:
        """Builds a MediaItem from a raw TMDB movie/tv object — either a
        full /movie or /tv detail response, or one entry from a
        /collection's `parts` list (same core fields, just without
        runtime/full genre names, which is why genres is left empty for
        those — this app's collection cards don't render genres anyway,
        see mobile/lib/screens/collections/collections_screen.dart).

        `data` must be from an English (or unlanguaged, TMDB's default is
        en-US) request — title/description/poster_url below are always
        the English fields. `ru_overlay`, when given, is the matching
        raw object from a *second*, `language=ru-RU` request for the same
        id (e.g. one entry of a ru-RU /collection response's `parts`) —
        its title/overview/poster_path become title.ru/description.ru/
        poster_url_ru. Passing an English-only `data` with no `ru_overlay`
        is exactly how this looked before ru support existed: title.ru
        and poster_url_ru simply stay unset, and LocalizedText.display
        falls back to English client-side either way.

        Same original-vs-translated guard as title_supplement(): TMDB
        quietly returns the *original* title (not empty) when it has no
        real translation, so title/overview from `ru_overlay` are only
        kept when they actually differ from `data`'s original text.
        """
        tmdb_id = data.get("id")
        if not tmdb_id:
            return None
        title = data.get("title") or data.get("name")
        if not title:
            return None
        date_str = data.get("release_date") or data.get("first_air_date") or None
        year = int(date_str[:4]) if date_str and len(date_str) >= 4 and date_str[:4].isdigit() else None
        genre_objs = data.get("genres") or []
        genres = [g["name"] for g in genre_objs if g.get("name")]
        # Anime overrides whichever of movie/series the caller guessed off
        # the TMDB segment — a Japanese-animation *movie* (a Ghibli film,
        # say) is "anime" in this app's own media_type just as much as a
        # Japanese-animation series is, regardless of runtime format.
        # See _is_anime's own docstring for the genre+origin heuristic.
        if _is_anime(genre_objs or data.get("genre_ids"), data.get("origin_country"), data.get("original_language")):
            media_type = "anime"

        title_ru = None
        overview_ru = None
        poster_url_ru = None
        if ru_overlay:
            ru_title = ru_overlay.get("title") or ru_overlay.get("name")
            if ru_title and ru_title != title:
                title_ru = ru_title
            ru_overview = ru_overlay.get("overview") or None
            if ru_overview and ru_overview != (data.get("overview") or None):
                overview_ru = ru_overview
            if ru_overlay.get("poster_path"):
                poster_url_ru = TmdbAdapter.poster_url(ru_overlay["poster_path"])

        return MediaItem(
            id=f"tmdb-{tmdb_id}",
            media_type=media_type,
            external_ids=ExternalIds(tmdb=str(tmdb_id)),
            title=LocalizedText(en=title, ru=title_ru),
            description=LocalizedText(en=data.get("overview") or None, ru=overview_ru),
            poster_url=TmdbAdapter.poster_url(data.get("poster_path")),
            poster_url_ru=poster_url_ru,
            backdrop_url=data.get("backdrop_path"),
            year=year,
            genres=genres,
            rating=data.get("vote_average") or None,
            source="tmdb",
            runtime_minutes=data.get("runtime") or None,
            release_date=date_str,
        )

    async def item_detail(self, tmdb_id: str, media_type: str) -> Optional[MediaItem]:
        """One title, resolved straight from TMDB — used to build `manual`
        Teamira-picks shelves item by item. `media_type` is "movie" or
        "series" (mirrors this app's own MediaItem.media_type convention;
        translated to TMDB's "tv" internally). Returns None on a 404 (bad
        id) or if no key is configured.

        Two requests, English (default) then ru-RU, same as collection()
        below — a manual pick is just as much a "movie shown on the
        Teamira tab" as a franchise entry, so it gets the same bilingual
        title/poster treatment rather than being English-only forever.
        The English request is the one that can 404 (bad id entirely);
        if the ru-RU one fails for some other reason the item still
        comes back, just without a ru overlay."""
        if not settings.tmdb_api_key:
            return None
        segment = "movie" if media_type == "movie" else "tv"
        url = f"{TMDB_BASE}/{segment}/{tmdb_id}"
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.get(url, params={"api_key": settings.tmdb_api_key})
            if resp.status_code == 404:
                return None
            resp.raise_for_status()
            data_ru = None
            try:
                resp_ru = await client.get(url, params={
                    "api_key": settings.tmdb_api_key,
                    "language": "ru-RU",
                })
                if resp_ru.status_code == 200:
                    data_ru = resp_ru.json()
            except httpx.HTTPError:
                pass
        return self._media_item_from_tmdb(resp.json(), media_type, ru_overlay=data_ru)

    async def collection(self, collection_id: str) -> tuple[Optional[str], Optional[str], List[MediaItem]]:
        """All movies in a TMDB "collection" (their term for a franchise —
        e.g. id 10 is Star Wars), in the order TMDB lists them, plus the
        collection's own `overview` in both languages — a short synopsis
        of the franchise as a whole that TMDB already maintains, so the
        "about this franchise" copy on the Teamira picks tab needs no
        hand-written text (see app/routers/teamira.py). Movies only: TMDB
        collections are a movie-catalog feature, series/anime have no
        equivalent grouping there.

        Returns (overview_en, overview_ru, items).

        Two requests: English (TMDB's default, no `language` param) is
        now the BASE one — `items`' title/description/poster_url come
        from it — and a second `language=ru-RU` one only overlays
        title.ru/description.ru/poster_url_ru onto each matching item (by
        id) via _media_item_from_tmdb's ru_overlay. This used to be a
        single ru-RU-only request whose title/poster_path went straight
        into title.en/poster_url regardless — so an English-mode user
        would still see the Russian title and, whenever TMDB's ru-RU
        response resolved a different default poster than the English
        one, a Russian-lettered poster too. Same original-vs-translated
        guard as title_supplement(): TMDB quietly returns the original
        title (not empty) when it has no real translation, so
        _media_item_from_tmdb only keeps a ru value that's actually
        different from the English one.

        Returns (None, None, []) on a 404 (bad id) or if no key is
        configured — callers treat a franchise shelf with no parts as
        "not available right now", same as any other empty shelf."""
        if not settings.tmdb_api_key:
            return None, None, []
        url = f"{TMDB_BASE}/collection/{collection_id}"
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.get(url, params={"api_key": settings.tmdb_api_key})
            if resp.status_code == 404:
                return None, None, []
            resp.raise_for_status()
            data_ru = None
            try:
                resp_ru = await client.get(
                    url, params={"api_key": settings.tmdb_api_key, "language": "ru-RU"}
                )
                if resp_ru.status_code == 200:
                    data_ru = resp_ru.json()
            except httpx.HTTPError:
                pass
        data = resp.json()
        overview_en = data.get("overview") or None
        overview_ru = (data_ru or {}).get("overview") or None
        if overview_ru and overview_ru == overview_en:
            overview_ru = None  # TMDB had no real translation, just echoed English back

        parts_ru_by_id = {p.get("id"): p for p in (data_ru or {}).get("parts") or [] if p.get("id")}
        parts = data.get("parts") or []
        items = [
            self._media_item_from_tmdb(p, "movie", ru_overlay=parts_ru_by_id.get(p.get("id")))
            for p in parts
        ]
        items = [i for i in items if i is not None]
        # TMDB's `parts` array is NOT release-ordered or story-ordered —
        # it's whatever order the titles were added to TMDB's own database
        # in, which for older franchises often means prequels/sequels land
        # out of sequence (confirmed on TMDB's own forums: there's "no
        # logical sort" to it). Sorting by release_date here is what
        # actually gives the "what order to watch this in" behaviour the
        # client's franchise sheet wants — undated items (rare, usually
        # unreleased/announced entries) sort last rather than being
        # dropped.
        items.sort(key=lambda i: i.release_date or "9999-99-99")
        return overview_en, overview_ru, items

    async def search(self, query: str, language: Optional[str] = None) -> List[dict]:
        """Movie/series search — just enough per hit (id, type, title,
        year, poster) to pick the right one before calling item_detail()
        with its id. Used by the Teamira-picks admin endpoint (no
        `language`, English results) and, with `language="ru-RU"`, by
        GET /media/search's Cyrillic-query fallback (see
        app/routers/media.py::search_media) — a plain English-language
        search only matches English/original titles, so a query typed in
        Russian finds nothing there even when the title obviously exists;
        asking TMDB in ru-RU catches those by matching its
        Russian-translated titles instead. Uses /search/multi and drops
        anything that isn't a movie or tv result (person hits, mainly)."""
        if not settings.tmdb_api_key or not query.strip():
            return []
        url = f"{TMDB_BASE}/search/multi"
        params = {"api_key": settings.tmdb_api_key, "query": query}
        if language:
            params["language"] = language
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.get(url, params=params)
            resp.raise_for_status()
        results = []
        for r in resp.json().get("results") or []:
            media_type = {"movie": "movie", "tv": "series"}.get(r.get("media_type"))
            if not media_type:
                continue
            title = r.get("title") or r.get("name")
            if not title:
                continue
            date_str = r.get("release_date") or r.get("first_air_date") or ""
            year = int(date_str[:4]) if len(date_str) >= 4 and date_str[:4].isdigit() else None
            results.append({
                "tmdb_id": str(r["id"]),
                "media_type": media_type,
                "title": title,
                "year": year,
                "poster_url": self.poster_url(r.get("poster_path")),
            })
        return results

    # -----------------------------------------------------------------
    # Primary movie/series/anime catalog (app/routers/media.py). TMDB is
    # the catalog: search, title detail (+ratings +similar), and
    # episodes. Anime keeps its Shikimori Russian-text overlay on top of
    # this (see app/routers/media.py::_apply_shikimori_ru) since TMDB's own
    # Russian translations for anime specifically tend to be thin or
    # missing — but the *matching*, the search, and the English text are
    # all TMDB.
    # -----------------------------------------------------------------

    def _media_item_from_search_hit(
        self, raw: dict, media_kind: str, lang_field: str
    ) -> Optional[tuple]:
        """Builds a MediaItem from one thin /search/multi, /discover, or
        /similar result object — as opposed to _media_item_from_tmdb above,
        which builds from a *full* /movie or /tv detail response. The two
        shapes differ in exactly the ways that matter here: this one only
        has `genre_ids` (bare ints, looked up in _MOVIE_GENRES/_TV_GENRES)
        rather than `genres: [{id,name}]`, and no `credits`/`videos`/
        `runtime` at all — a search hit is a card, not a detail sheet.

        `media_kind` is "movie" or "tv" (TMDB's own segment, not yet this
        app's movie/series/anime media_type — that's resolved below via
        _is_anime same as everywhere else). `lang_field` is "en" or "ru":
        which LocalizedText slot the fetched title/overview goes into,
        since the *entire* request this hit came from was already made in
        one language (see catalog_search) — there's no second per-hit call
        to also get the other language for every single search result,
        that's what the anime-only Shikimori pass and the per-title
        /media/detail call are for.

        Returns (item, original_title) — `original_title` is TMDB's
        `original_title`/`original_name` (the romaji title, for anime),
        needed by the caller to run the Shikimori match against the right
        text (see _apply_shikimori_ru's docstring in app/routers/media.py
        for why it can't just read item.title.en back out). None if the
        hit has no usable title.
        """
        title = raw.get("title") or raw.get("name")
        if not title:
            return None
        tmdb_id = raw.get("id")
        if not tmdb_id:
            return None
        original_title = raw.get("original_title") or raw.get("original_name")
        overview = raw.get("overview") or None
        date_str = raw.get("release_date") or raw.get("first_air_date") or None
        year = int(date_str[:4]) if date_str and len(date_str) >= 4 and date_str[:4].isdigit() else None

        genre_ids = raw.get("genre_ids") or []
        genre_table = _MOVIE_GENRES if media_kind == "movie" else _TV_GENRES
        genres = [genre_table[g] for g in genre_ids if g in genre_table]

        media_type = "movie" if media_kind == "movie" else "series"
        if _is_anime(genre_ids, raw.get("origin_country"), raw.get("original_language")):
            media_type = "anime"

        title_lt = LocalizedText(en=title) if lang_field == "en" else LocalizedText(ru=title)
        desc_lt = LocalizedText(en=overview) if lang_field == "en" else LocalizedText(ru=overview)

        item = MediaItem(
            id=f"tmdb-{tmdb_id}",
            media_type=media_type,
            external_ids=ExternalIds(tmdb=str(tmdb_id)),
            title=title_lt,
            description=desc_lt,
            poster_url=self.poster_url(raw.get("poster_path")),
            backdrop_url=raw.get("backdrop_path"),
            year=year,
            genres=genres,
            rating=raw.get("vote_average") or None,
            source="tmdb",
            release_date=date_str,
        )
        return item, original_title

    async def catalog_search(
        self, query: str, language: Optional[str] = None
    ) -> tuple:
        """The primary GET /media/search implementation — see
        app/routers/media.py::search_media. Straight /search/multi against
        TMDB directly, since TMDB *is* the catalog — `language="ru-RU"`
        for a Russian-typed query returns Russian titles natively, no
        fallback/resolve dance needed at all.

        Returns (items, original_titles) — `original_titles` maps an
        anime item's id to its romaji/original title (see
        _media_item_from_search_hit), for the caller to run the Shikimori
        overlay pass against; empty dict when there's nothing anime in
        the results.
        """
        if not settings.tmdb_api_key or not query.strip():
            return [], {}
        url = f"{TMDB_BASE}/search/multi"
        params = {"api_key": settings.tmdb_api_key, "query": query, "include_adult": "false"}
        if language:
            params["language"] = language
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.get(url, params=params)
            resp.raise_for_status()
        lang_field = "ru" if language and language.lower().startswith("ru") else "en"

        items: List[MediaItem] = []
        original_titles: dict = {}
        for r in resp.json().get("results") or []:
            media_kind = r.get("media_type")
            if media_kind not in ("movie", "tv"):
                continue  # drops person hits, the only other thing /search/multi returns
            built = self._media_item_from_search_hit(r, media_kind, lang_field)
            if built is None:
                continue
            item, original_title = built
            items.append(item)
            if item.media_type == "anime":
                original_titles[item.id] = original_title
        return items, original_titles

    async def full_detail(self, tmdb_id: str, media_type: str) -> Optional[tuple]:
        """The primary GET /media/detail implementation — detail+ratings+
        similar entirely from TMDB (see app/routers/media.py).
        `media_type` is this app's own "movie"/"series"/"anime" (from the
        item the client already has, e.g. off a search result); resolved
        to TMDB's "movie"/"tv" segment, then re-checked against the
        Animation+Japanese heuristic on the *full* detail response (which
        has real genre names + origin_country, unlike a thin search hit)
        in case the caller's guess needs correcting.

        One English call carries almost everything at once via
        `append_to_response`: cast/director (credits), the trailers shelf
        (videos), a similar-titles shelf (similar), the imdb id
        (external_ids), and an age certification (release_dates for
        movies, content_ratings for tv — different resources on TMDB's
        side, hence the segment-conditional append). A second, best-effort
        ru-RU call (same as the old title_supplement) fills title.ru/
        description.ru/poster_url_ru/character.ru for movies and series;
        for anime this gets overridden again right after by
        _apply_shikimori_ru in app/routers/media.py, same layering as
        before TMDB became primary.

        Returns (MediaDetailOut, original_title, ru_fetch_ok) —
        original_title is TMDB's original_title/original_name, needed by
        the caller for the same Shikimori-matching reason as
        catalog_search's return value. None on a 404 (bad id) or no key
        configured.

        `ru_fetch_ok` tells the caller (app/routers/media.py::media_detail)
        whether the ru-RU call actually succeeded (200) or was a genuine
        "TMDB has nothing here" (404) — as opposed to a transient failure
        (429/5xx/network error/timeout). The caller uses this to decide
        whether the result is safe to cache forever: this detail result is
        cached with no TTL (see app/cache.py::set_static_title), so if a
        429 from a momentary burst (e.g. the poster_ru collections
        backfill in app/routers/feed.py running concurrently) got silently
        folded into "no Russian data" the same way a real miss would, that
        title would be stuck showing English forever — never retried.
        Only a real 200 or 404 counts as "ru_fetch_ok"; anything else
        leaves data_ru empty for *this* response (still degrades
        gracefully, same as before) but tells the caller not to persist it
        as the final answer.
        """
        if not settings.tmdb_api_key:
            return None
        # "anime" (unlike this app's other two media_type values) doesn't
        # map onto a single TMDB segment — an anime *film* lives under
        # /movie/{id} on TMDB's side same as any other movie, an anime
        # *series* under /tv/{id}, and the search hit that got us here
        # only ever recorded this app's own movie/series/anime label, not
        # which of those two segments the title actually came from (see
        # _media_item_from_search_hit — media_kind is collapsed away).
        # "movie"/"series" always resolve correctly on the first guess
        # since those two never lose that distinction, so the retry below
        # is only ever exercised for anime.
        segment = "movie" if media_type == "movie" else "tv"
        alternate_segment = "tv" if segment == "movie" else "movie"
        append = "credits,images,videos,similar,external_ids"

        async def _fetch_en(seg: str) -> Optional[httpx.Response]:
            seg_append = append + (",release_dates" if seg == "movie" else ",content_ratings")
            return await client.get(f"{TMDB_BASE}/{seg}/{tmdb_id}", params={
                "api_key": settings.tmdb_api_key,
                "append_to_response": seg_append,
            })

        async with httpx.AsyncClient(timeout=10.0) as client:
            resp_en = await _fetch_en(segment)
            if resp_en.status_code == 404 and media_type == "anime":
                # Wrong guess for an anime film/series — same id, the
                # other TMDB segment, one extra round-trip only on this
                # cold path.
                segment = alternate_segment
                resp_en = await _fetch_en(segment)
            if resp_en.status_code == 404:
                return None
            resp_en.raise_for_status()
            data_en = resp_en.json()
            url = f"{TMDB_BASE}/{segment}/{tmdb_id}"
            data_ru: dict = {}
            ru_fetch_ok = True
            try:
                resp_ru = await client.get(url, params={
                    "api_key": settings.tmdb_api_key,
                    "language": "ru-RU",
                    "append_to_response": "credits,images",
                })
                if resp_ru.status_code == 200:
                    data_ru = resp_ru.json()
                elif resp_ru.status_code != 404:
                    # 429/5xx/anything else: not a real "no ru data" —
                    # don't let the caller cache this as final.
                    ru_fetch_ok = False
            except httpx.HTTPError:
                ru_fetch_ok = False

        genre_objs = data_en.get("genres") or []
        resolved_media_type = media_type
        if _is_anime(genre_objs, data_en.get("origin_country"), data_en.get("original_language")):
            resolved_media_type = "anime"

        original_title = data_en.get("original_title") or data_en.get("original_name")
        name_en = data_en.get("title") or data_en.get("name")
        title_en = name_en or original_title
        overview_en = data_en.get("overview") or None

        # Same original-vs-translated guard as _media_item_from_tmdb/
        # collection() above — compared against title_en (the genuine
        # English text from this same request), NOT original_title.
        # TMDB's per-title endpoint quietly falls back to *English* (its
        # own account default, not the title's original-language text)
        # whenever it has no real Russian translation — a French,
        # Japanese, Korean, ... title with no ru-RU translation still
        # comes back with an English string in `title`, which happens to
        # differ from `original_title` just as much as a genuine
        # translation would. Comparing against original_title only ever
        # catches the fallback for titles whose original_language is
        # already English; everything else slipped straight through this
        # guard and got cached as title.ru forever with plain English
        # text sitting in it (displayed as if it were genuinely Russian
        # once the ru toggle is on — the exact "poster/description are
        # Russian, title stays English" reports). overview_ru previously
        # had no guard against this at all, not even the broken one —
        # same fallback-to-English risk, fixed the same way collection()
        # already guards its own overview_ru.
        translated_title = data_ru.get("title") or data_ru.get("name")
        title_ru = translated_title if translated_title and translated_title != title_en else None
        overview_ru = data_ru.get("overview") or None
        if overview_ru and overview_ru == overview_en:
            overview_ru = None  # TMDB had no real translation, just echoed English back

        credits_en = (data_en.get("credits") or {}).get("cast") or []
        credits_ru = (data_ru.get("credits") or {}).get("cast") or []
        character_ru_by_person_id = {
            member.get("id"): member.get("character")
            for member in credits_ru
            if member.get("id") is not None and member.get("character")
        }
        cast = [
            CastMember(
                person_id=str(member["id"]) if member.get("id") is not None else None,
                name=member["name"],
                character=(
                    LocalizedText(
                        en=member.get("character") or None,
                        ru=character_ru_by_person_id.get(member.get("id")),
                    )
                    if member.get("character") or character_ru_by_person_id.get(member.get("id"))
                    else None
                ),
                photo_url=self.profile_url(member.get("profile_path")),
            )
            for member in credits_en
            if member.get("name")
        ]
        director_crew = [
            member
            for member in (data_en.get("credits") or {}).get("crew") or []
            if member.get("job") == "Director" and member.get("name")
        ]
        directors = [member["name"] for member in director_crew]
        # Only the first co-director's id — see MediaItem.director_id's
        # own docstring for why one id is enough here.
        director_id = str(director_crew[0]["id"]) if director_crew and director_crew[0].get("id") is not None else None

        ru_posters = [
            p for p in (data_ru.get("images") or {}).get("posters") or []
            if p.get("iso_639_1") == "ru" and p.get("file_path")
        ]
        ru_posters.sort(key=lambda p: p.get("vote_average") or 0, reverse=True)
        poster_ru = self.poster_url(ru_posters[0]["file_path"]) if ru_posters else None

        trailers = [TitleTrailer(**t) for t in self._extract_trailers(data_en.get("videos") or {})]

        date_str = data_en.get("release_date") or data_en.get("first_air_date") or None
        year = int(date_str[:4]) if date_str and len(date_str) >= 4 and date_str[:4].isdigit() else None

        if segment == "movie":
            runtime = data_en.get("runtime") or None
        else:
            run_times = data_en.get("episode_run_time") or []
            runtime = run_times[0] if run_times else None

        # Age certification lives on a different appended resource per
        # segment (TMDB has no single unified field) — both shaped as
        # "one entry per country, pick ours". US is used as the
        # reference market the same way most apps in this space do; a
        # title TMDB simply hasn't rated in the US yet just has none,
        # same "degrade to nothing extra" as everywhere else here.
        certification = None
        if segment == "movie":
            for entry in (data_en.get("release_dates") or {}).get("results") or []:
                if entry.get("iso_3166_1") != "US":
                    continue
                cert = next(
                    (d.get("certification") for d in entry.get("release_dates") or [] if d.get("certification")),
                    None,
                )
                if cert:
                    certification = cert
                break
        else:
            for entry in (data_en.get("content_ratings") or {}).get("results") or []:
                if entry.get("iso_3166_1") == "US" and entry.get("rating"):
                    certification = entry["rating"]
                    break

        status = data_en.get("status")
        status = status.lower() if status else None
        tagline = data_en.get("tagline") or None
        country = None
        if data_en.get("origin_country"):
            country = data_en["origin_country"][0]
        elif data_en.get("production_countries"):
            country = data_en["production_countries"][0].get("iso_3166_1")

        imdb_id = (data_en.get("external_ids") or {}).get("imdb_id") or None

        item = MediaItem(
            id=f"tmdb-{tmdb_id}",
            media_type=resolved_media_type,
            external_ids=ExternalIds(tmdb=str(tmdb_id), imdb=imdb_id),
            title=LocalizedText(en=title_en, ru=title_ru),
            description=LocalizedText(en=overview_en, ru=overview_ru),
            poster_url=self.poster_url(data_en.get("poster_path")),
            backdrop_url=data_en.get("backdrop_path"),
            poster_url_ru=poster_ru,
            year=year,
            genres=[g["name"] for g in genre_objs if g.get("name")],
            rating=data_en.get("vote_average") or None,
            source="tmdb",
            tagline=tagline,
            runtime_minutes=runtime,
            certification=certification,
            release_date=date_str,
            status=status,
            country=country,
            cast=cast,
            director=", ".join(directors) if directors else None,
            director_id=director_id,
        )

        ratings = RatingsOut(
            tmdb_rating=data_en.get("vote_average") or None,
            tmdb_votes=data_en.get("vote_count") or None,
        )

        similar_items: List[MediaItem] = []
        for r in ((data_en.get("similar") or {}).get("results") or [])[:12]:
            built = self._media_item_from_search_hit(r, segment, "en")
            if built:
                similar_items.append(built[0])

        result = MediaDetailOut(item=item, ratings=ratings, similar=similar_items, trailers=trailers)
        return result, original_title, ru_fetch_ok

    async def tv_episodes(self, tmdb_id: str) -> List[SeasonOut]:
        """A flat "season + episode + title" grid, sourced from TMDB's
        /tv/{id} (for the list
        of season numbers this show actually has) plus one
        /tv/{id}/season/{n} call per season. Movies never call this
        (there's nothing to season/episode-grid); a movie's tmdb_id
        simply 404s here since movie and tv ids are separate TMDB
        namespaces.

        Season 0 (specials) is dropped from the season-number list before
        any per-season calls are made —
        specials aren't part of
        "how far through the show am I", and mixing them into the season
        grid would make the episode counts per season lie. A season TMDB
        lists but that comes back with zero usable episodes (announced,
        not aired yet) is dropped from the result rather than shown as an
        empty shelf.
        """
        if not settings.tmdb_api_key:
            return []
        url = f"{TMDB_BASE}/tv/{tmdb_id}"
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.get(url, params={"api_key": settings.tmdb_api_key})
            if resp.status_code == 404:
                return []
            resp.raise_for_status()
            data = resp.json()
            season_summaries = data.get("seasons") or []
            season_numbers = [
                s["season_number"] for s in season_summaries
                if s.get("season_number") not in (None, 0)
            ]
            poster_by_season = {
                s["season_number"]: self.poster_url(s.get("poster_path"))
                for s in season_summaries if s.get("season_number") is not None
            }

            async def _season(n: int) -> Optional[SeasonOut]:
                r = await client.get(
                    f"{TMDB_BASE}/tv/{tmdb_id}/season/{n}",
                    params={"api_key": settings.tmdb_api_key},
                )
                if r.status_code != 200:
                    return None
                sd = r.json()
                eps = [
                    EpisodeOut(season=n, episode=e["episode_number"], title=e.get("name") or None)
                    for e in sd.get("episodes") or []
                    if e.get("episode_number") is not None
                ]
                if not eps:
                    return None
                return SeasonOut(season=n, episodes=eps, poster_url=poster_by_season.get(n))

            results = await asyncio.gather(*[_season(n) for n in season_numbers], return_exceptions=True)
        seasons = [r for r in results if isinstance(r, SeasonOut)]
        seasons.sort(key=lambda s: s.season)
        return seasons

    async def resolve_external_id(
        self, *, tmdb_id: Optional[str], imdb_id: Optional[str], media_type: str,
    ) -> Optional[MediaItem]:
        """Resolves a scrobble webhook's tmdb/imdb id into a MediaItem (see
        app/routers/integrations.py::_ingest). Reuses full_detail() rather
        than a separate lighter fetch — a scrobble event isn't a hot path,
        so the extra credits/videos/similar it also fetches costs nothing
        that matters, and reusing it means this can't drift from what
        GET /media/detail considers "the same title".

        If only `imdb_id` is known (some Plex/Jellyfin setups only carry
        that), TMDB's own /find/{imdb_id} endpoint resolves it to a tmdb
        id first.
        """
        resolved_tmdb_id = tmdb_id
        if not resolved_tmdb_id and imdb_id:
            resolved_tmdb_id = await self._find_tmdb_id_by_imdb(imdb_id, media_type)
        if not resolved_tmdb_id:
            return None
        built = await self.full_detail(resolved_tmdb_id, media_type)
        if built is None:
            return None
        return built[0].item

    async def _find_tmdb_id_by_imdb(self, imdb_id: str, media_type: str) -> Optional[str]:
        if not settings.tmdb_api_key:
            return None
        url = f"{TMDB_BASE}/find/{imdb_id}"
        params = {"api_key": settings.tmdb_api_key, "external_source": "imdb_id"}
        async with httpx.AsyncClient(timeout=8.0) as client:
            try:
                resp = await client.get(url, params=params)
                resp.raise_for_status()
            except httpx.HTTPError as exc:
                logger.warning("TMDB /find lookup failed [%s] -> %s", imdb_id, exc)
                return None
        data = resp.json()
        preferred_key = "movie_results" if media_type == "movie" else "tv_results"
        results = data.get(preferred_key) or []
        if not results:
            # The webhook's own media_type guess (movie vs episode) can be
            # wrong for an edge case TMDB's /find still resolves fine —
            # fall back to whichever bucket actually has something rather
            # than reporting no match at all.
            for other_key in ("movie_results", "tv_results"):
                if data.get(other_key):
                    results = data[other_key]
                    break
        if not results:
            return None
        return str(results[0]["id"])

    # -----------------------------------------------------------------
    # Feed/Collections (app/routers/feed.py) — discover/movies-feed/
    # similar/named-collections shelves. Every shelf here is a
    # real TMDB list endpoint (popular/top_rated/trending/discover), never
    # synthetic data.
    # -----------------------------------------------------------------

    async def _fetch_list(
        self, path: str, media_kind: str, params: Optional[dict] = None, language: Optional[str] = None,
    ) -> List[MediaItem]:
        """Shared GET for any TMDB list-shaped endpoint (/movie/popular,
        /tv/top_rated, /trending/*, /discover/movie, /discover/tv, ...) —
        every one of these returns the same `{results: [...]}` envelope
        with the same thin per-item shape _media_item_from_search_hit
        already knows how to build a MediaItem from. `media_kind` is
        "movie" or "tv" — the caller already knows which, since it picked
        the path. Empty list (not an error) on any failure or no key
        configured — every shelf in this app already treats an empty
        shelf as "not available right now", same as everywhere else.
        """
        if not settings.tmdb_api_key:
            return []
        request_params = {"api_key": settings.tmdb_api_key}
        if language:
            request_params["language"] = language
        if params:
            request_params.update(params)
        url = f"{TMDB_BASE}/{path}"
        async with httpx.AsyncClient(timeout=8.0) as client:
            try:
                resp = await client.get(url, params=request_params)
                resp.raise_for_status()
            except httpx.HTTPError as exc:
                logger.warning("TMDB list fetch failed [%s] %s -> %s", path, params, exc)
                return []
        items: List[MediaItem] = []
        lang_field = "ru" if language == "ru-RU" else "en"
        for r in resp.json().get("results") or []:
            built = self._media_item_from_search_hit(r, media_kind, lang_field)
            if built:
                items.append(built[0])
        return items

    # Caps how many discover_mixed() TMDB calls are ever in flight at
    # once. The source list below is now ~85+ requests — fine in total
    # since discover_mixed() only ever runs once per DYNAMIC_TTL window
    # (see cache.cached_dynamic's per-key lock in app/cache.py, and
    # get_feed's "feed:discover" cache key — this is one shared fetch for
    # every user, not per-user), but firing all ~85 at TMDB in the same
    # instant is the kind of burst that risks a 429/temporary key
    # throttle. A semaphore spreads the same total call count over a few
    # seconds instead of one instant, at no extra cost since the whole
    # batch is still one asyncio.gather.
    _DISCOVER_MIXED_CONCURRENCY = 8

    async def _throttled_fetch_list(
        self, semaphore: asyncio.Semaphore, path: str, media_kind: str, params: Optional[dict] = None,
    ) -> List[MediaItem]:
        async with semaphore:
            return await self._fetch_list(path, media_kind, params)

    async def discover_mixed(self) -> List[MediaItem]:
        """GET /feed's underlying pool — also what the mobile "can't
        decide?" flow (DecideFiltersScreen) narrows down by type -> genre
        -> decade.

        Used to be a single call to /trending/all/day — ~20 titles total.
        Then widened to a handful of lists, a few pages each — better,
        but a specific genre within a specific decade could still eat a
        ~250-item pool down to a handful, since popular/top_rated/
        now_playing/upcoming all skew toward recent, currently-relevant
        titles rather than spreading evenly across decades.

        Pulls deep per source across popular/top_rated/now_playing/
        upcoming for movies and popular/top_rated/on_the_air/
        airing_today for tv, a vote-count-sorted discover/{movie,tv} pass
        on each (skews toward well-known catalog titles rather than only
        what's currently trending), a dedicated JP-animation discover
        pass for anime, AND a decade-by-decade discover/{movie,tv} pass
        (see _decade_pages below) spanning the 1960s through today —
        that last part is what actually keeps an older-decade + specific-
        genre combo from starving, since none of the chart-style sources
        above reliably reach back that far on their own. Still the same
        "merge several real feeds, dedupe by id, drop whichever call
        fails" shape as movies_pool() — just a lot more of them.

        This is a big set of TMDB calls (~85+) — fine given the 24h
        shared cache on this endpoint (one fetch pays for every user
        until the cache expires, not one per user), and
        _DISCOVER_MIXED_CONCURRENCY caps how many are in flight at once
        so the whole batch doesn't land on TMDB in a single burst."""
        if not settings.tmdb_api_key:
            return []

        semaphore = asyncio.Semaphore(self._DISCOVER_MIXED_CONCURRENCY)

        def _pages(path: str, media_kind: str, count: int, params: Optional[dict] = None):
            return [
                self._throttled_fetch_list(semaphore, path, media_kind, {**(params or {}), "page": page})
                for page in range(1, count + 1)
            ]

        # One discover pass per decade (1960s..2020s), sorted by
        # vote-count so each decade surfaces its actually-known titles
        # rather than an arbitrary slice — this is what backfills older
        # decades for the "can't decide?" flow's decade filter, since
        # popular/top_rated/now_playing above are all recency-biased.
        # 2 pages/decade/media_kind is enough headroom for a decade x
        # genre combo to still have real options after DecideFiltersScreen
        # filters down to it.
        def _decade_pages(media_kind: str, count_per_decade: int = 2):
            path = "discover/movie" if media_kind == "movie" else "discover/tv"
            date_field = "primary_release_date" if media_kind == "movie" else "first_air_date"
            pages: list = []
            for decade_start in range(1960, 2030, 10):
                decade_end = decade_start + 9
                params = {
                    "sort_by": "vote_count.desc",
                    f"{date_field}.gte": f"{decade_start}-01-01",
                    f"{date_field}.lte": f"{decade_end}-12-31",
                }
                pages.extend(_pages(path, media_kind, count_per_decade, params))
            return pages

        sources = [
            *_pages("movie/popular", "movie", 8),
            *_pages("movie/top_rated", "movie", 8),
            *_pages("movie/now_playing", "movie", 4),
            *_pages("movie/upcoming", "movie", 3),
            *_pages("discover/movie", "movie", 5, {"sort_by": "vote_count.desc"}),
            *_decade_pages("movie"),
            *_pages("tv/popular", "tv", 6),
            *_pages("tv/top_rated", "tv", 6),
            *_pages("tv/on_the_air", "tv", 2),
            *_pages("tv/airing_today", "tv", 2),
            *_pages("discover/tv", "tv", 4, {"sort_by": "vote_count.desc"}),
            *_decade_pages("tv"),
            self._trending_all_day(),
            # Anime used to only show up as whatever fell out of the
            # general tv/* lists above via the origin+genre heuristic in
            # _is_anime — a real but incidental amount. These go after it
            # directly (Animation genre + JP origin, same filter
            # similar_by_genre's anime_only already uses elsewhere),
            # covering both TV anime and anime films.
            *_pages("discover/tv", "tv", 5, {
                "with_genres": _ANIME_GENRE_ID, "with_origin_country": "JP",
                "sort_by": "popularity.desc",
            }),
            *_pages("discover/movie", "movie", 3, {
                "with_genres": _ANIME_GENRE_ID, "with_origin_country": "JP",
                "sort_by": "popularity.desc",
            }),
        ]
        results = await asyncio.gather(*sources, return_exceptions=True)
        seen: set = set()
        pool: List[MediaItem] = []
        for result in results:
            if isinstance(result, Exception):
                continue
            for item in result:
                if item.id in seen:
                    continue
                seen.add(item.id)
                pool.append(item)
        return pool

    async def _trending_all_day(self) -> List[MediaItem]:
        """One extra source folded into discover_mixed()'s merge —
        /trending/all/day mixes movies and tv in one call (each hit
        tagged with its own media_type) and, empirically, surfaces anime
        more reliably near the top than tv/popular or tv/top_rated do on
        their own. Kept as a single page; the popular/top_rated/
        now_playing lists above are already the volume source."""
        params = {"api_key": settings.tmdb_api_key}
        url = f"{TMDB_BASE}/trending/all/day"
        async with httpx.AsyncClient(timeout=8.0) as client:
            try:
                resp = await client.get(url, params=params)
                resp.raise_for_status()
            except httpx.HTTPError as exc:
                logger.warning("TMDB trending/all fetch failed -> %s", exc)
                return []
        items: List[MediaItem] = []
        for r in resp.json().get("results") or []:
            media_kind = r.get("media_type")
            if media_kind not in ("movie", "tv"):
                continue  # drops person hits, same as catalog_search
            built = self._media_item_from_search_hit(r, media_kind, "en")
            if built:
                items.append(built[0])
        return items

    async def movies_pool(self) -> List[MediaItem]:
        """GET /feed/movies' underlying pool — merges popular + top-rated +
        now-playing movies (three real TMDB sources, "merge several real
        feeds rather than trust one"), deduped by tmdb id, shuffled by the
        caller."""
        results = await asyncio.gather(
            self._fetch_list("movie/popular", "movie"),
            self._fetch_list("movie/top_rated", "movie"),
            self._fetch_list("movie/now_playing", "movie"),
            return_exceptions=True,
        )
        seen: set = set()
        pool: List[MediaItem] = []
        for result in results:
            if isinstance(result, Exception):
                continue
            for item in result:
                if item.id in seen:
                    continue
                seen.add(item.id)
                pool.append(item)
        return pool

    async def similar_by_genre(
        self, media_kind: str, genres: List[str], *, anime_only: bool = False, exclude_id: Optional[str] = None,
        language: Optional[str] = None, match_all: bool = True,
    ) -> List[MediaItem]:
        """GET /feed/for-you's per-seed lookup.
        `genres` are this app's own genre *names* (off a MediaItem the
        caller already has, e.g. a seed title from the user's diary) —
        translated to TMDB genre ids via _MOVIE_GENRE_IDS/_TV_GENRE_IDS
        and queried against /discover/{movie,tv} with
        `with_genres=id1,id2,...` (TMDB ANDs a comma-separated list, which
        for 2-3 genres off a real title is exactly the "more of the same
        combination" behavior a seed-based recommendation wants — a title
        tagged only Action would otherwise dominate an Action+Romance
        seed's results).

        `match_all=False` switches that join to OR (pipe-separated)
        instead — needed when `genres` came off a single resolved "like
        X" reference (see app/routers/ai.py): requiring EVERY one of a
        specific title's genre tags at once is too strict there. TMDB's
        own tagging is inconsistent enough that films widely considered
        close to a given movie often miss one of its tags — e.g.
        Interstellar carries Adventure+Drama+Science Fiction, but Arrival
        and Gravity (both arguably closer to it than most sci-fi
        blockbusters) are tagged Drama+Science Fiction with no Adventure.
        An AND-of-3 discover call excludes them from the candidate pool
        entirely, before Ask Teamira's own genre/semantic scoring ever
        gets a chance to rank them — no amount of downstream reranking
        recovers a title that was never fetched. OR-of-genres widens
        recall considerably; that's fine here because the caller's own
        weighted scoring (partial genre overlap + semantic closeness),
        not this discover call, is what's meant to do the actual ranking.
        The default stays AND — /feed/for-you's multi-genre-seed use case
        above is a different shape of ask, where AND is still correct.

        `anime_only`, when set, additionally restricts to
        with_origin_country=JP so an anime seed's "more like this" pool
        doesn't fill up with non-Japanese animated movies/shows that
        happen to share a genre tag.
        """
        table = _MOVIE_GENRE_IDS if media_kind == "movie" else _TV_GENRE_IDS
        genre_ids = [str(table[g]) for g in genres if g in table]
        if not genre_ids:
            return []
        joiner = "," if match_all else "|"
        base_params = {
            "with_genres": joiner.join(genre_ids),
            "sort_by": "popularity.desc",
            "vote_count.gte": 20,
        }
        if anime_only:
            base_params["with_origin_country"] = "JP"
        # Two pages rather than one: a single TMDB page is only 20 results,
        # and for a narrow slice (anime especially — JP origin + one genre
        # + vote_count>=20) that's not much of a pool to begin with, before
        # _diversify's per-franchise cap even gets a say. See _diversify's
        # docstring for the shelf-starving failure mode this was feeding.
        pages = await asyncio.gather(
            self._fetch_list(f"discover/{media_kind}", media_kind, {**base_params, "page": 1}, language),
            self._fetch_list(f"discover/{media_kind}", media_kind, {**base_params, "page": 2}, language),
            return_exceptions=True,
        )
        seen_ids: set = set()
        items: List[MediaItem] = []
        for page in pages:
            if isinstance(page, Exception):
                continue
            for item in page:
                if item.id in seen_ids:
                    continue
                seen_ids.add(item.id)
                items.append(item)
        if exclude_id:
            items = [i for i in items if i.id != exclude_id]
        return items

    async def similar_titles(
        self, tmdb_id: str, media_type: str, language: Optional[str] = None
    ) -> List[MediaItem]:
        """Direct GET /{movie,tv}/{id}/similar — TMDB's own "people who
        liked this also liked" data, not a genre filter. Used by Ask
        Teamira's "like X" matching (app/routers/ai.py) as a much sharper
        signal than similar_by_genre's plain genre-AND for a specific
        reference title; a lighter call than full_detail() above, which
        also fetches credits/images/videos/ru-RU that this doesn't need.
        """
        if not settings.tmdb_api_key:
            return []
        segment = "movie" if media_type == "movie" else "tv"
        url = f"{TMDB_BASE}/{segment}/{tmdb_id}/similar"
        params = {"api_key": settings.tmdb_api_key}
        if language:
            params["language"] = language
        lang_field = "ru" if language and language.lower().startswith("ru") else "en"
        async with httpx.AsyncClient(timeout=8.0) as client:
            resp = await client.get(url, params=params)
            if resp.status_code == 404:
                return []
            resp.raise_for_status()
        items: List[MediaItem] = []
        for r in resp.json().get("results") or []:
            built = self._media_item_from_search_hit(r, segment, lang_field)
            if built:
                items.append(built[0])
        return items

    # (path, media_kind, params, display_label_ru, display_label_en) for the
    # plain top/popular/trending shelves — everything that isn't a
    # genre-scoped shelf below. `title` on the resulting Collection is
    # always the Russian label (see schemas.Collection.title /
    # mobile/lib/models/collection.dart::displayTitle — same "title is
    # always Russian, title_en is the fallback" contract curated_franchises.py
    # already follows for the Teamira shelves); English is carried
    # alongside as title_en rather than hardcoded as the primary string.
    def _core_shelves(self) -> list:
        year = date.today().year
        return [
            ("movie/top_rated", "movie", {}, "Лучшие фильмы", "Top Movies"),
            ("discover/movie", "movie",
             {"primary_release_year": year, "sort_by": "vote_average.desc", "vote_count.gte": 50},
             "Лучшие фильмы этого года", "Top Movies This Year"),
            ("tv/top_rated", "tv", {}, "Лучшие сериалы", "Top Series"),
            ("discover/tv", "tv",
             {"first_air_date_year": year, "sort_by": "vote_average.desc", "vote_count.gte": 30},
             "Лучшие сериалы этого года", "Top Series This Year"),
            ("discover/tv", "tv",
             {"with_genres": _ANIME_GENRE_ID, "with_origin_country": "JP",
              "sort_by": "vote_average.desc", "vote_count.gte": 30},
             "Лучшее аниме", "Top Anime"),
            ("discover/tv", "tv",
             {"with_genres": _ANIME_GENRE_ID, "with_origin_country": "JP",
              "first_air_date_year": year, "sort_by": "vote_average.desc", "vote_count.gte": 10},
             "Лучшее аниме этого года", "Top Anime This Year"),
            ("tv/on_the_air", "tv", {}, "Премьеры сериалов", "New Series Premieres"),
            ("discover/tv", "tv",
             {"first_air_date.gte": str(year) + "-01-01", "sort_by": "first_air_date.desc"},
             "Скоро: сериалы", "Coming Soon: Series"),
            ("discover/tv", "tv",
             {"with_genres": _ANIME_GENRE_ID, "with_origin_country": "JP", "sort_by": "first_air_date.desc"},
             "Премьеры аниме", "New Anime Premieres"),
            ("discover/tv", "tv",
             {"with_genres": _ANIME_GENRE_ID, "with_origin_country": "JP",
              "sort_by": "popularity.desc", "vote_count.gte": 5},
             "Скоро: аниме", "Coming Soon: Anime"),
            ("trending/movie/week", "movie", {}, "Популярные фильмы недели", "Popular Movies This Week"),
            ("trending/tv/week", "tv", {}, "Популярные сериалы недели", "Popular Series This Week"),
            ("discover/tv", "tv",
             {"with_genres": _ANIME_GENRE_ID, "with_origin_country": "JP", "sort_by": "popularity.desc"},
             "Популярное аниме недели", "Popular Anime This Week"),
            ("movie/now_playing", "movie", {}, "Новинки на DVD/цифре", "DVD/Digital Releases"),
        ]

    # Genre-scoped shelves:
    # (genre_name, display_label_ru, display_label_en, media_kind, anime_only)
    _GENRE_SHELVES = (
        ("Action", "Боевики", "Action", "movie", False),
        ("Comedy", "Комедии", "Comedy", "movie", False),
        ("Horror", "Ужасы", "Horror", "movie", False),
        ("Thriller", "Триллеры", "Thriller", "movie", False),
        ("Romance", "Мелодрамы", "Romance", "movie", False),
        ("Fantasy", "Фэнтези", "Fantasy", "movie", False),
        ("Animation", "Анимационные фильмы", "Animated Movies", "movie", False),
        ("Documentary", "Документальные фильмы", "Documentaries", "movie", False),
        ("Drama", "Драматические сериалы", "Drama Series", "tv", False),
        ("Comedy", "Комедийные сериалы", "Comedy Series", "tv", False),
        ("Crime", "Криминальные сериалы", "Crime Series", "tv", False),
        ("Action & Adventure", "Аниме-боевики", "Action Anime", "tv", True),
        ("Romance", "Романтическое аниме", "Romance Anime", "tv", True),
        ("Sci-Fi & Fantasy", "Аниме-фэнтези", "Fantasy Anime", "tv", True),
    )

    async def named_collections(self, language: Optional[str] = None) -> List[tuple]:
        """Returns [(title_ru, title_en, items)] for the Collections tab,
        sourced from real TMDB list/discover endpoints. Each shelf is
        franchise-diversified (_diversify above).

        `language` is TMDB's own code ("ru-RU") or None for English (TMDB's
        default when no language is given) — passed straight through to
        every underlying list/discover call so *card* titles/overviews come
        back already in the requested language instead of only after
        opening a title's own detail screen (see app/routers/feed.py::
        get_collections, which picks this from the request). The *shelf
        name itself* (e.g. "Top Anime") is unrelated to that and always
        returned as a (ru, en) pair — see _core_shelves/_GENRE_SHELVES —
        so the client's displayTitle can pick per its own locale toggle
        the same way it already does for Teamira franchise shelves,
        regardless of which language the cards under it came back in."""
        core = self._core_shelves()
        core_results = await asyncio.gather(
            *[self._fetch_list(path, kind, params, language) for path, kind, params, _, _ in core],
            return_exceptions=True,
        )
        genre_results = await asyncio.gather(
            *[
                self.similar_by_genre(kind, [genre], anime_only=anime_only, language=language)
                for genre, _, _, kind, anime_only in self._GENRE_SHELVES
            ],
            return_exceptions=True,
        )
        labels = [(label_ru, label_en) for *_, label_ru, label_en in core] + [
            (label_ru, label_en) for _, label_ru, label_en, _, _ in self._GENRE_SHELVES
        ]
        all_results = list(core_results) + list(genre_results)
        out = []
        for (label_ru, label_en), result in zip(labels, all_results):
            if isinstance(result, Exception) or not result:
                continue
            out.append((label_ru, label_en, _diversify(result)))
        return out

    async def person_detail(self, person_id: str) -> Optional[PersonDetailOut]:
        """What a tapped cast tile or "directed by ___" name opens — bio +
        photo + a filmography grid, from TMDB's /person/{id}. One English
        call carries almost everything via `append_to_response=
        combined_credits` (both their acting *and* crew/directing credits,
        across movie and tv at once); a second, best-effort ru-RU call
        fills in a Russian biography when TMDB has one (frequently doesn't,
        for anyone not widely covered in Russian-language media — same
        "degrade to English" as everywhere else localized in this app).

        Filmography is cast+crew merged, deduped by tmdb id (someone can
        show up in both lists for the same title — e.g. an actor-director),
        sorted by TMDB's own `popularity` on each credit, capped at 24 so
        a decades-long, hundreds-of-credits career doesn't turn into an
        endless grid. Built via the same _media_item_from_search_hit this
        app's other list endpoints use — combined_credits entries carry
        the same thin shape (genre_ids, poster_path, media_type, ...) a
        search/discover hit does.

        None on a 404 (bad id) or no key configured.
        """
        if not settings.tmdb_api_key:
            return None
        url = f"{TMDB_BASE}/person/{person_id}"
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp_en = await client.get(url, params={
                "api_key": settings.tmdb_api_key,
                "append_to_response": "combined_credits",
            })
            if resp_en.status_code == 404:
                return None
            resp_en.raise_for_status()
            data_en = resp_en.json()
            data_ru: dict = {}
            try:
                resp_ru = await client.get(url, params={
                    "api_key": settings.tmdb_api_key, "language": "ru-RU",
                })
                if resp_ru.status_code == 200:
                    data_ru = resp_ru.json()
            except httpx.HTTPError:
                pass

        bio_en = data_en.get("biography") or None
        bio_ru = data_ru.get("biography") or None
        biography = None
        if bio_en or (bio_ru and bio_ru != bio_en):
            biography = LocalizedText(en=bio_en, ru=(bio_ru if bio_ru != bio_en else None))

        credits = data_en.get("combined_credits") or {}
        raw_credits = (credits.get("cast") or []) + (credits.get("crew") or [])
        raw_credits.sort(key=lambda c: c.get("popularity") or 0, reverse=True)
        filmography: List[MediaItem] = []
        seen_ids: set = set()
        for c in raw_credits:
            media_kind = c.get("media_type")
            if media_kind not in ("movie", "tv"):
                continue
            cid = c.get("id")
            if cid is None or cid in seen_ids:
                continue
            seen_ids.add(cid)
            built = self._media_item_from_search_hit(c, media_kind, "en")
            if built:
                filmography.append(built[0])
            if len(filmography) >= 24:
                break

        return PersonDetailOut(
            person_id=str(person_id),
            name=data_en.get("name") or "",
            photo_url=self.profile_url(data_en.get("profile_path")),
            biography=biography,
            birthday=data_en.get("birthday") or None,
            known_for_department=data_en.get("known_for_department") or None,
            filmography=filmography,
            tmdb_attribution=TMDB_ATTRIBUTION,
        )
