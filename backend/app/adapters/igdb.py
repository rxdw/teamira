"""Games — search, browse, and detail, backed by IGDB (api-docs.igdb.com),
which runs on Twitch's developer platform. Free for non-commercial use
under the Twitch Developer Service Agreement; a monetized product (e.g.
Wrapped as a paid tier) technically needs IGDB's commercial partnership —
see partner@igdb.com. Same story as most game-data APIs at this scale;
worth confirming with them directly before charging for anything that
surfaces IGDB data.

Auth is OAuth2 client-credentials against Twitch, not a simple API key:
    POST https://id.twitch.tv/oauth2/token
        ?client_id=...&client_secret=...&grant_type=client_credentials
    -> {"access_token": "...", "expires_in": <seconds>, "token_type": "bearer"}
The token is long-lived (weeks), so it's cached in-process here rather than
re-requested per call — this is credentials, not content, so it doesn't go
through app/cache.py's per-title/per-day DB cache.

Every data request is a POST with an APICalypse query string as the body
(not query params, not JSON) — e.g.:
    fields name,genres.name; search "Zelda"; limit 20;
No key configured just means games quietly disappear from search/
collections/detail — same "degrade, don't fake it" approach this app
takes everywhere a key is missing.
"""
import asyncio
import logging
import time
from datetime import date, datetime, timezone
from typing import List, Optional

import httpx

from app.config import settings
from app.schemas import MediaItem, ExternalIds, LocalizedText
from app.adapters.base import MediaAdapter

logger = logging.getLogger("seenly.igdb")

TWITCH_TOKEN_URL = "https://id.twitch.tv/oauth2/token"
IGDB_BASE = "https://api.igdb.com/v4"

# IGDB enforces 4 requests/second per Client-ID (api-docs.igdb.com/#rate-limits).
# named_collections() below fans out 12 shelf queries concurrently via
# asyncio.gather — well over that limit if they're all just fired at once.
# Blowing past it doesn't queue/slow down, it 429s: _query() below catches
# that as an httpx.HTTPError like any other failure and quietly returns []
# for that shelf, so a burst like this silently empties out most/all of
# Collections' IGDB shelves even though the credentials and IGDB itself are
# fine (a single one-off call, like a search or an AI request, stays well
# under 4/s and never hits this). This limiter makes every _query() call —
# across all IgdbAdapter instances/callers, process-wide — wait its turn so
# no more than 4 calls start within any rolling 1-second window, trading a
# few seconds of extra latency on the 12-shelf Collections fetch for not
# silently dropping shelves.
_RATE_LIMIT_PER_SEC = 4


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

# IGDB's own genre IDs — stable reference data per api-docs.igdb.com/#genre,
# not something that needs a lookup call. Used to build the genre-scoped
# Collections shelves in named_collections() below.
_GENRE_SHELVES = [
    ("Role-Playing Games", 12),
    ("Shooters", 5),
    ("Strategy Games", 15),
    ("Adventure Games", 31),
    ("Indie Games", 32),
    ("Platformers", 8),
    ("Racing Games", 10),
    ("Fighting Games", 4),
]

# Requested every call — cover.url comes back as a low-res thumbnail path
# by default (t_thumb); swapped for a bigger size in _cover_url below.
_GAME_FIELDS = (
    "name,summary,genres.name,cover.url,first_release_date,"
    "rating,aggregated_rating,total_rating,artworks.url,screenshots.url"
)


def _cover_url(raw_url: Optional[str], size: str = "t_cover_big") -> Optional[str]:
    """IGDB image URLs are protocol-relative and default to a tiny
    thumbnail — e.g. "//images.igdb.com/igdb/image/upload/t_thumb/xyz.jpg".
    Swap the size segment and add the scheme."""
    if not raw_url:
        return None
    url = raw_url if raw_url.startswith("http") else f"https:{raw_url}"
    return url.replace("t_thumb", size)


