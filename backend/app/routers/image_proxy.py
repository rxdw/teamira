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

Unauthenticated, but not open: every route in this app now requires a
login token except this one, because this one is loaded directly by the
client's own image widget (Flutter's Image.network), which fetches a
plain URL and can't attach an Authorization header. Instead, every URL
this server itself hands out through here (see
app/image_urls.py::_proxied) carries a signed, expiring `exp`/`sig` pair;
a request missing those or carrying a signature that doesn't verify is
rejected before anything is fetched. That, plus the host allowlist above,
plus a per-IP rate limit (see app/rate_limit.py's image_proxy_limiter),
is what keeps this from being a free, unmetered CDN proxy for anyone who
finds this server's address — see app/image_urls.py's own docstring for
why the signature is window-aligned rather than a fresh one per request.

Cached on disk, not just via the response's Cache-Control header — a
TMDB image path never changes once published (a genuinely new image
gets a new path, the old one is never overwritten), so once this server
has fetched a given url it never needs to ask TMDB for it again. Lives
under the same bind-mounted uploads/ directory app/main.py already uses
for avatars (see _CACHE_DIR below), so it survives container rebuilds
the same way avatars already do, without needing a new volume mount.
Capped at settings.image_proxy_cache_max_bytes with LRU-by-atime
eviction once over — see _evict_lru_if_over_cap below for why nothing
else about this cache ever ages an entry out on its own.
"""

import asyncio
import hashlib
import logging
import mimetypes
import os
import time
from urllib.parse import urlparse

import httpx
from fastapi import APIRouter, BackgroundTasks, HTTPException, Query, Request
from fastapi.responses import Response

from app.config import settings
from app.image_urls import verify_proxy_signature
from app.rate_limit import client_key, image_proxy_limiter

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

# The cache above never expires an entry on its own — a TMDB image path
# never changes once published, so "cached forever" is the whole point —
# which means nothing shrinks it, and it grows for as long as the catalog
# does. This caps it at settings.image_proxy_cache_max_bytes (config.py),
# evicting the least-recently-*read* files first once it's over.
#
# Runs at most once every _EVICT_CHECK_INTERVAL_SECONDS, from a background
# task kicked off on a cache *miss* (a hit never writes anything, so it
# can't be what pushes the directory over the cap, and doesn't need to pay
# for checking). The debounce matters once the cache is warm and busy:
# without it, every miss in a burst (a deploy, a new region's replica
# warming up from empty) would each pay for a full directory scan+stat,
# to re-answer a question that barely changes request to request.
#
# Eviction order is atime, which is an approximation, not a guarantee:
# this filesystem may be mounted `relatime` (Linux's default for a long
# time now), which only updates atime once a day, or on write — so "least
# recently read" here really means "least recently read, rounded to about
# a day." That's good enough for a cache whose hot entries are read far
# more often than once a day, and nowhere near worth mount-option
# archaeology to make exact.
_EVICT_CHECK_INTERVAL_SECONDS = 5 * 60
_evict_state = {"last_check": 0.0, "running": False}


def _evict_lru_if_over_cap() -> None:
    """Synchronous and blocking (scandir + stat over however many files are
    in the cache directory) — only ever called from a background task
    (see image_proxy() below), never awaited inline, so it never delays
    the response that triggered it."""
    if _evict_state["running"]:
        return
    now = time.monotonic()
    if now - _evict_state["last_check"] < _EVICT_CHECK_INTERVAL_SECONDS:
        return
    _evict_state["running"] = True
    _evict_state["last_check"] = now
    try:
        entries: list[tuple[float, int, str]] = []
        total = 0
        try:
            with os.scandir(_CACHE_DIR) as it:
                for entry in it:
                    if ".tmp-" in entry.name:
                        # A write in progress, or one that never got
                        # renamed into place after a crash — never a real
                        # cache entry, never an eviction candidate.
                        continue
                    try:
                        if not entry.is_file(follow_symlinks=False):
                            continue
                        st = entry.stat()
                    except OSError:
                        continue
                    total += st.st_size
                    entries.append((st.st_atime, st.st_size, entry.path))
        except OSError:
            logger.warning("image proxy cache eviction: could not scan %s", _CACHE_DIR)
            return

        cap = settings.image_proxy_cache_max_bytes
        if total <= cap:
            return

        # Evict down to 90% of the cap rather than exactly to it, so a
        # cache sitting right at the boundary doesn't re-scan on every
        # single miss that follows.
        target = int(cap * 0.9)
        entries.sort()  # oldest atime first
        freed = 0
        removed = 0
        for _atime, size, path in entries:
            if total - freed <= target:
                break
            try:
                os.remove(path)
                freed += size
                removed += 1
            except OSError:
                pass
        if removed:
            logger.info(
                "image proxy cache: evicted %d file(s), freed ~%.0f MB (was ~%.0f MB over a %.0f MB cap)",
                removed, freed / 1e6, (total - cap) / 1e6, cap / 1e6,
            )
    finally:
        _evict_state["running"] = False


def _cache_path(url: str) -> str:
    key = hashlib.sha256(url.encode()).hexdigest()
    return os.path.join(_CACHE_DIR, key)


def _guess_media_type(url: str) -> str:
    guessed, _ = mimetypes.guess_type(urlparse(url).path)
    return guessed or "image/jpeg"


async def _fetch_and_cache(url: str, path: str) -> bytes:
    try:
        # follow_redirects intentionally left at its default (False) —
        # image_proxy() below only checks _ALLOWED_HOSTS against this
        # *initial* url. If httpx followed a redirect, whatever host it
        # landed on would fetch without ever being checked against that
        # allowlist itself — image.tmdb.org redirecting anywhere isn't
        # something this server can prevent from happening, and a
        # never-checked redirect target is exactly the gap an
        # allowlisted proxy exists to not have. TMDB's image CDN is a
        # static asset host and has no legitimate reason to redirect;
        # if it ever does, failing here is the correct outcome, not
        # silently following it.
        async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
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
async def image_proxy(
    request: Request,
    background_tasks: BackgroundTasks,
    url: str = Query(..., description="Full https:// URL of an allowlisted CDN image"),
    exp: int = Query(..., description="Unix timestamp this signature is valid until"),
    sig: str = Query(..., description="HMAC signature over url+exp — see app/image_urls.py"),
):
    image_proxy_limiter.check(None, client_key(request))

    if not verify_proxy_signature(url, exp, sig):
        raise HTTPException(status_code=403, detail="Invalid or expired signature")

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
        # Only a miss can have grown the cache — a hit just read an
        # existing file, atime bump aside. See _evict_lru_if_over_cap's
        # own docstring for the debounce that makes this cheap to call
        # on every miss rather than something to gate further here.
        background_tasks.add_task(_evict_lru_if_over_cap)

    return Response(
        content=content,
        media_type=_guess_media_type(url),
        headers={"Cache-Control": _CACHE_CONTROL},
    )
