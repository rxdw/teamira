import asyncio
import logging
import random
import re
from datetime import date
from typing import List, Optional

import httpx

from app.config import settings
from app.schemas import MediaItem, ExternalIds, LocalizedText
from app.adapters.base import MediaAdapter

logger = logging.getLogger("seenly.adapters.simkl")

SIMKL_BASE = "https://api.simkl.com"

# Every SIMKL request needs three URL params (client_id, app-name,
# app-version) plus a User-Agent header — confirmed against the current docs
# (api.simkl.org/conventions/headers). Missing app-name/app-version doesn't
# 412 on its own (client_id does the auth), but the docs are explicit these
# are required on *every* request, so we send them everywhere rather than
# only where we've seen a failure.
_APP_PARAMS = {"app-name": "seenly", "app-version": "1.0"}
_HEADERS = {"User-Agent": "seenly/1.0"}

# /search/movie and /search/tv only return title/year/ids — no overview or
# genres. Those live on the per-title "summary" endpoints (/movies/{id},
# /tv/{id}, /anime/{id}), which are Cloudflare-cached and return the full
# record by default. So search() does a second, concurrent round of calls
# to enrich each hit before returning it. The same is true of /tv/best,
# /anime/best, and /tv|anime/premieres — all documented as returning a
# thin {title, year, poster, ids, ratings} shape.
#
# IMPORTANT: SIMKL has *three* separate detail namespaces — /movies/{id},
# /tv/{id}, /anime/{id} — not two. Anime and TV shows have distinct simkl
# ids that only resolve under their own segment; calling /tv/{id} with an
# anime id 404s (and used to, silently, before this fix — that's why
# anime shelves were missing descriptions/genres). So every hit now carries
# its own detail *segment* ("movies" | "tv" | "anime") instead of deriving
# it from the app's media_type. Note "anime" is now also its own
# media_type (not folded into "series") — segment and media_type happen
# to share the string "anime" for that one case, but they're still two
# different concepts: segment is SIMKL's URL namespace, media_type is
# ours.
_ENRICH_LIMIT = 40  # cap concurrent detail calls per search/shelf — raised
# from 20 so Collections shelves show closer to a full page of titles
# instead of stopping at the first 20 SIMKL happens to return. Still well
# under what a single /best, /genres, or /premieres page tends to hold, so
# this mostly just stops us from throwing away real results we already
# fetched, rather than asking SIMKL for anything new.

# named_collections() fans out ~17 shelf calls concurrently, and each of
# those calls _enrich() which itself fans out up to _ENRICH_LIMIT detail
# calls — without a cap that's hundreds of simultaneous requests to SIMKL
# from a single /feed/collections hit, which is exactly what SIMKL's rate
# limiter is there to reject (documented as a 403, not a 429 — see
# api.simkl.org/conventions/errors: "invalid API key or unapproved app or
# requests are being denied due to API limits"). This semaphore is shared
# by every request this adapter instance makes, regardless of which method
# started it, so the real ceiling is enforced app-wide, not per-call.
# Bumped 6 -> 10 alongside the higher _ENRICH_LIMIT so the extra detail
# calls per shelf don't just serialize into a much slower /feed/collections
# — still comfortably below what's triggered 403s in practice, and the
# retry/backoff above still catches it if a burst does get rejected.
_HTTP_SEMAPHORE = asyncio.Semaphore(10)

# 403 from SIMKL is ambiguous by their own docs (bad key vs rate limit) —
# but if client_id were actually invalid every request would 403, not just
# the ones caught in a large concurrent burst. In practice for a burst
# fan-out like ours, 403s cluster with the fan-out size, which is the
# rate-limit case. So: back off and retry a couple of times before giving
# up and letting the caller treat it as "this shelf/detail just isn't
# available right now".
_RATE_LIMIT_STATUSES = {403, 429}
_RETRY_DELAYS = (0.6, 1.5)  # seconds, applied between attempts


async def _get(client: httpx.AsyncClient, url: str, params: dict) -> httpx.Response:
    """Every outbound SIMKL request goes through here: semaphore-limited
    concurrency + a couple of backed-off retries specifically for 403/429,
    then raise_for_status() as normal so existing callers' except blocks
    are unaffected."""
    async with _HTTP_SEMAPHORE:
        attempt = 0
        while True:
            resp = await client.get(url, params=params)
            if resp.status_code in _RATE_LIMIT_STATUSES and attempt < len(_RETRY_DELAYS):
                logger.info("SIMKL %s on %s — backing off %.1fs (attempt %d)", resp.status_code, url, _RETRY_DELAYS[attempt], attempt + 1)
                await asyncio.sleep(_RETRY_DELAYS[attempt])
                attempt += 1
                continue
            resp.raise_for_status()
            return resp

