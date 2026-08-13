"""Books and manga — search, browse, and detail, both backed by the Open
Library API (openlibrary.org/developers/api). Free forever, no key/OAuth
of any kind, and — unlike Google Books — nothing in its terms restricts
charging users for the app that calls it. Run by the Internet Archive as
a public-good service.

Manga rides the same catalog rather than a manga-specific API on purpose:
AniList's terms explicitly forbid "Anime/Manga list/tracker services"
(exactly what Seenly's manga tab is) without a full AniList-account sync,
and MangaDex's Acceptable Usage Policy explicitly prohibits ads or paid
services on apps that use it — both conflict with a monetized personal
tracker. Open Library catalogs manga volumes as ordinary books (most have
ISBNs and get indexed like any other title), so `OpenLibraryAdapter`
below is instantiated twice — once for books, once for manga — each
scoped to different subjects and returning a different `media_type`, but
sharing every request/parsing helper. Coverage/grouping is a real
tradeoff (manga tends to be indexed per-volume rather than per-series, and
niche/newer series may be thin), but it comes with zero new ToS risk.

The tradeoff for "free forever, no key": Open Library explicitly asks
callers to self-identify. Unidentified requests are capped at ~1/sec;
requests that send a User-Agent with an app name *and* a contact email/
phone get a 3x allowance instead (openlibrary.org/developers/api). That's
the ADAPTER_CONTACT constant below — put a real address in there before
shipping, it's the difference between 1 req/sec and 3.

Open Library's own docs are explicit that this live API isn't meant as a
bulk data backend for high-traffic commercial infrastructure — for real
production scale (thousands of DAU hammering search), the documented path
is their free monthly data dump + your own local index, not this live API.
That's a bigger lift; this adapter is the right-sized version for getting
real book/manga data into the app now, and easy to swap later without
touching anything outside this file.
"""
import asyncio
import logging
import re
import time
from typing import List, Optional, Tuple

import httpx

from app.schemas import MediaItem, ExternalIds, LocalizedText
from app.adapters.base import MediaAdapter

logger = logging.getLogger("seenly.adapters.open_library")

SEARCH_URL = "https://openlibrary.org/search.json"
WORKS_URL = "https://openlibrary.org/works"
AUTHORS_URL = "https://openlibrary.org/authors"
COVERS_URL = "https://covers.openlibrary.org/b/id"

# Set this to a real contact (email or a project URL) before shipping —
# see the module docstring: this is what unlocks the 3x-vs-1x rate.
ADAPTER_CONTACT = "seenly-app (contact: set ADAPTER_CONTACT in open_library.py)"
_HEADERS = {"User-Agent": f"seenly/1.0 ({ADAPTER_CONTACT})"}

# Open Library caps an unidentified caller (see ADAPTER_CONTACT above) at
# ~1 req/sec process-wide, not per-endpoint — every _get() call below
# shares this one limiter, same pattern as IgdbAdapter's _RateLimiter in
# app/adapters/igdb.py and for the same reason. Without it,
# _enrich_books_with_ru (app/routers/media.py) alone can fan out up to
# _SEARCH_ENRICH_LIMIT=24 concurrent ru_supplement() calls for a single
# book/manga search that happens to match many volumes/editions (e.g.
# "One Piece" matching a dozen separate volume records) — 24x over the
# limit from one search, before any other caller even gets involved.
# Kept conservative at 1/sec rather than the 3x "identified" rate since
# ADAPTER_CONTACT above is still the unfilled placeholder.
_RATE_LIMIT_PER_SEC = 1


class _RateLimiter:
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


_rate_limiter = _RateLimiter(_RATE_LIMIT_PER_SEC)

_SEARCH_FIELDS = (
    "key,title,author_name,first_publish_year,cover_i,"
    "ratings_average,ratings_count,subject,number_of_pages_median,first_sentence"
)

