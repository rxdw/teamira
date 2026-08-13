from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.database import get_db
from app import models
from app.deps import get_current_user
from app.schemas import DiaryEntryCreate, DiaryEntryOut, DiaryEntryUpdate

router = APIRouter(prefix="/diary", tags=["diary"])


def _linked_partner_username(db: Session, user_id: str) -> Optional[str]:
    """Small, deliberately local copy of the lookup in routers/partner.py —
    that module imports `log_watched` from here, so importing back from it
    would be circular. Just enough to resolve "watched with" toggles."""
    link = (
        db.query(models.PartnerLink)
        .filter(
            models.PartnerLink.status == models.PartnerLinkStatus.active,
            or_(models.PartnerLink.owner_id == user_id, models.PartnerLink.partner_id == user_id),
        )
        .first()
    )
    if link is None:
        return None
    other = link.partner if link.owner_id == user_id else link.owner
    return other.username if other else None


def _parse_watched_at(raw: Optional[str]) -> datetime:
    if not raw:
        return datetime.utcnow()
    try:
        # accepts both a bare date ("2026-07-10") and a full ISO datetime
        return datetime.fromisoformat(raw)
    except ValueError:
        raise HTTPException(status_code=400, detail="watched_at must be an ISO date or datetime")


def _to_out(entry: models.DiaryEntry) -> DiaryEntryOut:
    return DiaryEntryOut(
        id=entry.id,
        media_id=entry.media_id,
        media_type=entry.media_type.value if hasattr(entry.media_type, "value") else entry.media_type,
        source=entry.source,
        title_ru=entry.title_ru,
        title_en=entry.title_en,
        poster_url=entry.poster_url,
        backdrop_url=entry.backdrop_url,
        season=entry.season,
        episode=entry.episode,
        episodes_watched=entry.episodes_watched,
        rating=entry.rating,
        note=entry.note,
        mood_tags=entry.mood_tags or [],
        favorite_cast=entry.favorite_cast or [],
        watched_with_username=entry.watched_with_username,
        is_rewatch=bool(entry.is_rewatch),
        watched_at=entry.watched_at.isoformat() if entry.watched_at else "",
        created_at=entry.created_at.isoformat() if entry.created_at else "",
    )


