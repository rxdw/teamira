"""
Automatic watch tracking ("scrobbling") — how Trakt actually pulls
ahead of manual-logging-only apps, and the honest picture of what it takes
to build, because the three sources below are NOT equally easy or equally
durable:

- PLEX / JELLYFIN WEBHOOKS (plex_webhook / jellyfin_webhook below): official,
  stable, first-class features of those servers. Plex Pass webhooks POST a
  JSON payload (as a `payload` form field) on play/pause/stop/scrobble
  events; Jellyfin's official "Webhook" plugin does the same with
  configurable trigger events. Both typically carry the library's own
  TMDB/IMDB id, which is why these resolve reliably against our catalog via
  TmdbAdapter.resolve_external_id. This is the strongest, lowest-
  maintenance integration of the three — ship this first.

- KODI: no built-in webhook system, but addons get direct Python callbacks
  (xbmc.Player.onPlayBackStarted/onPlayBackStopped) — see
  integrations/kodi/ for a minimal addon that POSTs a ScrobblePayload
  straight to `generic_scrobble` below. Also stable; just requires
  installing an addon instead of flipping a server setting.

- BROWSER EXTENSION (Netflix/Hulu/Disney+/Crunchyroll): there is no
  official API for any of these for personal viewing data. A scrobbler
  extension works by injecting a content script into the watch page,
  reading whatever title text it can find (usually the document title or
  a JSON blob the page embeds for its own player UI), and polling the
  <video> element's currentTime/duration to know progress — then calling
  `generic_scrobble` once that crosses a threshold. This is inherently
  fragile: any of these sites can change its page structure at any time
  and silently break scrobbling for just that site, which is exactly why
  Trakt maintains this as ongoing work, not a one-time build. See
  integrations/browser-extension/ for a working skeleton and what
  specifically needs upkeep over time.

All three funnel into `_ingest()` below, which does the actual identity
resolution + diary/episode-progress writes — the one place "what counts as
watched" lives, regardless of where the event came from.
"""

import json
import secrets
import uuid
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy.orm import Session

from app import models
from app.database import get_db
from app.deps import get_current_user
from app.adapters.tmdb import TmdbAdapter
from app.routers.diary import log_watched
from app.schemas import (
    ExternalIds,
    IntegrationTokenOut,
    LocalizedText,
    MediaItem,
    ScrobbleEventOut,
    ScrobblePayload,
)

router = APIRouter(prefix="/integrations", tags=["integrations"])
_tmdb = TmdbAdapter()

# Below this fraction watched, a progress event doesn't count — mirrors the
# "did you actually finish it" bar most scrobblers use (Trakt/Plex both
# land somewhere around 80-90%). Only relevant to generic_scrobble; the
# Plex/Jellyfin webhook handlers only ever act on an explicit
# completed-playback event in the first place, so this threshold doesn't
# apply there.
WATCHED_THRESHOLD = 0.85


# ---------------------------------------------------------------------------
# Setup — one secret token per user, embedded in every URL below instead of
# a normal Authorization header, because Plex/Jellyfin/Kodi/a browser
# extension mostly can't be configured to send custom headers, only a URL.
# ---------------------------------------------------------------------------

def _token_out(request: Request, token: str) -> IntegrationTokenOut:
    base = str(request.base_url).rstrip("/")
    return IntegrationTokenOut(
        token=token,
        plex_webhook_url=f"{base}/integrations/{token}/plex",
        jellyfin_webhook_url=f"{base}/integrations/{token}/jellyfin",
        kodi_url=f"{base}/integrations/{token}/scrobble",
        extension_ingest_url=f"{base}/integrations/{token}/scrobble",
    )


