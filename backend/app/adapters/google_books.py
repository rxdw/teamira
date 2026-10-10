"""Books — search, browse, and detail, backed by the Google Books API
(developers.google.com/books). Free, no OAuth: a single API key on the
query string (not even a secret) is effectively required for real usage —
see the quota note below.
Get one at console.cloud.google.com: create a project, enable the
"Books API", then Credentials -> Create Credentials -> API key.

No client-credentials dance like IGDB/Twitch — every request is just:
    GET https://www.googleapis.com/books/v1/volumes?q=...&key=...

QUOTA WARNING: requests with no `key` at all draw from Google's *shared,
global, unauthenticated* pool — not a per-IP allowance the way this
module used to describe it. That pool gets drawn down by every
unkeyed caller of this API worldwide, not just this app's own traffic,
so it can (and in practice does) return 429 Too Many Requests at
essentially any volume, including light/testing traffic, with no
relationship to how many calls *this* deployment has made. A configured
key gets its own project-level quota instead (1,000 queries/day free,
raisable in the console) — set GOOGLE_BOOKS_API_KEY before relying on
this in anything beyond a quick local smoke test; without one, expect
intermittent 429s under normal use, not just "under real traffic".
`_query` below retries a 429 with a short backoff so an isolated hit
(keyed or not) doesn't fail an entire search, but no amount of retry
logic fixes a truly exhausted global pool — only a key does that.

Replaces app/adapters/open_library.py as the books/manga-detail-English
catalog (see git history for that module if it's ever needed again).
Chosen over Open Library for meaningfully better ru+en coverage in one
source — Google Books indexes real ru and en editions directly and
exposes both through `langRestrict` (see ru_supplement/en_supplement
below), rather than Open Library's catalog-skews-English-with-an-
occasional-Russian-edition-if-you're-lucky situation. Before shipping
this to anything that charges users, re-check Google Books' current API
Terms of Service for redistribution/monetization restrictions — Open
Library's own module docstring called this out as the reason it was
picked over Google Books originally, and that clause should be verified
against Google's live terms (not assumed from memory) before relying on
it commercially.
"""
import asyncio
import logging
import re
from typing import List, Optional, Tuple

import httpx

from app.config import settings
from app.schemas import MediaItem, ExternalIds, LocalizedText, TitleExtras, TitleCreator, TitleLink
from app.adapters.base import MediaAdapter

logger = logging.getLogger("seenly.adapters.google_books")

BOOKS_BASE = "https://www.googleapis.com/books/v1/volumes"

# Requested every call — averageRating/ratingsCount are what let us filter
# shelf results down to books that actually have a meaningful score,
# instead of every random self-published title Google indexes.
_FIELDS = (
    "items(id,volumeInfo(title,authors,description,categories,"
    "imageLinks,publishedDate,averageRating,ratingsCount,pageCount,language))"
)

_TAG_RE = re.compile(r"<[^>]+>")

# Subject-scoped shelves for the Collections tab — Google Books has no
# "top rated" browse endpoint like IGDB's sort=total_rating, so each shelf
# pulls a wider pool via keyword search and is ranked here (books with
# reader ratings first, then Google's own order), same "real data, filtered and ranked, not synthetic" approach as
# the IGDB genre shelves.
# (display_label_ru, display_label_en, subject query) — `title` on the
# resulting Collection is always Russian, title_en the fallback, same
# "title always Russian" contract curated_franchises.py already follows
# (see schemas.Collection.title / mobile/lib/models/collection.dart::
# displayTitle).
_SUBJECT_SHELVES = [
    ("Популярная художественная литература", "Popular Fiction", "fiction bestseller"),
    # Two queries, merged — see _shelf. "subject:science fiction" is the one
    # `subject:` form that still returns hits for a genre this broad.
    ("Фантастика и фэнтези", "Sci-Fi & Fantasy", ("subject:science fiction", "fantasy bestseller")),
    ("Детективы и триллеры", "Mystery & Thriller", ("mystery bestseller", "thriller bestseller")),
    ("Нон-фикшн", "Non-Fiction Picks", "nonfiction"),
    ("Биографии и мемуары", "Biographies & Memoirs", "biography bestseller"),
    ("Саморазвитие", "Self-Help & Growth", "subject:self-help"),
]

