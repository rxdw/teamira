"""Steam store page facts for a game — price, Metacritic, supported languages,
screenshots, achievements, controller/cloud features.

Same Valve endpoint app/adapters/steam.py already uses for the Russian
description (store.steampowered.com/api/appdetails — unofficial, no key,
no published limit), asked once more for the parts that description call
throws away. Kept as its own module with the same failure convention as
steam_reviews.py / anilist.py:

    couldn't ask (budget, paused, network, bad answer) -> SteamUnavailable,
                                                          never cached
    Steam has nothing for this app                     -> SteamStore(missing=True),
                                                          cached for a while

Why a per-request, TTL-cached layer (app/game_store.py) instead of baking
this into the forever title-detail cache: a price that was true on the day
somebody first opened the game is a lie a week later. Prices and the
Metacritic score move, so this is refreshed every few days; the static
IGDB facts (languages, screenshots, time to beat ...) are what lives in the
forever cache.

Field shapes (verified against the community docs at
github.com/Revadike/InternalSteamWebAPI/wiki/Get-App-Details):
  price_overview   {currency, initial, final, discount_percent,
                    initial_formatted, final_formatted}
  is_free          bool
  metacritic       {score, url}
  achievements     {total, highlighted:[...]}
  categories       [{id, description}]
  supported_languages  HTML: 'English<strong>*</strong>, Russian, ...
                       <br><strong>*</strong>languages with full audio support'
  screenshots      [{id, path_thumbnail, path_full}]
  pc_requirements  {minimum: HTML, recommended: HTML}  — or [] when absent
  platforms        {windows, mac, linux}  (bools)

Steam Deck compatibility is a different (equally unofficial) endpoint:
  /saleaction/ajaxgetdeckappcompatibilityreport?nAppID=<id>
  -> {"success": 1, "results": {"resolved_category": 0..3, ...}}
  with 3 = Verified, 2 = Playable, 1 = Unsupported, 0 = not tested yet.
It is optional: the store facts are returned without it if it fails.
"""

import html as _html
import logging
import re
from typing import List, Optional

import httpx
from pydantic import BaseModel

from app.adapters.quota_guard import QuotaGuard
from app.adapters.steam_reviews import SteamUnavailable
from app.schemas import GameLanguage, SpecRow

logger = logging.getLogger("seenly.adapters.steam_store")

APPDETAILS_URL = "https://store.steampowered.com/api/appdetails"
DECK_URL = "https://store.steampowered.com/saleaction/ajaxgetdeckappcompatibilityreport"
_TIMEOUT = httpx.Timeout(8.0, connect=4.0)
_USER_AGENT = "Seenly/1.0 (game store facts; steam attribution shown in-app)"

_DAILY_BUDGET = 3000
_PAUSE_NETWORK_SEC = 120
_PAUSE_RATE_LIMITED_SEC = 600

_guard = QuotaGuard(lambda: _DAILY_BUDGET)

MAX_SCREENSHOTS = 10

# Steam category ids worth a chip. Everything else Steam lists (trading
# cards, workshop, family sharing ...) is noise on a title card. The names
# are the client's own translation keys, not Steam's localized text.
_FEATURE_BY_CATEGORY_ID = {
    28: "Full controller support",
    18: "Partial controller support",
    23: "Steam Cloud",
}

_TAG_RE = re.compile(r"<[^>]+>")


class SteamStore(BaseModel):
    """What we keep per (app, region). `missing` is the cached "Steam has no
    store page for this app" (delisted, region-locked, not a game)."""
    missing: bool = False
    appid: Optional[str] = None
    free_to_play: Optional[bool] = None
    price: Optional[str] = None
    price_discount_pct: Optional[int] = None
    metacritic: Optional[int] = None
    metacritic_url: Optional[str] = None
    achievements: Optional[int] = None
    features: List[str] = []
    languages: List[GameLanguage] = []
    screenshots: List[str] = []
    requirements_min: List[SpecRow] = []
    requirements_rec: List[SpecRow] = []
    platforms: List[str] = []
    deck: Optional[str] = None


