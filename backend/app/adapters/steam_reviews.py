"""Steam user reviews for a game — the written-review source for games.

Public, key-less endpoint of Valve's store: store.steampowered.com/appreviews/<appid>.
Unofficial in the sense that Valve documents it only loosely (partner docs:
partner.steamgames.com/doc/store/getreviews), but it is the same JSON the store
page itself uses and has been stable for years. Response shape verified against
a live answer (appid 1245620, language=russian): `query_summary` with
total_positive / total_negative, and `reviews[]` each with `author`
(steamid, personaname, avatar, playtime_forever in MINUTES), `review` text,
`voted_up`, `votes_up`, `timestamp_created` (unix seconds), `language`.

Two requests per never-seen game, both cached by app/game_reviews.py:
  1. language=all, num_per_page=1  -> the all-language positive/negative totals
     (the per-language request below only counts reviews in that language)
  2. language=<russian|english>    -> the review texts, most helpful first
     (Steam's default order for filter=all)

Same failure convention as ПоискКино/Hardcover: anything that means "couldn't
ask right now" raises SteamUnavailable (never cached); "this game has no
reviews" is a normal answer (SteamReviews with no reviews).
"""

import logging
import re
from datetime import datetime, timezone
from typing import List, Optional

import httpx
from pydantic import BaseModel

from app.adapters.quota_guard import QuotaGuard

logger = logging.getLogger("seenly.adapters.steam_reviews")

APPREVIEWS_URL = "https://store.steampowered.com/appreviews/{appid}"
APP_PAGE_URL = "https://store.steampowered.com/app/{appid}"
AVATAR_URL = "https://avatars.steamstatic.com/{hash}_full.jpg"
REVIEW_URL = "https://steamcommunity.com/profiles/{steamid}/recommended/{appid}/"

_TIMEOUT = httpx.Timeout(8.0, connect=4.0)
_USER_AGENT = "Seenly/1.0 (game reviews; steam attribution shown in-app)"

# Steam has no published limit for this endpoint; community reports put
# anonymous callers at roughly 200 requests / 5 minutes per IP. Two requests
# per cache miss, so a day budget well under that is a safety net, not a cap
# anyone should hit.
_DAILY_BUDGET = 3000
_PAUSE_NETWORK_SEC = 120
_PAUSE_RATE_LIMITED_SEC = 600

_guard = QuotaGuard(lambda: _DAILY_BUDGET)

# How many reviews we keep per game and language, how short is too short to
# be worth a card, and where a long one is cut (the card has "read more" for
# the rest of this, and the link opens the full text on Steam).
MAX_REVIEWS = 15
MIN_CHARS = 60
MAX_CHARS = 1800

_SPACES_RE = re.compile(r"[ \t]+")
_BLANKS_RE = re.compile(r"\n{3,}")
# Steam's own review markup: [h1]..[/h1], [b], [i], [url=...], [spoiler], etc.
_BBCODE_RE = re.compile(r"\[/?(?:h[1-3]|b|i|u|strike|spoiler|noparse|hr|quote(?:=[^\]]*)?|"
                        r"list|olist|\*|code|table|tr|td|th|url(?:=[^\]]*)?|img|previewyoutube(?:=[^\]]*)?)\]",
                        re.IGNORECASE)
_SPOILER_RE = re.compile(r"\[spoiler\].*?\[/spoiler\]", re.IGNORECASE | re.DOTALL)


class SteamUnavailable(Exception):
    """Couldn't get an answer right now (over budget, paused after an error,
    network failure, bad response). Distinct from "this game has no reviews"."""


class SteamReview(BaseModel):
    author: str
    avatar_url: Optional[str] = None
    content: str
    voted_up: bool
    votes_up: int = 0
    playtime_hours: Optional[float] = None
    created_at: Optional[datetime] = None
    url: str = ""


class SteamReviews(BaseModel):
    """What we keep per (game, language). `missing` is the cached "this game
    has no Steam store page / no reviews at all"."""
    missing: bool = False
    appid: Optional[str] = None
    total_positive: int = 0
    total_negative: int = 0
    reviews: List[SteamReview] = []

    @property
    def total(self) -> int:
        return self.total_positive + self.total_negative

    @property
    def positive_pct(self) -> Optional[int]:
        return round(100 * self.total_positive / self.total) if self.total else None


