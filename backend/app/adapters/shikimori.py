"""
Shikimori (shikimori.io — formerly shikimori.one) — a Russian anime/manga cataloguing site whose
own database is written in Russian first, not translated from English —
so unlike TMDB (see app/adapters/tmdb.py), a Russian title/description here
isn't a *translation* of anything, it's the source text the Shikimori
community itself wrote for the title. That's the whole reason this
adapter exists as a second, anime-only translation source: TMDB rides
anime under its own "tv" segment and TMDB's ru-RU coverage there is
patchy (most anime on TMDB simply has no Russian translation at all,
because TMDB's translator community skews Western-film/TV), whereas
Shikimori's russian/description fields exist for almost every anime in
its catalog, including obscure ones. So for media_type == "anime",
title_ru/overview_ru/poster_url_ru are taken from here instead of from
TmdbAdapter.full_detail (see app/routers/media.py::
_merge_anime_ru_from_shikimori) — cast/director/trailers stay TMDB's,
Shikimori's own people/video data is far thinner and not worth a second
source for.

No API key: Shikimori's read-only `/api/animes` (search + show) endpoints
are unauthenticated — OAuth is only needed for write actions (rating,
list-editing, etc.) this app never does. The one thing their docs do ask
of every client is a descriptive User-Agent identifying the app (see
SHIKIMORI_USER_AGENT below) — Shikimori is a much smaller, community-run
service than TMDB and blocks anonymous/default-looking user agents outright.

Matching is the fundamentally different — and fundamentally lossier —
part of this adapter compared to TMDB's. TMDB is looked up by an exact
id the item already carries (result.item.external_ids.tmdb); nothing
here plays that role for Shikimori, so every lookup is a best-effort
title(+year) search against Shikimori's own catalog rather than an id
fetch. That means occasional wrong or missing matches are expected
(common titles, same-named remakes, sequels sharing a franchise name),
not a bug to chase — see anime_supplement()'s docstring for exactly how
candidates are scored and how bad matches are screened out.
"""

import asyncio
import logging
import re
import time
from typing import List, Optional, Tuple

import httpx

from app.schemas import MediaItem, ExternalIds, LocalizedText
from app.adapters.base import MediaAdapter
from app.adapters.google_books import GoogleBooksAdapter

logger = logging.getLogger("seenly.adapters.shikimori")

SHIKIMORI_BASE = "https://shikimori.io/api"

# Shikimori's own ToS asks every API client to identify itself in the
# User-Agent (they rate-limit/block generic ones) — this app's own name is
# enough, no registration/key required for these read-only endpoints.
SHIKIMORI_USER_AGENT = "Seenly (+https://github.com/seenly)"

SHIKIMORI_ATTRIBUTION = "Русские описания предоставлены Shikimori"

# How many search hits we look at before giving up on a title — Shikimori's
# own relevance ranking almost always puts the right title in the first
# handful of hits; anything past this is more likely a same-named
# franchise entry than the one we're actually after.
_SEARCH_CANDIDATES = 5

# BBCode-ish markup Shikimori descriptions carry (its editor's own dialect,
# not real BBCode) — stripped down to plain text since this app has no rich
# text renderer for it. `[character=1234]Name[/character]` links a mention
# to a character page; everything else (`[i]`, `[b]`, `[spoiler]`, etc.)
# is plain emphasis/formatting with no equivalent worth preserving here.
_CHARACTER_TAG_RE = re.compile(r"\[character=\d+\](.*?)\[/character\]", re.DOTALL)
_BBCODE_TAG_RE = re.compile(r"\[/?[a-zA-Z_]+(?:=[^\]]*)?\]")


def _clean_description(raw: Optional[str]) -> Optional[str]:
    """Strips Shikimori's editor markup out of a raw `description` field
    down to plain text. Returns None for an empty/whitespace-only result —
    some Shikimori entries carry a description that's nothing but markup
    (rare, but seen on very obscure titles), and an empty string should
    degrade exactly like "no description" everywhere else in this app,
    not render as a blank paragraph."""
    if not raw:
        return None
    text = _CHARACTER_TAG_RE.sub(r"\1", raw)
    text = _BBCODE_TAG_RE.sub("", text)
    text = text.replace("\r\n", "\n").strip()
    return text or None