# Subject-scoped shelves for the Collections tab. Open Library's subject
# tags are free-text (not a fixed enum like IGDB genre IDs), lowercase
# with underscores for multi-word subjects — these are the well-populated
# ones that consistently return enough rated work. Each entry is a full
# Solr query string (not just a bare subject name) so shelves can combine
# more than one subject filter, e.g. "manga action".
#
# Widened from 6 to 10 subjects — discover() below flattens every shelf
# into one pool for GET /feed, and more distinct subjects (not just a
# higher per-shelf cap) is what actually broadens genre coverage once
# the "can't decide?" flow filters that pool down by genre.
_BOOK_SHELVES: List[Tuple[str, str]] = [
    ("Popular Fiction", "subject:fiction"),
    ("Science Fiction & Fantasy", "subject:science_fiction"),
    ("Mystery & Thriller", "subject:mystery"),
    ("Non-Fiction Picks", "subject:nonfiction"),
    ("Biographies & Memoirs", "subject:biography"),
    ("Self-Help & Growth", "subject:self-help"),
    ("Horror", "subject:horror"),
    ("Romance", "subject:romance"),
    ("Young Adult", "subject:young_adult_fiction"),
    ("Graphic Novels & Comics", "subject:comics"),
]

# Manga is catalogued in Open Library as ordinary books tagged with the
# "manga" subject (and often also a genre subject alongside it) — so
# these shelves AND a second subject onto the base "manga" filter rather
# than using a dedicated manga taxonomy, which Open Library doesn't have.
_MANGA_SHELVES: List[Tuple[str, str]] = [
    ("Popular Manga", "subject:manga"),
    ("Shonen & Action", 'subject:manga subject:action'),
    ("Fantasy & Adventure Manga", "subject:manga subject:fantasy"),
    ("Romance Manga", "subject:manga subject:romance"),
    ("Horror & Thriller Manga", "subject:manga subject:horror"),
    ("Slice of Life Manga", 'subject:manga subject:"slice of life"'),
    ("Sci-Fi & Isekai Manga", "subject:manga subject:science_fiction"),
    ("Comedy Manga", "subject:manga subject:comedy"),
]

_MIN_RATINGS_COUNT = 3  # Open Library's rating counts run much lower than Google's

# Open Library's `subject` field is free-text tagging by whoever cataloged
# the work — not a fixed enum like TMDB's ~19 genre ids. A popular work's
# subject list can run into the hundreds ("Fiction", "Large type books",
# "Protected DAISY", "Fiction, general", "Nyt:trade-fiction-paperback",
# "Accessible book", ...), and even the ones that ARE genuine genre
# signal are wildly inconsistent in phrasing/casing/granularity across
# records. Dumping that raw list straight into the "can't decide?" genre
# step (mobile DecideFiltersScreen) meant books/manga alone could surface
# hundreds of distinct "genre" chips, most of them cataloging noise
# rather than anything a person would filter by — nothing like the
# curated, human-sized genre list movies/series get from TMDB.
#
# _curated_genres() below maps that noisy free text onto the SAME small,
# human-facing genre set _BOOK_SHELVES/_MANGA_SHELVES already use for
# named shelves, via keyword matching. Anything that matches nothing
# here is dropped rather than shown verbatim — it's cataloging metadata,
# not a genre a person picks a book by. Order matters: it's the display/
# match-priority order (checked top to bottom, first few matches kept),
# roughly broad-fiction-first then manga-flavored terms after, since a
# manga record often carries both "manga" and a genre subject and the
# genre is the more useful signal to surface first.
_GENRE_KEYWORDS: List[Tuple[str, List[str]]] = [
    ("Fantasy", ["fantasy"]),
    ("Science Fiction", ["science fiction", "sci-fi", "scifi", "space opera"]),
    ("Mystery & Thriller", ["mystery", "thriller", "detective", "suspense"]),
    ("Horror", ["horror", "ghost stories", "supernatural"]),
    ("Romance", ["romance", "love stories"]),
    ("Historical Fiction", ["historical fiction"]),
    ("Adventure", ["adventure"]),
    ("Young Adult", ["young adult", "juvenile fiction", "teen fiction"]),
    ("Comedy", ["humor", "humour", "comedy"]),
    ("Drama", ["drama"]),
    ("War & Military", ["war stories", "military"]),
    ("Crime", ["crime"]),
    ("Classics", ["classic literature", "classics"]),
    ("Poetry", ["poetry", "poems"]),
    ("Comics & Graphic Novels", ["comic", "graphic novel"]),
    ("Biography & Memoir", ["biography", "autobiograph", "memoir"]),
    ("Self-Help", ["self-help", "self help", "personal growth"]),
    ("History", ["world history", "history"]),
    ("Non-Fiction", ["nonfiction", "non-fiction"]),
    # Manga-flavored subjects Open Library carries alongside "manga" on
    # the same record — same shape as _MANGA_SHELVES' second subject.
    ("Slice of Life", ["slice of life"]),
    ("Isekai", ["isekai"]),
    ("Action", ["action"]),
]
# How many curated genres one title shows — plenty for a title to still
# read as "Fantasy, Adventure" rather than every loosely-related bucket
# its messy raw subject list happened to brush against.
_MAX_GENRES_PER_TITLE = 4