# (path, media_type, detail_segment) — media_type is what our app model
# uses; detail_segment is the real SIMKL namespace for the per-title call.
#
# See _genre_browse_path()'s docstring for the three genre-browse path
# shapes (movies/anime are 5-segment, tv is the 6-segment odd one out).
def _genre_browse_path(
    segment: str,
    genre: str,
    sort: str,
    *,
    genre_type: str = "all",
    country: str = "all",
    network: str = "all",
    year: str = "all",
) -> str:
    """Builds a genre-browse path for movies/tv/anime.

    Confirmed against the current api.simkl.org reference (2026-07) — the
    old apiary docs this was first written against are frozen/stale. Three
    different shapes, and getting any segment count wrong doesn't 404 (the
    endpoint silently falls back / returns null per its own docs), so a
    wrong path here fails *silently* as an empty shelf, not an error:

    - movies: /movies/genres/{genre}/{type}/{country}/{year}/{sort} —
      5 segments after genre. `{type}` is a *reserved literal* here, not a
      wildcard — must be exactly "movies", not "all".
    - tv:     /tv/genres/{genre}/{type}/{country}/{network}/{year}/{sort} —
      6 segments (the only one with both country AND network).
    - anime:  /anime/genres/{genre}/{type}/{network}/{year}/{sort} —
      5 segments, no country (anime is Japan-dominated; country filtering
      isn't offered).

    Wildcards are the literal string "all" everywhere — not "all-types" /
    "all-countries" / etc, which aren't recognized values.
    """
    if segment == "movies":
        return f"movies/genres/{genre}/movies/{country}/{year}/{sort}"
    if segment == "tv":
        return f"tv/genres/{genre}/{genre_type}/{country}/{network}/{year}/{sort}"
    return f"anime/genres/{genre}/{genre_type}/{network}/{year}/{sort}"


_DISCOVER_PATHS = (
    (_genre_browse_path("movies", "all", "popular-this-week"), "movie", "movies"),
    (_genre_browse_path("tv", "all", "popular-this-week"), "series", "tv"),
)

# Extra genre-scoped shelves — same browse endpoint, just a specific genre
# instead of "all". (genre_slug, display_label, segment, media_type)
_GENRE_SHELVES = (
    ("action", "Action", "movies", "movie"),
    ("comedy", "Comedy", "movies", "movie"),
    ("horror", "Horror", "movies", "movie"),
    ("thriller", "Thriller", "movies", "movie"),
    ("romance", "Romance", "movies", "movie"),
    ("fantasy", "Fantasy", "movies", "movie"),
    ("animation", "Animated Movies", "movies", "movie"),
    ("documentary", "Documentaries", "movies", "movie"),
    ("drama", "Drama Series", "tv", "series"),
    ("comedy", "Comedy Series", "tv", "series"),
    ("crime", "Crime Series", "tv", "series"),
    ("action", "Action Anime", "anime", "anime"),
    ("romance", "Romance Anime", "anime", "anime"),
    ("fantasy", "Fantasy Anime", "anime", "anime"),
)


def _franchise_key(title: Optional[str]) -> str:
    """Rough franchise fingerprint: the title text before the first colon/
    dash, with a trailing "Part 2" / roman numeral / number stripped, all
    lowercased — e.g. "Harry Potter and the Deathly Hallows: Part 2" and
    "Harry Potter and the Goblet of Fire" both collapse to "harry potter
    and the". Good enough to stop one multi-film franchise (a real
    possibility on a genuine "trending this week" chart — franchises spike
    together) from filling an entire shelf, without needing real franchise
    metadata SIMKL doesn't expose."""
    if not title:
        return ""
    base = re.split(r"[:\-–—]", title, maxsplit=1)[0].strip().lower()
    base = re.sub(r"\s+(part\s*)?\b([ivxlcdm]{1,4}|\d{1,2})\b\s*$", "", base)
    return base


def _diversify(items: List[MediaItem], max_per_franchise: int = 2) -> List[MediaItem]:
    """Caps how many entries from the same apparent franchise can appear in
    one shelf — order-preserving, so it still favors the highest-ranked
    items overall."""
    counts: dict = {}
    result = []
    for item in items:
        key = _franchise_key(item.title.en or item.title.ru)
        counts[key] = counts.get(key, 0) + 1
        if counts[key] <= max_per_franchise:
            result.append(item)
    return result


