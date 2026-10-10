"""Turns a *stored* image reference into the full URL a client can load,
at the moment a response is actually sent — never earlier.

Why this exists: poster/backdrop/photo/logo fields get written once, into
the DB (diary/watchlist/lists/etc.) or into the forever-caches
(CachedTitleDetail & friends), and then read back unchanged for as long
as that row exists. If what got stored was already a *full* URL — worse,
one already rewritten through this server's own /media/image-proxy (see
app/routers/image_proxy.py) — then every such row is permanently pinned
to whatever PUBLIC_API_BASE_URL happened to be set to on the day it was
written. Change that setting later (new domain, moved server) and every
old row silently breaks, needing a one-off migration to fix
(scripts/migrate_proxy_images.py is exactly that one-off fix, kept around
for existing rows and for the cache tables, which still store fully
resolved JSON — see that script's docstring).

The fix going forward: TMDB-backed adapters (app/adapters/tmdb.py) now
store just the bare path TMDB itself hands back — e.g.
"/2gBnvu6OEMq7Po2qMXd4JiAA4ZD.jpg", exactly as TMDB's own poster_path/
backdrop_path/profile_path/logo_path fields look — with no base URL and
no proxying applied at write time. resolve_image_url() below does that
work instead, and it's only ever called from a Pydantic field_serializer
(via ImageFieldsModel), which fires at response-serialization time, using
whatever PUBLIC_API_BASE_URL is configured *right now* — so a domain
change is just an .env edit, nothing stored needs touching again.

Values that already are a full URL — a non-TMDB source's own CDN link
(IGDB box art, Open Library covers, YouTube/Twitch thumbnails, Shikimori
manga covers), or a pre-existing DB/cache row from before this change —
are passed through untouched; there's no bare path to resolve, and
nothing here ever un-does an already-baked-in URL.
"""
import hashlib
import hmac
import time
from typing import Optional
from urllib.parse import parse_qs, quote, urlparse

from app.config import settings

TMDB_LOGO_BASE = "https://image.tmdb.org/t/p/w92"      # watch-provider logos
TMDB_PROFILE_BASE = "https://image.tmdb.org/t/p/w185"  # cast/person photos
TMDB_POSTER_BASE = "https://image.tmdb.org/t/p/w500"
TMDB_BACKDROP_BASE = "https://image.tmdb.org/t/p/w780"

# /media/image-proxy (app/routers/image_proxy.py) can't require a login
# token the way the rest of this API now does — it's loaded directly by
# the client's own image widget (Flutter's Image.network), which fetches
# a plain URL and can't attach an Authorization header. A signed, expiring
# URL is the standard substitute: anyone who finds the server's address
# still can't get it to fetch an arbitrary upstream URL for them, since
# they'd need this secret to produce a signature that verifies.
#
# The expiry is *window-aligned* (rounded up to the next multiple of
# _PROXY_SIG_WINDOW) rather than "now + TTL" computed fresh on every call.
# That matters because resolve_image_url() below runs at response-
# serialization time — every single time a cached MediaDetailOut (etc.)
# is served, not once when it's first cached (see this module's own
# docstring) — so a plain "now + TTL" would mint a brand new `sig`/`exp`
# on every response, changing the full image URL every time and defeating
# the client's own on-device image cache (which keys off the URL). Window-
# aligning means the same source url keeps producing the exact same
# signed proxy URL for the whole window, then rotates.
_PROXY_SIG_WINDOW = 7 * 24 * 3600  # 7 days


def _proxy_secret() -> bytes:
    return (settings.image_proxy_secret or settings.jwt_secret).encode("utf-8")


def _proxy_signature(url: str, exp: int) -> str:
    return hmac.new(_proxy_secret(), f"{url}:{exp}".encode("utf-8"), hashlib.sha256).hexdigest()[:32]