def _curated_genres(raw_subjects: List[str]) -> List[str]:
    """Raw Open Library `subject`/`subjects` list -> a short list of
    genres drawn from _GENRE_KEYWORDS, so books/manga expose the same
    kind of small, pickable genre set movies/series do (see
    _GENRE_KEYWORDS' docstring for why the raw field can't be used
    as-is). Looks at every subject the record has, not just the first
    few — some records front-load cataloging noise ("Accessible book",
    "Large type books") ahead of the actual genre tags."""
    if not raw_subjects:
        return []
    haystack = " | ".join(s.lower() for s in raw_subjects)
    matched: List[str] = []
    for genre, keywords in _GENRE_KEYWORDS:
        if any(kw in haystack for kw in keywords):
            matched.append(genre)
            if len(matched) >= _MAX_GENRES_PER_TITLE:
                break
    return matched


def _cover_url(cover_i: Optional[int]) -> Optional[str]:
    if not cover_i:
        return None
    return f"{COVERS_URL}/{cover_i}-L.jpg"


_MD_LINK_RE = re.compile(r"\[([^\]]+)\]\([^)]+\)")  # [text](url) -> text
_MD_BULLET_RE = re.compile(r"^[ \t]*[-*][ \t]+", re.MULTILINE)  # "- item" -> "item"
_MD_HEADER_RE = re.compile(r"^#{1,6}[ \t]+", re.MULTILINE)  # "## Heading" -> "Heading"
_MD_EMPHASIS_RE = re.compile(r"(\*\*|__|\*|_)(.+?)\1")  # **bold**/*italic* -> bare text


def _strip_markdown(text: str) -> str:
    """Open Library work descriptions are free-text Markdown written by
    volunteers — sometimes plain prose, sometimes a bulleted "Contains: -
    Animal Farm - Nineteen Eighty-Four" list with links, since the same
    field is reused for omnibus/boxset records. The app has no Markdown
    renderer for synopsis text, so this flattens it to plain prose instead
    of showing raw `[text](url)` / `- ` syntax to the user."""
    text = _MD_LINK_RE.sub(r"\1", text)
    text = _MD_BULLET_RE.sub("", text)
    text = _MD_HEADER_RE.sub("", text)
    text = _MD_EMPHASIS_RE.sub(r"\2", text)
    # Collapse the bullet-list line breaks into a comma-joined line rather
    # than leaving bare newlines, which the UI would render as one run-on
    # paragraph anyway.
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    return ", ".join(lines) if len(lines) > 1 else (lines[0] if lines else "")


def _description_text(raw) -> Optional[str]:
    """Open Library's `description` is either a plain string or a
    {"type": "/type/text", "value": "..."} dict — same field, two shapes,
    depending on how that particular work record was authored."""
    if raw is None:
        return None
    value = raw.get("value") if isinstance(raw, dict) else str(raw)
    if not value:
        return None
    cleaned = _strip_markdown(value.strip())
    return cleaned or None


