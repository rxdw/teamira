"""
"Your sources" — a link-based bring-your-history-over for YouTube and
Twitch, kept deliberately separate from the Settings > Import screen
(app/routers/imports.py) even though it reuses that screen's exact
preview -> review -> commit shape and even its response schemas.

Why separate rather than a third branch inside imports.py:
  - imports.py resolves pasted *titles* against the TMDB catalog
    (movies/series/anime); a YouTube/Twitch link resolves to whatever
    video(s) are actually at that link — there's no catalog match step
    at all, and "the video itself" *is* the result.
  - The result is a genuinely different media_type ("video", never movie/
    series/game/book), and lives on its own screen in the app ("your
    sources", reachable from Settings) with its own watched/watching/
    plan-to-watch shelves — see get_source_collections below — so it
    doesn't get mixed into the movie/show stats on the main Profile tab.

Import method is a pasted public URL, not a Google/Twitch account login:
  - Simpler and faster to ship than a real OAuth flow for either platform.
  - Works today for anything actually shareable — a public playlist, a
    channel's uploads, a single video/VOD, a Twitch channel's past
    broadcasts.
  - The one real gap: YouTube's "Watch Later" and "Liked videos" are
    private with no public URL at all (not even a login-gated one — the
    old public Watch Later feature is long gone), so those specifically
    can't be brought over this way. Bringing those in would need actual
    Google OAuth consent from inside the app — a bigger, separate feature
    if it's ever worth building, not a limitation of the URL parser here.

Two-step flow, same reasoning (and literally the same schemas) as
imports.py: POST .../preview resolves the link and returns rows for the
person to review and toggle watched/watching/plan-to-watch on, nothing
written yet; POST /import/commit (unchanged, imports.py) does the actual
write once they confirm — see mobile's sources_screen.dart for the UI.
"""
import logging

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app import models
from app.database import get_db
from app.deps import get_current_user
from app.routers.imports import ImportRowOut, ImportPreviewOut
from app.schemas import CollectionsOut
from app.adapters.youtube import YoutubeAdapter
from app.adapters.twitch import TwitchAdapter

logger = logging.getLogger("teamira.routers.sources")

router = APIRouter(prefix="/import/sources", tags=["sources"])

_youtube = YoutubeAdapter()
_twitch = TwitchAdapter()

# Every source this screen currently knows how to pull in. Kept as one
# list (rather than scattering "youtube"/"twitch" string literals) so
# adding a third platform later is: write the adapter, add one line here,
# nothing else in this file changes.
SOURCE_PLATFORMS = ("youtube", "twitch")


def _detect_platform(url: str) -> str:
    lowered = url.lower()
    if "youtube.com" in lowered or "youtu.be" in lowered:
        return "youtube"
    if "twitch.tv" in lowered:
        return "twitch"
    raise HTTPException(
        status_code=400,
        detail="That doesn't look like a YouTube or Twitch link",
    )


class SourcePreviewRequest(BaseModel):
    url: str


@router.post("/preview", response_model=ImportPreviewOut)
async def preview_source(
    payload: SourcePreviewRequest,
    current_user: models.User = Depends(get_current_user),
):
    url = payload.url.strip()
    if not url:
        raise HTTPException(status_code=400, detail="Paste a link first")

    platform = _detect_platform(url)
    adapter = _youtube if platform == "youtube" else _twitch

    try:
        items, label, truncated = await adapter.resolve(url)
    except RuntimeError as exc:
        # Adapter not configured (no API key on this server) — a server
        # setup problem, not something retrying fixes.
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except ValueError as exc:
        # Link parsed fine but nothing usable came back (private/deleted/
        # empty) — the person's problem to fix by pasting a different link.
        raise HTTPException(status_code=404, detail=str(exc)) from exc

    rows = [
        ImportRowOut(raw=item.title.en or item.id, matched=item, alternates=[], year=item.year)
        for item in items
    ]
    if truncated:
        label += " (showing the most recent — paste again later to catch up on newer ones)"
    return ImportPreviewOut(rows=rows, source_detected=label)


@router.get("/collections", response_model=CollectionsOut)
def get_source_collections(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The same watch_later/watching/watched split as /profile/collections
    (see routers/profile.py::get_collections), scoped to just the rows
    that came in through this screen — every WatchlistEntry whose
    `source` is one of SOURCE_PLATFORMS."""
    entries = (
        db.query(models.WatchlistEntry)
        .filter(
            models.WatchlistEntry.user_id == current_user.id,
            models.WatchlistEntry.source.in_(SOURCE_PLATFORMS),
        )
        .order_by(models.WatchlistEntry.updated_at.desc())
        .all()
    )
    return CollectionsOut(
        watch_later=[e for e in entries if e.status == models.WatchStatus.watch_later],
        watching=[e for e in entries if e.status == models.WatchStatus.watching],
        watched=[e for e in entries if e.status == models.WatchStatus.watched],
    )