def verify_proxy_signature(url: str, exp: int, sig: str) -> bool:
    """Used by app/routers/image_proxy.py to check an incoming request's
    `exp`/`sig` before it will fetch `url` for anyone. `exp` in the past
    is rejected even with an otherwise-valid signature — that's the
    actual expiry; the signature alone never expires on its own."""
    if exp < int(time.time()):
        return False
    expected = _proxy_signature(url, exp)
    # constant-time compare — this is exactly the kind of secret-derived
    # value a timing side-channel could otherwise leak bit-by-bit.
    return hmac.compare_digest(expected, sig)


def _proxied(url: str) -> str:
    if not settings.public_api_base_url:
        return url
    exp = (int(time.time()) // _PROXY_SIG_WINDOW + 1) * _PROXY_SIG_WINDOW
    sig = _proxy_signature(url, exp)
    base = settings.public_api_base_url.rstrip('/')
    return (
        f"{base}/media/image-proxy?url={quote(url, safe='')}"
        f"&exp={exp}&sig={sig}"
    )


_TMDB_IMAGE_HOST = "image.tmdb.org"

# Google Books covers (books.google.com/books/content?id=...). The browser
# (Flutter web loads Image.network through XHR) rejects them with a CORS
# error because Google sends no Access-Control-Allow-Origin for these, so
# they have to go through /media/image-proxy like TMDB posters do. Native
# apps aren't affected by CORS, but proxying is harmless there too.
_GOOGLE_BOOKS_HOSTS = {"books.google.com", "books.googleusercontent.com"}


def _is_proxiable_source(url: str) -> bool:
    try:
        parsed = urlparse(url)
    except ValueError:
        return False
    if parsed.scheme != "https":
        return False
    if parsed.netloc == _TMDB_IMAGE_HOST:
        return True
    if parsed.netloc == "books.google.com":
        return parsed.path.startswith("/books/content")
    return parsed.netloc in _GOOGLE_BOOKS_HOSTS


def _tmdb_source_url(value: str) -> Optional[str]:
    """If `value` is a *legacy* baked-in reference to a proxiable image
    (TMDB, or a Google Books cover), returns the plain upstream URL
    underneath it; otherwise None.

    Two shapes get baked into old rows (diary/watchlist/lists, the forever
    caches and the daily feed snapshots written before bare paths were
    stored — see this module's docstring):

      1. a direct CDN link, `https://image.tmdb.org/t/p/w500/x.jpg` —
         unreachable from regions where that CDN is blocked, which is the
         whole reason the proxy exists;
      2. a link already run through *some* /media/image-proxy — pinned to
         whatever PUBLIC_API_BASE_URL (an old LAN IP, an old domain) and
         whatever signature window was current on the day it was written,
         so it breaks when either moves on (the `exp` also lapses after a
         week, after which the proxy refuses it).

    Both are unwrapped here so they can be re-issued against the *current*
    setting, exactly like a freshly stored bare path. Anything else
    (IGDB/Open Library/YouTube covers, user uploads) returns None and is
    left alone.

    Old Google Books rows may hold an http:// link; it is upgraded to
    https:// here, since the proxy only fetches https."""
    if value.startswith("http://books.google.com/books/content"):
        value = "https://" + value[len("http://"):]
    if _is_proxiable_source(value):
        return value
    try:
        parsed = urlparse(value)
    except ValueError:
        return None
    if parsed.path.endswith("/media/image-proxy"):
        inner = parse_qs(parsed.query).get("url", [""])[0]
        if inner and _is_proxiable_source(inner):
            return inner
    return None


def resolve_image_url(value: Optional[str], base: str) -> Optional[str]:
    """`value` is whatever's stored: None, a bare TMDB path ("/xyz.jpg"),
    or an already-full URL.

    A full URL from another source (IGDB box art, Open Library covers, ...)
    is returned as-is. A full URL that is really a *legacy TMDB image* —
    a direct image.tmdb.org link, or one baked through an old proxy base
    or an expired signature — is unwrapped and re-issued against the
    current PUBLIC_API_BASE_URL (or left as the direct CDN link when no
    proxy is configured), so old cached rows heal themselves instead of
    needing a one-off migration."""
    if not value:
        return value
    if value.startswith("http://") or value.startswith("https://"):
        source = _tmdb_source_url(value)
        return _proxied(source) if source else value
    return _proxied(f"{base}{value}")