def clean_review_text(raw: Optional[str]) -> str:
    """Plain text for a card: spoiler blocks dropped, Steam markup stripped,
    whitespace tidied, cut at a word boundary if too long."""
    text = _SPOILER_RE.sub("", raw or "")
    text = _BBCODE_RE.sub("", text)
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = _SPACES_RE.sub(" ", text)
    text = _BLANKS_RE.sub("\n\n", text).strip()
    if len(text) > MAX_CHARS:
        cut = text[:MAX_CHARS]
        space = cut.rfind(" ")
        text = (cut[:space] if space > MAX_CHARS * 0.6 else cut).rstrip() + "…"
    return text


def _created(ts) -> Optional[datetime]:
    try:
        return datetime.fromtimestamp(int(ts), tz=timezone.utc)
    except (TypeError, ValueError, OverflowError, OSError):
        return None


def parse_reviews(appid: str, payload: dict) -> List[SteamReview]:
    out: List[SteamReview] = []
    for r in (payload.get("reviews") or []):
        if not isinstance(r, dict):
            continue
        if r.get("refunded"):
            continue
        content = clean_review_text(r.get("review"))
        if len(content) < MIN_CHARS:
            continue
        author = r.get("author") or {}
        steamid = author.get("steamid")
        avatar_hash = author.get("avatar")
        minutes = author.get("playtime_at_review") or author.get("playtime_forever")
        out.append(
            SteamReview(
                author=(author.get("personaname") or "").strip() or "Steam",
                avatar_url=AVATAR_URL.format(hash=avatar_hash) if avatar_hash else None,
                content=content,
                voted_up=bool(r.get("voted_up")),
                votes_up=int(r.get("votes_up") or 0),
                playtime_hours=round(minutes / 60, 1) if isinstance(minutes, (int, float)) and minutes > 0 else None,
                created_at=_created(r.get("timestamp_created")),
                url=REVIEW_URL.format(steamid=steamid, appid=appid) if steamid else APP_PAGE_URL.format(appid=appid),
            )
        )
        if len(out) >= MAX_REVIEWS:
            break
    return out


class SteamReviewsAdapter:
    source_name = "steam_reviews"

    async def _get(self, appid: str, params: dict) -> dict:
        if not _guard.allow():
            raise SteamUnavailable("paused or daily budget used up")
        _guard.spend()
        try:
            async with httpx.AsyncClient(timeout=_TIMEOUT, headers={"User-Agent": _USER_AGENT}) as client:
                resp = await client.get(APPREVIEWS_URL.format(appid=appid), params={"json": 1, **params})
        except httpx.HTTPError as exc:
            _guard.pause(_PAUSE_NETWORK_SEC)
            logger.warning("Steam reviews unreachable (%s), pausing %ss", type(exc).__name__, _PAUSE_NETWORK_SEC)
            raise SteamUnavailable("network error") from exc
        if resp.status_code == 429:
            _guard.pause(_PAUSE_RATE_LIMITED_SEC)
            logger.warning("Steam reviews 429 — pausing %ss", _PAUSE_RATE_LIMITED_SEC)
            raise SteamUnavailable("rate limited")
        if resp.status_code != 200:
            _guard.pause(_PAUSE_NETWORK_SEC)
            logger.warning("Steam reviews unexpected %s", resp.status_code)
            raise SteamUnavailable(f"unexpected status {resp.status_code}")
        try:
            data = resp.json()
        except ValueError as exc:
            raise SteamUnavailable("invalid JSON") from exc
        if not isinstance(data, dict):
            raise SteamUnavailable("unexpected payload")
        return data

    async def fetch(self, appid: str, lang: str) -> SteamReviews:
        """`lang` is "ru" or anything else (English). Raises SteamUnavailable
        when Steam can't be asked; a game with no reviews is a normal
        SteamReviews(missing=True)."""
        steam_lang = "russian" if lang == "ru" else "english"

        overall = await self._get(appid, {
            "language": "all", "filter": "all", "num_per_page": 1,
            "purchase_type": "all", "filter_offtopic_activity": 1,
        })
        if overall.get("success") != 1:
            return SteamReviews(missing=True, appid=appid)
        summary = overall.get("query_summary") or {}
        positive = int(summary.get("total_positive") or 0)
        negative = int(summary.get("total_negative") or 0)
        if positive + negative == 0:
            return SteamReviews(missing=True, appid=appid)

        texts = await self._get(appid, {
            "language": steam_lang, "filter": "all", "num_per_page": 40,
            "purchase_type": "all", "filter_offtopic_activity": 1,
        })
        return SteamReviews(
            appid=appid,
            total_positive=positive,
            total_negative=negative,
            reviews=parse_reviews(appid, texts) if texts.get("success") == 1 else [],
        )
