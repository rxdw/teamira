import json
from datetime import datetime, timezone
from typing import List, Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Response
from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from app.database import get_db
from app import content_filter, models, push, sincerity
from app.deps import get_current_user
from app.routers.activity import friend_ids as _friend_ids_for_push, visible_to_friend
from app.schemas import DiaryEntryCreate, DiaryEntryOut, DiaryEntryUpdate, SincerityTransactionOut

router = APIRouter(prefix="/diary", tags=["diary"])

# Matches the page size routers/sincerity.py uses for the same
# cursor-pagination shape (see list_diary below).
_PAGE_SIZE = 60


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


def _resolve_country(db: Session, item) -> Optional[str]:
    """Best-effort country of origin for the diary snapshot (see
    models.DiaryEntry.country) — used by the "12 countries in a year"
    challenge.

    Only GET /media/detail ever fills MediaItem.country, so a title logged
    straight from search arrives here without one. Rather than give up (and
    leave that challenge permanently stuck for anyone who logs from search),
    this falls back to the **already-cached** static title detail — one
    indexed local SELECT, no network call, no upstream quota. A title
    nobody has ever opened the detail page for simply stays null, which the
    challenge's own caption explains rather than hiding.
    """
    direct = getattr(item, "country", None)
    if direct:
        return direct
    try:
        from app import cache

        # get_static_title hands back the raw cached JSON *string*, not a
        # model — see app/cache.py. Parsed here rather than validated
        # through MediaDetailOut because one optional field isn't worth
        # the cost (or the failure mode) of full schema validation.
        raw = cache.get_static_title(db, item.id, item.source)
        if not raw:
            return None
        payload = json.loads(raw)
    except Exception:
        # A cache miss, malformed JSON, a shape change, anything at all —
        # a missing country is never worth failing a log over.
        return None
    if isinstance(payload, dict):
        country = payload.get("country")
        return country if isinstance(country, str) and country else None
    return None


def _parse_watched_at(raw: Optional[str]) -> datetime:
    """Accepts both a bare date ("2026-07-10") and a full ISO datetime
    from the client. `datetime.fromisoformat` hands back a naive result
    for either shape unless the client's ISO string carries an explicit
    offset (the mobile client's own date pickers never send one) — naive
    used to be harmless when DiaryEntry.watched_at was naive too, but
    now that it's DateTime(timezone=True) (see app/models.py) a naive
    value here would either get silently reinterpreted in Postgres'
    session timezone on write, or raise the moment it's compared in
    Python against something aware (e.g. the sort/period-bounds code in
    challenges.py, feed.py, shared_diary.py). Treated as UTC, matching
    every other implicit-UTC assumption already in this codebase."""
    if not raw:
        return datetime.now(timezone.utc)
    try:
        parsed = datetime.fromisoformat(raw)
    except ValueError:
        raise HTTPException(status_code=400, detail="watched_at must be an ISO date or datetime")
    return parsed if parsed.tzinfo is not None else parsed.replace(tzinfo=timezone.utc)


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


