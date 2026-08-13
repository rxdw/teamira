"""
"Your sources" — YouTube half. Link-based, not OAuth: a person pastes a
public playlist/channel/video URL and this resolves it straight to one or
more MediaItem cards (media_type == "video", source == "youtube"), the
same shape app/routers/imports.py already knows how to preview/commit.

Deliberately does NOT attempt "Watch Later" or "Liked videos" — both are
private playlists with no public URL at all (YouTube dropped the old
public-Watch-Later feature years ago), so there is nothing a link could
point at. Bringing those over would need real Google OAuth (a person
signing into their own YouTube account from inside this app) and is out
of scope here; see routers/sources.py's docstring for the fuller reasoning.

Auth is a single read-only API key (YOUTUBE_API_KEY, "YouTube Data API
v3" enabled in Google Cloud Console) — same "public data only, app-level
key" shape as tmdb_api_key elsewhere in this codebase. No key configured
means source imports for YouTube links fail with a clear 503 rather than
silently returning nothing.
"""
import logging
import re
from typing import List, Optional, Tuple

import httpx

from app.config import settings
from app.schemas import ExternalIds, LocalizedText, MediaItem

logger = logging.getLogger("seenly.youtube")

_API_BASE = "https://www.googleapis.com/youtube/v3"

# One page is plenty for "bring a few things over" — a whole channel's
# upload history can run into the thousands, and nobody's reviewing a
# thousand-row import in the app anyway. Whoever pastes a big channel
# gets its most recent uploads, with a note in the response saying so
# (see YoutubeAdapter.resolve's `truncated` return value).
_MAX_ITEMS = 50

_DURATION_RE = re.compile(
    r"^PT(?:(?P<h>\d+)H)?(?:(?P<m>\d+)M)?(?:(?P<s>\d+)S)?$"
)

_VIDEO_RE = re.compile(r"(?:youtu\.be/|[?&]v=)([\w-]{11})")
_PLAYLIST_RE = re.compile(r"[?&]list=([\w-]+)")
_CHANNEL_ID_RE = re.compile(r"youtube\.com/channel/([\w-]+)")
_CHANNEL_HANDLE_RE = re.compile(r"youtube\.com/@([\w.-]+)")
_CHANNEL_LEGACY_RE = re.compile(r"youtube\.com/(?:c|user)/([\w.-]+)")


def _parse_duration(raw: Optional[str]) -> Optional[int]:
    """ISO-8601 ("PT1H2M3S") -> whole minutes, rounded up so a 45s short
    doesn't collapse to 0 and vanish from runtime-based stats."""
    if not raw:
        return None
    match = _DURATION_RE.match(raw)
    if not match:
        return None
    h = int(match.group("h") or 0)
    m = int(match.group("m") or 0)
    s = int(match.group("s") or 0)
    total_seconds = h * 3600 + m * 60 + s
    if total_seconds <= 0:
        return None
    return max(1, round(total_seconds / 60))


def parse_url(url: str) -> Optional[Tuple[str, str]]:
    """Returns (kind, id) where kind is "video" | "playlist" | "channel_id"
    | "channel_handle" | "channel_legacy", or None if this isn't a
    recognizable YouTube URL at all. A playlist URL can also carry a
    `v=` (an "in this playlist" view of one video) — playlist wins,
    since that's what the person is more likely pasting a whole
    watch-order for.
    """
    if "youtube.com" not in url and "youtu.be" not in url:
        return None
    for kind, pattern in (
        ("playlist", _PLAYLIST_RE),
        ("video", _VIDEO_RE),
        ("channel_id", _CHANNEL_ID_RE),
        ("channel_handle", _CHANNEL_HANDLE_RE),
        ("channel_legacy", _CHANNEL_LEGACY_RE),
    ):
        match = pattern.search(url)
        if match:
            return kind, match.group(1)
    return None


def _thumbnail(thumbnails: dict) -> Optional[str]:
    for size in ("high", "medium", "default"):
        if size in thumbnails:
            return thumbnails[size].get("url")
    return None


def _to_media_item(
    video_id: str,
    snippet: dict,
    duration_minutes: Optional[int],
) -> MediaItem:
    title = (snippet.get("title") or "").strip() or "(untitled)"
    published = snippet.get("publishedAt") or ""
    year = int(published[:4]) if published[:4].isdigit() else None
    return MediaItem(
        id=video_id,
        media_type="video",
        external_ids=ExternalIds(),
        title=LocalizedText(en=title),
        description=LocalizedText(en=(snippet.get("description") or "")[:500] or None),
        poster_url=_thumbnail(snippet.get("thumbnails") or {}),
        year=year,
        genres=[],
        rating=None,
        source="youtube",
        runtime_minutes=duration_minutes,
    )


