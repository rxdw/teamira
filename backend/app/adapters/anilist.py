"""AniList (anilist.co) — written reviews and the community score for a manga.

Why AniList and not Jikan/MyAnimeList: Jikan is unreachable from Russian
networks (TLS handshake hangs — seen from a Russian home connection), and
AniList answers there. It is also key-less and free.

GraphQL, one endpoint: https://graphql.anilist.co. A title is found by its
MyAnimeList id, which is the same number as the Shikimori id this app already
uses for manga (`shikimanga-<id>`), so there is nothing to match:

    Media(idMal: $mal, type: MANGA) {
        id meanScore siteUrl
        reviews(limit: 8, sort: RATING_DESC) {
            nodes { summary score rating ratingAmount siteUrl createdAt body user { name avatar { medium } } }
        }
    }

Verified against a live answer (idMal 2): `score` is 0-100, `rating` is how
many readers found the review helpful out of `ratingAmount` votes, `body` is
markdown-ish text that can be tens of thousands of characters (the three
reviews of Berserk were ~75 KB each) — hence the cleaning and the cut below.
AniList reviews are mostly English; there is no language filter.

Rate limit: 90 requests/minute (temporarily lowered to 30 at times), shown in
X-RateLimit-* headers; 429 carries Retry-After. One request per never-seen
manga, cached for weeks (app/manga_reviews.py).

Same failure convention as the other optional sources: "couldn't ask" raises
AniListUnavailable and is never cached; "AniList has no such manga" is
AniListManga(missing=True).
"""

import logging
import re
from datetime import datetime, timezone
from typing import List, Optional

import httpx
from pydantic import BaseModel

from app.adapters.quota_guard import QuotaGuard
from app.schemas import TitleLink, TitleTag

logger = logging.getLogger("seenly.adapters.anilist")

ANILIST_URL = "https://graphql.anilist.co"
_TIMEOUT = httpx.Timeout(10.0, connect=4.0)
_USER_AGENT = "Seenly/1.0 (manga reviews; anilist attribution shown in-app)"

_DAILY_BUDGET = 2000
_PAUSE_NETWORK_SEC = 120
_MAX_RETRY_AFTER_SEC = 900

_guard = QuotaGuard(lambda: _DAILY_BUDGET)

# Reviews asked for, kept, and the shortest/longest text worth a card.
FETCH_REVIEWS = 8
MAX_REVIEWS = 6
MIN_CHARS = 80
MAX_CHARS = 1800

_QUERY = """
query ($mal: Int) {
  Media(idMal: $mal, type: MANGA) {
    id
    meanScore
    siteUrl
    reviews(limit: %d, sort: RATING_DESC) {
      nodes {
        summary
        score
        rating
        ratingAmount
        siteUrl
        createdAt
        body(asHtml: false)
        user { name avatar { medium } }
      }
    }
  }
}
""" % FETCH_REVIEWS

# AniList review markup: ~!spoiler!~, ~~~img(url)~~~, img(url) / webm(url) /
# youtube(id) lines, ___bold___ / __bold__ / **bold** / _italic_, # headings,
# --- rules, [text](url) links, ~~~ blocks, `>` quotes.
_SPOILER_RE = re.compile(r"~!.*?!~", re.DOTALL)
_MEDIA_RE = re.compile(r"(?:img|webm|youtube)\d*\([^)]*\)", re.IGNORECASE)
_LINK_RE = re.compile(r"\[([^\]]*)\]\([^)]*\)")
_HEADING_RE = re.compile(r"^\s{0,3}#{1,6}\s*", re.MULTILINE)
_QUOTE_RE = re.compile(r"^\s*>\s?", re.MULTILINE)
_RULE_RE = re.compile(r"^\s*(?:-{3,}|_{3,}|\*{3,})\s*$", re.MULTILINE)
_EMPHASIS_RE = re.compile(r"(?:~{2,}|_{2,}|\*{1,3}|(?<!\w)_|_(?!\w))")
_SPACES_RE = re.compile(r"[ \t]+")
_BLANKS_RE = re.compile(r"\n{3,}")


class AniListUnavailable(Exception):
    """Couldn't get an answer right now (over budget, paused, network, bad
    response). Distinct from "AniList doesn't have this manga"."""


class AniListReview(BaseModel):
    author: str
    avatar_url: Optional[str] = None
    title: Optional[str] = None  # the reviewer's own one-line headline
    content: str
    score: Optional[float] = None  # 0-10 (AniList gives 0-100)
    helpful: int = 0  # readers who found it helpful
    created_at: Optional[datetime] = None
    url: str = ""


class AniListManga(BaseModel):
    """`missing=True` is the cached "AniList has no such manga"."""
    missing: bool = False
    score: Optional[float] = None  # community mean, 0-10 (AniList gives 0-100)
    url: Optional[str] = None
    reviews: List[AniListReview] = []


# ---------------------------------------------------------------------------
# The "passport" of a title (tags with weights, popularity, banner, where to
# read legally, source material). A SEPARATE query and a separate cache row
# from the reviews above on purpose: the reviews query is verified against
# live answers, this one was written from the documentation — if AniList ever
# rejects one of its fields, only these extras go missing, never the reviews.
# ---------------------------------------------------------------------------