class ShikimoriAdapter:
    source_name = "shikimori"

    async def _search(self, client: httpx.AsyncClient, query: str) -> List[dict]:
        resp = await client.get(
            f"{SHIKIMORI_BASE}/animes",
            params={"search": query, "limit": _SEARCH_CANDIDATES},
        )
        resp.raise_for_status()
        return resp.json() or []

    @staticmethod
    def _year_of(entry: dict) -> Optional[int]:
        date_str = entry.get("aired_on") or entry.get("released_on")
        return int(date_str[:4]) if date_str and len(date_str) >= 4 and date_str[:4].isdigit() else None

    @classmethod
    def _pick_best_match(cls, candidates: List[dict], title: str, year: Optional[int]) -> Optional[dict]:
        """Scores Shikimori's search hits against the title we're actually
        trying to translate and returns the best one, or None when nothing
        looks like a real match — a wrong Shikimori entry attached to the
        wrong anime (e.g. matching a same-named spin-off or remake) would
        be worse than just falling back to TMDB/English, so this errs
        toward returning nothing over guessing.

        Scored on two independent signals:
        - name match: Shikimori's own `name` (romaji/English) or `russian`
          equals our title case-insensitively -> strong signal, since a
          title match is usually enough on its own for anime (far less
          ambiguous than movies/TV, where "search" is a common word).
        - year match: our `year` (when we have one) equals the year parsed
          out of Shikimori's `aired_on`/`released_on` -> tie-breaker between
          same-named entries (a franchise reusing its own title across
          seasons/remakes is the main case this guards against).

        A candidate needs the name match at minimum; year is only used to
        choose between multiple name-matching candidates, never to accept
        a title match on its own (Shikimori doesn't reliably have a year
        for every entry, and a bare year match with no title agreement is
        too weak to trust)."""
        norm_title = title.strip().casefold()
        name_matches = [
            c for c in candidates
            if norm_title in {
                (c.get("name") or "").strip().casefold(),
                (c.get("russian") or "").strip().casefold(),
            }
        ]
        if not name_matches:
            return None
        if year:
            for c in name_matches:
                if cls._year_of(c) == year:
                    return c
        return name_matches[0]

    async def anime_supplement(self, title: str, year: Optional[int] = None) -> Optional[dict]:
        """Looks up `title` (the item's own English/original anime title —
        callers pass result.item.title.en, not anything Shikimori-specific)
        on Shikimori and returns its Russian title/description/poster, or
        None when nothing on Shikimori looks like a confident match for
        it. `year` narrows down same-named franchise entries when we have
        one (see _pick_best_match above); passing None just means ties are
        broken by whichever candidate Shikimori's own search ranked first.

        Two requests: the search hit only carries a truncated/no
        description, so a second GET /animes/{id} fetches the full one.
        `poster.originalUrl` (Shikimori's largest size) is used over
        `poster.mainUrl`/`main2xUrl` — this app's poster tiles want the
        same "biggest available, let the client downscale" treatment as
        TMDB's w500 poster_url elsewhere.

        Returns None outright on any request failure or an empty search —
        this is a best-effort overlay, and a Shikimori hiccup should
        degrade to "just keep TMDB's/English text" exactly like every
        other optional TMDB call in this app degrades on its own failures."""
        if not title.strip():
            return None
        async with httpx.AsyncClient(
            timeout=8.0, headers={"User-Agent": SHIKIMORI_USER_AGENT}
        ) as client:
            try:
                candidates = await self._search(client, title)
            except httpx.HTTPError:
                return None
            match = self._pick_best_match(candidates, title, year)
            if not match or not match.get("id"):
                return None
            try:
                resp = await client.get(f"{SHIKIMORI_BASE}/animes/{match['id']}")
                if resp.status_code == 404:
                    return None
                resp.raise_for_status()
            except httpx.HTTPError:
                return None
        detail = resp.json()

        title_ru = (detail.get("russian") or "").strip() or None
        overview_ru = _clean_description(detail.get("description"))
        poster = detail.get("image") or {}
        poster_url = poster.get("original") or poster.get("preview") or None
        if poster_url and poster_url.startswith("/"):
            poster_url = f"https://shikimori.io{poster_url}"

        if not title_ru and not overview_ru and not poster_url:
            return None

        return {
            "title_ru": title_ru,
            "overview_ru": overview_ru,
            "poster_ru": poster_url,
        }