def _simkl_id(ids: dict):
    # API docs disagree across versions: current guides say `ids.simkl_id`,
    # older Apiary examples show `ids.simkl`. Accept either.
    return ids.get("simkl_id") or ids.get("simkl")


def _cdn_image_url(kind: str, hash_: Optional[str], suffix: str) -> Optional[str]:
    """Builds a simkl.in image URL.

    The `poster`/`fanart` value returned by SIMKL's API can come in two shapes:
    - a bare hash, e.g. `74415673dcdc9cdd` — needs the `xx/` subfolder
      (first two chars of the hash) prepended: `posters/74/74415673dcdc9cdd_m.webp`.
    - already-prefixed, e.g. `74/74415673dcdc9cdd` — the subfolder is baked
      into the value itself, and prepending it again produces a doubled,
      404ing path like `posters/74/74/74415673dcdc9cdd_m.webp`.

    We only add the subfolder when it isn't already present."""
    if not hash_:
        return None
    path = hash_ if "/" in hash_ else f"{hash_[:2]}/{hash_}"
    target = f"https://simkl.in/{kind}/{path}{suffix}"
    # SIMKL's own docs say to route images through wsrv.nl rather than
    # hitting simkl.in directly ("preferred, minimises traffic to our
    # servers") — direct simkl.in links may be rate-limited/blocked.
    return f"https://wsrv.nl/?url={target}"


def _poster_url(poster: Optional[str]) -> Optional[str]:
    return _cdn_image_url("posters", poster, "_m.webp")


def _backdrop_url(fanart: Optional[str]) -> Optional[str]:
    return _cdn_image_url("fanart", fanart, "_medium.webp")


def _unwrap_trending(item: dict) -> Optional[dict]:
    """Trending CDN file entries are either a flat Standard Media Object
    (the case for the real per-type files, e.g. movies/week_100.json) or
    wrap the title under a movie/show/anime key (the combined today_100.json
    style files mix all three, keyed this way) — accept either shape so a
    format difference between files doesn't silently return nothing."""
    if not isinstance(item, dict):
        return None
    if "ids" in item:
        return item
    for key in ("movie", "show", "anime", "tv"):
        nested = item.get(key)
        if isinstance(nested, dict):
            return nested
    return None


def _normalize(raw: dict, media_type: str) -> MediaItem:
    ids = raw.get("ids") or {}
    ratings = raw.get("ratings") or {}
    simkl_rating = ratings.get("simkl") or {}
    simkl_id = _simkl_id(ids)

    return MediaItem(
        id=f"simkl-{simkl_id or raw.get('title')}",
        media_type=media_type,
        external_ids=ExternalIds(
            tmdb=str(ids["tmdb"]) if ids.get("tmdb") else None,
            imdb=ids.get("imdb"),
            simkl=str(simkl_id) if simkl_id else None,
        ),
        title=LocalizedText(ru=None, en=raw.get("title")),
        description=LocalizedText(ru=None, en=raw.get("overview") or raw.get("plot")),
        poster_url=_poster_url(raw.get("poster")),
        backdrop_url=_backdrop_url(raw.get("fanart")),
        year=raw.get("year"),
        genres=raw.get("genres") or [],
        rating=simkl_rating.get("rating") or raw.get("rating"),
        source="simkl",
    )


def _first(raw: dict, *keys):
    for key in keys:
        value = raw.get(key)
        if value not in (None, ""):
            return value
    return None


def _normalize_full(raw: dict, media_type: str) -> MediaItem:
    """Overlays the extended-detail fields onto the normal _normalize()
    mapping. Field names below are best-effort against SIMKL's documented
    `extended=full` behavior and general Trakt-like tracker conventions
    (SIMKL's own schema for this specific response isn't fully published
    anywhere we could find) — every lookup tries a couple of plausible key
    spellings and falls back to null rather than guessing wrong, so a bad
    guess here degrades to "field just doesn't show up" instead of a crash.
    Worth spot-checking against a real response once a live SIMKL key is
    available in an environment that can actually reach api.simkl.com."""
    item = _normalize(raw, media_type)
    runtime = _first(raw, "runtime", "runtime_minutes")
    certification = _first(raw, "certification", "age_rating", "content_rating")
    release_date = _first(raw, "released", "release_date", "first_aired")
    status = _first(raw, "status")
    country = _first(raw, "country")
    tagline = _first(raw, "tagline")

    return item.model_copy(update={
        "tagline": tagline,
        "runtime_minutes": int(runtime) if isinstance(runtime, (int, float)) else None,
        "certification": str(certification) if certification else None,
        "release_date": str(release_date) if release_date else None,
        "status": str(status) if status else None,
        "country": str(country) if country else None,
    })