# Why these are plain keyword queries and not `subject:X` for every shelf:
# probed against the live API (see backend/check_books2.py) — `subject:fiction`,
# `subject:mystery`, `subject:thriller`, `subject:nonfiction`,
# `subject:biography` and `subject:fantasy` all return totalItems=0 now, while
# the same words as plain keywords return hundreds of hits. Only
# `subject:science fiction` and `subject:self-help` still work. Also: Google's
# rating data is essentially gone (not one hit in the probe had >=5 ratings),
# so shelves are no longer filtered on ratings — see _shelf.

# Lightweight fields for the ru_supplement/en_supplement lookups below —
# these are card-only overlays (title/description/cover), not a full
# detail fetch, so there's no reason to pull authors/categories/ratings
# for them (mirrors OpenLibraryAdapter.ru_supplement's own "search cards
# don't pay for detail-level calls" scoping).
_SUPPLEMENT_FIELDS = "items(id,volumeInfo(title,description,imageLinks))"


def _clean_description(raw: Optional[str]) -> Optional[str]:
    """Google's description field is HTML (<p>, <b>, <br> ...); strip tags
    for a plain-text synopsis matching what TMDB/IGDB already return."""
    if not raw:
        return None
    text = _TAG_RE.sub("", raw).replace("&nbsp;", " ").replace("&amp;", "&")
    return text.strip() or None


def _cover_url(image_links: Optional[dict]) -> Optional[str]:
    """Google returns http:// thumbnails at a small default zoom, plus a
    "page curl" decoration (edge=curl) meant for their own reader UI —
    upgraded to https, a bigger zoom, and stripped of the curl here."""
    if not image_links:
        return None
    raw = image_links.get("thumbnail") or image_links.get("smallThumbnail")
    if not raw:
        return None
    url = raw.replace("http://", "https://")
    url = url.replace("zoom=1", "zoom=2").replace("&edge=curl", "")
    return url


def _year(published_date: Optional[str]) -> Optional[int]:
    if not published_date:
        return None
    try:
        return int(published_date[:4])
    except ValueError:
        return None


def _reading_minutes(page_count: Optional[int]) -> Optional[int]:
    """A real (if approximate) per-book estimate from its actual page
    count, at ~1.2 min/page (roughly 250 wpm over a ~300-word page) —
    used for Wrapped hour totals when present; profile.py's flat 6h
    default for MediaType.book still covers books with no pageCount."""
    if not page_count or page_count <= 0:
        return None
    return round(page_count * 1.2)


_MAX_GENRES_PER_TITLE = 4


def _clean_categories(raw: Optional[List[str]]) -> List[str]:
    """Google's `categories` are BISAC-style strings like "Fiction /
    Fantasy / Epic" or "Juvenile Fiction / Action & Adventure / General"
    — a slash-separated path, not a flat tag list like Open Library's
    `subject`. Splitting on "/" and keeping each segment (deduped, "/
    General" trimmed since it's a BISAC catch-all rather than a real
    genre) gets close to the same small, pickable genre set the other
    adapters expose, without needing Open Library's keyword-matching
    table — BISAC's own vocabulary is already reasonably genre-shaped."""
    if not raw:
        return []
    seen: List[str] = []
    for entry in raw:
        for part in str(entry).split("/"):
            genre = part.strip()
            if not genre or genre.casefold() == "general":
                continue
            if genre not in seen:
                seen.append(genre)
            if len(seen) >= _MAX_GENRES_PER_TITLE:
                return seen
    return seen