class YoutubeAdapter:
    source_name = "youtube"

    @property
    def _configured(self) -> bool:
        return bool(settings.youtube_api_key)

    async def _get(self, client: httpx.AsyncClient, path: str, **params) -> dict:
        params["key"] = settings.youtube_api_key
        res = await client.get(f"{_API_BASE}/{path}", params=params)
        res.raise_for_status()
        return res.json()

    async def _durations(self, client: httpx.AsyncClient, video_ids: List[str]) -> dict:
        """One extra call (ids batch up to 50 per YouTube's own limit) so
        playlist/channel rows carry a real runtime — worth it for Wrapped's
        hour totals down the line, same reasoning as WatchlistEntry's own
        runtime_minutes snapshot."""
        if not video_ids:
            return {}
        data = await self._get(
            client, "videos", part="contentDetails", id=",".join(video_ids)
        )
        return {
            item["id"]: _parse_duration(item.get("contentDetails", {}).get("duration"))
            for item in data.get("items", [])
        }

    async def _resolve_uploads_playlist(self, client: httpx.AsyncClient, kind: str, value: str) -> Optional[str]:
        params = {"part": "contentDetails"}
        if kind == "channel_id":
            params["id"] = value
        elif kind == "channel_handle":
            params["forHandle"] = f"@{value}"
        else:  # channel_legacy — could be a /c/ vanity name or a /user/ username
            params["forUsername"] = value
        data = await self._get(client, "channels", **params)
        items = data.get("items") or []
        if not items and kind == "channel_legacy":
            # /c/ vanity names aren't guaranteed to match forUsername —
            # fall back to a plain search, best-effort.
            search = await self._get(
                client, "search", part="snippet", q=value, type="channel", maxResults=1
            )
            hits = search.get("items") or []
            if not hits:
                return None
            channel_id = hits[0]["snippet"]["channelId"]
            data = await self._get(client, "channels", part="contentDetails", id=channel_id)
            items = data.get("items") or []
        if not items:
            return None
        return items[0]["contentDetails"]["relatedPlaylists"]["uploads"]

    async def _playlist_items(self, client: httpx.AsyncClient, playlist_id: str) -> Tuple[List[MediaItem], bool]:
        data = await self._get(
            client,
            "playlistItems",
            part="snippet",
            playlistId=playlist_id,
            maxResults=_MAX_ITEMS,
        )
        raw_items = [
            it for it in data.get("items", [])
            # Deleted/private videos still occupy a playlist slot but come
            # back with a placeholder title — skip them, nothing to import.
            if it.get("snippet", {}).get("title") not in (None, "Deleted video", "Private video")
        ]
        video_ids = [it["snippet"]["resourceId"]["videoId"] for it in raw_items]
        durations = await self._durations(client, video_ids)
        rows = [
            _to_media_item(vid, it["snippet"], durations.get(vid))
            for vid, it in zip(video_ids, raw_items)
        ]
        truncated = bool(data.get("nextPageToken"))
        return rows, truncated

    async def resolve(self, url: str) -> Tuple[List[MediaItem], str, bool]:
        """Returns (rows, context_label, truncated). Raises RuntimeError
        (no key configured) or ValueError (URL not recognized / nothing
        found) — routers/sources.py turns both into the right HTTP status."""
        if not self._configured:
            raise RuntimeError("YouTube import isn't configured on this server yet")
        parsed = parse_url(url)
        if parsed is None:
            raise ValueError("That doesn't look like a YouTube link")
        kind, value = parsed

        async with httpx.AsyncClient(timeout=10.0) as client:
            if kind == "video":
                data = await self._get(client, "videos", part="snippet,contentDetails", id=value)
                items = data.get("items") or []
                if not items:
                    raise ValueError("Couldn't find that video — it may be private or deleted")
                item = items[0]
                duration = _parse_duration(item.get("contentDetails", {}).get("duration"))
                row = _to_media_item(value, item["snippet"], duration)
                return [row], "YouTube video", False

            if kind == "playlist":
                rows, truncated = await self._playlist_items(client, value)
                if not rows:
                    raise ValueError("That playlist looks empty (or private)")
                label = f"YouTube playlist — {len(rows)}{'+' if truncated else ''} videos"
                return rows, label, truncated

            # channel_id / channel_handle / channel_legacy
            uploads_id = await self._resolve_uploads_playlist(client, kind, value)
            if uploads_id is None:
                raise ValueError("Couldn't find that channel")
            rows, truncated = await self._playlist_items(client, uploads_id)
            if not rows:
                raise ValueError("That channel doesn't have any public uploads")
            label = f"YouTube channel — latest {len(rows)} upload{'s' if len(rows) != 1 else ''}"
            return rows, label, truncated