def _normalize(raw: dict) -> Optional[MediaItem]:
    game_id = raw.get("id")
    name = raw.get("name")
    if game_id is None or not name:
        return None

    year = None
    release_ts = raw.get("first_release_date")
    if release_ts:
        try:
            year = datetime.fromtimestamp(release_ts, tz=timezone.utc).year
        except (ValueError, OSError):
            year = None

    genres = [
        g["name"] for g in raw.get("genres") or []
        if isinstance(g, dict) and g.get("name")
    ]

    # IGDB scores are 0-100 (user "rating", critic "aggregated_rating", and
    # "total_rating" blending both when there's enough of each). Preferred
    # in that order, halved onto the same ~0-10 scale TMDB ratings use.
    score = raw.get("total_rating") or raw.get("rating") or raw.get("aggregated_rating")
    rating10 = round(score / 10, 1) if score else None

    cover = (raw.get("cover") or {}).get("url")
    artworks = raw.get("artworks") or []
    screenshots = raw.get("screenshots") or []
    backdrop_raw = (artworks[0]["url"] if artworks else None) or (
        screenshots[0]["url"] if screenshots else None
    )

    return MediaItem(
        id=f"igdb-{game_id}",
        media_type="game",
        external_ids=ExternalIds(tmdb=None, imdb=None),
        title=LocalizedText(ru=None, en=name),
        description=LocalizedText(ru=None, en=raw.get("summary")),
        poster_url=_cover_url(cover),
        backdrop_url=_cover_url(backdrop_raw, size="t_1080p") if backdrop_raw else _cover_url(cover),
        year=year,
        genres=genres,
        rating=rating10,
        runtime_minutes=None,  # IGDB has no "average time to beat" field — see module docstring
        source="igdb",
    )