# ---------------------------------------------------------------------------
# Manga — a full catalog adapter (search/discover/named_collections/
# full_detail, the same MediaAdapter interface IGDB/Open Library implement),
# unlike ShikimoriAdapter above which is only ever a Russian-text overlay on
# top of TMDB. Manga used to ride Open Library's book catalog scoped to the
# "manga" subject (see app/adapters/open_library.py's module docstring for
# why AniList/MangaDex were both ruled out) — moved here instead because
# Shikimori's own /api/mangas is a real manga-specific catalog: native
# Russian titles/descriptions (no separate ru_supplement enrichment pass
# needed, unlike Open Library's "maybe a Russian edition happens to be
# indexed too"), plus status/volume/chapter counts Open Library's book
# records simply don't carry for a manga series.
# ---------------------------------------------------------------------------

# Shikimori's public API docs ask for no more than ~5 requests/second from
# one client — same "be a good citizen of a small community-run API"
# reasoning as Open Library's own _RateLimiter, just a looser cap since
# Shikimori's own published limit is looser than Open Library's.
_MANGA_RATE_LIMIT_PER_SEC = 5


class _MangaRateLimiter:
    def __init__(self, max_per_sec: int):
        self._max = max_per_sec
        self._lock = asyncio.Lock()
        self._call_times: list[float] = []

    async def wait(self) -> None:
        async with self._lock:
            now = time.monotonic()
            self._call_times = [t for t in self._call_times if now - t < 1.0]
            if len(self._call_times) >= self._max:
                sleep_for = 1.0 - (now - self._call_times[0])
                if sleep_for > 0:
                    await asyncio.sleep(sleep_for)
                now = time.monotonic()
                self._call_times = [t for t in self._call_times if now - t < 1.0]
            self._call_times.append(time.monotonic())


_manga_rate_limiter = _MangaRateLimiter(_MANGA_RATE_LIMIT_PER_SEC)

# Shikimori's `status` enum (anons/ongoing/released/paused/discontinued) ->
# a human-facing label for MediaItem.status, the same field TMDB fills with
# "Returning Series"/"Ended" for shows.
_MANGA_STATUS_LABELS = {
    "anons": "Announced",
    "ongoing": "Ongoing",
    "released": "Completed",
    "paused": "On Hiatus",
    "discontinued": "Discontinued",
}

# Shikimori's `kind` values that aren't the plain default "manga" — surfaced
# as the first genre-style chip so a manhwa/manhua/light novel doesn't read
# as an ordinary Japanese manga on the card. Nothing shown when kind is
# "manga" itself or unrecognized, same "only surface it when it's actually
# informative" reasoning as everywhere else genres get curated in this app.
_MANGA_KIND_LABELS = {
    "manhwa": "Manhwa",
    "manhua": "Manhua",
    "light_novel": "Light Novel",
    "novel": "Novel",
    "one_shot": "One-Shot",
    "doujin": "Doujin",
}

# Browse shelves for the Collections tab and GET /feed's discover pool —
# same "real data, not synthetic" approach as IGDB's _GENRE_SHELVES/Open
# Library's _BOOK_SHELVES, built from `order`/`status`/`kind` query params
# rather than genre ids (Shikimori's genre taxonomy isn't confidently known
# without hitting their /api/genres endpoint first, so this sticks to the
# params this adapter can already build correctly).
# (display_label_ru, display_label_en, query params) — `title` on the
# resulting Collection is always Russian, title_en the fallback, same
# "title always Russian" contract curated_franchises.py already follows
# (see schemas.Collection.title / mobile/lib/models/collection.dart::
# displayTitle).
_MANGA_SHELF_PARAMS: List[Tuple[str, str, dict]] = [
    ("Популярная манга", "Popular Manga", {"order": "popularity"}),
    ("Манга с высоким рейтингом", "Top Rated Manga", {"order": "ranked"}),
    ("Выходит сейчас", "Currently Ongoing", {"order": "popularity", "status": "ongoing"}),
    ("Завершённая манга", "Completed Manga", {"order": "popularity", "status": "released"}),
    ("Манхва и маньхуа", "Manhwa & Manhua", {"order": "popularity", "kind": "manhwa,manhua"}),
    ("Ваншоты", "One-Shots", {"order": "popularity", "kind": "one_shot"}),
]


