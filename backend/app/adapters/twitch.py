"""
"Your sources" — Twitch half. Same link-based shape as adapters/youtube.py:
paste a public channel or VOD URL, get back MediaItem cards (media_type ==
"video", source == "twitch"). Live streams aren't handled here — there's
nothing to "watch later" about something that isn't a recording yet; a
channel link resolves to that channel's past broadcasts (VODs) instead.

Auth is OAuth2 client-credentials against Twitch itself — an app-level
token, not a per-user login, identical mechanism to how app/adapters/igdb.py
already authenticates (IGDB runs on this same Twitch developer platform).
TWITCH_CLIENT_ID/TWITCH_CLIENT_SECRET default to whatever IGDB is already
using (see _client_id/_client_secret below) so a deployment that already
has games working doesn't need a second app registration just for this —
a dedicated Twitch app is only worth it for a separate rate-limit budget.
"""
import asyncio
import logging
import re
import time
from typing import List, Optional, Tuple

import httpx

from app.config import settings
from app.schemas import ExternalIds, LocalizedText, MediaItem

logger = logging.getLogger("seenly.twitch")

_TOKEN_URL = "https://id.twitch.tv/oauth2/token"
_HELIX_BASE = "https://api.twitch.tv/helix"

_MAX_ITEMS = 50

_DURATION_RE = re.compile(r"(?:(?P<h>\d+)h)?(?:(?P<m>\d+)m)?(?:(?P<s>\d+)s)?$")

_VOD_RE = re.compile(r"twitch\.tv/videos/(\d+)")
# A bare channel URL: twitch.tv/<login>, optionally with a trailing
# /clip/... or /videos — the login is always the first path segment, and
# "videos"/"clips"/"about"/"schedule" aren't valid channel logins so this
# never confuses those sub-pages for a different channel.
_CHANNEL_RE = re.compile(r"twitch\.tv/([A-Za-z0-9_]{2,25})(?:/|$|\?)")
_RESERVED_PATHS = {"videos", "clips", "directory", "settings", "subscriptions", "p"}


def _parse_duration(raw: Optional[str]) -> Optional[int]:
    """Twitch's own duration format, e.g. "1h2m3s" — whole minutes."""
    if not raw:
        return None
    match = _DURATION_RE.match(raw)
    if not match or not any(match.groups()):
        return None
    h = int(match.group("h") or 0)
    m = int(match.group("m") or 0)
    s = int(match.group("s") or 0)
    total_seconds = h * 3600 + m * 60 + s
    if total_seconds <= 0:
        return None
    return max(1, round(total_seconds / 60))


def parse_url(url: str) -> Optional[Tuple[str, str]]:
    """Returns ("video", vod_id) or ("channel", login), or None."""
    if "twitch.tv" not in url:
        return None
    vod_match = _VOD_RE.search(url)
    if vod_match:
        return "video", vod_match.group(1)
    channel_match = _CHANNEL_RE.search(url)
    if channel_match and channel_match.group(1).lower() not in _RESERVED_PATHS:
        return "channel", channel_match.group(1)
    return None


def _thumbnail(template: Optional[str]) -> Optional[str]:
    if not template:
        return None
    return template.replace("%{width}", "320").replace("%{height}", "180")


def _to_media_item(video: dict) -> MediaItem:
    title = (video.get("title") or "").strip() or "(untitled)"
    published = video.get("published_at") or video.get("created_at") or ""
    year = int(published[:4]) if published[:4].isdigit() else None
    return MediaItem(
        id=video["id"],
        media_type="video",
        external_ids=ExternalIds(),
        title=LocalizedText(en=title),
        description=LocalizedText(en=(video.get("description") or "")[:500] or None),
        poster_url=_thumbnail(video.get("thumbnail_url")),
        year=year,
        genres=[],
        rating=None,
        source="twitch",
        runtime_minutes=_parse_duration(video.get("duration")),
    )


class TwitchAdapter:
    source_name = "twitch"

    def __init__(self):
        self._token: Optional[str] = None
        self._token_expires_at: float = 0.0
        self._token_lock = asyncio.Lock()

    @property
    def _client_id(self) -> str:
        return settings.twitch_client_id or settings.igdb_client_id

    @property
    def _client_secret(self) -> str:
        return settings.twitch_client_secret or settings.igdb_client_secret

    @property
    def _configured(self) -> bool:
        return bool(self._client_id and self._client_secret)

    async def _access_token(self) -> str:
        if self._token and time.monotonic() < self._token_expires_at:
            return self._token
        async with self._token_lock:
            if self._token and time.monotonic() < self._token_expires_at:
                return self._token
            async with httpx.AsyncClient(timeout=8.0) as client:
                res = await client.post(_TOKEN_URL, params={
                    "client_id": self._client_id,
                    "client_secret": self._client_secret,
                    "grant_type": "client_credentials",
                })
                res.raise_for_status()
                data = res.json()
            self._token = data["access_token"]
            # Same 60s safety margin as igdb.py — refresh a little early
            # rather than getting caught by clock skew mid-request.
            self._token_expires_at = time.monotonic() + data.get("expires_in", 3600) - 60
            return self._token

    async def _headers(self) -> dict:
        return {
            "Client-Id": self._client_id,
            "Authorization": f"Bearer {await self._access_token()}",
        }

    async def resolve(self, url: str) -> Tuple[List[MediaItem], str, bool]:
        if not self._configured:
            raise RuntimeError("Twitch import isn't configured on this server yet")
        parsed = parse_url(url)
        if parsed is None:
            raise ValueError("That doesn't look like a Twitch link")
        kind, value = parsed

        async with httpx.AsyncClient(timeout=10.0) as client:
            headers = await self._headers()

            if kind == "video":
                res = await client.get(f"{_HELIX_BASE}/videos", params={"id": value}, headers=headers)
                res.raise_for_status()
                items = res.json().get("data") or []
                if not items:
                    raise ValueError("Couldn't find that VOD — it may be expired or private")
                return [_to_media_item(items[0])], "Twitch VOD", False

            # channel — resolve login -> user id, then their past broadcasts
            users_res = await client.get(f"{_HELIX_BASE}/users", params={"login": value}, headers=headers)
            users_res.raise_for_status()
            users = users_res.json().get("data") or []
            if not users:
                raise ValueError("Couldn't find that channel")
            user_id = users[0]["id"]
            display_name = users[0].get("display_name", value)

            videos_res = await client.get(
                f"{_HELIX_BASE}/videos",
                params={"user_id": user_id, "type": "archive", "first": _MAX_ITEMS},
                headers=headers,
            )
            videos_res.raise_for_status()
            payload = videos_res.json()
            items = payload.get("data") or []
            if not items:
                raise ValueError(f"{display_name} doesn't have any public VODs right now")
            rows = [_to_media_item(v) for v in items]
            truncated = bool((payload.get("pagination") or {}).get("cursor"))
            label = f"Twitch — {display_name}, {len(rows)}{'+' if truncated else ''} past broadcasts"
            return rows, label, truncated