def _normalize(volume_id: Optional[str], info: dict) -> Optional[MediaItem]:
    title = info.get("title")
    if not volume_id or not title:
        return None

    authors = info.get("authors") or []
    rating = info.get("averageRating")  # Google's own scale is 0-5
    rating10 = round(rating * 2, 1) if rating else None

    return MediaItem(
        id=f"gbooks-{volume_id}",
        media_type="book",
        external_ids=ExternalIds(tmdb=None, imdb=None),
        title=LocalizedText(ru=None, en=title),
        description=LocalizedText(ru=None, en=_clean_description(info.get("description"))),
        poster_url=_cover_url(info.get("imageLinks")),
        backdrop_url=None,  # no wide art from Google Books; UI falls back to the cover
        year=_year(info.get("publishedDate")),
        genres=_clean_categories(info.get("categories")),
        rating=rating10,
        # Reused as a free-text subtitle (see schemas.MediaItem.tagline) —
        # not shown anywhere yet, but the natural place for "by X, Y" until
        # the client grows a dedicated authors field.
        source="google_books",
        runtime_minutes=_reading_minutes(info.get("pageCount")),
        tagline=("By " + ", ".join(authors)) if authors else None,
    )


# ---------------------------------------------------------------------------
# Detail-screen enrichment. GET /volumes/{id} (no `fields` filter) already
# returns the whole record — publisher, page count, ISBNs, language, preview
# and sale links are all in it; the search-card normaliser just never read
# them, so a book's "facts" block was always empty.
# ---------------------------------------------------------------------------

MAX_MORE_BY_AUTHOR = 12
MAX_AUTHORS = 3


def _isbn(info: dict) -> Optional[str]:
    """volumeInfo.industryIdentifiers -> ISBN-13 if present, else ISBN-10."""
    found = {}
    for ident in info.get("industryIdentifiers") or []:
        if isinstance(ident, dict) and ident.get("type") in ("ISBN_13", "ISBN_10") and ident.get("identifier"):
            found[ident["type"]] = str(ident["identifier"]).replace("-", "")
    return found.get("ISBN_13") or found.get("ISBN_10")


def _book_links(volume: dict) -> List[TitleLink]:
    """A free sample and a store page when Google has them. `saleability`
    is FOR_SALE / FREE / NOT_FOR_SALE; a preview is only worth a link when
    some pages are actually viewable."""
    info = volume.get("volumeInfo") or {}
    access = volume.get("accessInfo") or {}
    sale = volume.get("saleInfo") or {}
    out: List[TitleLink] = []
    preview = info.get("previewLink")
    if preview and access.get("viewability") in ("PARTIAL", "ALL_PAGES"):
        out.append(TitleLink(kind="preview", label="Read a sample", url=preview))
    if sale.get("saleability") in ("FOR_SALE", "FREE") and sale.get("buyLink"):
        out.append(TitleLink(kind="buy", label="Google Play Books", url=sale["buyLink"]))
    info_link = info.get("infoLink")
    if info_link and not out:
        out.append(TitleLink(kind="other", label="Google Books", url=info_link))
    return out


def normalize_detail(volume: dict) -> Optional[MediaItem]:
    """A full /volumes/{id} record -> the card plus its extras (publisher,
    ISBN, pages, language, authors, links). Pure — unit-tested without the
    network."""
    info = volume.get("volumeInfo") or {}
    item = _normalize(volume.get("id"), info)
    if item is None:
        return None
    item.publisher = (info.get("publisher") or "").strip() or None
    item.isbn = _isbn(info)
    pages = info.get("pageCount")
    authors = [a for a in (info.get("authors") or []) if isinstance(a, str) and a.strip()]
    extras = TitleExtras(
        pages=int(pages) if isinstance(pages, int) and pages > 0 else None,
        published_date=(info.get("publishedDate") or "").strip() or None,
        subtitle=(info.get("subtitle") or "").strip() or None,
        book_language=(info.get("language") or "").strip().lower() or None,
        creators=[TitleCreator(name=a.strip(), role="Author") for a in authors[:MAX_AUTHORS]],
        links=_book_links(volume),
    )
    item.extras = extras
    return item


def _title_key(title: str) -> str:
    return re.sub(r"[\W_]+", "", (title or "").casefold())