class IgdbAdapter(MediaAdapter):
    source_name = "igdb"

    def __init__(self):
        self.client_id = settings.igdb_client_id
        self.client_secret = settings.igdb_client_secret
        self._token: Optional[str] = None
        self._token_expires_at: float = 0.0
        self._token_lock = asyncio.Lock()

    @property
    def _configured(self) -> bool:
        return bool(self.client_id and self.client_secret)

    async def _access_token(self) -> str:
        """Cached in-process; only re-requested once it's actually close to
        expiring (Twitch tokens for client-credentials are typically valid
        for weeks), so a healthy process makes this Twitch call rarely."""
        if self._token and time.monotonic() < self._token_expires_at:
            return self._token
        async with self._token_lock:
            if self._token and time.monotonic() < self._token_expires_at:
                return self._token
            async with httpx.AsyncClient(timeout=8.0) as client:
                resp = await client.post(TWITCH_TOKEN_URL, params={
                    "client_id": self.client_id,
                    "client_secret": self.client_secret,
                    "grant_type": "client_credentials",
                })
                resp.raise_for_status()
                data = resp.json()
            self._token = data["access_token"]
            # Refresh a bit early rather than right at the edge.
            self._token_expires_at = time.monotonic() + max(data.get("expires_in", 3600) - 60, 60)
            return self._token

    async def _headers(self) -> dict:
        token = await self._access_token()
        return {
            "Client-ID": self.client_id,
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
        }

    async def _query(self, endpoint: str, apicalypse: str) -> List[dict]:
        if not self._configured:
            raise RuntimeError("IGDB_CLIENT_ID / IGDB_CLIENT_SECRET are not configured")
        try:
            headers = await self._headers()
            await _rate_limiter.wait()
            async with httpx.AsyncClient(timeout=8.0) as client:
                resp = await client.post(
                    f"{IGDB_BASE}/{endpoint}", headers=headers, content=apicalypse
                )
                resp.raise_for_status()
                data = resp.json()
        except httpx.HTTPError as exc:
            status = getattr(getattr(exc, "response", None), "status_code", "?")
            logger.warning("IGDB %s query failed [%s]: %s", endpoint, status, exc)
            return []
        return data if isinstance(data, list) else []

    async def search(
        self,
        query: str,
        year_from: Optional[int] = None,
        year_to: Optional[int] = None,
    ) -> List[MediaItem]:
        if not self._configured:
            return []  # no synthetic fallback — see module docstring
        if query:
            # IGDB's `search` only matches a game's name/aliases — real
            # for an actual title ("Fallout"), useless for genre words
            # ("sci-fi", "strategy"): those never appear in a game's name,
            # so a genre-only ask fed in here just comes back empty. Genre-
            # driven asks go through the `else` branch below instead (see
            # its callers in app/routers/ai.py), which pulls a real,
            # well-known pool and lets per-item genre/year scoring do the
            # actual filtering — the same pattern already used for the
            # "no query" Collections-tab call to this branch.
            apicalypse = f'search "{_escape(query)}"; fields {_GAME_FIELDS}; limit 20;'
        else:
            clauses = ["total_rating != null"]
            if year_from is not None:
                start_ts = int(datetime(year_from, 1, 1, tzinfo=timezone.utc).timestamp())
                clauses.append(f"first_release_date >= {start_ts}")
            if year_to is not None:
                end_ts = int(datetime(year_to, 12, 31, tzinfo=timezone.utc).timestamp())
                clauses.append(f"first_release_date <= {end_ts}")
            where = " & ".join(clauses)
            apicalypse = (
                f"fields {_GAME_FIELDS}; where {where}; "
                "sort total_rating desc; limit 40;"
            )
        raw = await self._query("games", apicalypse)
        return [item for r in raw if (item := _normalize(r)) is not None]

    async def _shelf(self, title: str, apicalypse: str) -> tuple:
        raw = await self._query("games", apicalypse)
        items = [item for r in raw if (item := _normalize(r)) is not None]
        return (title, items)

    async def named_collections(self) -> List[tuple]:
        """Real IGDB-backed shelves for the Collections tab — "real
        data or nothing" rule: Top Rated, New & Notable,
        Upcoming, All-Time Classics, plus one shelf per genre in
        _GENRE_SHELVES. Each is its own round-trip, fanned out concurrently;
        an empty/failed one just doesn't show up (see _shelf/return_exceptions
        below), it doesn't take the others down with it.

        Each shelf's `limit` was raised from 12 to 40 — IGDB happily returns
        that many in one round-trip (well under its 500-per-request cap), so
        this is just asking for a fuller shelf, not adding extra calls."""
        if not self._configured:
            return []
        year_start_ts = int(datetime(date.today().year, 1, 1, tzinfo=timezone.utc).timestamp())
        now_ts = int(time.time())
        classics_cutoff_ts = int(
            datetime(date.today().year - 10, 1, 1, tzinfo=timezone.utc).timestamp()
        )

        tasks = [
            self._shelf(
                "Top Rated Games",
                f"fields {_GAME_FIELDS}; where total_rating != null & "
                "total_rating_count > 20; sort total_rating desc; limit 40;",
            ),
            self._shelf(
                "New & Notable This Year",
                f"fields {_GAME_FIELDS}; where first_release_date > {year_start_ts} "
                f"& first_release_date < {now_ts} & total_rating != null; "
                "sort total_rating_count desc; limit 40;",
            ),
            self._shelf(
                "Coming Soon",
                f"fields {_GAME_FIELDS}; where first_release_date > {now_ts}; "
                "sort hypes desc; limit 40;",
            ),
            self._shelf(
                "All-Time Classics",
                f"fields {_GAME_FIELDS}; where first_release_date < {classics_cutoff_ts} "
                "& total_rating != null & total_rating_count > 50; "
                "sort total_rating desc; limit 40;",
            ),
        ]
        for label, genre_id in _GENRE_SHELVES:
            tasks.append(
                self._shelf(
                    label,
                    f"fields {_GAME_FIELDS}; where genres = ({genre_id}) & "
                    "total_rating != null & total_rating_count > 10; "
                    "sort total_rating desc; limit 40;",
                )
            )

        try:
            results = await asyncio.gather(*tasks, return_exceptions=True)
        except RuntimeError:
            return []
        return [r for r in results if isinstance(r, tuple) and r[1]]

    async def full_detail(self, raw_id: str) -> Optional[MediaItem]:
        if not self._configured:
            raise RuntimeError("IGDB_CLIENT_ID / IGDB_CLIENT_SECRET are not configured")
        apicalypse = f"fields {_GAME_FIELDS}; where id = {raw_id};"
        raw = await self._query("games", apicalypse)
        if not raw:
            return None
        return _normalize(raw[0])


def _escape(text: str) -> str:
    """APICalypse string literals are double-quoted; escape embedded quotes
    so a search like `he said "hi"` can't break the query syntax."""
    return text.replace('"', '\\"')