def _manga_year(entry: dict) -> Optional[int]:
    date_str = entry.get("aired_on") or entry.get("released_on")
    return int(date_str[:4]) if date_str and len(date_str) >= 4 and date_str[:4].isdigit() else None


def _manga_poster(entry: dict) -> Optional[str]:
    image = entry.get("image") or {}
    url = image.get("original") or image.get("preview")
    if url and url.startswith("/"):
        url = f"https://shikimori.io{url}"
    return url


def _manga_genres(entry: dict) -> List[str]:
    kind_label = _MANGA_KIND_LABELS.get(entry.get("kind"))
    names = [
        g["name"] for g in entry.get("genres") or []
        if isinstance(g, dict) and g.get("name")
    ]
    return ([kind_label] if kind_label else []) + names


def _manga_publisher(entry: dict) -> Optional[str]:
    names = [
        p["name"] for p in entry.get("publishers") or []
        if isinstance(p, dict) and p.get("name")
    ][:3]
    return ", ".join(names) if names else None


def _normalize_manga(entry: dict) -> Optional[MediaItem]:
    """Shared by search/shelf/full_detail — search and shelf hits come off
    Shikimori's /mangas list endpoint (no `description`/`genres`/
    `publishers`, same "thin card, richer detail" tradeoff Open Library's
    own search results already had); full_detail's GET /mangas/{id}
    carries all of it, and calls this with that richer payload instead.
    """
    manga_id = entry.get("id")
    name = entry.get("name")
    if manga_id is None or not name:
        return None

    score = entry.get("score")
    try:
        # Shikimori's own score is already on a 0-10 scale (like MAL), no
        # rescaling needed here unlike Open Library's 1-5 ratings_average.
        rating10 = round(float(score), 1) if score else None
    except (TypeError, ValueError):
        rating10 = None

    return MediaItem(
        id=f"shikimanga-{manga_id}",
        media_type="manga",
        external_ids=ExternalIds(tmdb=None, imdb=None),
        title=LocalizedText(ru=(entry.get("russian") or None), en=name),
        description=LocalizedText(ru=None, en=None),
        poster_url=_manga_poster(entry),
        backdrop_url=None,
        year=_manga_year(entry),
        genres=_manga_genres(entry),
        rating=rating10,
        source="shikimori_manga",
        status=_MANGA_STATUS_LABELS.get(entry.get("status")),
        volumes=entry.get("volumes") or None,
        chapters=entry.get("chapters") or None,
        publisher=_manga_publisher(entry),
        tagline=(f"Published by {p}" if (p := _manga_publisher(entry)) else None),
    )