def _reading_minutes(page_count: Optional[int]) -> Optional[int]:
    """A rough per-book estimate from the actual page count, at ~1.2
    min/page (roughly 250 wpm over a ~300-word page) — feeds Wrapped's
    hour totals. Not shown as "X min" in the title screen's meta line
    (that would read as nonsense next to a book) — see certification
    below for the page-count badge that *is* shown there."""
    if not page_count or page_count <= 0:
        return None
    return round(page_count * 1.2)


def _first_sentence(raw) -> Optional[str]:
    """Open Library's `first_sentence` search field is a plain string on
    some records and a one-item-per-language list on others. Used as a
    synopsis fallback when a work has no `description` at all (common —
    see the module docstring), since a real opening line beats nothing."""
    if not raw:
        return None
    if isinstance(raw, list):
        raw = raw[0] if raw else None
    if not raw:
        return None
    return str(raw).strip() or None


def _page_badge(page_count: Optional[int]) -> Optional[str]:
    return f"{page_count} pages" if page_count else None


def _normalize(doc: dict, media_type: str, id_prefix: str, source: str) -> Optional[MediaItem]:
    key = doc.get("key")  # "/works/OL27448W"
    title = doc.get("title")
    if not key or not title:
        return None
    raw_id = key.split("/")[-1]  # "OL27448W"

    authors = doc.get("author_name") or []
    rating5 = doc.get("ratings_average")  # Open Library's own scale is 1-5
    rating10 = round(rating5 * 2, 1) if rating5 else None
    page_count = doc.get("number_of_pages_median")

    return MediaItem(
        id=f"{id_prefix}{raw_id}",
        media_type=media_type,
        external_ids=ExternalIds(tmdb=None, imdb=None),
        title=LocalizedText(ru=None, en=title),
        # Search results carry no real synopsis field — first_sentence is
        # the closest thing available here; full_detail() may still
        # replace this with the work's actual description, if it has one.
        description=LocalizedText(ru=None, en=_first_sentence(doc.get("first_sentence"))),
        poster_url=_cover_url(doc.get("cover_i")),
        backdrop_url=None,
        year=doc.get("first_publish_year"),
        genres=_curated_genres(doc.get("subject") or []),
        rating=rating10,
        source=source,
        certification=_page_badge(page_count),
        runtime_minutes=_reading_minutes(page_count),
        tagline=("By " + ", ".join(authors[:3])) if authors else None,
    )


