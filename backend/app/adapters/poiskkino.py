"""ПоискКино (poiskkino.dev) — Kinopoisk ratings and written reviews for
Russian-language users. Third review/rating source alongside TMDB and Trakt
(see app/kinopoisk.py for caching and app/routers/reviews.py for the merge).

Not an official Kinopoisk/Yandex API (there isn't a public one) — an
intermediary that mirrors Kinopoisk/IMDb/TMDB data. Treat it as something
that can disappear, throttle, or be unreachable from some networks without
warning: every failure here raises KpUnavailable, and callers just hide the
Kinopoisk bits for that request. Nothing else in the app depends on it.

Verified against the live API (v1.5):
    GET /v1.5/movie?externalId.tmdb=<id>&limit=5
        -> {"docs": [{"id", "isSeries", "rating": {"kp", "imdb"},
                      "votes": {"kp", "imdb"}, ...}]}
    GET /v1.5/review?movieId=<kp id>&limit=20
        -> {"docs": [{"id", "author", "title", "review", "type",
                      "userRating", "reviewLikes", "reviewDislikes",
                      "date", "createdAt"}], "hasNext", "next"}
Auth is an `X-API-KEY` header. The free tier is 200 requests/day, so this
module also keeps its own daily budget (see _Guard) — cheaper to stop
asking than to find out the key got blocked.

`userRating` comes back as 0 for reviewers who gave no score, so 0 is
treated as "no rating", not as a one-star review.
"""

import logging
import re
from datetime import datetime, timezone
from typing import List, Optional

import httpx
from pydantic import BaseModel

from app.adapters.quota_guard import QuotaGuard
from app.config import settings

logger = logging.getLogger("seenly.adapters.poiskkino")

POISKKINO_BASE = "https://api.poiskkino.dev"
API_VERSION = "v1.5"

# Short on purpose: this runs while the title screen is loading. A reset
# connection fails instantly (that's what an unreachable network looks
# like); a black-holed one must not hold the screen for long.
_TIMEOUT = httpx.Timeout(6.0, connect=3.0)

# How long to stop calling after a failure, so a down/blocked API costs
# the first caller a short wait instead of every caller.
_PAUSE_NETWORK_SEC = 120
_PAUSE_RATE_LIMITED_SEC = 900
_PAUSE_BAD_KEY_SEC = 3600

# Reviews fetched per title / kept after ranking. The API returns newest
# first; we pull a wider window and keep the most useful (liked) ones.
_REVIEWS_FETCH = 20
REVIEWS_KEEP = 8
_MIN_REVIEW_CHARS = 40
# Kinopoisk reviews run to several thousand characters. A card shows a
# fragment and links to the original — we don't mirror whole reviews.
MAX_REVIEW_CHARS = 1500

_BLANK_LINES_RE = re.compile(r"\n{3,}")


class KpUnavailable(Exception):
    """The source couldn't answer right now (not configured, over budget,
    paused after an error, network failure, bad response). Distinct from
    "answered, and the title isn't there", which is a normal result."""


class KpTitle(BaseModel):
    """What we keep from a /movie hit. `missing=True` is the cached
    "Kinopoisk doesn't know this TMDB id" answer."""
    missing: bool = False
    kp_id: Optional[int] = None
    is_series: bool = False
    # Release year (the API gives the year only) — decides how long this
    # title's cache entries live, see app/kinopoisk.py::is_recent.
    year: Optional[int] = None
    kp_rating: Optional[float] = None
    kp_votes: Optional[int] = None
    imdb_rating: Optional[float] = None
    imdb_votes: Optional[int] = None


class KpReview(BaseModel):
    id: int
    author: str
    title: Optional[str] = None
    text: str
    tone: Optional[str] = None  # "positive" | "negative" | "neutral"
    rating: Optional[float] = None  # reviewer's own 1-10, when they gave one
    likes: int = 0
    dislikes: int = 0
    created_at: Optional[datetime] = None


class KpReviews(BaseModel):
    reviews: List[KpReview]


_guard = QuotaGuard(lambda: settings.poiskkino_daily_budget)


def _positive_float(value) -> Optional[float]:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return round(number, 1) if number > 0 else None


def _positive_int(value) -> Optional[int]:
    try:
        number = int(value)
    except (TypeError, ValueError):
        return None
    return number if number > 0 else None


def parse_title(doc: dict) -> KpTitle:
    rating = doc.get("rating") or {}
    votes = doc.get("votes") or {}
    return KpTitle(
        kp_id=doc.get("id"),
        is_series=bool(doc.get("isSeries")),
        year=_positive_int(doc.get("year")),
        kp_rating=_positive_float(rating.get("kp")),
        kp_votes=_positive_int(votes.get("kp")),
        imdb_rating=_positive_float(rating.get("imdb")),
        imdb_votes=_positive_int(votes.get("imdb")),
    )


_TONES = {"позитивный": "positive", "негативный": "negative", "нейтральный": "neutral"}


def _parse_date(raw) -> Optional[datetime]:
    if not raw or not isinstance(raw, str):
        return None
    try:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def clean_text(raw: Optional[str]) -> str:
    text = (raw or "").replace("\r\n", "\n").replace("\r", "\n").strip()
    return _BLANK_LINES_RE.sub("\n\n", text)


