"""Streams images from a small allowlist of external CDNs (TMDB's
image.tmdb.org today — see _ALLOWED_HOSTS below to add more later)
through this server instead of the client fetching them directly.

Why this exists at all: every image URL this API returns (poster_url,
backdrop_url, etc.) has always just been a direct link to the source
CDN — the client fetches the bytes itself, this server is never in that
path. That's normally the right call: less bandwidth/cost on this
server, and the CDN is usually faster/closer to the client than we are.
It breaks down specifically when the CDN itself is blocked somewhere a
client can still reach *this* API fine — image.tmdb.org is blocked by
some ISPs in Russia, for example, which is exactly the "posters don't
load but everything else does" symptom this exists to fix.

Opt-in, not automatic: adapters/tmdb.py::_proxied only rewrites a URL
through here when settings.public_api_base_url is actually set (see
that function's own docstring) — nothing changes for a deployment that
hasn't configured it, and this endpoint sits unused.

Not a general-purpose proxy: `url` is checked against _ALLOWED_HOSTS
before this server will fetch it, so this can't be turned into an open
relay for arbitrary URLs (SSRF, hotlinking someone else's bandwidth
through this server, etc.) by a client passing in whatever it wants.

Cached on disk, not just via the response's Cache-Control header — a
TMDB image path never changes once published (a genuinely new image
gets a new path, the old one is never overwritten), so once this server
has fetched a given url it never needs to ask TMDB for it again. Lives
under the same bind-mounted uploads/ directory app/main.py already uses
for avatars (see _CACHE_DIR below), so it survives container rebuilds
the same way avatars already do, without needing a new volume mount.
"""

import asyncio
import hashlib
import logging
import mimetypes
import os
from urllib.parse import urlparse

import httpx
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import Response

logger = logging.getLogger("seenly.routers.image_proxy")

router = APIRouter(prefix="/media", tags=["media"])

# Add a host here the same day an adapter's own CDN needs proxying too
# (Shikimori/IGDB/Open Library covers aren't known to be blocked
# anywhere today, so they're not proxied — see config.py's
# public_api_base_url docstring).
_ALLOWED_HOSTS = {"image.tmdb.org"}

# What this server tells the *client* it can cache for — separate from
# the on-disk cache below, and necessarily shorter, since there's no
# literal "forever" in HTTP (some caches special-case very large values
# rather than honoring them). A year plus `immutable` is the standard
# "this will never change, stop asking" convention; the on-disk cache
# is what actually makes it permanent on this server's side regardless
# of what any client/CDN in between chooses to honor.
_CACHE_CONTROL = "public, max-age=31536000, immutable"  # 1 year

_TIMEOUT = httpx.Timeout(10.0)

_CACHE_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "uploads", "image_cache")
os.makedirs(_CACHE_DIR, exist_ok=True)

# One lock per in-flight cache key, so N concurrent requests for the same
# not-yet-cached image (e.g. a poster several people open at once right
# after it's first added to the catalog) fetch it from TMDB exactly
# once, not N times — the other N-1 just wait for the first fetch to
# finish and then read the now-populated cache file. Entries are popped
# once their fetch completes so this dict doesn't grow unbounded.
_fetch_locks: dict[str, asyncio.Lock] = {}
_fetch_locks_guard = asyncio.Lock()


def _cache_path(url: str) -> str:
    key = hashlib.sha256(url.encode()).hexdigest()
    return os.path.join(_CACHE_DIR, key)


def _guess_media_type(url: str) -> str:
    guessed, _ = mimetypes.guess_type(urlparse(url).path)
    return guessed or "image/jpeg"


async def _fetch_and_cache(url: str, path: str) -> bytes:
    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT, follow_redirects=True) as client:
            upstream = await client.get(url)
    except httpx.HTTPError as exc:
        logger.warning("image proxy fetch failed for %s: %s", url, exc)
        raise HTTPException(status_code=502, detail="upstream fetch failed") from exc

    if upstream.status_code == 404:
        raise HTTPException(status_code=404, detail="not found")
    if upstream.status_code != 200:
        logger.warning("image proxy got %s from %s", upstream.status_code, url)
        raise HTTPException(status_code=502, detail="upstream error")

    # Written to a temp path and renamed into place, so a request that
    # reads the cache file mid-write (or a container restart mid-write)
    # never sees a truncated/partial image — os.replace is atomic on the
    # same filesystem, which this always is (both paths are under
    # _CACHE_DIR).
    tmp_path = f"{path}.tmp-{os.getpid()}"
    with open(tmp_path, "wb") as f:
        f.write(upstream.content)
    os.replace(tmp_path, path)
    return upstream.content


@router.get("/image-proxy")
async def image_proxy(url: str = Query(..., description="Full https:// URL of an allowlisted CDN image")):
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.hostname not in _ALLOWED_HOSTS:
        raise HTTPException(status_code=400, detail="URL not allowed")

    path = _cache_path(url)
    if os.path.exists(path):
        with open(path, "rb") as f:
            content = f.read()
    else:
        async with _fetch_locks_guard:
            lock = _fetch_locks.setdefault(path, asyncio.Lock())
        async with lock:
            # Re-check: another request may have finished fetching this
            # exact url while we were waiting on the lock above.
            if os.path.exists(path):
                with open(path, "rb") as f:
                    content = f.read()
            else:
                content = await _fetch_and_cache(url, path)
        async with _fetch_locks_guard:
            _fetch_locks.pop(path, None)

    return Response(
        content=content,
        media_type=_guess_media_type(url),
        headers={"Cache-Control": _CACHE_CONTROL},
    )