def parse_languages(raw: Optional[str]) -> List[GameLanguage]:
    """Steam's `supported_languages` HTML -> structured languages. The
    asterisk marks full voice-over; Steam doesn't split interface from
    subtitles, so a language here is "interface" always and "audio" when
    starred (the trailing 'languages with full audio support' footnote is
    dropped first, it's after a <br>)."""
    if not raw:
        return []
    body = re.split(r"<br\s*/?>", raw, maxsplit=1, flags=re.IGNORECASE)[0]
    out: List[GameLanguage] = []
    seen = set()
    for part in body.split(","):
        audio = "*" in part
        name = _TAG_RE.sub("", part).replace("*", "").strip()
        if not name or name.lower() in seen:
            continue
        seen.add(name.lower())
        out.append(GameLanguage(name=name[:1].upper() + name[1:], interface=True, audio=audio))
    return out


def _clean_price(price: Optional[dict]) -> tuple:
    """(formatted price, discount %) from price_overview, or (None, None)."""
    if not isinstance(price, dict):
        return None, None
    final = price.get("final_formatted")
    if not final and isinstance(price.get("final"), (int, float)) and price.get("currency"):
        final = f"{price['final'] / 100:.2f} {price['currency']}"
    if not final:
        return None, None
    discount = price.get("discount_percent")
    return str(final).strip(), (int(discount) if isinstance(discount, (int, float)) and discount > 0 else None)


MAX_SPEC_ROWS = 10
MAX_SPEC_VALUE_CHARS = 200

# Steam's free-form requirement labels -> one canonical English name each, so
# the client can translate them. Anything not listed keeps the studio's own
# wording.
_SPEC_LABELS = {
    "os": "OS", "operating system": "OS",
    "processor": "Processor", "cpu": "Processor",
    "memory": "Memory", "ram": "Memory",
    "graphics": "Graphics", "video card": "Graphics", "gpu": "Graphics",
    "directx": "DirectX",
    "storage": "Storage", "hard drive": "Storage", "hard disk space": "Storage",
    "disk space": "Storage",
    "sound card": "Sound card",
    "network": "Network",
    "additional notes": "Additional notes",
}

_LI_RE = re.compile(r"<li[^>]*>(.*?)</li>", re.IGNORECASE | re.DOTALL)
_HEADING_RE = re.compile(r"^\s*<strong>\s*(minimum|recommended)\s*:?\s*</strong>\s*", re.IGNORECASE)
_BR_RE = re.compile(r"<br\s*/?>", re.IGNORECASE)
_DECK_CATEGORY = {3: "verified", 2: "playable", 1: "unsupported"}


def _plain(fragment: str) -> str:
    """HTML fragment -> one tidy line of text."""
    text = _html.unescape(_TAG_RE.sub("", fragment))
    return re.sub(r"\s+", " ", text.replace("\xa0", " ")).strip()


def parse_requirements(raw: Optional[str]) -> List[SpecRow]:
    """One requirements HTML blob (Steam's `minimum` or `recommended`) ->
    rows. Steam writes either a <ul> of "<strong>Label:</strong> value" items
    or bare lines separated by <br>; both are handled, and the leading
    "Minimum:" heading is dropped. Pure."""
    if not raw or not isinstance(raw, str):
        return []
    body = _HEADING_RE.sub("", raw, count=1)
    items = _LI_RE.findall(body)
    if not items:
        items = _BR_RE.split(body)
    rows: List[SpecRow] = []
    for item in items:
        line = _plain(item)
        if not line:
            continue
        label, sep, value = line.partition(":")
        if not sep or not value.strip():
            label, value = "", line
        label = label.replace("*", "").strip()
        canonical = _SPEC_LABELS.get(label.lower(), label)
        value = value.strip()[:MAX_SPEC_VALUE_CHARS]
        if value:
            rows.append(SpecRow(label=canonical, value=value))
    return rows[:MAX_SPEC_ROWS]