def _screen_note(note: str | None) -> str | None:
    """Runs a diary note through the content filter — but only because a
    note can leave the person's own diary.

    A note is the most private thing in this app, and filtering something
    nobody else will ever read would be both pointless and intrusive. It
    stops being private in two ways, though: a shared (couple/company)
    diary shows it to everyone in the circle (see
    models.PartnerPrefs.share_notes), and moderation can be asked to look
    at one. Rather than trying to work out at write time whether *this*
    note will end up shared — the setting is read later, and can change —
    the filter runs on all of them. It only ever rejects links, contact
    handles, invisible characters and character walls, none of which
    belong in a note about an evening either way.
    """
    try:
        return content_filter.check(note, field="note")
    except content_filter.ContentRejected as exc:
        raise HTTPException(status_code=400, detail=str(exc))


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
    watched_together: bool = False,
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
    # Snapshotted before anything below mutates watchlist_entry — feeds
    # the sincerity-points hook near the end of this function (see
    # app/sincerity.py). Both are None/False when there's no prior
    # watchlist_entry at all, i.e. this is the very first log for this
    # title — never a "closed gestalt" or a "revised rating", just a
    # fresh entry.
    _was_watch_later_before = (
        watchlist_entry is not None and watchlist_entry.status == models.WatchStatus.watch_later
    )
    _planned_since_before = watchlist_entry.created_at if watchlist_entry is not None else None
    _old_user_rating_before = watchlist_entry.user_rating if watchlist_entry is not None else None
    # Feeds earn_second_chance below — updated_at is the last time this
    # row changed, which (barring some other edit landing in between)
    # is when the drop itself happened, since dropping is itself a
    # write to this row.
    _was_dropped_before = (
        watchlist_entry is not None and watchlist_entry.status == models.WatchStatus.dropped
    )
    _dropped_since_before = watchlist_entry.updated_at if watchlist_entry is not None else None
    _dropped_reason_before = watchlist_entry.drop_reason if watchlist_entry is not None else None

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
    # Snapshotted before anything below mutates `entry` — a series has
    # exactly one persistent DiaryEntry row (see this function's own
    # docstring), so "just became a rewatch"/"just became a together
    # evening" for a series means these flags flipping from false to
    # true on *this* call, not merely being true afterward. Feeds the
    # everyday-activity sincerity hooks near the end of this function
    # (see app/sincerity.py::earn_rewatch_logged/earn_watched_together).
    # Both stay False for a movie/whole-title log, where every log is a
    # fresh row and prior_count/watched_together below already answer
    # the same question directly.
    _entry_is_new = entry is None
    _series_prior_is_rewatch = bool(entry.is_rewatch) if entry is not None else False
    _series_prior_watched_together = bool(entry.watched_together) if entry is not None else False
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

    # --- Shared diary + country snapshot ---------------------------------
    # Both resolved once, here, before either branch below writes a row —
    # the series branch and the movie branch each need them and neither
    # should be doing lookups of its own.
    #
    # Function-level imports on purpose: routers/partner.py and
    # routers/shared_diary.py both import `log_watched` from this module,
    # so a module-level import back into either is circular (see
    # `_linked_partner_username` above, which exists for the same reason).
    from app.routers.shared_diary import shared_link_id_for_log

    resolved_shared_link_id = shared_link_id_for_log(
        db, user_id, watched_together=watched_together
    )
    resolved_country = _resolve_country(db, item)

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
        # A series has exactly one row, updated in place forever (see
        # models.DiaryEntry's docstring), so these two are "sticky": once
        # a series has been shared with the circle, a later solo episode
        # doesn't quietly pull the whole show back out of the shared
        # diary, and once any episode was watched together the show stays
        # marked as a together-watch. Un-sharing is an explicit action
        # (POST /partner/shared/diary/{id}/share), not a side effect of
        # watching one episode alone.
        if resolved_shared_link_id is not None:
            entry.shared_link_id = resolved_shared_link_id
        if watched_together:
            entry.watched_together = 1
        entry.country = resolved_country or entry.country
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
            shared_link_id=resolved_shared_link_id,
            watched_together=1 if watched_together else 0,
            country=resolved_country,
            is_rewatch=1 if prior_count > 0 else 0,
            watched_at=watched_at,
            genres=item.genres,
            runtime_minutes=item.runtime_minutes,
            year=item.year,
            director=item.director,
        )
        db.add(entry)

    # Resolved once, right after `entry` has its final state for this
    # call, for the everyday-activity sincerity hooks further down —
    # see the snapshots taken right before the series/movie branch above
    # for why a series (one persistent row) and a movie/whole-title (a
    # fresh row every log) each need their own rule here.
    if is_series_log:
        _rewatch_just_logged = bool(entry.is_rewatch) and not _series_prior_is_rewatch
        _together_just_logged = bool(entry.watched_together) and not _series_prior_watched_together
        _review_just_written = _entry_is_new and bool(note and note.strip())
    else:
        _rewatch_just_logged = prior_count > 0
        _together_just_logged = bool(watched_together)
        _review_just_written = bool(note and note.strip())

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

    # Sincerity points (see app/sincerity.py) — only for the specific
    # honest-act shapes it rewards, never for logging in general. A
    # fresh User query rather than threading a `user` object through
    # this whole function's signature: log_watched is also called from
    # co-view's mark-both-accounts-watched flow (routers/partner.py),
    # so this keeps that call site unchanged. Best-effort: if the user
    # row somehow isn't found (shouldn't happen — user_id came from an
    # authenticated request), sincerity is simply skipped rather than
    # failing the whole log.
    _sincerity_user = db.query(models.User).filter(models.User.id == user_id).first()
    # Stashed on the ORM object as a plain attribute, not a DB column —
    # purely so routers/diary.py::log_entry (the one endpoint the
    # logging form actually hits) can hand the awarded transaction(s)
    # straight back in its response, so the client can show a quiet
    # "+2 sincerity points" toast right when it happened, instead of the
    # person only finding out next time they open the profile screen.
    # The other three call sites of log_watched (partner.py's co-view
    # flow, integrations.py, imports.py) never read this attribute, so
    # this changes nothing about their behavior.
    entry._sincerity_awards = []
    # See DiaryEntryOut.sincerity_awarded's docstring for the awards list
    # above; this one's the same idea for a different audience — pushes
    # for the *staker* of a recommendation this rating just resolved, not
    # for `user_id` themselves, so it can't ride the same list. Reasons
    # this stays a plain attribute rather than sending the push right
    # here: log_watched has no `background_tasks` of its own (only the
    # routers/diary.py::log_entry endpoint that calls it does — see that
    # endpoint's own scheduling of these, right after the sincerity
    # awards above), and app/push.py's own convention is "only after
    # db.commit() has already succeeded".
    entry._resolved_recommendation_pushes = []
    if _sincerity_user is not None:
        if (
            _was_watch_later_before
            and new_entry_status == models.WatchStatus.watched
            and _planned_since_before is not None
        ):
            txn = sincerity.earn_closed_gestalt(
                db, _sincerity_user,
                entry_id=watchlist_entry.id,
                title=display_title,
                planned_since=_planned_since_before,
                closed_honestly_as="watched",
            )
            if txn is not None:
                entry._sincerity_awards.append(txn)
        if (
            _was_dropped_before
            and new_entry_status == models.WatchStatus.watched
            and rating is not None
            and _dropped_since_before is not None
        ):
            txn = sincerity.earn_second_chance(
                db, _sincerity_user,
                entry_id=watchlist_entry.id,
                title=display_title,
                dropped_since=_dropped_since_before,
                dropped_reason=_dropped_reason_before,
            )
            if txn is not None:
                entry._sincerity_awards.append(txn)
        if (
            rating is not None
            and _old_user_rating_before is not None
            and _old_user_rating_before != rating
        ):
            txn = sincerity.earn_revised_rating(
                db, _sincerity_user,
                title_key=sincerity.title_key(watchlist_entry.source, watchlist_entry.media_id),
                title=display_title,
                old_rating=_old_user_rating_before,
                new_rating=rating,
            )
            if txn is not None:
                entry._sincerity_awards.append(txn)
        # Formed an opinion on a shared title independently, rather than
        # paying to see a circle-mate's already-shared rating first — see
        # app/sincerity.py::earn_formed_own_opinion_if_eligible for the
        # full eligibility check. Scoped to `resolved_shared_link_id`
        # (this exact log's own sharing choice), and to a genuinely
        # first-ever rating of the title — a rewatch or plain revision
        # already has its own reward above.
        if rating is not None and prior_count == 0 and resolved_shared_link_id is not None:
            txn = sincerity.earn_formed_own_opinion_if_eligible(
                db, _sincerity_user,
                link_id=resolved_shared_link_id,
                source=watchlist_entry.source,
                media_id=watchlist_entry.media_id,
                title=display_title,
            )
            if txn is not None:
                entry._sincerity_awards.append(txn)

        # Everyday-activity sincerity points — the wells merged in from
        # the old, separate XP/level system (see app/sincerity.py's own
        # docstring). Each fires at most once for the event it
        # represents, using the just-computed / snapshotted flags above
        # (`became_watched_now`, `_rewatch_just_logged`,
        # `_together_just_logged`, `_review_just_written`) rather than
        # re-deriving "is this the first time" from scratch here.
        became_watched_now = (not was_already_watched) and new_entry_status == models.WatchStatus.watched
        if became_watched_now:
            entry._sincerity_awards.append(sincerity.earn_watched_logged(
                db, _sincerity_user, entry_id=watchlist_entry.id, title=display_title,
            ))
        if _rewatch_just_logged:
            entry._sincerity_awards.append(sincerity.earn_rewatch_logged(
                db, _sincerity_user, entry_id=watchlist_entry.id, title=display_title,
            ))
        if _together_just_logged:
            entry._sincerity_awards.append(sincerity.earn_watched_together(
                db, _sincerity_user, entry_id=watchlist_entry.id, title=display_title,
            ))
        if _review_just_written:
            entry._sincerity_awards.append(sincerity.earn_review_written(
                db, _sincerity_user, entry_id=entry.id, title=display_title,
            ))
        if item.genres:
            entry._sincerity_awards.extend(
                sincerity.earn_genres_explored(db, _sincerity_user, genres=item.genres)
            )
        # Streak — computed from this account's ActivityEvent history,
        # which the ActivityEvent row further down in this same function
        # is about to extend, so this reads the streak as it stands
        # *before* today's own event lands. Harmless: a streak that
        # already included today (a second log the same day) simply
        # measures the same length again and earn_streak_progress's own
        # high-water check no-ops it; a streak that's about to gain
        # today for the first time gets credit for it on the *next* log
        # or the next read of GET /sincerity/me, not a beat later than
        # any other lazily-recomputed number in this backend (see e.g.
        # apply_stale_planned_decay's own docstring on the same shape).
        from app import streaks as _streaks
        txn = sincerity.earn_streak_progress(
            db, _sincerity_user, _streaks.current_streak(db, user_id),
        )
        if txn is not None:
            entry._sincerity_awards.append(txn)

        # Recommendation stakes — see app/sincerity.py's module docstring
        # and app/routers/recommendations.py::create_recommendation. This
        # is where a stake actually resolves: the moment its *recipient*
        # (this user) logs a rating for the exact title it was staked on.
        # Not gated on prior_count/first-time — a friend's stake is about
        # the recipient's honest verdict landing, whichever visit that
        # verdict comes from.
        if rating is not None:
            pending_recs = (
                db.query(models.Recommendation)
                .filter(
                    models.Recommendation.recipient_id == user_id,
                    models.Recommendation.source == watchlist_entry.source,
                    models.Recommendation.media_id == watchlist_entry.media_id,
                    models.Recommendation.status == models.RecommendationStatus.pending,
                )
                .all()
            )
            for rec in pending_recs:
                staker = db.query(models.User).filter(models.User.id == rec.staker_id).first()
                if staker is None:
                    continue
                resolve_txn = sincerity.resolve_recommendation_stake(
                    db, staker,
                    friend_id=user_id,
                    friend_name=_sincerity_user.display_name or _sincerity_user.username,
                    title=rec.title,
                    staked_amount=rec.staked_amount,
                    predicted_rating=rec.predicted_rating,
                    actual_rating=rating,
                )
                hit = abs(rec.predicted_rating - rating) <= sincerity.RECOMMENDATION_TOLERANCE
                rec.actual_rating = rating
                rec.status = models.RecommendationStatus.hit if hit else models.RecommendationStatus.missed
                rec.resolved_at = datetime.now(timezone.utc)
                entry._resolved_recommendation_pushes.append((
                    rec.staker_id,
                    _sincerity_user.display_name or _sincerity_user.username,
                    rec.title,
                    hit,
                    resolve_txn.delta,
                ))

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
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    # Captured before log_watched's write, for the level-up push below —
    # level is a derived read (see profile.py::compute_level_for_user's
    # own docstring), never a stored counter, so "did this cross a
    # threshold" only exists as a before/after compare done here, not as
    # an event log_watched itself could raise on its own.
    from app.routers.profile import compute_level_for_user
    level_before = compute_level_for_user(db, current_user.id).level

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
        note=_screen_note(payload.note),
        mood_tags=payload.mood_tags,
        favorite_cast=[c.model_dump() for c in payload.favorite_cast] if payload.favorite_cast else None,
        watched_with_username=watched_with_username,
        is_favorite=bool(payload.is_favorite),
        season=payload.season,
        episode=payload.episode,
        episode_count=payload.episode_count,
        # The log form's "watched with" toggle is exactly the signal the
        # shared diary means by "together" — same evening, same people —
        # so it marks the entry the same way the co-viewing screen's
        # "watched" button does, and lands in the shared diary regardless
        # of the auto-share setting (see shared_diary.py::
        # shared_link_id_for_log for why together always shares).
        watched_together=bool(payload.watched_with_partner) and watched_with_username is not None,
    )
    # An evening logged "watched with" also opens the circle's joint review,
    # so the others are asked for their own part (routers/circle_review.py).
    review_invite_ids: list[str] = []
    review_ready_ids: list[str] = []
    _review_title = ""
    if payload.watched_with_partner and watched_with_username is not None:
        from app import circle_review as _review_rules
        from app.routers.circle_review import _maybe_reveal, open_review
        from app.routers.partner import _member_ids as _circle_member_ids, get_active_link as _circle_link
        _link = _circle_link(db, current_user.id)
        if _link is not None:
            _members = _circle_member_ids(_link)
            _review = open_review(
                db, _link, origin="logged", created_by_id=current_user.id,
                media_id=entry.media_id, media_type=entry.media_type, source=entry.source,
                title_ru=entry.title_ru, title_en=entry.title_en, poster_url=entry.poster_url,
                year=getattr(payload.item, "year", None),
                participant_ids=list(_members), watched_at=entry.watched_at,
            )
            _review_title = entry.title_ru or entry.title_en or "что-то"
            # The person has just rated this evening themselves, so their part
            # of the joint review is already written: seal it from the log
            # (rating and tags; the one-line note stays theirs to add) rather
            # than asking the same question twice. If this completes the set —
            # the others logged the same evening first — the review opens now.
            _tags = _review_rules.clean_tags(payload.mood_tags)
            if payload.rating or _tags:
                if not any(e.user_id == current_user.id for e in _review.entries):
                    _mine = models.CircleReviewEntry(
                        review_id=_review.id, user_id=current_user.id,
                        rating=payload.rating, tags=_tags, line=None, skipped=False,
                    )
                    db.add(_mine)
                    _review.entries.append(_mine)
                    db.flush()
                if _maybe_reveal(db, _link, _review):
                    review_ready_ids = [m for m in _members if m != current_user.id]
            if not review_ready_ids:
                _done = {e.user_id for e in _review.entries}
                review_invite_ids = [m for m in _members if m != current_user.id and m not in _done]
    db.commit()
    db.refresh(entry)
    out = _to_out(entry)
    for _uid in review_invite_ids:
        background_tasks.add_task(
            push.notify_review_invite, _uid,
            current_user.display_name or current_user.username, _review_title,
        )
    for _uid in review_ready_ids:
        background_tasks.add_task(push.notify_review_ready, _uid, _review_title)
    # See DiaryEntryOut.sincerity_awarded's own docstring — refresh()
    # above only reloads DB columns, so the plain-attribute list
    # log_watched stashed on `entry` survives it untouched.
    awards = getattr(entry, "_sincerity_awards", None)
    if awards:
        out.sincerity_awarded = [
            SincerityTransactionOut(
                id=t.id, delta=t.delta, reason=t.reason.value, note=t.note, created_at=t.created_at,
            )
            for t in awards
        ]

    # A staked recommendation this log just resolved — see log_watched's
    # own comment on why this couldn't just send the push itself
    # (no background_tasks in scope there). One push per resolved stake;
    # in practice a title has at most one or two friends' stakes pending
    # on it at once.
    for staker_id, friend_display_name, rec_title, hit, amount in getattr(
        entry, "_resolved_recommendation_pushes", []
    ):
        background_tasks.add_task(
            push.notify_recommendation_resolved, staker_id, friend_display_name, rec_title, hit, amount,
        )

    # Both pushes below fire only now, after db.commit() has already
    # succeeded — see app/push.py's own docstring on why every trigger in
    # this app waits for that rather than sending on the strength of a
    # write that could still roll back.
    level_after = compute_level_for_user(db, current_user.id).level
    if level_after > level_before:
        background_tasks.add_task(push.notify_level_up, current_user.id, level_after)

    # Friend-activity push — deliberately only from this interactive
    # "I just watched this" endpoint, never from log_watched's other
    # three call sites (partner.py's co-view "watched" button,
    # integrations.py's Jellyfin webhook, imports.py's CSV import). A
    # CSV import replaying two years of Letterboxd history is not two
    # years of "come see what they watched" moments for your friends —
    # it's one settings-screen action, and imports.py already knows not
    # to touch ActivityEvent-driven surfaces the way a real-time log does.
    recipient_ids = [
        fid for fid in _friend_ids_for_push(db, current_user.id)
        if visible_to_friend(current_user, "watched")
    ]
    if recipient_ids:
        actor_name = current_user.display_name or current_user.username
        display_title = payload.item.title.ru or payload.item.title.en or "что-то"
        background_tasks.add_task(
            push.notify_friend_activity, recipient_ids, actor_name, display_title, payload.rating,
            payload.item.id, payload.item.source,
            payload.item.media_type.value if hasattr(payload.item.media_type, "value") else payload.item.media_type,
        )

    return out