def pick_more_by_author(rows: List[dict], exclude_id: str, exclude_title: str,
                        language: Optional[str]) -> List[MediaItem]:
    """`inauthor:` search rows -> other books by the same author. Skips the
    book itself and its other editions (same title), books without a cover,
    and — when the language is known — books in another language, so a
    Russian reader isn't offered the same novel's English edition. Most
    rated first: the popular ones are what "more by this author" should lead
    with. Pure."""
    own_key = _title_key(exclude_title)
    seen = {own_key}
    picked: List[Tuple[int, MediaItem]] = []
    for r in rows:
        info = r.get("volumeInfo") or {}
        if r.get("id") == exclude_id:
            continue
        if language and info.get("language") and info["language"] != language:
            continue
        item = _normalize(r.get("id"), info)
        if item is None or not item.poster_url:
            continue
        key = _title_key(item.title.en or "")
        if not key or key in seen:
            continue
        seen.add(key)
        picked.append((info.get("ratingsCount") or 0, item))
    picked.sort(key=lambda t: -t[0])
    return [it for _, it in picked[:MAX_MORE_BY_AUTHOR]]



class GoogleBooksAdapter(MediaAdapter):
    """Books' live catalog adapter. `id_prefix`/`media_type` are exposed
    as plain attributes (not just baked into `_normalize`'s f-string) so
    callers like app/routers/media.py's GET /media/detail dispatch can
    strip a media_id's prefix generically via `adapter.id_prefix`, the
    same convention OpenLibraryAdapter's constructor params established."""

    source_name = "google_books"
    id_prefix = "gbooks-"
    media_type = "book"

    def __init__(self):
        self.api_key = settings.google_books_api_key

    def _params(self, **extra) -> dict:
        params = {**extra}
        if self.api_key:
            params["key"] = self.api_key
        return params

    # A lone 429 is common enough with the unauthenticated global pool
    # (see the module docstring's quota warning) that treating every one
    # as a hard failure would make search flaky even for otherwise-normal
    # traffic. Two short retries smooth over a transient throttle without
    # holding up a user-facing search for long — this is not a substitute
    # for a configured key, just enough to stop one bad tick from
    # blanking out results that a half-second later would have worked.
    _RETRY_DELAYS_SEC = (0.5, 1.5)

    async def _get_with_retry(self, client: httpx.AsyncClient, url: str, params: dict):
        """Shared GET-with-429-retry behind both _query (search/shelves)
        and full_detail below — same reasoning either way (see
        _RETRY_DELAYS_SEC's comment), just two different endpoints/response
        shapes calling it. Returns the parsed JSON body on success, None on
        a failure that isn't worth retrying further."""
        for attempt, delay in enumerate((*self._RETRY_DELAYS_SEC, None)):
            try:
                resp = await client.get(url, params=params)
                resp.raise_for_status()
                return resp.json()
            except httpx.HTTPError as exc:
                status = getattr(getattr(exc, "response", None), "status_code", "?")
                if status == 429 and delay is not None:
                    logger.warning(
                        "Google Books query hit 429, retrying in %.1fs (attempt %d) [%s]",
                        delay, attempt + 1, url,
                    )
                    await asyncio.sleep(delay)
                    continue
                logger.warning("Google Books query failed [%s]: %s", status, exc)
                return None
        return None

    async def _query(self, params: dict) -> List[dict]:
        async with httpx.AsyncClient(timeout=8.0) as client:
            data = await self._get_with_retry(client, BOOKS_BASE, self._params(**params))
        return (data or {}).get("items") or []

    async def search(self, query: str) -> List[MediaItem]:
        if not query:
            return []
        raw = await self._query({
            "q": query,
            "maxResults": 20,
            "printType": "books",
            "fields": _FIELDS,
        })
        items = [
            item for r in raw
            if (item := _normalize(r.get("id"), r.get("volumeInfo") or {})) is not None
        ]
        if raw and not items:
            logger.warning("Google Books search %r: %d raw hits, none usable after normalising", query, len(raw))
        return items

    async def _language_supplement(self, title: str, lang: str) -> Optional[dict]:
        """Shared lookup behind ru_supplement/en_supplement below — same
        title text, restricted to a specific language edition via
        `langRestrict`. Unlike Open Library, Google Books actually
        indexes the language a volume is written in, so this is a direct
        filter rather than a fuzzy "search + hope one result happens to
        be Russian" pass — but the same same-work sanity check still
        applies, since `q=title:"..."` is a relevance match, not an exact
        one, and a short/common title can still pull back an unrelated
        same-language book that merely scored well.
        """
        if not title.strip():
            return None
        raw = await self._query({
            "q": f'intitle:"{title}"',
            "langRestrict": lang,
            "maxResults": 3,
            "printType": "books",
            "fields": _SUPPLEMENT_FIELDS,
        })
        needle = title.strip().casefold()
        for r in raw:
            info = r.get("volumeInfo") or {}
            candidate = (info.get("title") or "").strip()
            if not candidate:
                continue
            hay = candidate.casefold()
            if needle in hay or hay in needle:
                return {
                    "title": candidate if hay != needle else None,
                    "description": _clean_description(info.get("description")),
                    "poster": _cover_url(info.get("imageLinks")),
                }
        return None

    async def ru_supplement(self, title: str) -> Optional[dict]:
        """Best-effort Russian text for a book search card, filling in
        title.ru/description.ru/poster_url_ru — same role and return
        shape as OpenLibraryAdapter.ru_supplement (see
        app/routers/media.py::_enrich_books_with_ru, which calls this
        without caring which adapter it's talking to), but backed by a
        real `langRestrict=ru` filter instead of a title-only search that
        happens to sometimes land on a Russian record. Coverage is still
        not guaranteed — a genuinely separate ru edition has to actually
        be indexed by Google Books for this title — just meaningfully
        more likely to exist and to be matched correctly than under Open
        Library's catalog. Returns None on no match or a request failure.
        """
        supplement = await self._language_supplement(title, "ru")
        if not supplement:
            return None
        result = {
            "title_ru": supplement["title"],
            "description_ru": supplement["description"],
            "poster_ru": supplement["poster"],
        }
        return result if any(result.values()) else None

    async def en_supplement(self, title: str) -> Optional[str]:
        """Best-effort English description for a manga detail card — same
        role as OpenLibraryAdapter.en_supplement (see
        app/adapters/shikimori.py::ShikimoriMangaAdapter, whose own
        description text is Russian-only). Only the description comes
        back, same "just the one thing this source is actually better
        for" scope ru_supplement above keeps. Returns None on no match or
        a request failure.
        """
        supplement = await self._language_supplement(title, "en")
        return supplement["description"] if supplement else None

    async def _shelf(self, title_ru: str, title_en: str, subject_query) -> tuple:
        """`subject_query` is one query string or a tuple of them (results
        are merged, de-duplicated by volume id)."""
        queries = (subject_query,) if isinstance(subject_query, str) else tuple(subject_query)
        batches = await asyncio.gather(*[
            self._query({
                "q": q,
                "maxResults": 40,  # Google's per-request cap; it may still answer with fewer
                "printType": "books",
                "orderBy": "relevance",
                "fields": _FIELDS,
            })
            for q in queries
        ])
        raw: List[dict] = []
        seen_ids: set = set()
        for batch in batches:
            for r in batch:
                rid = r.get("id")
                if rid and rid not in seen_ids:
                    seen_ids.add(rid)
                    raw.append(r)

        # No ratings threshold any more (Google barely has ratings data now).
        # A book needs a cover to make a shelf; among those, ones that do have
        # reader ratings come first, and ties keep Google's own relevance order
        # (list.sort is stable, also with reverse=True).
        ranked = []
        no_cover = 0
        for r in raw:
            info = r.get("volumeInfo") or {}
            item = _normalize(r.get("id"), info)
            if item is None:
                continue
            if not item.poster_url:
                no_cover += 1
                continue
            ranked.append((info.get("ratingsCount") or 0, info.get("averageRating") or 0, item))
        ranked.sort(key=lambda t: (t[0], t[1]), reverse=True)
        candidates = [t[2] for t in ranked]

        # An empty shelf is dropped silently one level up (named_collections
        # filters on `r[2]`), so this is the only place that can say *why*:
        # raw=0 means Google returned nothing (or the request failed — look
        # for a "Google Books query failed" line just above); raw>0 with
        # kept=0 means every hit was unusable (no cover / no title).
        if not candidates:
            logger.warning(
                "Google Books shelf %r is empty: raw=%d, without cover=%d, q=%r",
                title_en, len(raw), no_cover, subject_query,
            )
        return (title_ru, title_en, candidates[:12])

    async def discover(self) -> List[MediaItem]:
        """A flat pool for GET /feed — there's no single "trending books"
        endpoint here, so this reuses the
        same subject shelves as named_collections() and flattens them,
        de-duplicated by id since a book can legitimately match more than
        one subject shelf (e.g. a mystery/thriller crossover)."""
        shelves = await self.named_collections()
        seen: set = set()
        pool: List[MediaItem] = []
        for _title_ru, _title_en, items in shelves:
            for item in items:
                if item.id not in seen:
                    seen.add(item.id)
                    pool.append(item)
        return pool

    async def named_collections(self) -> List[tuple]:
        """Subject-scoped shelves for the Collections tab — see
        _SUBJECT_SHELVES. Same fan-out-concurrently, drop-what-fails
        pattern as IGDB's named_collections(). Returns
        [(title_ru, title_en, items)] — `title` on the resulting
        Collection is always the Russian label, title_en the fallback
        (see schemas.Collection.title)."""
        results = await asyncio.gather(
            *[self._shelf(title_ru, title_en, q) for title_ru, title_en, q in _SUBJECT_SHELVES],
            return_exceptions=True,
        )
        for (_ru, title_en, _q), r in zip(_SUBJECT_SHELVES, results):
            if isinstance(r, BaseException):
                logger.warning("Google Books shelf %r raised %s: %s", title_en, type(r).__name__, r)
        built = [r for r in results if isinstance(r, tuple) and r[2]]
        if not built:
            logger.warning(
                "Google Books: 0 of %d shelves built — books will be missing from "
                "/feed/collections (that response is cached for up to 3h)",
                len(_SUBJECT_SHELVES),
            )
        return built

    async def isbns(self, raw_id: str) -> Optional[dict]:
        """{"isbn_13": ..., "isbn_10": ...} (either may be None) for one
        volume, or None when the lookup itself failed — so a caller can tell
        "this book has no ISBN" (cacheable) from "couldn't ask" (retry)."""
        async with httpx.AsyncClient(timeout=8.0) as client:
            data = await self._get_with_retry(
                client,
                f"{BOOKS_BASE}/{raw_id}",
                self._params(fields="volumeInfo(industryIdentifiers)"),
            )
        if data is None:
            return None
        found = {"isbn_13": None, "isbn_10": None}
        for ident in (data.get("volumeInfo") or {}).get("industryIdentifiers") or []:
            kind = (ident or {}).get("type")
            if kind in ("ISBN_13", "ISBN_10"):
                found[kind.lower()] = ident.get("identifier")
        return found

    async def full_detail(self, raw_id: str) -> Optional[MediaItem]:
        async with httpx.AsyncClient(timeout=8.0) as client:
            data = await self._get_with_retry(
                client, f"{BOOKS_BASE}/{raw_id}", self._params()
            )
        if data is None:
            return None
        return normalize_detail(data)

    async def more_by_author(self, author: str, exclude_id: str, exclude_title: str,
                             language: Optional[str]) -> List[MediaItem]:
        """Other books by `author`, for the "more from this author" shelf.
        Best-effort: any failure is just an empty shelf."""
        if not author:
            return []
        try:
            raw = await self._query({
                "q": f'inauthor:"{author}"',
                "maxResults": 30,
                "printType": "books",
                "orderBy": "relevance",
                "fields": _FIELDS,
            })
        except Exception as exc:  # noqa: BLE001
            logger.warning("Google Books more-by-author failed: %s", exc)
            return []
        return pick_more_by_author(raw, exclude_id, exclude_title, language)

    async def full_detail_bundle(self, raw_id: str) -> Optional[Tuple[MediaItem, List[MediaItem]]]:
        """(card with extras, more books by the same author)."""
        item = await self.full_detail(raw_id)
        if item is None:
            return None
        creators = item.extras.creators if item.extras else []
        language = item.extras.book_language if item.extras else None
        similar = await self.more_by_author(
            creators[0].name if creators else "", item.id[len(self.id_prefix):] if item.id.startswith(self.id_prefix) else raw_id,
            item.title.en or "", language,
        )
        return item, similar
