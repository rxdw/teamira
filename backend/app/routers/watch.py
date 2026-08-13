"""
"Where to watch" — availability data plus a monetization-ready click layer.

THE HONEST VERSION OF HOW THIS ACTUALLY MAKES MONEY, because the free data
source (TMDB, itself backed by JustWatch — see app/adapters/tmdb.py) does
NOT hand you a monetizable per-provider link on its own:

1. SHIPPED HERE: show availability for free using TMDB's data, and send
   every tap through OUR OWN `/media/watch-out` redirect below. Today that
   mostly opens each provider's own search page for the title (see
   app/seed.py) — no commission yet, but a real working link, plus a
   logged click. Every click lands in `outbound_clicks` regardless.

2. THE STANDARD ROUTE: apply for JustWatch's official Partner/Monetization
   API. Most "where to watch" apps get both their availability data AND
   monetizable per-provider deep links this way, with a JustWatch rev-share
   — search "JustWatch partner API" / see justwatch.com for their current
   developer contact. Requires an application/approval process.

3. DIRECT PROGRAMS you can join without waiting on #2:
   - Amazon Associates — usually approved fast, covers Prime Video
     rent/buy: add `&tag=yourtag-20` to the amazon.com URL in
     `affiliate_providers`.
   - Apple Services Performance Partners — covers Apple TV/iTunes rent/buy.
   - Impact, CJ Affiliate, Rakuten Advertising — the networks Hulu,
     Paramount+, Peacock, Starz, ESPN+ and others commonly run their
     affiliate programs through; apply to the network, then to that
     brand's specific program inside it.
   Netflix and Disney+ don't run public consumer affiliate programs as of
   this writing — nothing here will earn from those two specifically no
   matter which route you take; most competitors just deep-link there for
   free, same as this does.

Whichever of these lands, the only change needed is an UPDATE to a row in
`affiliate_providers` (see app/seed.py) — this router and the mobile app
don't change.
"""

from datetime import timedelta
from typing import Optional
from urllib.parse import quote, urlencode

from fastapi import APIRouter, Query, Request, Depends
from fastapi.responses import RedirectResponse
from sqlalchemy.orm import Session

from app import cache, models
from app.database import get_db
from app.adapters.tmdb import TmdbAdapter
from app.schemas import WatchProviderOut, WatchProvidersOut

router = APIRouter(prefix="/media", tags=["watch-providers"])
_tmdb = TmdbAdapter()

WATCH_PROVIDERS_TTL = timedelta(days=3)  # availability shifts monthly at most; no need to re-ask TMDB every visit

_VALID_MEDIA_TYPES = {m.value for m in models.MediaType}


def _segment_for(media_type: str) -> str:
    return "movie" if media_type == "movie" else "tv"


async def _fetch_providers(tmdb_id: str, segment: str, country: str) -> WatchProvidersOut:
    """The cached half of the round trip — availability only, no `out_url`
    yet, since that depends on this specific title's name/id/source, which
    we deliberately keep out of the cache key so every request for the
    same tmdb_id+country shares one TMDB call."""
    try:
        raw = await _tmdb.watch_providers(tmdb_id, segment, country)
    except RuntimeError:
        return WatchProvidersOut(country=country, providers=[])
    if not raw:
        return WatchProvidersOut(country=country, providers=[])

    seen: set[str] = set()
    providers: list[WatchProviderOut] = []
    for kind in ("flatrate", "rent", "buy"):
        for entry in raw.get(kind, []) or []:
            key = str(entry.get("provider_id"))
            if not key or key in seen:
                continue
            seen.add(key)
            providers.append(WatchProviderOut(
                provider_key=key,
                name=entry.get("provider_name", ""),
                logo_url=_tmdb.logo_url(entry.get("logo_path")),
                kind=kind,
                out_url="",  # the caller fills this in with request-specific info
            ))
    return WatchProvidersOut(country=country, providers=providers, more_url=raw.get("link"))


@router.get("/watch-providers", response_model=WatchProvidersOut)
async def watch_providers(
    request: Request,
    media_id: str = Query(...),
    source: str = Query(...),
    media_type: str = Query(...),
    title: str = Query(...),
    tmdb_id: Optional[str] = Query(None),
    country: str = Query("US"),
    db: Session = Depends(get_db),
):
    """Empty (not an error) whenever there's simply nothing to show: no
    tmdb_id at all (games, books, or manga), or TMDB/JustWatch just has
    no listing for this title in this country — both very ordinary, not
    failures.
    """
    if not tmdb_id or media_type not in ("movie", "series", "anime"):
        return WatchProvidersOut(country=country, providers=[])

    segment = _segment_for(media_type)
    cache_key = f"watch:{tmdb_id}:{segment}:{country}"
    payload_json = await cache.cached_dynamic(
        db, cache_key, lambda: _fetch_providers(tmdb_id, segment, country), ttl=WATCH_PROVIDERS_TTL,
    )
    cached = WatchProvidersOut.model_validate_json(payload_json)

    base = str(request.base_url).rstrip("/")
    providers = [
        WatchProviderOut(
            provider_key=p.provider_key,
            name=p.name,
            logo_url=p.logo_url,
            kind=p.kind,
            out_url=f"{base}/media/watch-out?" + urlencode({
                "media_id": media_id,
                "source": source,
                "media_type": media_type,
                "title": title,
                "provider_key": p.provider_key,
                "provider_name": p.name,
                "more_url": cached.more_url or "",
            }),
        )
        for p in cached.providers
    ]
    return WatchProvidersOut(country=cached.country, providers=providers, more_url=cached.more_url)


@router.get("/watch-out")
def watch_out(
    media_id: str = Query(...),
    source: str = Query(...),
    media_type: str = Query(...),
    title: str = Query(...),
    provider_key: str = Query(...),
    provider_name: str = Query(...),
    more_url: str = Query(""),
    db: Session = Depends(get_db),
):
    """The one link every "where to watch" tap actually opens — opened in
    the device's own browser, outside the app's authenticated API client,
    so this stays unauthenticated on purpose (no token to safely carry in
    a plain browser link, and nothing sensitive to protect here). Logs the
    click first regardless of payout status, then redirects to whatever
    `affiliate_providers` currently has configured for this provider,
    falling back to TMDB's combined watch page, and finally to a plain web
    search if even that's missing."""
    media_type_value = media_type if media_type in _VALID_MEDIA_TYPES else models.MediaType.movie.value

    provider = db.get(models.AffiliateProvider, provider_key)
    target = None
    if provider and provider.deep_link_template:
        target = provider.deep_link_template.format(title=quote(title))
    if not target:
        target = more_url or f"https://www.google.com/search?q={quote(f'watch {title}')}"

    db.add(models.OutboundClick(
        media_id=media_id,
        media_type=models.MediaType(media_type_value),
        source=source,
        title=title,
        provider_key=provider_key,
        provider_name=provider_name,
        target_url=target,
    ))
    db.commit()
    return RedirectResponse(url=target, status_code=302)