def parse_store(appid: str, entry: Optional[dict]) -> SteamStore:
    """One `data` object from appdetails -> SteamStore. Pure, no network."""
    info = entry if isinstance(entry, dict) else {}
    price, discount = _clean_price(info.get("price_overview"))

    meta = info.get("metacritic") if isinstance(info.get("metacritic"), dict) else {}
    score = meta.get("score")

    ach = info.get("achievements") if isinstance(info.get("achievements"), dict) else {}
    ach_total = ach.get("total")

    features: List[str] = []
    for cat in info.get("categories") or []:
        label = _FEATURE_BY_CATEGORY_ID.get((cat or {}).get("id"))
        if label and label not in features:
            features.append(label)
    # Full support makes "partial" redundant.
    if "Full controller support" in features and "Partial controller support" in features:
        features.remove("Partial controller support")

    shots: List[str] = []
    for shot in info.get("screenshots") or []:
        url = (shot or {}).get("path_full") or (shot or {}).get("path_thumbnail")
        if url and url not in shots:
            shots.append(url)

    reqs = info.get("pc_requirements") if isinstance(info.get("pc_requirements"), dict) else {}
    plat = info.get("platforms") if isinstance(info.get("platforms"), dict) else {}
    platforms = [name for name in ("windows", "mac", "linux") if plat.get(name) is True]

    return SteamStore(
        appid=str(appid),
        requirements_min=parse_requirements(reqs.get("minimum")),
        requirements_rec=parse_requirements(reqs.get("recommended")),
        platforms=platforms,
        free_to_play=bool(info["is_free"]) if "is_free" in info else None,
        price=price,
        price_discount_pct=discount,
        metacritic=int(score) if isinstance(score, (int, float)) and score > 0 else None,
        metacritic_url=meta.get("url") or None,
        achievements=int(ach_total) if isinstance(ach_total, (int, float)) and ach_total > 0 else None,
        features=features,
        languages=parse_languages(info.get("supported_languages")),
        screenshots=shots[:MAX_SCREENSHOTS],
    )


class SteamStoreAdapter:
    async def fetch(self, appid: str, lang: str) -> SteamStore:
        """Store facts for `appid`. Prices are asked for the reader's own
        region (Russian readers see rubles); everything else is
        language-independent (English names, translated on the client)."""
        if not _guard.allow():
            raise SteamUnavailable("paused or over budget")
        _guard.spend()
        params = {"appids": appid, "l": "english", "cc": "ru" if lang == "ru" else "us"}
        try:
            async with httpx.AsyncClient(
                timeout=_TIMEOUT, headers={"User-Agent": _USER_AGENT},
            ) as client:
                resp = await client.get(APPDETAILS_URL, params=params)
        except httpx.HTTPError as exc:
            _guard.pause(_PAUSE_NETWORK_SEC)
            raise SteamUnavailable(f"network: {type(exc).__name__}") from exc
        if resp.status_code == 429:
            _guard.pause(_PAUSE_RATE_LIMITED_SEC)
            raise SteamUnavailable("rate limited")
        if resp.status_code != 200:
            _guard.pause(_PAUSE_NETWORK_SEC)
            raise SteamUnavailable(f"unexpected status {resp.status_code}")
        try:
            data = resp.json()
        except ValueError as exc:
            raise SteamUnavailable("bad json") from exc
        entry = (data or {}).get(str(appid)) if isinstance(data, dict) else None
        if not isinstance(entry, dict):
            raise SteamUnavailable("unexpected body")
        if not entry.get("success"):
            return SteamStore(missing=True, appid=str(appid))
        store = parse_store(appid, entry.get("data"))
        store.deck = await self._deck_status(appid)
        return store

    async def _deck_status(self, appid: str) -> Optional[str]:
        """"verified" | "playable" | "unsupported", or None when Valve hasn't
        tested the game or this endpoint can't be asked. Never raises and
        never pauses the shared guard: the Deck badge is a bonus, and losing
        it must not cost the price/languages/requirements fetched above."""
        if not _guard.allow():
            return None
        _guard.spend()
        try:
            async with httpx.AsyncClient(
                timeout=_TIMEOUT, headers={"User-Agent": _USER_AGENT},
            ) as client:
                resp = await client.get(DECK_URL, params={"nAppID": appid})
            if resp.status_code != 200:
                return None
            data = resp.json()
        except (httpx.HTTPError, ValueError):
            return None
        results = (data or {}).get("results") if isinstance(data, dict) else None
        category = results.get("resolved_category") if isinstance(results, dict) else None
        return _DECK_CATEGORY.get(category) if isinstance(category, int) else None