def truncate(text: str, limit: int = MAX_REVIEW_CHARS) -> str:
    """Cut at a paragraph or sentence end when one is reasonably close to
    the limit, otherwise at a word — never mid-word — and mark the cut."""
    if len(text) <= limit:
        return text
    window = text[:limit]
    floor = int(limit * 0.6)
    for marker in ("\n\n", ". ", "! ", "? "):
        cut = window.rfind(marker)
        if cut >= floor:
            return window[: cut + (0 if marker == "\n\n" else 1)].rstrip() + "…"
    cut = window.rfind(" ")
    return (window[:cut] if cut >= floor else window).rstrip() + "…"


def parse_reviews(docs: List[dict]) -> List[KpReview]:
    """Cleaned, short-form-filtered reviews in API order (no ranking yet)."""
    out: List[KpReview] = []
    for doc in docs or []:
        text = clean_text(doc.get("review"))
        review_id = doc.get("id")
        if len(text) < _MIN_REVIEW_CHARS or not review_id:
            continue
        title = (doc.get("title") or "").strip() or None
        tone = _TONES.get(str(doc.get("type") or "").strip().lower())
        user_rating = _positive_float(doc.get("userRating"))
        out.append(
            KpReview(
                id=review_id,
                author=(doc.get("author") or "").strip() or "Аноним",
                title=title,
                text=truncate(text),
                tone=tone,
                rating=user_rating if user_rating and user_rating <= 10 else None,
                likes=_positive_int(doc.get("reviewLikes")) or 0,
                dislikes=_positive_int(doc.get("reviewDislikes")) or 0,
                created_at=_parse_date(doc.get("date")) or _parse_date(doc.get("createdAt")),
            )
        )
    return out


def rank_reviews(reviews: List[KpReview], keep: int = REVIEWS_KEEP) -> List[KpReview]:
    """Most useful first (likes minus dislikes), newer wins a tie."""
    def key(r: KpReview):
        ts = r.created_at.timestamp() if r.created_at else 0.0
        return (r.likes - r.dislikes, ts)

    return sorted(reviews, key=key, reverse=True)[:keep]


class PoiskKinoAdapter:
    source_name = "poiskkino"

    @staticmethod
    def configured() -> bool:
        return bool(settings.poiskkino_api_key)

    async def _get(self, path: str, params: dict) -> dict:
        if not self.configured():
            raise KpUnavailable("POISKKINO_API_KEY is not set")
        if not _guard.allow():
            raise KpUnavailable("paused or daily budget used up")
        _guard.spend()
        try:
            async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
                resp = await client.get(
                    f"{POISKKINO_BASE}/{API_VERSION}/{path}",
                    params=params,
                    headers={"X-API-KEY": settings.poiskkino_api_key, "Accept": "application/json"},
                )
        except httpx.HTTPError as exc:
            _guard.pause(_PAUSE_NETWORK_SEC)
            logger.warning("PoiskKino unreachable (%s), pausing %ss", type(exc).__name__, _PAUSE_NETWORK_SEC)
            raise KpUnavailable("network error") from exc

        status = resp.status_code
        if status == 429:
            _guard.pause(_PAUSE_RATE_LIMITED_SEC)
            logger.warning("PoiskKino 429 — limit hit, pausing %ss", _PAUSE_RATE_LIMITED_SEC)
            raise KpUnavailable("rate limited")
        if status in (401, 403):
            _guard.pause(_PAUSE_BAD_KEY_SEC)
            logger.error("PoiskKino rejected the API key (%s) — check POISKKINO_API_KEY", status)
            raise KpUnavailable("key rejected")
        if status >= 500:
            _guard.pause(_PAUSE_NETWORK_SEC)
            logger.warning("PoiskKino %s, pausing %ss", status, _PAUSE_NETWORK_SEC)
            raise KpUnavailable(f"server error {status}")
        if status != 200:
            logger.warning("PoiskKino unexpected %s for %s", status, path)
            raise KpUnavailable(f"unexpected status {status}")
        try:
            data = resp.json()
        except ValueError as exc:
            raise KpUnavailable("invalid JSON") from exc
        if not isinstance(data, dict):
            raise KpUnavailable("unexpected payload")
        return data

    async def find_title(self, tmdb_id: str, is_series: bool) -> KpTitle:
        """Match by TMDB id directly — no title search. TMDB numbers movies
        and shows in separate id spaces, so the same number can belong to
        both; `isSeries` picks the right one. Not found is a normal answer
        (KpTitle.missing), not an error."""
        data = await self._get("movie", {"externalId.tmdb": tmdb_id, "limit": 5})
        for doc in data.get("docs") or []:
            if doc.get("id") and bool(doc.get("isSeries")) == is_series:
                return parse_title(doc)
        return KpTitle(missing=True)

    async def reviews(self, kp_id: int) -> List[KpReview]:
        data = await self._get("review", {"movieId": kp_id, "limit": _REVIEWS_FETCH})
        return rank_reviews(parse_reviews(data.get("docs") or []))