class ShikimoriMangaAdapter(MediaAdapter):
    """Manga's live catalog adapter — same MediaAdapter shape/contract
    IgdbAdapter and GoogleBooksAdapter already implement (search/discover/
    named_collections/full_detail), so it's a drop-in replacement for the
    manga-scoped book-catalog instance everywhere that used to be
    wired in (see app/routers/media.py and friends)."""

    source_name = "shikimori_manga"
    id_prefix = "shikimanga-"

    def __init__(self):
        # Detail-screen-only fallback for description.en — see
        # GoogleBooksAdapter.en_supplement's own docstring for why this is
        # needed at all (Shikimori's description text is Russian-only).
        self._google_books = GoogleBooksAdapter()

    def _client(self) -> httpx.AsyncClient:
        return httpx.AsyncClient(timeout=8.0, headers={"User-Agent": SHIKIMORI_USER_AGENT})

    async def _query(self, client: httpx.AsyncClient, params: dict) -> List[dict]:
        await _manga_rate_limiter.wait()
        try:
            resp = await client.get(f"{SHIKIMORI_BASE}/mangas", params=params)
            resp.raise_for_status()
            data = resp.json()
        except httpx.HTTPError as exc:
            status = getattr(getattr(exc, "response", None), "status_code", "?")
            logger.warning("Shikimori manga query failed [%s]: %s", status, exc)
            return []
        return data if isinstance(data, list) else []

    async def search(self, query: str) -> List[MediaItem]:
        if not query:
            return []
        async with self._client() as client:
            raw = await self._query(client, {"search": query, "limit": 20})
        return [item for r in raw if (item := _normalize_manga(r)) is not None]

    async def _shelf(self, client: httpx.AsyncClient, title_ru: str, title_en: str, params: dict) -> tuple:
        raw = await self._query(client, {**params, "limit": 40})
        items = [item for r in raw if (item := _normalize_manga(r)) is not None]
        return (title_ru, title_en, items)

    async def named_collections(self) -> List[tuple]:
        """Real Shikimori-backed shelves for the Collections tab — see
        _MANGA_SHELF_PARAMS. Same fan-out-concurrently, drop-what-fails
        pattern as IGDB's/Open Library's named_collections(). Returns
        [(title_ru, title_en, items)] — `title` on the resulting
        Collection is always the Russian label, title_en the fallback
        (see schemas.Collection.title)."""
        async with self._client() as client:
            results = await asyncio.gather(
                *[
                    self._shelf(client, title_ru, title_en, params)
                    for title_ru, title_en, params in _MANGA_SHELF_PARAMS
                ],
                return_exceptions=True,
            )
        return [r for r in results if isinstance(r, tuple) and r[2]]

    async def discover(self) -> List[MediaItem]:
        """A flat pool for GET /feed — reuses the shelves above and
        flattens them, de-duplicated by id (a title can legitimately
        appear on more than one shelf, e.g. a popular ongoing manhwa)."""
        shelves = await self.named_collections()
        seen: set = set()
        pool: List[MediaItem] = []
        for _title_ru, _title_en, items in shelves:
            for item in items:
                if item.id not in seen:
                    seen.add(item.id)
                    pool.append(item)
        return pool

    async def full_detail(self, raw_id: str) -> Optional[MediaItem]:
        async with self._client() as client:
            await _manga_rate_limiter.wait()
            try:
                resp = await client.get(f"{SHIKIMORI_BASE}/mangas/{raw_id}")
                if resp.status_code == 404:
                    return None
                resp.raise_for_status()
            except httpx.HTTPError as exc:
                status = getattr(getattr(exc, "response", None), "status_code", "?")
                logger.warning("Shikimori manga detail query failed [%s]: %s", status, exc)
                return None
            detail = resp.json()

        item = _normalize_manga(detail)
        if item is None:
            return None
        # The list endpoint above has neither of these — description is
        # Shikimori's own Russian community text (same field
        # anime_supplement() already treats as Russian, see its
        # docstring); this app has no English translation for it, so
        # description.en stays null and the client falls back to Russian
        # exactly like poster_url_ru/title_ru degrade elsewhere on this
        # model (see schemas.py's module docstring).
        item.description = LocalizedText(ru=_clean_description(detail.get("description")), en=None)

        # Best-effort English text, on the detail screen only (not
        # search/shelves — same "enrichment is a detail-screen-only cost"
        # convention app/adapters/steam.py's Russian game overlay already
        # follows). A miss here just leaves description.en null, same as
        # it already was before this existed — the client already falls
        # back to Russian in that case, so this can never make a manga
        # card worse than it already was, only sometimes better.
        try:
            description_en = await self._google_books.en_supplement(item.title.en or "")
        except Exception as exc:  # noqa: BLE001 — a detail screen should never break over this
            logger.warning("Google Books en enrichment failed [shikimanga-%s]: %s", raw_id, exc)
            description_en = None
        if description_en:
            item.description.en = description_en

        return item