@router.get("", response_model=List[DiaryEntryOut])
def list_diary(
    response: Response,
    before: Optional[str] = Query(
        default=None, description="diary entry id to page before, for older evenings"
    ),
    limit: int = Query(default=_PAGE_SIZE, ge=1, le=200),
    full: bool = Query(
        default=False,
        description=(
            "bypass pagination and return the complete diary in one response. "
            "Only for the views that genuinely need the whole history at once — "
            "the diary constellation, wrapped, and the keepsake PDF export — "
            "never for the day-grouped scrolling list itself, which pages "
            "normally via `before`/`limit`."
        ),
    ),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Newest evening first — the client groups these by calendar date
    (today / yesterday / ...) for the Diary tab. The body is still the
    same bare array it's always been (existing tests and clients pin
    that shape — see tests/test_diary_ownership.py); pagination rides
    in the `X-Has-More` response header instead of reshaping it, the
    same way a `Link`/`X-Has-More`-style header works on any API that
    has to add paging to an endpoint after the fact without breaking
    whoever already reads it. `before` takes the last-seen entry's id
    (entries already carry their own id, so no separate cursor value is
    needed); ties on `watched_at` (same-day entries logged without a
    time) are broken by `id` so the cursor never skips or repeats a
    row."""
    q = db.query(models.DiaryEntry).filter(models.DiaryEntry.user_id == current_user.id)

    if full:
        entries = q.order_by(models.DiaryEntry.watched_at.desc(), models.DiaryEntry.id.desc()).all()
        response.headers["X-Has-More"] = "false"
        return [_to_out(e) for e in entries]

    if before:
        anchor = (
            db.query(models.DiaryEntry)
            .filter(models.DiaryEntry.id == before, models.DiaryEntry.user_id == current_user.id)
            .first()
        )
        if anchor is not None:
            q = q.filter(
                or_(
                    models.DiaryEntry.watched_at < anchor.watched_at,
                    and_(
                        models.DiaryEntry.watched_at == anchor.watched_at,
                        models.DiaryEntry.id < anchor.id,
                    ),
                )
            )
    rows = (
        q.order_by(models.DiaryEntry.watched_at.desc(), models.DiaryEntry.id.desc())
        .limit(limit + 1)
        .all()
    )
    has_more = len(rows) > limit
    rows = rows[:limit]
    response.headers["X-Has-More"] = "true" if has_more else "false"
    return [_to_out(e) for e in rows]


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
    # Snapshotted before the mutation below overwrites it — feeds the
    # sincerity-points hook further down (see app/sincerity.py). This
    # PATCH endpoint, not log_watched's re-logging path, is the actual
    # everyday way someone changes a rating they already gave — editing
    # the entry in place, not re-submitting a whole new log.
    _old_rating_before_edit = entry.rating
    if "watched_at" in changes:
        entry.watched_at = _parse_watched_at(changes["watched_at"])
    if "rating" in changes:
        entry.rating = changes["rating"]
    if "note" in changes:
        entry.note = _screen_note(changes["note"])
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
    out = _to_out(entry)
    if "rating" in changes and _old_rating_before_edit is not None:
        _sincerity_user = db.query(models.User).filter(models.User.id == current_user.id).first()
        if _sincerity_user is not None:
            txn = sincerity.earn_revised_rating(
                db, _sincerity_user,
                title_key=sincerity.title_key(entry.source, entry.media_id),
                title=entry.title_en or entry.title_ru or "—",
                old_rating=_old_rating_before_edit,
                new_rating=changes["rating"],
            )
            if txn is not None:
                db.commit()
                out.sincerity_awarded = [
                    SincerityTransactionOut(
                        id=txn.id, delta=txn.delta, reason=txn.reason.value,
                        note=txn.note, created_at=txn.created_at,
                    )
                ]
    return out


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