_INFO_QUERY = """
query ($mal: Int, $type: MediaType) {
  Media(idMal: $mal, type: $type) {
    id
    siteUrl
    bannerImage
    countryOfOrigin
    source
    popularity
    favourites
    tags { name rank isMediaSpoiler isGeneralSpoiler }
    externalLinks { site url type isDisabled }
  }
}
"""

MAX_TAGS = 8
MIN_TAG_RANK = 30
MAX_LINKS = 5

# AniList's `source` enum -> the label the client translates.
_SOURCE_LABELS = {
    "ORIGINAL": "Original", "MANGA": "Manga", "LIGHT_NOVEL": "Light novel",
    "NOVEL": "Novel", "WEB_NOVEL": "Web novel", "VISUAL_NOVEL": "Visual novel",
    "VIDEO_GAME": "Video game", "GAME": "Video game", "DOUJINSHI": "Doujinshi",
    "COMIC": "Comic", "LIVE_ACTION": "Live action", "ANIME": "Anime",
}
# AniList countryOfOrigin (ISO 3166-1 alpha-2) -> the language code the
# client already understands for TitleExtras.original_language.
_COUNTRY_LANG = {"JP": "ja", "KR": "ko", "CN": "zh", "TW": "zh"}


class AniListInfo(BaseModel):
    """`missing=True` is the cached "AniList has no such title"."""
    missing: bool = False
    url: Optional[str] = None
    banner: Optional[str] = None
    language: Optional[str] = None
    source: Optional[str] = None
    popularity: Optional[int] = None
    favourites: Optional[int] = None
    tags: List[TitleTag] = []
    links: List[TitleLink] = []


def parse_info(media: Optional[dict], *, with_links: bool) -> AniListInfo:
    """One `Media` object -> AniListInfo. Pure, so it's unit-tested. Spoiler
    tags are dropped (the card has no per-tag spoiler veil); only tags the
    community agrees on (rank >= MIN_TAG_RANK) are kept, strongest first.
    Links are only kept for manga, and only legal places to read or the
    official site — this is not a link farm."""
    if not media:
        return AniListInfo(missing=True)
    tags = []
    for t in media.get("tags") or []:
        if not isinstance(t, dict) or not t.get("name"):
            continue
        if t.get("isMediaSpoiler") or t.get("isGeneralSpoiler"):
            continue
        rank = t.get("rank")
        if not isinstance(rank, (int, float)) or rank < MIN_TAG_RANK:
            continue
        tags.append(TitleTag(name=t["name"], rank=int(rank)))
    tags.sort(key=lambda t: -(t.rank or 0))

    links: List[TitleLink] = []
    if with_links:
        seen = set()
        for l in media.get("externalLinks") or []:
            if not isinstance(l, dict) or l.get("isDisabled"):
                continue
            url, site = (l.get("url") or "").strip(), (l.get("site") or "").strip()
            if not url.startswith("http") or not site or site.lower() in seen:
                continue
            if l.get("type") == "STREAMING":
                kind = "read"
            elif site.lower() in ("official site", "official website"):
                kind = "official"
            else:
                continue
            seen.add(site.lower())
            links.append(TitleLink(kind=kind, label="Official site" if kind == "official" else site, url=url))
        links.sort(key=lambda l: 0 if l.kind == "read" else 1)

    pop, fav = media.get("popularity"), media.get("favourites")
    return AniListInfo(
        url=media.get("siteUrl") or None,
        banner=media.get("bannerImage") or None,
        language=_COUNTRY_LANG.get((media.get("countryOfOrigin") or "").upper()),
        source=_SOURCE_LABELS.get(media.get("source")),
        popularity=int(pop) if isinstance(pop, (int, float)) and pop > 0 else None,
        favourites=int(fav) if isinstance(fav, (int, float)) and fav > 0 else None,
        tags=tags[:MAX_TAGS],
        links=links[:MAX_LINKS],
    )


def clean_review_text(raw: Optional[str]) -> str:
    """Plain text for a card. Spoiler blocks are dropped (the app has no
    per-review spoiler flag for this source, so they must not reach the
    screen), images/video lines and markdown marks are stripped, and the text
    is cut at a word boundary — AniList reviews can run to tens of thousands
    of characters."""
    text = _SPOILER_RE.sub("", raw or "")
    text = _MEDIA_RE.sub("", text)
    text = _LINK_RE.sub(r"\1", text)
    text = _HEADING_RE.sub("", text)
    text = _QUOTE_RE.sub("", text)
    text = _RULE_RE.sub("", text)
    text = _EMPHASIS_RE.sub("", text)
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = "\n".join(line.strip() for line in text.split("\n"))
    text = _SPACES_RE.sub(" ", text)
    text = _BLANKS_RE.sub("\n\n", text).strip()
    if len(text) > MAX_CHARS:
        cut = text[:MAX_CHARS]
        space = cut.rfind(" ")
        text = (cut[:space] if space > MAX_CHARS * 0.6 else cut).rstrip() + "…"
    return text