def log_watched(
    db: Session,
    user_id: str,
    item,
    watched_at: datetime,
    rating: int | None = None,
    note: str | None = None,
    mood_tags: list[str] | None = None,
    favorite_cast: list[dict] | None = None,
    watched_with_username: str | None = None,
    is_favorite: bool = False,
    season: int | None = None,
    episode: int | None = None,
    episode_count: int | None = None,
) -> models.DiaryEntry:
    """The actual "log one evening" write — one DiaryEntry row plus the
    upserted WatchlistEntry/ActivityEvent bookkeeping. Factored out of
    `log_entry` below so co-viewing's "watched" button can write the exact
    same evening into *both* linked accounts' diaries (see
    routers/partner.py::mark_coview_watched) without duplicating this
    logic. Caller is responsible for `db.commit()`.

    `season` set (with or without `episode`) means this log is for a
    series. A series gets exactly one DiaryEntry row, ever — created the
    first time any episode of it is logged, and updated in place every
    time after that (see models.DiaryEntry's own docstring). So this
    never inserts a second row for a series; it finds the existing one
    (if any) and refreshes its date/season/episode/progress instead.
    Movies and other whole-title logs (season/episode both null) are
    unaffected and keep writing one fresh row per evening, with rewatch
    meaning "any prior row for this title".

    `episode_count`, meaningful only alongside a season-completion log
    (season set, episode null), is how many episodes that season has —
    used below only as a fallback when episode-level progress can't be
    counted for some reason.
    """
    display_title = item.title.en or item.title.ru or "—"
    if season is not None and episode is not None:
        activity_title = f"{display_title} — S{season}E{episode}"
    elif season is not None:
        activity_title = f"{display_title} — Season {season}"
    else:
        activity_title = display_title

    is_series_log = season is not None

    # A watchlist entry already sitting at `watched` means the series (or
    # movie) had already been finished at least once before *this* log —
    # that's what "rewatch" means for the single series row too, not
    # "already has a diary row" (it always will, after the first log).
    watchlist_entry = (
        db.query(models.WatchlistEntry)
        .filter(
            models.WatchlistEntry.user_id == user_id,
            models.WatchlistEntry.media_id == item.id,
            models.WatchlistEntry.source == item.source,
        )
        .first()
    )
    was_already_watched = (
        watchlist_entry is not None and watchlist_entry.status == models.WatchStatus.watched
    )

    entry = None
    if is_series_log:
        entry = (
            db.query(models.DiaryEntry)
            .filter(
                models.DiaryEntry.user_id == user_id,
                models.DiaryEntry.media_id == item.id,
                models.DiaryEntry.source == item.source,
                models.DiaryEntry.season.isnot(None),
            )
            .first()
        )
    prior_count = 0
    if not is_series_log:
        prior_count = (
            db.query(models.DiaryEntry)
            .filter(
                models.DiaryEntry.user_id == user_id,
                models.DiaryEntry.media_id == item.id,
                models.DiaryEntry.source == item.source,
            )
            .count()
        )

    # Record this exact episode as watched *before* counting progress
    # below, so a per-episode log (season+episode both set) sees itself
    # included in its own episodes_watched count rather than being a beat
    # behind. Harmless if the client already ticked it via
    # POST /progress/toggle (see mobile's markEpisodeWatched) — this is
    # just an upsert either way.
    is_episode_log = season is not None and episode is not None
    if is_episode_log:
        existing_progress = (
            db.query(models.EpisodeProgress)
            .filter_by(
                user_id=user_id,
                source=item.source,
                media_id=item.id,
                season=season,
                episode=episode,
            )
            .first()
        )
        if existing_progress is None:
            db.add(models.EpisodeProgress(
                user_id=user_id,
                source=item.source,
                media_id=item.id,
                season=season,
                episode=episode,
            ))
        else:
            existing_progress.watched_at = watched_at
        # This session doesn't autoflush — without this, a brand-new
        # EpisodeProgress row above wouldn't be visible to the count
        # query just below yet, undercounting this episode by one.
        db.flush()

    # Episode-level progress (see the is_episode_log block below) is the
    # source of truth for "how much of this series has been watched" —
    # counted fresh each time rather than incremented, so it's correct
    # regardless of how many different places call into this function.
    # Only falls back to episode_count (a season's worth) when this log
    # itself carries no episode-level detail to count from and there's no
    # existing row to fall back to.
    def _episodes_watched_count() -> int:
        count = (
            db.query(models.EpisodeProgress)
            .filter_by(user_id=user_id, source=item.source, media_id=item.id)
            .count()
        )
        if count > 0:
            return count
        if entry is not None and entry.episodes_watched:
            return entry.episodes_watched
        if episode_count:
            return episode_count
        return 0

    if is_series_log:
        episodes_watched = _episodes_watched_count()
        entry_runtime_minutes = (
            episodes_watched * item.runtime_minutes if item.runtime_minutes else None
        )
        is_rewatch = 1 if (was_already_watched or (entry is not None and entry.is_rewatch)) else 0

        if entry is None:
            entry = models.DiaryEntry(
                user_id=user_id,
                media_id=item.id,
                media_type=item.media_type,
                source=item.source,
                genres=item.genres,
            )
            db.add(entry)

        entry.title_ru = item.title.ru
        entry.title_en = item.title.en
        entry.poster_url = item.poster_url
        entry.backdrop_url = item.backdrop_url or entry.backdrop_url
        entry.year = item.year
        entry.director = item.director
        entry.season = season
        # A season-completion call doesn't know a specific episode — keep
        # whatever episode this row last pointed at rather than blanking
        # it out.
        if episode is not None:
            entry.episode = episode
        entry.episodes_watched = episodes_watched
        if rating is not None:
            entry.rating = rating
        if note is not None:
            entry.note = note
        if mood_tags is not None:
            entry.mood_tags = mood_tags
        if favorite_cast is not None:
            entry.favorite_cast = favorite_cast
        if watched_with_username is not None:
            entry.watched_with_username = watched_with_username
        entry.is_rewatch = is_rewatch
        entry.watched_at = watched_at
        entry.genres = item.genres
        entry.runtime_minutes = entry_runtime_minutes
    else:
        entry = models.DiaryEntry(
            user_id=user_id,
            media_id=item.id,
            media_type=item.media_type,
            source=item.source,
            title_ru=item.title.ru,
            title_en=item.title.en,
            poster_url=item.poster_url,
            backdrop_url=item.backdrop_url,
            season=season,
            episode=episode,
            rating=rating,
            note=note,
            mood_tags=mood_tags or [],
            favorite_cast=favorite_cast or [],
            watched_with_username=watched_with_username,
            is_rewatch=1 if prior_count > 0 else 0,
            watched_at=watched_at,
            genres=item.genres,
            runtime_minutes=item.runtime_minutes,
            year=item.year,
            director=item.director,
        )
        db.add(entry)

    # Keep the "current status" snapshot (watched/plan-to-watch shelves,
    # profile stats) in sync with the newest logged evening for this title —
    # `watchlist_entry` was already fetched above, for the rewatch check.
    # Logging one episode or one season only ever means "at least that
    # much has been watched" — not "the whole series is done". That final
    # step is explicit, via POST /progress/complete once the client sees
    # every episode ticked off. A plain movie/whole-title log (season and
    # episode both null) keeps going straight to `watched`, same as
    # always. Either way, a title already `watched` never gets silently
    # downgraded back to `watching` by a later rewatch-style log.
    is_partial_log = season is not None
    is_episode_log = season is not None and episode is not None
    new_entry_status = models.WatchStatus.watching if is_partial_log else models.WatchStatus.watched

    if watchlist_entry is None:
        watchlist_entry = models.WatchlistEntry(
            user_id=user_id,
            media_id=item.id,
            media_type=item.media_type,
            source=item.source,
            title_ru=item.title.ru,
            title_en=item.title.en,
            poster_url=item.poster_url,
            backdrop_url=item.backdrop_url,
            year=item.year,
            genres=item.genres,
            rating=item.rating,
            runtime_minutes=item.runtime_minutes,
            status=new_entry_status,
        )
        db.add(watchlist_entry)
    else:
        if watchlist_entry.status != models.WatchStatus.watched:
            watchlist_entry.status = new_entry_status
        watchlist_entry.runtime_minutes = item.runtime_minutes or watchlist_entry.runtime_minutes
        watchlist_entry.backdrop_url = item.backdrop_url or watchlist_entry.backdrop_url
    if rating is not None:
        watchlist_entry.user_rating = rating
    if note is not None:
        watchlist_entry.note = note
    if mood_tags is not None:
        watchlist_entry.mood_tags = mood_tags
    if favorite_cast is not None:
        watchlist_entry.favorite_cast = favorite_cast
    if is_favorite:
        # Only ever turns this ON from the log form — see the field's own
        # docstring on DiaryEntryCreate for why unchecked never unfavorites.
        watchlist_entry.is_favorite = True
    watchlist_entry.watched_at = watched_at

    verb = "rewatched" if prior_count > 0 else "watched"
    db.add(models.ActivityEvent(
        user_id=user_id,
        verb=verb,
        media_title=activity_title,
        media_type=item.media_type,
        media_id=item.id,
        source=item.source,
        poster_url=item.poster_url,
        rating=rating,
    ))
    return entry