@router.get("/token", response_model=IntegrationTokenOut)
def get_integration_token(
    request: Request,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Creates the token on first request rather than at signup — most
    people never open Settings > Integrations, no reason for everyone to
    have one sitting unused."""
    if not current_user.scrobble_token:
        current_user.scrobble_token = secrets.token_urlsafe(24)
        db.commit()
    return _token_out(request, current_user.scrobble_token)


@router.post("/token/rotate", response_model=IntegrationTokenOut)
def rotate_integration_token(
    request: Request,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Invalidates every previously configured Plex/Jellyfin/Kodi/browser
    URL at once — use if a token ever leaks (pasted somewhere public by
    mistake, screenshot with it visible, etc). Every integration needs
    re-pasting the new URL afterward."""
    current_user.scrobble_token = secrets.token_urlsafe(24)
    db.commit()
    return _token_out(request, current_user.scrobble_token)


@router.get("/events", response_model=list[ScrobbleEventOut])
def recent_scrobble_events(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The debugging surface for "why didn't my Netflix watch show up" —
    every incoming event, matched or not, newest first."""
    rows = (
        db.query(models.ScrobbleEvent)
        .filter_by(user_id=current_user.id)
        .order_by(models.ScrobbleEvent.created_at.desc())
        .limit(50)
        .all()
    )
    return [ScrobbleEventOut.model_validate(r) for r in rows]


def _user_for_token(db: Session, token: str) -> models.User:
    user = db.query(models.User).filter(models.User.scrobble_token == token).first()
    if user is None:
        raise HTTPException(status_code=404, detail="Unknown integration token")
    return user


# ---------------------------------------------------------------------------
# The shared ingestion path
# ---------------------------------------------------------------------------

async def _ingest(db: Session, user: models.User, integration: str, payload: ScrobblePayload) -> None:
    item: Optional[MediaItem] = None
    if payload.tmdb_id or payload.imdb_id:
        media_type_hint = payload.media_type if payload.media_type in ("movie", "series") else "movie"
        item = await _tmdb.resolve_external_id(
            tmdb_id=payload.tmdb_id, imdb_id=payload.imdb_id, media_type=media_type_hint,
        )

    if item is None:
        # No catalog match — still log the evening, just as a lightweight
        # standalone snapshot (the same idea as any manual entry for a
        # title search that never resolved), tagged with where it came
        # from. A real watched evening logged imperfectly beats one
        # silently dropped.
        media_type = payload.media_type if payload.media_type in ("movie", "series") else "movie"
        item = MediaItem(
            id=f"scrobble-{uuid.uuid4()}",
            media_type=media_type,
            external_ids=ExternalIds(tmdb=payload.tmdb_id, imdb=payload.imdb_id),
            title=LocalizedText(en=payload.title),
            description=LocalizedText(),
            year=payload.year,
            genres=[],
            source=integration,
        )

    log_watched(db, user.id, item, watched_at=datetime.utcnow())

    matched = not item.id.startswith("scrobble-")

    # A matched series/anime episode also advances the season tracker — the
    # same EpisodeProgress rows the manual "mark watched" toggle writes —
    # so a night of scrobbled episodes shows up ticked off there too, not
    # just as repeated diary rows.
    if matched and item.media_type in ("series", "anime") and payload.season is not None and payload.episode is not None:
        existing = (
            db.query(models.EpisodeProgress)
            .filter_by(user_id=user.id, source=item.source, media_id=item.id,
                       season=payload.season, episode=payload.episode)
            .first()
        )
        if existing is None:
            db.add(models.EpisodeProgress(
                user_id=user.id, media_id=item.id, source=item.source,
                season=payload.season, episode=payload.episode,
            ))

    db.add(models.ScrobbleEvent(
        user_id=user.id,
        integration=integration,
        raw_title=payload.title,
        matched_media_id=item.id if matched else None,
        matched_source=item.source if matched else None,
        action="logged",
    ))
    db.commit()


def _log_ignored(db: Session, user: models.User, integration: str, title: Optional[str], detail: str) -> None:
    db.add(models.ScrobbleEvent(
        user_id=user.id, integration=integration, raw_title=title,
        action="ignored", detail=detail,
    ))
    db.commit()


# ---------------------------------------------------------------------------
# Plex — https://support.plex.tv/articles/115002267687-webhooks/
# ---------------------------------------------------------------------------

@router.post("/{token}/plex")
async def plex_webhook(token: str, request: Request, db: Session = Depends(get_db)):
    user = _user_for_token(db, token)
    form = await request.form()
    raw = form.get("payload")
    if raw is None:
        return {"ignored": "no payload field"}
    try:
        payload = json.loads(raw)
    except ValueError:
        return {"ignored": "payload wasn't valid JSON"}

    event = payload.get("event")
    # Plex's own "this counts as watched" event, firing once per view
    # around Plex's configured watched-threshold (a Plex-side setting,
    # usually ~90%). Deliberately ignoring play/pause/resume/stop — acting
    # on those would double-count a single sitting, or fire on someone who
    # only watched the first five minutes.
    if event != "media.scrobble":
        return {"ignored": event}

    parsed = _parse_plex_metadata(payload.get("Metadata") or {})
    if parsed is None:
        _log_ignored(db, user, "plex", None, "unsupported media type")
        return {"ignored": "unsupported media type"}

    await _ingest(db, user, "plex", parsed)
    return {"status": "ok"}


def _parse_plex_metadata(metadata: dict) -> Optional[ScrobblePayload]:
    kind = metadata.get("type")  # "movie" | "episode"
    if kind not in ("movie", "episode"):
        return None
    tmdb_id = imdb_id = None
    for guid in metadata.get("Guid") or []:  # e.g. {"id": "tmdb://603"}
        gid = guid.get("id", "")
        if gid.startswith("tmdb://"):
            tmdb_id = gid[len("tmdb://"):]
        elif gid.startswith("imdb://"):
            imdb_id = gid[len("imdb://"):]
    title = metadata.get("grandparentTitle") if kind == "episode" else metadata.get("title")
    return ScrobblePayload(
        title=title or metadata.get("title") or "Untitled",
        media_type="series" if kind == "episode" else "movie",
        season=metadata.get("parentIndex"),
        episode=metadata.get("index"),
        year=metadata.get("year"),
        tmdb_id=tmdb_id,
        imdb_id=imdb_id,
        completed=True,
    )


# ---------------------------------------------------------------------------
# Jellyfin — the official "Webhook" plugin (not built into Jellyfin core)
# ---------------------------------------------------------------------------

@router.post("/{token}/jellyfin")
async def jellyfin_webhook(token: str, request: Request, db: Session = Depends(get_db)):
    user = _user_for_token(db, token)
    try:
        payload = await request.json()
    except (json.JSONDecodeError, ValueError):
        return {"ignored": "payload wasn't valid JSON"}

    notification_type = payload.get("NotificationType")
    # Only act on an actually-finished playback (or an explicit "mark
    # played") — everything else risks double-logging the same sitting.
    if notification_type not in ("PlaybackStop", "ItemMarkedAsPlayed"):
        return {"ignored": notification_type}
    if notification_type == "PlaybackStop" and not payload.get("PlayedToCompletion"):
        return {"ignored": "stopped before the end"}

    parsed = _parse_jellyfin_payload(payload)
    if parsed is None:
        _log_ignored(db, user, "jellyfin", payload.get("Name"), "unsupported item type")
        return {"ignored": "unsupported item type"}

    await _ingest(db, user, "jellyfin", parsed)
    return {"status": "ok"}


def _parse_jellyfin_payload(payload: dict) -> Optional[ScrobblePayload]:
    """The webhook plugin's template determines exactly which fields show
    up — this assumes the commonly-documented defaults (ItemType, Name,
    SeriesName, SeasonNumber, EpisodeNumber, Provider_tmdb/Provider_imdb).
    If matches aren't landing, open the plugin's webhook template in
    Jellyfin and confirm these field names against the current version;
    community plugin field names have moved before and aren't guaranteed
    stable the way Plex's built-in payload is."""
    item_type = (payload.get("ItemType") or "").lower()
    if item_type not in ("movie", "episode"):
        return None
    tmdb_id = payload.get("Provider_tmdb")
    imdb_id = payload.get("Provider_imdb")
    title = payload.get("SeriesName") if item_type == "episode" else payload.get("Name")
    return ScrobblePayload(
        title=title or payload.get("Name") or "Untitled",
        media_type="series" if item_type == "episode" else "movie",
        season=payload.get("SeasonNumber"),
        episode=payload.get("EpisodeNumber"),
        year=payload.get("Year"),
        tmdb_id=str(tmdb_id) if tmdb_id else None,
        imdb_id=imdb_id,
        completed=True,
    )


# ---------------------------------------------------------------------------
# Generic — what the Kodi addon and the browser extension both call
# directly, since neither has a webhook format of its own to translate from.
# ---------------------------------------------------------------------------

@router.post("/{token}/scrobble")
async def generic_scrobble(
    token: str,
    payload: ScrobblePayload,
    integration: str = Query("scrobble", description='e.g. "kodi", "netflix", "hulu"'),
    db: Session = Depends(get_db),
):
    user = _user_for_token(db, token)
    if not payload.completed and payload.progress < WATCHED_THRESHOLD:
        _log_ignored(db, user, integration, payload.title, "below watched threshold")
        return {"ignored": "below watched threshold"}
    await _ingest(db, user, integration, payload)
    return {"status": "ok"}