def _score10(value) -> Optional[float]:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return round(number / 10, 1) if number > 0 else None


def _created(ts) -> Optional[datetime]:
    try:
        return datetime.fromtimestamp(int(ts), tz=timezone.utc)
    except (TypeError, ValueError, OverflowError, OSError):
        return None


def parse_manga(media: Optional[dict]) -> AniListManga:
    if not media:
        return AniListManga(missing=True)
    reviews: List[AniListReview] = []
    nodes = ((media.get("reviews") or {}).get("nodes")) or []
    for n in nodes:
        if not isinstance(n, dict):
            continue
        content = clean_review_text(n.get("body"))
        if len(content) < MIN_CHARS:
            continue
        user = n.get("user") or {}
        summary = clean_review_text(n.get("summary")).replace("\n", " ").strip()
        # Reviewers often repeat their headline as the first line of the
        # body; the card shows the headline on its own, so drop the echo.
        if summary and content.lower().startswith(summary.lower()):
            content = content[len(summary):].lstrip()
        if len(content) < MIN_CHARS:
            continue
        reviews.append(
            AniListReview(
                author=(user.get("name") or "").strip() or "AniList",
                avatar_url=((user.get("avatar") or {}).get("medium")) or None,
                title=summary or None,
                content=content,
                score=_score10(n.get("score")),
                helpful=int(n.get("rating") or 0),
                created_at=_created(n.get("createdAt")),
                url=n.get("siteUrl") or "",
            )
        )
        if len(reviews) >= MAX_REVIEWS:
            break
    return AniListManga(
        score=_score10(media.get("meanScore")),
        url=media.get("siteUrl") or None,
        reviews=reviews,
    )


class AniListAdapter:
    source_name = "anilist"

    @staticmethod
    def _retry_after(resp: httpx.Response, default: float) -> float:
        try:
            return min(float(resp.headers.get("Retry-After", default)), _MAX_RETRY_AFTER_SEC)
        except (TypeError, ValueError):
            return default

    async def _post(self, query: str, variables: dict) -> Optional[dict]:
        """One GraphQL request -> the `Media` object, None when AniList
        answers "Not Found", AniListUnavailable when it couldn't be asked."""
        if not _guard.allow():
            raise AniListUnavailable("paused or daily budget used up")
        _guard.spend()
        try:
            async with httpx.AsyncClient(timeout=_TIMEOUT, headers={"User-Agent": _USER_AGENT}) as client:
                resp = await client.post(
                    ANILIST_URL,
                    json={"query": query, "variables": variables},
                    headers={"Accept": "application/json"},
                )
        except httpx.HTTPError as exc:
            _guard.pause(_PAUSE_NETWORK_SEC)
            logger.warning("AniList unreachable (%s), pausing %ss", type(exc).__name__, _PAUSE_NETWORK_SEC)
            raise AniListUnavailable("network error") from exc

        status = resp.status_code
        if status == 429:
            wait = self._retry_after(resp, 60)
            _guard.pause(wait)
            logger.warning("AniList 429 — pausing %ss", wait)
            raise AniListUnavailable("rate limited")
        if status == 404:
            # AniList answers a Media lookup that matches nothing with 404
            # and a GraphQL "Not Found." error — that is "no such title".
            return None
        if status in (500, 502, 503, 504, 408):
            _guard.pause(_PAUSE_NETWORK_SEC)
            logger.warning("AniList %s, pausing %ss", status, _PAUSE_NETWORK_SEC)
            raise AniListUnavailable(f"server error {status}")
        if status != 200:
            logger.warning("AniList unexpected %s", status)
            raise AniListUnavailable(f"unexpected status {status}")
        try:
            data = resp.json()
        except ValueError as exc:
            raise AniListUnavailable("invalid JSON") from exc
        if not isinstance(data, dict):
            raise AniListUnavailable("unexpected payload")
        if data.get("errors") and not (data.get("data") or {}).get("Media"):
            # A 200 carrying only GraphQL errors: either "Not Found" (fine)
            # or the query itself was rejected (a bug worth a loud log).
            messages = " ".join(str(e.get("message", "")) for e in data["errors"] if isinstance(e, dict))
            if "not found" not in messages.lower():
                logger.error("AniList rejected the query: %s", messages[:300])
                raise AniListUnavailable("query rejected")
        return (data.get("data") or {}).get("Media")

    async def manga(self, mal_id: int) -> AniListManga:
        """Everything for one manga in a single request. A manga AniList
        doesn't know is a normal answer (AniListManga(missing=True))."""
        return parse_manga(await self._post(_QUERY, {"mal": int(mal_id)}))

    async def info(self, mal_id: int, kind: str) -> AniListInfo:
        """The title's passport (tags, popularity, banner, links, source).
        `kind` is "manga" or "anime" — the MyAnimeList id space is separate
        for the two, so the type must be sent with it."""
        media_type = "ANIME" if kind == "anime" else "MANGA"
        media = await self._post(_INFO_QUERY, {"mal": int(mal_id), "type": media_type})
        return parse_info(media, with_links=(kind == "manga"))