class OpenLibraryAdapter(MediaAdapter):
    """Two instances of this live in the app: one for books, one for
    manga (see the module docstring for why manga rides the same catalog
    instead of a manga-specific API). `media_type`/`id_prefix`/`source`
    tag every MediaItem this instance returns; `shelves` and
    `search_filter` scope which subset of Open Library's catalog it
    draws from."""

    def __init__(
        self,
        media_type: str = "book",
        id_prefix: str = "ol-",
        source: str = "open_library",
        shelves: Optional[List[Tuple[str, str]]] = None,
        search_filter: Optional[str] = None,
    ):
        self.media_type = media_type
        self.id_prefix = id_prefix
        self.source_name = source
        self.shelves = shelves if shelves is not None else _BOOK_SHELVES
        # ANDed onto every free-text search query for this instance — e.g.
        # "subject:manga" so a manga-tab search for "naruto" doesn't also
        # surface an unrelated novel that happens to share the title.
        self.search_filter = search_filter

    def _normalize(self, doc: dict) -> Optional[MediaItem]:
        return _normalize(doc, self.media_type, self.id_prefix, self.source_name)

    async def _get(self, client: httpx.AsyncClient, url: str, params: dict) -> Optional[dict]:
        await _rate_limiter.wait()
        try:
            resp = await client.get(url, params=params)
            resp.raise_for_status()
            return resp.json()
        except httpx.HTTPError as exc:
            status = getattr(getattr(exc, "response", None), "status_code", "?")
            logger.warning("Open Library query failed [%s]: %s", status, exc)
            return None

    async def ru_supplement(self, title: str) -> Optional[dict]:
        """Best-effort Russian text for a book/manga search card — NOT a
        machine translation of the English record (Open Library has no
        such feature, unlike TMDB's per-language detail endpoint), but a
        *separate, actual Russian-language edition* of the same work,
        when Open Library happens to have one indexed. Matched purely by
        title text plus Open Library's own `language:rus` facet, so this
        is meaningfully less reliable than the TMDB overlay movies/series
        get: a false match (a same-titled but unrelated work) or, far
        more often, simply no match at all (Open Library's catalog skews
        English/Western; most books here have no Russian edition indexed
        at all) are both ordinary outcomes, not bugs. Callers already
        degrade to the English text in either case, same as any other
        TMDB-less item — see app/routers/media.py::_enrich_books_with_ru.

        Only `title`/`description`/`cover` come back (`first_sentence` on
        the ru doc, same synopsis source `_normalize` already uses for
        English cards — a real `description` needs a further
        /works/{id}.json call this cheap card-only lookup deliberately
        skips, matching the "search cards don't pay for detail-level
        calls" convention above). Returns None on no match, no key
        needed here (Open Library takes none), or a request failure.
        """
        if not title.strip():
            return None
        async with httpx.AsyncClient(timeout=8.0, headers=_HEADERS) as client:
            data = await self._get(client, SEARCH_URL, {
                "q": f'title:"{title}"',
                "language": "rus",
                "limit": 3,
                "fields": _SEARCH_FIELDS,
            })
        docs = (data or {}).get("docs") or []
        # Cheap same-work sanity check: require the candidate's own title
        # to actually contain (or be contained by) the title we searched
        # for — Solr's title: query is a relevance match, not an exact
        # one, so without this a short/common title could pull back an
        # unrelated Russian-catalog book that merely scored well.
        needle = title.strip().casefold()
        for doc in docs:
            candidate = (doc.get("title") or "").strip()
            if not candidate:
                continue
            hay = candidate.casefold()
            if needle in hay or hay in needle:
                supplement = {
                    "title_ru": candidate if hay != needle else None,
                    "description_ru": _first_sentence(doc.get("first_sentence")),
                    "poster_ru": _cover_url(doc.get("cover_i")),
                }
                if any(supplement.values()):
                    return supplement
                return None
        return None

    async def search(self, query: str) -> List[MediaItem]:
        if not query:
            return []
        q = f"{query} {self.search_filter}" if self.search_filter else query
        async with httpx.AsyncClient(timeout=8.0, headers=_HEADERS) as client:
            data = await self._get(client, SEARCH_URL, {
                "q": q,
                "limit": 20,
                "fields": _SEARCH_FIELDS,
            })
        docs = (data or {}).get("docs") or []
        return [item for d in docs if (item := self._normalize(d)) is not None]

    async def _shelf(self, client: httpx.AsyncClient, title: str, query: str) -> tuple:
        data = await self._get(client, SEARCH_URL, {
            "q": query,
            "limit": 200,  # over-fetch a pool, then rank/trim below — same shape as the other adapters
            "fields": _SEARCH_FIELDS,
        })
        docs = (data or {}).get("docs") or []
        candidates = []
        for d in docs:
            if (d.get("ratings_count") or 0) < _MIN_RATINGS_COUNT:
                continue
            item = self._normalize(d)
            if item is not None:
                candidates.append(item)
        candidates.sort(key=lambda m: m.rating or 0, reverse=True)
        # Was capped at 12, then 30 — discover() below flattens every
        # shelf into one pool for GET /feed, which the "can't decide?"
        # flow then narrows by type, then genre, then decade. Raised
        # again to 50 (now against a 200-result over-fetch instead of
        # 100, so there's still real signal behind the extra results,
        # not padding) — combined with going from 6 to 10 shelves above,
        # this pushes the flattened pool from ~72 to as much as ~500
        # raw hits per type before dedup.
        return (title, candidates[:50])


    async def named_collections(self) -> List[tuple]:
        """Subject-scoped shelves for the Collections tab — same
        fan-out-concurrently, drop-what-fails pattern as the other
        adapters. One shared client so every shelf's request reuses the
        same connection instead of opening six each time."""
        async with httpx.AsyncClient(timeout=8.0, headers=_HEADERS) as client:
            results = await asyncio.gather(
                *[self._shelf(client, title, query) for title, query in self.shelves],
                return_exceptions=True,
            )
        return [r for r in results if isinstance(r, tuple) and r[1]]

    async def discover(self) -> List[MediaItem]:
        """A flat pool for GET /feed — reuses the subject shelves and
        flattens them, de-duplicated by id (a title can legitimately match
        more than one shelf)."""
        shelves = await self.named_collections()
        seen: set = set()
        pool: List[MediaItem] = []
        for _title, items in shelves:
            for item in items:
                if item.id not in seen:
                    seen.add(item.id)
                    pool.append(item)
        return pool

    async def full_detail(self, raw_id: str) -> Optional[MediaItem]:
        async with httpx.AsyncClient(timeout=8.0, headers=_HEADERS) as client:
            work = await self._get(client, f"{WORKS_URL}/{raw_id}.json", {})
            if work is None:
                return None

            # /works/{id}.json alone has no year, rating, or page count —
            # those only live in the search/Solr index, not the work
            # record itself (see _normalize's comments for the same
            # split). A title search finds this work's search-index doc;
            # matched by key rather than trusting an exact `q=key:...`
            # query, since Open Library's own docs show the indexed key
            # format ("/works/OLxxxW" vs bare "OLxxxW") inconsistently
            # across API versions — matching after the fact sidesteps that.
            title = work.get("title")
            enrich_doc: dict = {}
            if title:
                enrich = await self._get(client, SEARCH_URL, {
                    "q": f'title:"{title}"',
                    "limit": 5,
                    "fields": "key,first_publish_year,ratings_average,ratings_count,"
                              "number_of_pages_median,first_sentence",
                })
                for d in (enrich or {}).get("docs") or []:
                    if (d.get("key") or "").endswith(raw_id):
                        enrich_doc = d
                        break

            author_keys = [
                a["author"]["key"].split("/")[-1]
                for a in (work.get("authors") or [])
                if isinstance(a, dict) and a.get("author", {}).get("key")
            ][:3]
            author_names: List[str] = []
            if author_keys:
                author_docs = await asyncio.gather(
                    *[self._get(client, f"{AUTHORS_URL}/{ak}.json", {}) for ak in author_keys],
                    return_exceptions=True,
                )
                author_names = [
                    d["name"] for d in author_docs
                    if isinstance(d, dict) and d.get("name")
                ]

        if not title:
            return None
        covers = work.get("covers") or []
        cover_i = covers[0] if covers else None

        rating5 = enrich_doc.get("ratings_average")
        page_count = enrich_doc.get("number_of_pages_median")
        # A real synopsis beats the opening-line fallback when we have one.
        description = _description_text(work.get("description")) or _first_sentence(
            enrich_doc.get("first_sentence")
        )

        return MediaItem(
            id=f"{self.id_prefix}{raw_id}",
            media_type=self.media_type,
            external_ids=ExternalIds(tmdb=None, imdb=None),
            title=LocalizedText(ru=None, en=title),
            description=LocalizedText(ru=None, en=description),
            poster_url=_cover_url(cover_i),
            backdrop_url=None,
            year=enrich_doc.get("first_publish_year"),
            genres=_curated_genres(work.get("subjects") or []),
            rating=round(rating5 * 2, 1) if rating5 else None,
            source=self.source_name,
            certification=_page_badge(page_count),
            runtime_minutes=_reading_minutes(page_count),
            tagline=("By " + ", ".join(author_names)) if author_names else None,
        )
