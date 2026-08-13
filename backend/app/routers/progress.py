from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app import models
from app.database import get_db
from app.deps import get_current_user
from app.schemas import (
    CompleteSeriesRequest,
    EpisodeKey,
    EpisodeRatingRequest,
    ProgressToggleRequest,
    SeriesProgressOut,
    WatchedEpisodeOut,
)

router = APIRouter(prefix="/progress", tags=["progress"])


def _watched_out(db: Session, user_id: str, media_id: str, source: str) -> SeriesProgressOut:
    rows = (
        db.query(models.EpisodeProgress)
        .filter_by(user_id=user_id, media_id=media_id, source=source)
        .all()
    )
    return SeriesProgressOut(
        watched=[
            WatchedEpisodeOut(
                season=r.season,
                episode=r.episode,
                watched_at=r.watched_at.isoformat() if r.watched_at else "",
                rating=r.rating,
                note=r.note,
            )
            for r in rows
        ]
    )


@router.get("/series", response_model=SeriesProgressOut)
def get_series_progress(
    media_id: str = Query(...),
    source: str = Query(...),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Which episodes of one series the current user has marked watched —
    loaded once when the title screen's season tracker opens."""
    return _watched_out(db, current_user.id, media_id, source)


@router.post("/toggle", response_model=SeriesProgressOut)
def toggle_progress(
    payload: ProgressToggleRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Marks or unmarks one or more episodes at once — a single tap sends
    one EpisodeKey, "mark whole season watched" sends every episode in
    that season. Returns the full updated watched-set so the client can
    just replace its local copy rather than reconcile a diff.

    Also keeps a series' single diary row (see models.DiaryEntry's own
    docstring) in sync: unmarking an episode here — the episode list's
    own "remove from watched" — doesn't go through log_watched at all,
    so without this the diary's episode count would just sit stale until
    the next time something *was* logged. Only touches episodes_watched;
    the row's date/season/episode/rating stay whatever they were last
    logged as, since un-watching one episode isn't itself an evening
    worth re-dating.
    """
    for ep in payload.episodes:
        existing = (
            db.query(models.EpisodeProgress)
            .filter_by(
                user_id=current_user.id,
                source=payload.source,
                media_id=payload.media_id,
                season=ep.season,
                episode=ep.episode,
            )
            .first()
        )
        if payload.watched and existing is None:
            db.add(models.EpisodeProgress(
                user_id=current_user.id,
                source=payload.source,
                media_id=payload.media_id,
                season=ep.season,
                episode=ep.episode,
            ))
        elif not payload.watched and existing is not None:
            db.delete(existing)
    db.flush()

    diary_entry = (
        db.query(models.DiaryEntry)
        .filter(
            models.DiaryEntry.user_id == current_user.id,
            models.DiaryEntry.media_id == payload.media_id,
            models.DiaryEntry.source == payload.source,
            models.DiaryEntry.season.isnot(None),
        )
        .first()
    )
    if diary_entry is not None:
        diary_entry.episodes_watched = (
            db.query(models.EpisodeProgress)
            .filter_by(user_id=current_user.id, source=payload.source, media_id=payload.media_id)
            .count()
        )

    db.commit()
    return _watched_out(db, current_user.id, payload.media_id, payload.source)


@router.post("/episode-rating", response_model=SeriesProgressOut)
def rate_episode(
    payload: EpisodeRatingRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Sets one episode's own lightweight rating/note from the episode
    list — separate from the full log ritual, and never creates a diary
    row by itself (see EpisodeRatingRequest's own docstring). Marks the
    episode watched if it wasn't already; a rating implies you've seen it.
    Returns the full updated watched-set, same as /toggle, so the client
    can just replace its local copy.
    """
    existing = (
        db.query(models.EpisodeProgress)
        .filter_by(
            user_id=current_user.id,
            source=payload.source,
            media_id=payload.media_id,
            season=payload.season,
            episode=payload.episode,
        )
        .first()
    )
    if existing is None:
        existing = models.EpisodeProgress(
            user_id=current_user.id,
            source=payload.source,
            media_id=payload.media_id,
            season=payload.season,
            episode=payload.episode,
        )
        db.add(existing)
    existing.rating = payload.rating
    existing.note = payload.note
    db.commit()
    return _watched_out(db, current_user.id, payload.media_id, payload.source)


@router.post("/complete", status_code=204)
def complete_series(
    payload: CompleteSeriesRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The one place a series' WatchlistEntry actually moves to `watched`
    once episode-level logging is involved — called by the client once
    it sees every episode ticked off, never inferred server-side from a
    single episode log (see routers/diary.py::log_watched, which only
    ever sets `watching`). A no-op if there's no watchlist row yet — the
    client only calls this after at least one episode log has already
    created one, but there's nothing useful to promote if it hasn't."""
    watchlist_entry = (
        db.query(models.WatchlistEntry)
        .filter(
            models.WatchlistEntry.user_id == current_user.id,
            models.WatchlistEntry.media_id == payload.media_id,
            models.WatchlistEntry.source == payload.source,
        )
        .first()
    )
    if watchlist_entry is not None:
        watchlist_entry.status = models.WatchStatus.watched
        db.commit()
    return None