@router.post("", response_model=DiaryEntryOut, status_code=201)
def log_entry(
    payload: DiaryEntryCreate,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    watched_with_username = (
        _linked_partner_username(db, current_user.id)
        if payload.watched_with_partner
        else None
    )
    entry = log_watched(
        db,
        current_user.id,
        payload.item,
        watched_at=_parse_watched_at(payload.watched_at),
        rating=payload.rating,
        note=payload.note,
        mood_tags=payload.mood_tags,
        favorite_cast=[c.model_dump() for c in payload.favorite_cast] if payload.favorite_cast else None,
        watched_with_username=watched_with_username,
        is_favorite=bool(payload.is_favorite),
        season=payload.season,
        episode=payload.episode,
        episode_count=payload.episode_count,
    )
    db.commit()
    db.refresh(entry)
    return _to_out(entry)


@router.get("", response_model=List[DiaryEntryOut])
def list_diary(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Full diary, newest evening first — the client groups these by
    calendar date (today / yesterday / ...) for the Diary tab."""
    entries = (
        db.query(models.DiaryEntry)
        .filter(models.DiaryEntry.user_id == current_user.id)
        .order_by(models.DiaryEntry.watched_at.desc())
        .all()
    )
    return [_to_out(e) for e in entries]


@router.get("/media/{media_id}", response_model=List[DiaryEntryOut])
def media_history(
    media_id: str,
    source: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Every logged evening for one title, oldest first — feeds the
    "your evenings with this film" timeline on the title screen."""
    entries = (
        db.query(models.DiaryEntry)
        .filter(
            models.DiaryEntry.user_id == current_user.id,
            models.DiaryEntry.media_id == media_id,
            models.DiaryEntry.source == source,
        )
        .order_by(models.DiaryEntry.watched_at.asc())
        .all()
    )
    return [_to_out(e) for e in entries]


@router.patch("/{entry_id}", response_model=DiaryEntryOut)
def update_entry(
    entry_id: str,
    payload: DiaryEntryUpdate,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Edits an already-logged evening in place — the rating and/or review
    text most of the time, occasionally the mood tags or the date. Only
    fields actually present in the request body are touched
    (`exclude_unset`), so a client can send just `{"note": "..."}` to fix
    a typo without disturbing the rating next to it.

    Mirrors the watchlist snapshot the same way `log_watched` does when
    this happens to be the *most recent* logged evening for that title —
    editing an older rewatch's review shouldn't overwrite what the
    watched shelf shows for a title that's since been watched again.
    """
    entry = (
        db.query(models.DiaryEntry)
        .filter(models.DiaryEntry.id == entry_id, models.DiaryEntry.user_id == current_user.id)
        .first()
    )
    if not entry:
        raise HTTPException(status_code=404, detail="Diary entry not found")

    changes = payload.model_dump(exclude_unset=True)
    if "watched_at" in changes:
        entry.watched_at = _parse_watched_at(changes["watched_at"])
    if "rating" in changes:
        entry.rating = changes["rating"]
    if "note" in changes:
        entry.note = changes["note"]
    if "mood_tags" in changes:
        entry.mood_tags = changes["mood_tags"] or []
    if "favorite_cast" in changes:
        entry.favorite_cast = changes["favorite_cast"] or []

    latest = (
        db.query(models.DiaryEntry)
        .filter(
            models.DiaryEntry.user_id == current_user.id,
            models.DiaryEntry.media_id == entry.media_id,
            models.DiaryEntry.source == entry.source,
        )
        .order_by(models.DiaryEntry.watched_at.desc())
        .first()
    )
    if latest is not None and latest.id == entry.id:
        watchlist_entry = (
            db.query(models.WatchlistEntry)
            .filter(
                models.WatchlistEntry.user_id == current_user.id,
                models.WatchlistEntry.media_id == entry.media_id,
                models.WatchlistEntry.source == entry.source,
            )
            .first()
        )
        if watchlist_entry is not None:
            if "rating" in changes:
                watchlist_entry.user_rating = changes["rating"]
            if "note" in changes:
                watchlist_entry.note = changes["note"]
            if "mood_tags" in changes:
                watchlist_entry.mood_tags = changes["mood_tags"] or []
            if "favorite_cast" in changes:
                watchlist_entry.favorite_cast = changes["favorite_cast"] or []

    db.commit()
    db.refresh(entry)
    return _to_out(entry)


@router.delete("/{entry_id}", status_code=204)
def delete_entry(
    entry_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Deletes one logged evening.

    A movie/game/book/etc has one row per evening, so deleting one
    leaves any other evenings for the same title untouched — the
    watchlist snapshot just re-syncs to whichever is now the most
    recently logged one (same "most recent evening wins" rule
    `update_entry` above already follows). A series is the one
    exception: it only ever has a single row, continuously updated in
    place (see models.DiaryEntry's own docstring) — so deleting it
    always means zero watch history is left, and its per-episode
    progress goes with it too, rather than leaving orphaned ticks a
    future log would silently inherit a stale count from.

    Either way, once a title has no watch history left at all, the
    watchlist shelf drops back to `watch_later` — the same status a
    freshly-created row starts at — and its personal fields (rating,
    review, mood tags, favorite cast, watched date) clear along with
    it, since they described the evening that's now gone.
    `is_favorite` is deliberately left alone (see
    WatchlistEntry.is_favorite's own docstring: independent of watched
    status on purpose).
    """
    entry = (
        db.query(models.DiaryEntry)
        .filter(models.DiaryEntry.id == entry_id, models.DiaryEntry.user_id == current_user.id)
        .first()
    )
    if not entry:
        raise HTTPException(status_code=404, detail="Diary entry not found")

    user_id = current_user.id
    media_id = entry.media_id
    source = entry.source
    is_series_entry = entry.season is not None

    db.delete(entry)
    db.flush()

    if is_series_entry:
        db.query(models.EpisodeProgress).filter(
            models.EpisodeProgress.user_id == user_id,
            models.EpisodeProgress.source == source,
            models.EpisodeProgress.media_id == media_id,
        ).delete()
        remaining = None
    else:
        remaining = (
            db.query(models.DiaryEntry)
            .filter(
                models.DiaryEntry.user_id == user_id,
                models.DiaryEntry.media_id == media_id,
                models.DiaryEntry.source == source,
            )
            .order_by(models.DiaryEntry.watched_at.desc())
            .first()
        )

    watchlist_entry = (
        db.query(models.WatchlistEntry)
        .filter(
            models.WatchlistEntry.user_id == user_id,
            models.WatchlistEntry.media_id == media_id,
            models.WatchlistEntry.source == source,
        )
        .first()
    )
    if watchlist_entry is not None:
        if remaining is not None:
            watchlist_entry.user_rating = remaining.rating
            watchlist_entry.note = remaining.note
            watchlist_entry.mood_tags = remaining.mood_tags or []
            watchlist_entry.favorite_cast = remaining.favorite_cast or []
            watchlist_entry.watched_at = remaining.watched_at
        elif watchlist_entry.status in (models.WatchStatus.watching, models.WatchStatus.watched):
            watchlist_entry.status = models.WatchStatus.watch_later
            watchlist_entry.user_rating = None
            watchlist_entry.note = None
            watchlist_entry.mood_tags = []
            watchlist_entry.favorite_cast = []
            watchlist_entry.watched_at = None

    db.commit()
    return None
