"""Games — best-effort Russian-language descriptions, backed by Valve's
Steam Store API (store.steampowered.com/api/appdetails). Unofficial (no
public docs from Valve for this specific endpoint), but stable and
widely used — see the community-maintained docs at
github.com/Revadike/InternalSteamWebAPI/wiki/Get-App-Details. No key
needed.

Unlike IGDB (which has no language concept at all — see
app/adapters/igdb.py's module docstring), Steam store pages ARE
genuinely localized per-language by each game's own publisher, so
`l=russian` returns real, publisher-written Russian text when the
game's Steam page has one — not a machine translation, and not every
game has it (localization is each publisher's own choice, same
"real data or nothing" convention as every other adapter in this app).

Only usable for a game that has a Steam store page at all — matched via
the game's own IGDB `websites` entry (see app/adapters/igdb.py's
_steam_appid_from_websites), not by searching Steam by name, since a
title search there is far more collision-prone (remasters, demos, same-
named indie games) than reusing an id IGDB already resolved. Console-
exclusive or non-Steam PC titles simply have nothing to look up here and
stay English-only, same as they already did before this existed.
"""
import asyncio
import logging
import re
import time
from typing import Optional

import httpx

logger = logging.getLogger("seenly.adapters.steam")

APPDETAILS_URL = "https://store.steampowered.com/api/appdetails"

# No published hard limit from Valve for this endpoint — community
# reports put anonymous callers at roughly 200 requests/5 minutes per IP.
# Kept conservative here regardless, since in steady state this is only
# ever called once per *cache miss* of a game's detail screen (see
# app/routers/media.py — the whole MediaDetailOut is cached forever after
# the first successful fetch) — this limiter is really just protecting a
# cold cache / bulk reseed from bursting, not a hot path.
_RATE_LIMIT_PER_SEC = 2


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

_TAG_RE = re.compile(r"<[^>]+>")
_WHITESPACE_RE = re.compile(r"\s+")


def _clean_html(raw: Optional[str]) -> Optional[str]:
    """Steam's short_description/about_the_game come back as HTML (Steam's
    own store-page formatting — <h2>, <ul>, <a>, <br> ...) — stripped to
    plain text, same treatment Google Books' HTML description already
    gets in app/adapters/google_books.py::_clean_description."""
    if not raw:
        return None
    text = _TAG_RE.sub(" ", raw)
    text = text.replace("&nbsp;", " ").replace("&amp;", "&").replace("&quot;", '"')
    text = _WHITESPACE_RE.sub(" ", text).strip()
    return text or None


class SteamAdapter:
    async def description_ru(self, appid: str) -> Optional[str]:
        """Real, publisher-written Russian text for `appid`'s Steam store
        page, or None when Steam has nothing for it (no such app, no
        Russian localization on its page, or the request failed) —
        degrades exactly like every other optional enrichment call in
        this app. Prefers the short store blurb over the full
        "about the game" essay — same card-sized-synopsis scope every
        other adapter's description field already has, not a full
        feature-list dump.
        """
        await _rate_limiter.wait()
        try:
            async with httpx.AsyncClient(timeout=8.0) as client:
                resp = await client.get(APPDETAILS_URL, params={
                    "appids": appid,
                    "l": "russian",
                })
                resp.raise_for_status()
                data = resp.json()
        except httpx.HTTPError as exc:
            logger.warning("Steam appdetails query failed [%s]: %s", appid, exc)
            return None
        entry = (data or {}).get(str(appid)) or {}
        if not entry.get("success"):
            return None
        info = entry.get("data") or {}
        return (
            _clean_html(info.get("short_description"))
            or _clean_html(info.get("about_the_game"))
        )
