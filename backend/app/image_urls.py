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
from typing import Optional
from urllib.parse import quote

from app.config import settings

TMDB_LOGO_BASE = "https://image.tmdb.org/t/p/w92"      # watch-provider logos
TMDB_PROFILE_BASE = "https://image.tmdb.org/t/p/w185"  # cast/person photos
TMDB_POSTER_BASE = "https://image.tmdb.org/t/p/w500"
TMDB_BACKDROP_BASE = "https://image.tmdb.org/t/p/w780"


def _proxied(url: str) -> str:
    if not settings.public_api_base_url:
        return url
    return f"{settings.public_api_base_url.rstrip('/')}/media/image-proxy?url={quote(url, safe='')}"


def resolve_image_url(value: Optional[str], base: str) -> Optional[str]:
    """`value` is whatever's stored: None, a bare TMDB path ("/xyz.jpg"),
    or an already-full URL (other source, or a legacy row) — the last
    case is returned as-is."""
    if not value:
        return value
    if value.startswith("http://") or value.startswith("https://"):
        return value
    return _proxied(f"{base}{value}")