class SimklAdapter(MediaAdapter):
    source_name = "simkl"

    def __init__(self, client_id: Optional[str] = None):
        self.client_id = client_id or settings.simkl_client_id

    def _params(self, **extra) -> dict:
        return {"client_id": self.client_id, **_APP_PARAMS, **extra}

    async def _fetch_detail(self, client: httpx.AsyncClient, simkl_id, segment: str) -> Optional[dict]:
        """`segment` must be the real SIMKL namespace — "movies" | "tv" |
        "anime" — not the app's simplified media_type. Get this wrong and
        the call 404s silently, which is exactly what made anime shelves
        lose their overview/genres before this was split out."""
        if not simkl_id:
            logger.warning("SIMKL detail skipped: hit had no ids.simkl_id/ids.simkl (segment=%s)", segment)
            return None
        url = f"{SIMKL_BASE}/{segment}/{simkl_id}"
        try:
            resp = await _get(client, url, self._params())
            return resp.json()
        except httpx.HTTPError as exc:
            status = getattr(getattr(exc, "response", None), "status_code", "?")
            logger.warning("SIMKL detail fetch failed [%s] %s -> %s", status, url, exc)
            return None

    async def _enrich(self, client: httpx.AsyncClient, hits: List[tuple]) -> List[MediaItem]:
        """hits: list of (raw_doc, media_type, detail_segment). Always tries
        a detail call — cheap Cloudflare-cached lookups — since neither
        /search nor /genres reliably includes overview/genres despite what
        the docs claim."""
        hits = hits[:_ENRICH_LIMIT]
        details = await asyncio.gather(
            *[self._fetch_detail(client, _simkl_id(doc.get("ids") or {}), segment) for doc, _mt, segment in hits]
        )
        results: List[MediaItem] = []
        for (doc, media_type, _segment), detail in zip(hits, details):
            # Fall back to the bare snippet if the detail call failed or the
            # item had no simkl id — still returns something rather than
            # dropping the hit.
            results.append(_normalize(detail or doc, media_type))
        return results

    async def lookup_by_external_id(
        self, client: httpx.AsyncClient, *, tmdb: Optional[str] = None, imdb: Optional[str] = None,
    ) -> Optional[MediaItem]:
        """Resolves a TMDB or IMDB id — the ids Plex/Jellyfin libraries
        almost always carry, and the closest thing a scrobble event has to
        a reliable identity — to our own catalog, via SIMKL's `/search/id`
        endpoint. Used by app/routers/integrations.py; nowhere else in
        this adapter exercises that endpoint, so this parses its response
        defensively (several plausible shapes) and returns None on
        anything unexpected rather than raising — a failed match should
        fall back to a lightweight standalone snapshot, not break the
        whole scrobble. Confirm the exact response shape against current
        SIMKL docs if matches aren't landing; id-lookup endpoints are the
        least-exercised part of most catalog APIs and the most likely to
        have drifted from what's assumed here.
        """
        if not (tmdb or imdb):
            return None
        params = self._params(**({"tmdb": tmdb} if tmdb else {"imdb": imdb}))
        try:
            resp = await _get(client, f"{SIMKL_BASE}/search/id", params)
            hits = resp.json()
        except (httpx.HTTPError, ValueError):
            return None
        if not hits:
            return None

        hit = hits[0]
        kind = hit.get("type")
        raw = hit.get("movie") or hit.get("show") or hit.get("anime") or hit
        if kind == "movie":
            media_type, segment = "movie", "movies"
        elif kind == "anime":
            media_type, segment = "anime", "anime"
        else:
            media_type, segment = "series", "tv"

        detail = await self._fetch_detail(client, _simkl_id(raw.get("ids") or {}), segment)
        try:
            return _normalize(detail or raw, media_type)
        except Exception:
            logger.warning("SIMKL id-lookup: couldn't normalize hit for tmdb=%s imdb=%s", tmdb, imdb)
            return None

    async def full_detail(self, simkl_id: str, segment: str, media_type: str) -> Optional[MediaItem]:
        """extended=full detail call for the title screen — runtime,
        certification, release date, status, on top of the normal
        overview/genres/poster _fetch_detail already gets. See
        _normalize_full()'s docstring for the caveat on field names."""
        if not self.client_id:
            raise RuntimeError("SIMKL_CLIENT_ID is not configured")
        url = f"{SIMKL_BASE}/{segment}/{simkl_id}"
        async with httpx.AsyncClient(timeout=8.0, headers=_HEADERS) as client:
            try:
                resp = await _get(client, url, self._params(extended="full"))
                return _normalize_full(resp.json(), media_type)
            except httpx.HTTPError as exc:
                status = getattr(getattr(exc, "response", None), "status_code", "?")
                logger.warning("SIMKL full detail fetch failed [%s] %s -> %s", status, url, exc)
                return None

    async def episodes(self, simkl_id: str, segment: str) -> List[dict]:
        """GET /{segment}/episodes/{id} — the flat episode list SIMKL keeps
        per show (segment is "tv" or "anime"; movies never call this).
        Response shape is SIMKL's own per-episode dict with `season` and
        `episode` numbers plus a title — same "best-effort against
        documented behavior, degrade to empty rather than guess wrong"
        approach as _normalize_full above, since this project has never
        run against a live key. Specials (season 0) are dropped: they're
        not part of "how far through the show am I", and mixing them into
        the season grid would make the episode counts per season lie.
        """
        if not self.client_id:
            raise RuntimeError("SIMKL_CLIENT_ID is not configured")
        if not simkl_id:
            return []
        url = f"{SIMKL_BASE}/{segment}/episodes/{simkl_id}"
        async with httpx.AsyncClient(timeout=8.0, headers=_HEADERS) as client:
            try:
                resp = await _get(client, url, self._params(extended="full"))
                data = resp.json()
            except httpx.HTTPError as exc:
                status = getattr(getattr(exc, "response", None), "status_code", "?")
                logger.warning("SIMKL episodes fetch failed [%s] %s -> %s", status, url, exc)
                return []

        if not isinstance(data, list):
            return []

        out = []
        for raw in data:
            if not isinstance(raw, dict):
                continue
            season = raw.get("season")
            episode = _first(raw, "episode", "episode_number")
            if season is None or episode is None:
                continue
            if int(season) == 0:
                continue  # specials — see docstring
            out.append({
                "season": int(season),
                "episode": int(episode),
                "title": _first(raw, "title", "name"),
            })
        return out

    async def ratings(self, simkl_id: str, media_type: str) -> Optional[dict]:
        """GET /ratings — Simkl's own community rating + votes, the
        matched IMDB rating + votes, Simkl rank, drop rate, and
        review/comment counts (not review text — SIMKL doesn't expose
        review bodies over the API, only these aggregate counts via the
        `reactions` field). `type` narrows the search space per the docs
        ('show' covers both tv and anime)."""
        if not self.client_id:
            raise RuntimeError("SIMKL_CLIENT_ID is not configured")
        type_param = "movie" if media_type == "movie" else "show"
        async with httpx.AsyncClient(timeout=8.0, headers=_HEADERS) as client:
            try:
                resp = await _get(
                    client,
                    f"{SIMKL_BASE}/ratings",
                    self._params(
                        simkl=simkl_id,
                        type=type_param,
                        fields="rank,droprate,simkl,ext,has_trailer,reactions,year",
                    ),
                )
                data = resp.json() or {}
            except httpx.HTTPError as exc:
                status = getattr(getattr(exc, "response", None), "status_code", "?")
                logger.warning("SIMKL ratings fetch failed [%s] simkl=%s -> %s", status, simkl_id, exc)
                return None

        simkl_block = data.get("simkl") or {}
        imdb_block = data.get("IMDB") or data.get("imdb") or {}
        rank_block = data.get("rank") or {}
        reactions = data.get("reactions") or {}
        return {
            "simkl_rating": simkl_block.get("rating"),
            "simkl_votes": simkl_block.get("votes"),
            "imdb_rating": imdb_block.get("rating"),
            "imdb_votes": imdb_block.get("votes"),
            "rank": rank_block.get("value") if isinstance(rank_block, dict) else rank_block,
            "droprate": data.get("droprate"),
            "reviews_count": reactions.get("reviews"),
            "comments_count": reactions.get("comments"),
        }

    async def similar(self, segment: str, media_type: str, genres: List[str], exclude_id: str) -> List[MediaItem]:
        """"Similar titles" via genre-browse on the title's own primary
        genre, popularity-sorted, with the title itself filtered out.
        SIMKL doesn't publish a dedicated recommendations/similar-titles
        endpoint (their in-app "personalized recommendations" is a
        simkl.com feature built on a user's synced history, not something
        the public catalog API exposes) — this is an honest "titles that
        share a genre" shelf, not a claim of SIMKL's own ML recs."""
        if not genres:
            return []
        primary_genre = genres[0].lower()
        try:
            hits = await self.genre_shelf(segment, primary_genre, media_type, sort="popular-this-month")
        except (RuntimeError, httpx.HTTPError):
            return []
        return [item for item in hits if item.id != exclude_id][:10]

    async def search(self, query: str) -> List[MediaItem]:
        if not self.client_id:
            # No app-level SIMKL key configured — caller should fall back to mock data.
            raise RuntimeError("SIMKL_CLIENT_ID is not configured")

        hits: List[tuple] = []  # (raw_search_doc, media_type, detail_segment)
        async with httpx.AsyncClient(timeout=8.0, headers=_HEADERS) as client:
            for endpoint, media_type, segment in (
                ("search/movie", "movie", "movies"),
                ("search/tv", "series", "tv"),
                ("search/anime", "anime", "anime"),
            ):
                try:
                    resp = await _get(
                        client,
                        f"{SIMKL_BASE}/{endpoint}",
                        self._params(q=query),
                    )
                    data = resp.json() or []
                    hits.extend((item, media_type, segment) for item in data)
                except httpx.HTTPError as exc:
                    status = getattr(getattr(exc, "response", None), "status_code", "?")
                    logger.warning("SIMKL search failed [%s] %s/%s?q=%s -> %s", status, SIMKL_BASE, endpoint, query, exc)
                    continue

            return await self._enrich(client, hits)

    async def discover(self) -> List[MediaItem]:
        """Trending titles for the feed. Uses the same enrichment pass as
        search() — the raw discovery payload isn't reliably enough on its
        own (docs claim it includes overview/genres; in practice it doesn't
        always)."""
        if not self.client_id:
            raise RuntimeError("SIMKL_CLIENT_ID is not configured")

        hits: List[tuple] = []
        async with httpx.AsyncClient(timeout=8.0, headers=_HEADERS) as client:
            for path, media_type, segment in _DISCOVER_PATHS:
                try:
                    resp = await _get(client, f"{SIMKL_BASE}/{path}", self._params())
                    data = resp.json() or []
                    hits.extend((item, media_type, segment) for item in data)
                except httpx.HTTPError as exc:
                    status = getattr(getattr(exc, "response", None), "status_code", "?")
                    logger.warning("SIMKL discover failed [%s] %s/%s -> %s", status, SIMKL_BASE, path, exc)
                    continue

            return await self._enrich(client, hits)

    async def _thin_list(self, client: httpx.AsyncClient, path: str, media_type: str, segment: str, *, paginated: bool = False) -> List[tuple]:
        """Fetches a /best or /premieres style endpoint and returns raw
        (doc, media_type, detail_segment) triples — same thin shape as a
        search hit, ready for _enrich(). Handles the documented `null` body
        (empty result set).

        `paginated` must only be set for endpoint families SIMKL's own
        pagination docs actually list (currently: premieres). /best is
        NOT in that list — it's a fixed-size chart, and passing page/limit
        to it is a no-op at best, so we don't."""
        params = self._params(page=1, limit=60) if paginated else self._params()
        try:
            resp = await _get(client, f"{SIMKL_BASE}/{path}", params)
            data = resp.json()
            if not data:
                return []
            return [(item, media_type, segment) for item in data]
        except httpx.HTTPError as exc:
            status = getattr(getattr(exc, "response", None), "status_code", "?")
            logger.warning("SIMKL list fetch failed [%s] %s/%s -> %s", status, SIMKL_BASE, path, exc)
            return []

    async def best(self, kind: str, filter: str = "all") -> List[MediaItem]:
        """GET /{tv|anime}/best/{filter} — filter is one of all|year|
        month|voted|watched. `kind` is also the real SIMKL detail segment.

        Movies do NOT have a /best endpoint — confirmed both by a live 404
        (`GET /movies/best/all` -> 404) and by api.simkl.org's Movies
        reference page, which lists only Genres + the CDN trending/DVD
        files for movies, no /best route. Use top_movies() instead, which
        gets the same "top of the catalog" result via genre-browse.

        Unlike genre-browse and premieres, /best is NOT in SIMKL's
        pagination table — it's a fixed-size chart that doesn't grow no
        matter what page/limit you pass it. For a bigger "Top X" shelf,
        see best_merged() below, which combines several of these charts
        instead of trying to paginate a single one."""
        if kind == "movies":
            raise ValueError(
                "SIMKL has no /movies/best/{filter} endpoint (only /tv and "
                "/anime do) — use top_movies() instead"
            )
        if not self.client_id:
            raise RuntimeError("SIMKL_CLIENT_ID is not configured")
        segment = kind if kind in ("tv", "anime") else "anime"
        media_type = "series" if segment == "tv" else "anime"
        async with httpx.AsyncClient(timeout=8.0, headers=_HEADERS) as client:
            hits = await self._thin_list(client, f"{segment}/best/{filter}", media_type, segment)
            return _diversify(await self._enrich(client, hits))

    async def best_merged(self, kind: str, filters: tuple = ("all", "voted", "watched")) -> List[MediaItem]:
        """A bigger "Top X" shelf built from several /best charts instead
        of one. /best doesn't paginate (see best()'s docstring) — each
        `filter` is its own independently-ranked, fixed-size chart (top by
        rating, top by number of ratings, top by watch count), so fetching
        a few and merging/de-duping by SIMKL id gives a real, wider pool
        instead of the same ~20 titles every time. One shared client and
        one shared _enrich/_diversify pass, so overlapping titles across
        charts only cost one detail call each, not one per chart."""
        if kind == "movies":
            raise ValueError(
                "SIMKL has no /movies/best/{filter} endpoint — use top_movies() instead"
            )
        if not self.client_id:
            raise RuntimeError("SIMKL_CLIENT_ID is not configured")
        segment = kind if kind in ("tv", "anime") else "anime"
        media_type = "series" if segment == "tv" else "anime"
        async with httpx.AsyncClient(timeout=8.0, headers=_HEADERS) as client:
            chart_hits = await asyncio.gather(
                *[self._thin_list(client, f"{segment}/best/{f}", media_type, segment) for f in filters]
            )
            seen: set = set()
            merged: List[tuple] = []
            for hits in chart_hits:
                for doc, mt, seg in hits:
                    key = _simkl_id(doc.get("ids") or {}) or id(doc)
                    if key in seen:
                        continue
                    seen.add(key)
                    merged.append((doc, mt, seg))
            return _diversify(await self._enrich(client, merged))

    async def top_movies(self, year: str = "all", sort: str = "rank") -> List[MediaItem]:
        """The movies equivalent of best() — since /movies/best/{filter}
        doesn't exist, this goes through the genre-browse endpoint with
        genre=all instead (optionally scoped to one year), sorted by
        Simkl's own popularity/quality rank by default."""
        return await self.genre_shelf("movies", "all", "movie", sort=sort, year=year)

    async def premieres(self, kind: str, when: str = "new") -> List[MediaItem]:
        """GET /{tv|anime}/premieres/{new|soon}."""
        if not self.client_id:
            raise RuntimeError("SIMKL_CLIENT_ID is not configured")
        segment = "tv" if kind == "tv" else "anime"
        media_type = "series" if segment == "tv" else "anime"
        async with httpx.AsyncClient(timeout=8.0, headers=_HEADERS) as client:
            hits = await self._thin_list(client, f"{segment}/premieres/{when}", media_type, segment, paginated=True)
            return _diversify(await self._enrich(client, hits))

    async def popular(self, media_type: str, min_year: Optional[int] = None) -> List[MediaItem]:
        """"Popular Movies/Series This Week" — SIMKL's pre-built CDN
        trending file (data.simkl.in). There IS a dedicated per-type file
        for this (e.g. `movies/week_100.json`, confirmed against SIMKL's
        Trending data files reference) — separate from the combined
        `week_100.json` that mixes all three categories. We use the
        per-type one so we don't have to guess a title's category from a
        wrapper key.

        We *prefer* to drop anything older than `min_year` (default: last 2
        release years) — "trending this week" and "new/current" aren't the
        same thing, and a decades-old catalog title can spike in the raw
        trending file (rewatch waves, a streaming re-add, a reboot
        announcement — a real "Harry Potter" HBO-series-news spike is
        exactly this) without being something someone would call "top of
        the week" in the everyday sense.

        But that filter used to be unconditional, and a real trending chart
        can legitimately be *mostly* older catalog titles in a given week —
        applying it unconditionally once collapsed this shelf down to a
        single surviving item. A shelf we advertise as "popular this week"
        showing one movie is a worse experience than one that includes a
        few older-but-genuinely-trending titles, so: use the recency filter
        only when enough titles actually survive it; otherwise fall back to
        the full trending list (still franchise-diversified) rather than
        showing something that looks broken.
        """
        if min_year is None:
            min_year = date.today().year - 2
        MIN_RECENT_ITEMS = 8

        segment = {"movie": "movies", "anime": "anime"}.get(media_type, "tv")
        url = f"https://data.simkl.in/discover/trending/{segment}/week_100.json"
        async with httpx.AsyncClient(timeout=8.0, headers=_HEADERS) as client:
            try:
                resp = await _get(client, url, self._params())
                data = resp.json() or []
            except httpx.HTTPError as exc:
                logger.warning("SIMKL trending fetch failed [%s] -> %s", url, exc)
                return []

            all_hits = []
            recent_hits = []
            for item in data:
                doc = _unwrap_trending(item)
                if not doc:
                    continue
                hit = (doc, media_type, segment)
                all_hits.append(hit)
                year = doc.get("year")
                if year is None or year >= min_year:
                    recent_hits.append(hit)

            hits = recent_hits if len(recent_hits) >= MIN_RECENT_ITEMS else all_hits
            return _diversify(await self._enrich(client, hits))

    async def genre_shelf(self, segment: str, genre: str, media_type: str, sort: str = "popular-this-month", year: str = "all") -> List[MediaItem]:
        """One genre-scoped shelf via the same genre-browse endpoint
        discover() uses for "all" genres — e.g. Action (action movies),
        Comedy (comedies), Horror (horror)."""
        if not self.client_id:
            raise RuntimeError("SIMKL_CLIENT_ID is not configured")
        path = _genre_browse_path(segment, genre, sort, year=year)
        async with httpx.AsyncClient(timeout=8.0, headers=_HEADERS) as client:
            try:
                # Genre-browse defaults to limit=60 per SIMKL's pagination
                # docs, but we ask for it explicitly rather than trust an
                # undocumented default not to quietly change on us.
                resp = await _get(client, f"{SIMKL_BASE}/{path}", self._params(page=1, limit=60))
                data = resp.json() or []
            except httpx.HTTPError as exc:
                status = getattr(getattr(exc, "response", None), "status_code", "?")
                logger.warning("SIMKL genre shelf failed [%s] %s/%s -> %s", status, SIMKL_BASE, path, exc)
                return []
            hits = [(doc, media_type, segment) for doc in data]
            return _diversify(await self._enrich(client, hits))

    async def movies_feed(self) -> List[MediaItem]:
        """A dedicated movies-only feed (as opposed to /feed, which mixes
        in games too) — pulled from several real movie sources and merged/
        deduplicated by SIMKL id, then shuffled so it doesn't just read like
        three shelves stapled together."""
        if not self.client_id:
            raise RuntimeError("SIMKL_CLIENT_ID is not configured")

        results = await asyncio.gather(
            self.popular("movie"),
            self.top_movies("all"),
            self.top_movies(str(date.today().year)),
            self.dvd_releases(),
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

        random.shuffle(pool)
        return pool

    async def dvd_releases(self) -> List[MediaItem]:
        """GET data.simkl.in/discover/dvd/releases_100.json — SIMKL's
        documented "latest popular DVD/digital releases" CDN file, same
        data as simkl.com/movies/dvd-releases/. Movies only."""
        url = "https://data.simkl.in/discover/dvd/releases_100.json"
        async with httpx.AsyncClient(timeout=8.0, headers=_HEADERS) as client:
            try:
                resp = await _get(client, url, self._params())
                data = resp.json() or []
            except httpx.HTTPError as exc:
                logger.warning("SIMKL dvd releases fetch failed [%s] -> %s", url, exc)
                return []

            hits = [(doc, "movie", "movies") for doc in (_unwrap_trending(item) for item in data) if doc]
            return _diversify(await self._enrich(client, hits))

    async def named_collections(self) -> List[tuple]:
        """Returns [(title, items)] for the shelves this adapter can build
        from real, documented endpoints — no synthetic/mock collections."""
        labels = [
            "Top Movies", "Top Movies This Year",
            "Top Series", "Top Series This Year",
            "Top Anime", "Top Anime This Year",
            "New Series Premieres", "Coming Soon: Series",
            "New Anime Premieres", "Coming Soon: Anime",
            "Popular Movies This Week", "Popular Series This Week", "Popular Anime This Week",
            "DVD/Digital Releases",
        ] + [label for _, label, _, _ in _GENRE_SHELVES]

        base_results = await asyncio.gather(
            self.top_movies("all"),
            self.top_movies(str(date.today().year)),
            self.best_merged("tv"),
            self.best("tv", "year"),
            self.best_merged("anime"),
            self.best("anime", "year"),
            self.premieres("tv", "new"),
            self.premieres("tv", "soon"),
            self.premieres("anime", "new"),
            self.premieres("anime", "soon"),
            self.popular("movie"),
            self.popular("series"),
            self.popular("anime"),
            self.dvd_releases(),
        )
        genre_results = await asyncio.gather(
            *[self.genre_shelf(segment, genre, media_type) for genre, _, segment, media_type in _GENRE_SHELVES]
        )
        results = list(base_results) + list(genre_results)
        return [(label, items) for label, items in zip(labels, results) if items]
