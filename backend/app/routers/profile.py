import re
import calendar
import uuid
from collections import Counter
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Response, UploadFile, File
from sqlalchemy.orm import Session
from sqlalchemy import and_, func, or_

from app.database import get_db
from app import content_filter, models, sincerity
from app.deps import get_current_user
from app.routers.teamira import get_teamira_collections
from app.storage import get_avatar_storage
from app.streaks import current_streak
from app.schemas import (
    ProfileStats,
    CollectionsOut,
    ProfileYearStats,
    GenreCount,
    WrappedStat,
    WrappedBreakdown,
    WrappedSummary,
    WrappedTitleMoment,
    WrappedDirectorCount,
    WrappedDecadeBucket,
    WrappedTimelineBucket,
    WrappedWeekdayCount,
    WrappedGenreShare,
    WrappedReviewItem,
    WrappedReceiptItem,
    WrappedRatingBucket,
    WrappedPeriodsOut,
    WrappedMonthPeriod,
    AchievementOut,
    AchievementsOut,
    PinAchievementsIn,
    LevelOut,
    FavoriteToggleIn,
    FavoriteToggleOut,
    ProfileMeOut,
    ProfileUpdateIn,
    TopFavoritePickIn,
    TopFavoritePick,
    AvatarUploadOut,
)

router = APIRouter(prefix="/profile", tags=["profile"])

# Bundled-in-app avatar choices the client can pick from with no upload —
# ids only, the actual asset lives client-side (see
# mobile/assets/mascot/*.png). Kept here as the single source of truth
# for "is this a real preset id" so a client can't set avatar_preset to
# garbage; add a new mascot asset on the client, add its id here.
AVATAR_PRESETS = {
    "bunnies_coviewing",
}

# Local avatar upload storage — see main.py's StaticFiles mount at
# /static, which serves exactly this directory back out.
_ALLOWED_AVATAR_TYPES = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}
_MAX_AVATAR_BYTES = 5 * 1024 * 1024
# Read in bounded chunks (see upload_avatar) rather than one
# `await file.read()` for the whole thing — a client can send
# Content-Type: image/jpeg and then just keep streaming bytes past
# _MAX_AVATAR_BYTES; reading unconditionally would buffer all of it in
# memory before the size check ever runs. 256 KB is arbitrary but
# reasonable: small enough that the worst case over-read past the cap
# is negligible, large enough not to spend more time in the read loop
# than the request is worth.
_AVATAR_READ_CHUNK_BYTES = 256 * 1024

# First bytes of each format upload_avatar actually accepts, checked
# against the real file content rather than trusting the client's
# Content-Type header — that header is just whatever the client sends,
# and a request lying about it (a same-site scripting payload named
# avatar.jpg, say) would otherwise get written to disk/S3 and served
# back out from this app's own origin under an image content-type.
_AVATAR_MAGIC_BYTES = {
    "image/jpeg": (b"\xff\xd8\xff",),
    "image/png": (b"\x89PNG\r\n\x1a\n",),
    # RIFF????WEBP — the 4-byte size in the middle varies per file, so
    # this is checked as two separate prefixes rather than one contiguous
    # signature (see _sniff_avatar_type below).
    "image/webp": (b"RIFF", b"WEBP"),
}


def _sniff_avatar_type(head: bytes) -> Optional[str]:
    """Returns the content-type `head` (the first _AVATAR_MAGIC_BYTES-
    worth of the upload) actually looks like, by its own magic bytes —
    or None if it doesn't match any format this endpoint accepts."""
    if head.startswith(_AVATAR_MAGIC_BYTES["image/jpeg"][0]):
        return "image/jpeg"
    if head.startswith(_AVATAR_MAGIC_BYTES["image/png"][0]):
        return "image/png"
    riff, webp = _AVATAR_MAGIC_BYTES["image/webp"]
    if head.startswith(riff) and head[8:12] == webp:
        return "image/webp"
    return None


def _me_out(user: models.User) -> ProfileMeOut:
    return ProfileMeOut(
        user_id=user.id,
        username=user.username,
        display_name=user.display_name,
        avatar_preset=user.avatar_preset,
        avatar_url=user.avatar_url,
        status_text=user.status_text,
        created_at=user.created_at,
        privacy_watched=user.privacy_watched or "everyone",
        privacy_watching=user.privacy_watching or "everyone",
        privacy_planned=user.privacy_planned or "everyone",
        privacy_favorites=user.privacy_favorites or "everyone",
        discoverable=True if user.discoverable is None else bool(user.discoverable),
        top_favorite_picks=[TopFavoritePick(**p) for p in (user.top_favorite_picks or [])],
    )


@router.get("/me", response_model=ProfileMeOut)
def get_me(
    current_user: models.User = Depends(get_current_user),
):
    """The editable identity block for the profile header/edit screen —
    name, avatar, status. Everything else on the profile screen (stats,
    collections, level, friends) already has its own endpoint; this one
    exists purely so the edit screen has a single place to read the
    current values from before the person changes any of them."""
    return _me_out(current_user)


@router.patch("/me", response_model=ProfileMeOut)
def update_me(
    payload: ProfileUpdateIn,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Updates whichever of name/status/avatar-preset/privacy the client
    actually sent — `exclude_unset` (see routers/diary.py::update_entry
    for the same pattern) so a client can PATCH just
    `{"status_text": "..."}` without clobbering anything else in the
    same call."""
    changes = payload.model_dump(exclude_unset=True)

    # Both of these are shown to other people — on the friends screen, on
    # the profile screen, on every activity-feed card — so they're
    # user-generated content and go through the same filter as anything
    # else that is (see app/content_filter.py). A nickname carrying a
    # Telegram handle or a zero-width character is the single most common
    # abuse of a profile field, and catching it at write time is what
    # keeps it from needing a report at all.
    if "display_name" in changes:
        name = (changes["display_name"] or "").strip()
        try:
            content_filter.check(name, field="display name")
        except content_filter.ContentRejected as exc:
            raise HTTPException(status_code=400, detail=str(exc))
        current_user.display_name = name or None

    if "status_text" in changes:
        status_text = (changes["status_text"] or "").strip()
        try:
            content_filter.check(status_text, field="status")
        except content_filter.ContentRejected as exc:
            raise HTTPException(status_code=400, detail=str(exc))
        current_user.status_text = status_text or None

    if "avatar_preset" in changes:
        preset = changes["avatar_preset"]
        if preset is not None and preset not in AVATAR_PRESETS:
            raise HTTPException(status_code=400, detail="Unknown avatar preset")
        # Picking a preset always wins over a previously uploaded photo —
        # the two are mutually exclusive (see models.User.avatar_preset).
        current_user.avatar_preset = preset
        if preset is not None:
            current_user.avatar_url = None

    # Validity ("everyone"|"friends"|"nobody") is already enforced by
    # ProfileUpdateIn's own field_validator — nothing left to check here.
    if "privacy_watched" in changes and changes["privacy_watched"] is not None:
        current_user.privacy_watched = changes["privacy_watched"]
    if "privacy_watching" in changes and changes["privacy_watching"] is not None:
        current_user.privacy_watching = changes["privacy_watching"]
    if "privacy_planned" in changes and changes["privacy_planned"] is not None:
        current_user.privacy_planned = changes["privacy_planned"]
    if "privacy_favorites" in changes and changes["privacy_favorites"] is not None:
        current_user.privacy_favorites = changes["privacy_favorites"]

    # "people can find me by my username" — the opt-out for
    # routers/friends.py::search_users. Separate from the three shelf
    # settings above because it governs whether this account turns up in
    # a stranger's search at all, not what a viewer sees once they're
    # already looking at it.
    if "discoverable" in changes and changes["discoverable"] is not None:
        current_user.discoverable = bool(changes["discoverable"])

    db.commit()
    db.refresh(current_user)
    return _me_out(current_user)


@router.post("/favorites/pick", response_model=ProfileMeOut)
def set_top_favorites(
    payload: TopFavoritePickIn,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Sets the ordered stories deck that swipes across the Profile
    header banner (see models.User.top_favorite_picks) — reached from
    the star on a poster in the favorite-films screen. Sending an empty
    list clears it, falling back to the banner's plain placeholder look.
    Every entry must already be one of this account's own favorite
    movies, and duplicates are rejected — this endpoint only spotlights
    existing favorites, it doesn't create one (use POST
    /profile/favorites/toggle for that)."""
    seen: set[tuple[str, str]] = set()
    for pick in payload.picks:
        key = (pick.media_id, pick.source)
        if key in seen:
            raise HTTPException(status_code=400, detail="Duplicate pick")
        seen.add(key)
        entry = (
            db.query(models.WatchlistEntry)
            .filter_by(user_id=current_user.id, media_id=pick.media_id, source=pick.source)
            .first()
        )
        if not entry or not entry.is_favorite or entry.media_type != "movie":
            raise HTTPException(status_code=400, detail="Not one of your favorite films")

    current_user.top_favorite_picks = [p.model_dump() for p in payload.picks]
    # Old single-pick columns kept in sync (first of the new deck, or
    # cleared) purely so nothing reading them directly goes stale.
    if payload.picks:
        current_user.top_favorite_media_id = payload.picks[0].media_id
        current_user.top_favorite_source = payload.picks[0].source
    else:
        current_user.top_favorite_media_id = None
        current_user.top_favorite_source = None

    db.commit()
    db.refresh(current_user)
    return _me_out(current_user)



@router.post("/avatar", response_model=AvatarUploadOut)
async def upload_avatar(
    file: UploadFile = File(...),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The other half of avatar_preset (see its docstring) — a photo the
    person picked from their own device. Written through
    app/storage.py's AvatarStorage (local disk by default, S3-compatible
    when Settings.avatar_storage_backend=s3 — see that module for why);
    the returned avatar_url is already the full path/URL the client
    hands straight to Image.network either way."""
    content_type = (file.content_type or "").lower()
    if content_type not in _ALLOWED_AVATAR_TYPES:
        raise HTTPException(status_code=400, detail="Use a JPEG, PNG, or WebP image")

    # Bounded read: stop as soon as the cap is crossed rather than
    # buffering an arbitrarily large upload first and only checking its
    # size once it's all in memory. `over` short-circuits the loop the
    # moment there's any evidence the file is too big — the exact final
    # size stops mattering at that point, only the 400 does.
    chunks = []
    total = 0
    over = False
    while True:
        chunk = await file.read(_AVATAR_READ_CHUNK_BYTES)
        if not chunk:
            break
        total += len(chunk)
        if total > _MAX_AVATAR_BYTES:
            over = True
            break
        chunks.append(chunk)
    if over:
        raise HTTPException(status_code=400, detail="Image is larger than 5 MB")
    body = b"".join(chunks)

    # The Content-Type header above is just whatever the client claims —
    # confirm the bytes actually are what it says before writing them to
    # disk/S3 and serving them back out from this app's own origin.
    sniffed = _sniff_avatar_type(body)
    if sniffed is None or sniffed != content_type:
        raise HTTPException(status_code=400, detail="File content doesn't match a JPEG, PNG, or WebP image")

    ext = _ALLOWED_AVATAR_TYPES[content_type]
    filename = f"{current_user.id}-{uuid.uuid4().hex[:8]}.{ext}"
    avatar_url = get_avatar_storage().save(filename, body, content_type)

    # An uploaded photo always wins over a previously chosen preset —
    # same mutual-exclusivity rule as update_me's preset branch above.
    current_user.avatar_url = avatar_url
    current_user.avatar_preset = None
    db.commit()
    return AvatarUploadOut(avatar_url=current_user.avatar_url)


@router.get("/stats", response_model=ProfileStats)
def get_stats(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    def count(media_type: models.MediaType) -> int:
        return (
            db.query(func.count(models.WatchlistEntry.id))
            .filter(
                models.WatchlistEntry.user_id == current_user.id,
                models.WatchlistEntry.media_type == media_type,
                models.WatchlistEntry.status == models.WatchStatus.watched,
            )
            .scalar()
        ) or 0

    return ProfileStats(
        movies=count(models.MediaType.movie),
        series=count(models.MediaType.series),
        games=count(models.MediaType.game),
        anime=count(models.MediaType.anime),
        books=count(models.MediaType.book),
        manga=count(models.MediaType.manga),
    )


_COLLECTIONS_PAGE_SIZE = 200


def _paginate_shelf(
    db: Session,
    q,
    before: Optional[str],
    limit: int,
    full: bool,
) -> tuple[list, bool]:
    """One shelf's slice of the WatchlistEntry query, cursor-paginated
    the same way GET /sincerity/me is (see routers/sincerity.py) —
    factored out since GET /profile/collections runs this three times,
    once per shelf, each with its own independent cursor."""
    if full:
        return q.order_by(models.WatchlistEntry.updated_at.desc(), models.WatchlistEntry.id.desc()).all(), False
    if before:
        anchor = db.query(models.WatchlistEntry).filter(models.WatchlistEntry.id == before).first()
        if anchor is not None:
            q = q.filter(
                or_(
                    models.WatchlistEntry.updated_at < anchor.updated_at,
                    and_(
                        models.WatchlistEntry.updated_at == anchor.updated_at,
                        models.WatchlistEntry.id < anchor.id,
                    ),
                )
            )
    rows = (
        q.order_by(models.WatchlistEntry.updated_at.desc(), models.WatchlistEntry.id.desc())
        .limit(limit + 1)
        .all()
    )
    has_more = len(rows) > limit
    return rows[:limit], has_more


@router.get("/collections", response_model=CollectionsOut)
def get_collections(
    response: Response,
    watch_later_before: Optional[str] = Query(default=None),
    watching_before: Optional[str] = Query(default=None),
    watched_before: Optional[str] = Query(default=None),
    limit: int = Query(default=_COLLECTIONS_PAGE_SIZE, ge=1, le=500),
    full: bool = Query(
        default=True,
        description=(
            "return every entry on every shelf in one response, ignoring "
            "the cursors above. Every current caller needs the complete "
            "shelves to compute a title's status locally (already-in-my-"
            "watchlist badges, favorite pickers, wrapped/stats) rather than "
            "browse them, so this defaults to True; a future shelf-browsing "
            "screen would pass full=false and page with the *_before params."
        ),
    ),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Splits the WatchlistEntry rows into the shelves the app shows:
    "watch later", "watching" (mid-series, at least one episode logged
    but not completed — see models.WatchStatus.watching), and "watched".
    Each shelf is cursor-paginated independently (see _paginate_shelf
    above) the same way GET /sincerity/me is (see routers/sincerity.py);
    the body keeps its original three keys (see CollectionsOut's own
    docstring), so each shelf's has-more flag comes back in its own
    header instead."""
    base = db.query(models.WatchlistEntry).filter(models.WatchlistEntry.user_id == current_user.id)

    watch_later_rows, watch_later_more = _paginate_shelf(
        db,
        base.filter(models.WatchlistEntry.status == models.WatchStatus.watch_later),
        watch_later_before,
        limit,
        full,
    )
    watching_rows, watching_more = _paginate_shelf(
        db,
        base.filter(models.WatchlistEntry.status == models.WatchStatus.watching),
        watching_before,
        limit,
        full,
    )
    watched_rows, watched_more = _paginate_shelf(
        db,
        base.filter(models.WatchlistEntry.status == models.WatchStatus.watched),
        watched_before,
        limit,
        full,
    )
    response.headers["X-Watch-Later-Has-More"] = "true" if watch_later_more else "false"
    response.headers["X-Watching-Has-More"] = "true" if watching_more else "false"
    response.headers["X-Watched-Has-More"] = "true" if watched_more else "false"
    return CollectionsOut(
        watch_later=watch_later_rows,
        watching=watching_rows,
        watched=watched_rows,
    )


@router.get("/favorites/status", response_model=FavoriteToggleOut)
def get_favorite_status(
    media_id: str,
    source: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Whether this title is already one of the person's favorites — the
    title screen's heart button reads this on load. A title with no
    WatchlistEntry at all yet (never watched, planned, or favorited)
    just reads as not-a-favorite, same as one that exists with the flag
    off — there's nothing to distinguish and no reason to."""
    entry = (
        db.query(models.WatchlistEntry)
        .filter(
            models.WatchlistEntry.user_id == current_user.id,
            models.WatchlistEntry.media_id == media_id,
            models.WatchlistEntry.source == source,
        )
        .first()
    )
    return FavoriteToggleOut(is_favorite=bool(entry.is_favorite) if entry else False)


@router.post("/favorites/toggle", response_model=FavoriteToggleOut)
def toggle_favorite(
    payload: FavoriteToggleIn,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Marks (or unmarks) a title as one of the person's favorite films —
    from the heart on the title screen, independent of watched/watch-later
    status (see WatchlistEntry.is_favorite's own docstring). Upserts the
    same WatchlistEntry row every other title-level action writes, so
    favoriting something not yet on any shelf just adds it as watch_later
    rather than needing a separate table."""
    item = payload.item
    entry = (
        db.query(models.WatchlistEntry)
        .filter(
            models.WatchlistEntry.user_id == current_user.id,
            models.WatchlistEntry.media_id == item.id,
            models.WatchlistEntry.source == item.source,
        )
        .first()
    )
    if entry is None:
        entry = models.WatchlistEntry(
            user_id=current_user.id,
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
            status=models.WatchStatus.watch_later,
            is_favorite=payload.is_favorite,
        )
        db.add(entry)
    else:
        entry.is_favorite = payload.is_favorite
    # Un-favoriting a title still in the header's stories deck drops it
    # from the deck too — a banner beats one silently holding a slide
    # for a title that's no longer even a favorite. See
    # models.User.top_favorite_picks.
    if not payload.is_favorite and current_user.top_favorite_picks:
        current_user.top_favorite_picks = [
            p for p in current_user.top_favorite_picks
            if not (p.get("media_id") == item.id and p.get("source") == item.source)
        ]
        if current_user.top_favorite_media_id == item.id and current_user.top_favorite_source == item.source:
            first = current_user.top_favorite_picks[0] if current_user.top_favorite_picks else None
            current_user.top_favorite_media_id = first["media_id"] if first else None
            current_user.top_favorite_source = first["source"] if first else None
    db.commit()
    return FavoriteToggleOut(is_favorite=entry.is_favorite)


@router.get("/stats/year", response_model=ProfileYearStats)
def get_year_stats(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    def count(media_type: models.MediaType) -> int:
        return (
            db.query(func.count(models.WatchlistEntry.id))
            .filter(
                models.WatchlistEntry.user_id == current_user.id,
                models.WatchlistEntry.media_type == media_type,
                models.WatchlistEntry.status == models.WatchStatus.watched,
            )
            .scalar()
        ) or 0

    movies = count(models.MediaType.movie)
    series = count(models.MediaType.series)
    games = count(models.MediaType.game)
    anime = count(models.MediaType.anime)
    books = count(models.MediaType.book)
    manga = count(models.MediaType.manga)

    watched_entries = (
        db.query(models.WatchlistEntry)
        .filter(
            models.WatchlistEntry.user_id == current_user.id,
            models.WatchlistEntry.status == models.WatchStatus.watched,
        )
        .all()
    )
    genre_counter: Counter = Counter()
    for entry in watched_entries:
        for genre in entry.genres or []:
            genre_counter[genre] += 1
    top_genres = [GenreCount(genre=g, count=c) for g, c in genre_counter.most_common(5)]

    # Streak: consecutive calendar days (ending today or yesterday) with at
    # least one ActivityEvent — see app/streaks.py::current_streak for the
    # actual algorithm (shared with scripts/send_scheduled_push.py's
    # streak-at-risk reminder, which needs the exact same definition of
    # what a streak is).
    streak = current_streak(db, current_user.id)

    return ProfileYearStats(
        movies=movies,
        series=series,
        games=games,
        anime=anime,
        books=books,
        manga=manga,
        total=movies + series + games + anime + books + manga,
        top_genres=top_genres,
        streak_days=streak,
    )


# ---------------------------------------------------------------------------
# Leveling — deliberately built from the same well the achievements and
# year-stats endpoints already draw from (watched count, diary notes,
# rewatches, streaks, genre breadth), rather than a stored XP counter, so
# it can never drift out of sync with what's actually logged and can't be
# farmed by anything other than actually using the app. Two sources are
# event rows rather than a tally of diary entries — collected challenges
# (models.ChallengeProgress) and share cards (models.CardShare) — because
# "was pressed" / "left the app" isn't something the diary can tell us;
# both are still summed fresh on every read, never a stored total, and
# card shares carry their own once-per-card and per-day limits (see
# routers/card_shares.py). Kept independent
# of get_achievements() on purpose — that one makes a network call out to
# the Teamira/TMDB franchise data for saga badges, which this endpoint
# has no need to pay for just to draw a progress ring.
# ---------------------------------------------------------------------------

def compute_level_for_user(db: Session, user_id: str) -> LevelOut:
    """The actual GET /level implementation, pulled out so other routers
    (routers/friends.py, for the level shown next to each friend) can get
    someone's level without duplicating this query.

    Level itself now comes straight off User.lifetime_sincerity_earned
    and app/sincerity.py::compute_level — see that column's own
    docstring for why level is computed from the lifetime total rather
    than the spendable sincerity_balance. Everything below the level
    fields is pure informational stats for the level-detail screen (how
    many titles, how many with a note, and so on) — none of it is
    weighted into a point total any more, on purpose: the honest
    breakdown of *where* someone's points actually came from now lives
    in the sincerity ledger itself (GET /sincerity/me's history), not in
    a second, parallel formula here that could quietly drift from what
    was actually paid out.
    """
    user = db.query(models.User).filter(models.User.id == user_id).one()
    level, points_into_level, points_for_next_level = sincerity.compute_level(
        user.lifetime_sincerity_earned
    )

    watched_total = (
        db.query(func.count(models.WatchlistEntry.id))
        .filter(
            models.WatchlistEntry.user_id == user_id,
            models.WatchlistEntry.status == models.WatchStatus.watched,
        )
        .scalar()
    ) or 0

    diary_entries = (
        db.query(models.DiaryEntry)
        .filter(models.DiaryEntry.user_id == user_id)
        .all()
    )
    reviews_written = sum(1 for e in diary_entries if e.note and e.note.strip())
    rewatches_logged = sum(1 for e in diary_entries if e.is_rewatch)

    watched_entries = (
        db.query(models.WatchlistEntry)
        .filter(
            models.WatchlistEntry.user_id == user_id,
            models.WatchlistEntry.status == models.WatchStatus.watched,
        )
        .all()
    )
    distinct_genres: set = set()
    for e in watched_entries:
        for genre in e.genres or []:
            key = genre.strip().lower()
            if key:
                distinct_genres.add(key)

    # Same longest-ever-streak read as get_achievements() — consecutive
    # calendar days with at least one ActivityEvent, across every date on
    # file rather than stopping at the first gap from today.
    event_dates = sorted({
        e.created_at.date()
        for e in db.query(models.ActivityEvent)
        .filter(models.ActivityEvent.user_id == user_id)
        .all()
        if e.created_at
    })
    longest_streak_ever = 0
    if event_dates:
        run = 1
        longest_streak_ever = 1
        for prev, nxt in zip(event_dates, event_dates[1:]):
            gap = (nxt - prev).days
            if gap == 1:
                run += 1
                longest_streak_ever = max(longest_streak_ever, run)
            elif gap > 1:
                run = 1

    # Friends who registered using this account's own invite code (see
    # routers/friends.py::get_invite) — a real onboarded person, not
    # something farmable the way re-tagging an existing entry would be.
    invites_count = (
        db.query(func.count(models.User.id))
        .filter(models.User.referred_by_id == user_id)
        .scalar()
    ) or 0

    # Evenings watched together — same predicate app/challenges.py uses
    # for its own "together" measures: the co-viewing screen's "watched"
    # button and the log form's "watched with" toggle both set
    # watched_together, and watched_with_username is the snapshot left
    # behind by either of them.
    together_count = sum(
        1 for e in diary_entries if e.watched_together or e.watched_with_username
    )

    # Share cards sent out of the app — one row per distinct card, only
    # ever written by POST /shares/card, which enforces the daily cap.
    card_shares_count = (
        db.query(func.count(models.CardShare.id))
        .filter(models.CardShare.user_id == user_id)
        .scalar()
    ) or 0

    challenges_claimed = (
        db.query(func.count(models.ChallengeProgress.id))
        .filter(
            models.ChallengeProgress.user_id == user_id,
            models.ChallengeProgress.claimed_at.isnot(None),
        )
        .scalar()
    ) or 0

    return LevelOut(
        level=level,
        points=user.lifetime_sincerity_earned,
        points_into_level=points_into_level,
        points_for_next_level=points_for_next_level,
        progress=points_into_level / points_for_next_level if points_for_next_level else 0.0,
        watched_count=watched_total,
        reviews_count=reviews_written,
        rewatch_count=rewatches_logged,
        genres_count=len(distinct_genres),
        longest_streak_ever=longest_streak_ever,
        invites_count=invites_count,
        challenges_claimed=challenges_claimed,
        watched_together_count=together_count,
        card_shares_count=card_shares_count,
    )


@router.get("/level", response_model=LevelOut)
def get_level(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return compute_level_for_user(db, current_user.id)


# ---------------------------------------------------------------------------
# Wrapped
# ---------------------------------------------------------------------------

# Rough, honestly-labelled hour assumptions per media type, used only when
# we don't have a real runtime snapshot for that evening. Movies/series
# come from TMDB when it has runtime data; games/anime/books/manga fall
# back to these averages, since Seenly doesn't track play-time or reading
# progress (yet).
_DEFAULT_HOURS = {
    models.MediaType.movie: 1.9,
    models.MediaType.series: 6.0,   # a few episodes in one sitting, on average
    models.MediaType.anime: 2.0,    # roughly half a season
    models.MediaType.game: 10.0,
    models.MediaType.book: 6.0,
    models.MediaType.manga: 1.5,
}

_MONTH_NAMES = [
    "", "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
]


@router.get("/wrapped", response_model=WrappedStat)
def get_wrapped(
    period: str = "month",
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if period not in ("month", "year"):
        period = "month"

    now = datetime.now(timezone.utc)
    if period == "month":
        start = datetime(now.year, now.month, 1, tzinfo=timezone.utc)
        period_label = f"{_MONTH_NAMES[now.month]} {now.year}"
    else:
        start = datetime(now.year, 1, 1, tzinfo=timezone.utc)
        period_label = str(now.year)

    entries = (
        db.query(models.DiaryEntry)
        .filter(
            models.DiaryEntry.user_id == current_user.id,
            models.DiaryEntry.watched_at >= start,
            models.DiaryEntry.watched_at <= now,
        )
        .all()
    )

    breakdown = WrappedBreakdown()
    hours = 0.0
    genre_counter: Counter = Counter()
    day_counter: Counter = Counter()
    dates: set = set()
    favorite = None  # highest-rated entry this period

    for e in entries:
        media_type = e.media_type if isinstance(e.media_type, models.MediaType) else models.MediaType(e.media_type)
        if media_type == models.MediaType.movie:
            breakdown.movies += 1
        elif media_type == models.MediaType.series:
            breakdown.series += 1
        elif media_type == models.MediaType.anime:
            breakdown.anime += 1
        elif media_type == models.MediaType.game:
            breakdown.games += 1
        elif media_type == models.MediaType.book:
            breakdown.books += 1
        elif media_type == models.MediaType.manga:
            breakdown.manga += 1

        if e.runtime_minutes:
            hours += e.runtime_minutes / 60
        else:
            hours += _DEFAULT_HOURS.get(media_type, 1.5)

        for genre in e.genres or []:
            genre_counter[genre] += 1

        if e.watched_at:
            day_counter[e.watched_at.strftime("%A")] += 1
            dates.add(e.watched_at.date())

        if e.rating and (favorite is None or e.rating > favorite.rating):
            favorite = e

    top_genres = [GenreCount(genre=g, count=c) for g, c in genre_counter.most_common(5)]
    busiest_day = day_counter.most_common(1)[0][0] if day_counter else None

    # Longest run of consecutive calendar days within the period.
    longest_streak = 0
    if dates:
        current_run = 1
        longest_streak = 1
        ordered = sorted(dates)
        for prev, nxt in zip(ordered, ordered[1:]):
            if (nxt - prev).days == 1:
                current_run += 1
                longest_streak = max(longest_streak, current_run)
            else:
                current_run = 1

    favorite_title = None
    favorite_poster = None
    favorite_media_type = None
    if favorite is not None:
        favorite_title = favorite.title_en or favorite.title_ru
        favorite_poster = favorite.poster_url
        favorite_media_type = (
            favorite.media_type.value
            if hasattr(favorite.media_type, "value")
            else favorite.media_type
        )

    return WrappedStat(
        period=period,
        period_label=period_label,
        total_logged=len(entries),
        hours=round(hours, 1),
        breakdown=breakdown,
        top_genres=top_genres,
        longest_streak=longest_streak,
        busiest_day=busiest_day,
        favorite_title=favorite_title,
        favorite_poster=favorite_poster,
        favorite_media_type=favorite_media_type,
        is_premium=True,
        unlocked=True,  # demo: Wrapped is free to try for everyone right now
    )


# ---------------------------------------------------------------------------
# Wrapped — full recap, any period
# ---------------------------------------------------------------------------
#
# The richer "envelope -> cards -> letter -> receipt" flow (see
# WrappedSummary in schemas.py). Deliberately separate endpoints from
# GET /wrapped above rather than folding into its `period` param — that
# one keeps its own simpler year-to-date shape for anything still reading
# it; these are built for the card-carousel screen only, and cover three
# scopes: one calendar month, one calendar year, or the account's whole
# history.

_WEEKDAY_RU = ["понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресенье"]
_MONTH_RU_GENITIVE = [
    "", "января", "февраля", "марта", "апреля", "мая", "июня",
    "июля", "августа", "сентября", "октября", "ноября", "декабря",
]
_MONTH_RU_NOMINATIVE = [
    "", "январь", "февраль", "март", "апрель", "май", "июнь",
    "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь",
]
_MONTH_RU_ABBR = [
    "", "янв", "фев", "мар", "апр", "май", "июн",
    "июл", "авг", "сен", "окт", "ноя", "дек",
]

# Common TMDB/IGDB genre strings -> Russian display labels for the
# Wrapped cards. Anything not in here just falls back to the raw genre
# string (lowercased) rather than guessing — an honest degrade, same
# spirit as the rest of Wrapped.
_GENRE_RU = {
    "drama": "драма", "comedy": "комедия", "thriller": "триллер",
    "action": "боевик", "horror": "ужасы", "documentary": "документальное",
    "animation": "анимация", "romance": "мелодрама", "adventure": "приключения",
    "fantasy": "фэнтези", "crime": "криминал", "mystery": "детектив",
    "sci-fi": "фантастика", "science fiction": "фантастика", "family": "семейное",
    "music": "музыкальное", "musical": "мюзикл", "war": "военное",
    "history": "исторический", "western": "вестерн", "biography": "биография",
    "sport": "спорт", "rpg": "rpg", "shooter": "шутер", "strategy": "стратегия",
    "adventure game": "приключения", "indie": "инди",
}


def _genre_ru(genre: str) -> str:
    key = (genre or "").strip().lower()
    return _GENRE_RU.get(key, key or "другое")


def _date_label_ru(dt: datetime) -> str:
    return f"{dt.day} {_MONTH_RU_GENITIVE[dt.month]}"


def _archetype_label(peak_hour: Optional[int], solo_percent: float, top_genre: Optional[str]) -> str:
    if peak_hour is not None:
        if 0 <= peak_hour < 6:
            time_word = "ночной"
        elif 6 <= peak_hour < 12:
            time_word = "утренний"
        elif 12 <= peak_hour < 18:
            time_word = "дневной"
        else:
            time_word = "вечерний"
    else:
        time_word = None

    genre_word = f" {top_genre}а" if top_genre and top_genre.endswith("а") else ""
    base = f"синефил{genre_word}" if genre_word else "синефил"
    label = f"{time_word} {base}" if time_word else base
    label += "-одиночка" if solo_percent >= 50 else ", в компании"
    return label


def _resolve_wrapped_range(scope: str, year: Optional[int], month: Optional[int], now: datetime):
    """Returns (start, end, anchor_year, anchor_month, period_label,
    range_label_or_None). range_label is None for scope=="all" — the
    caller fills it in afterwards from the actual first/last entry, since
    "all time" has no fixed calendar bound to print up front.

    start/end are always UTC-aware (built with tzinfo=timezone.utc), to
    match DiaryEntry.watched_at (DateTime(timezone=True) — see
    app/models.py) and `now`, which every caller already passes in aware.
    A naive boundary here would still filter without raising, but
    Postgres would read it in the connection's session timezone instead
    of UTC — a silent off-by-some-hours bug, not a crash, which is why
    it's worth being explicit rather than relying on nobody ever setting
    a non-UTC session timezone."""
    if scope == "month":
        y = year or now.year
        m = month or now.month
        m = min(max(m, 1), 12)
        start = datetime(y, m, 1, tzinfo=timezone.utc)
        last_day = calendar.monthrange(y, m)[1]
        end = datetime(y, m, last_day, 23, 59, 59, tzinfo=timezone.utc)
        period_label = f"{_MONTH_RU_NOMINATIVE[m]} {y}"
        range_label = f"01.{m:02d} — {last_day:02d}.{m:02d}"
        return start, end, y, m, period_label, range_label
    if scope == "all":
        return None, now, now.year, None, "за всё время", None
    # "year" (default)
    y = year or now.year
    start = datetime(y, 1, 1, tzinfo=timezone.utc)
    end = datetime(y, 12, 31, 23, 59, 59, tzinfo=timezone.utc)
    return start, end, y, None, str(y), "01.01 — 31.12"


@router.get("/wrapped/periods", response_model=WrappedPeriodsOut)
def get_wrapped_periods(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    rows = (
        db.query(
            func.extract("year", models.DiaryEntry.watched_at),
            func.extract("month", models.DiaryEntry.watched_at),
        )
        .filter(models.DiaryEntry.user_id == current_user.id, models.DiaryEntry.watched_at.isnot(None))
        .distinct()
        .all()
    )
    years = sorted({int(y) for y, _m in rows}, reverse=True)
    months = sorted(
        ({"year": int(y), "month": int(m)} for y, m in rows),
        key=lambda p: (p["year"], p["month"]),
        reverse=True,
    )
    return WrappedPeriodsOut(
        years=years,
        months=[WrappedMonthPeriod(**p) for p in months],
        has_any=bool(rows),
    )


@router.get("/wrapped/summary", response_model=WrappedSummary)
def get_wrapped_summary(
    scope: str = "year",           # "month" | "year" | "all"
    year: Optional[int] = None,
    month: Optional[int] = None,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if scope not in ("month", "year", "all"):
        raise HTTPException(status_code=400, detail="scope must be month, year, or all")
    if scope == "month" and month is not None and not (1 <= month <= 12):
        raise HTTPException(status_code=400, detail="month must be 1-12")

    now = datetime.now(timezone.utc)
    start, end, anchor_year, anchor_month, period_label, fixed_range_label = _resolve_wrapped_range(
        scope, year, month, now
    )

    q = db.query(models.DiaryEntry).filter(models.DiaryEntry.user_id == current_user.id)
    if start is not None:
        q = q.filter(models.DiaryEntry.watched_at >= start)
    if end is not None:
        q = q.filter(models.DiaryEntry.watched_at <= end)
    entries = q.order_by(models.DiaryEntry.watched_at.asc()).all()

    if not entries:
        return WrappedSummary(
            scope=scope, year=anchor_year, month=anchor_month,
            period_label=period_label, range_label=fixed_range_label or "—",
            total_logged=0, total_hours=0.0, unlocked=True,
        )

    total_hours = 0.0
    for e in entries:
        media_type = e.media_type if isinstance(e.media_type, models.MediaType) else models.MediaType(e.media_type)
        total_hours += (e.runtime_minutes / 60) if e.runtime_minutes else _DEFAULT_HOURS.get(media_type, 1.5)

    dated = [e for e in entries if e.watched_at]
    first_entry = dated[0] if dated else None
    last_entry = dated[-1] if dated else None
    days_span = (last_entry.watched_at.date() - first_entry.watched_at.date()).days + 1 if dated else 0

    range_label = fixed_range_label or (
        f"{first_entry.watched_at:%d.%m.%y} — {last_entry.watched_at:%d.%m.%y}" if dated else "—"
    )

    director_counter: Counter = Counter()
    for e in entries:
        for name in (e.director or "").split(","):
            name = name.strip()
            if name:
                director_counter[name] += 1
    top_directors = [
        WrappedDirectorCount(name=n, count=c) for n, c in director_counter.most_common(4)
    ]

    decade_counter: Counter = Counter()
    for e in entries:
        if e.year:
            if e.year >= 2020:
                decade_counter["2020s"] += 1
            elif e.year >= 2010:
                decade_counter["2010s"] += 1
            else:
                decade_counter["older"] += 1
    total_with_year = sum(decade_counter.values())
    decades = [
        WrappedDecadeBucket(label=label, count=c, percent=round(c / total_with_year * 100, 1))
        for label, c in decade_counter.most_common()
    ] if total_with_year else []

    new_count = sum(1 for e in entries if not e.is_rewatch)
    rewatch_count = sum(1 for e in entries if e.is_rewatch)

    # The finer-grained "timeline" card: days-of-month for a single month
    # (nothing coarser would show any variation), months-of-year otherwise.
    if scope == "month" and anchor_month is not None:
        days_in_month = calendar.monthrange(anchor_year, anchor_month)[1]
        day_counter: Counter = Counter(e.watched_at.day for e in dated)
        timeline = [
            WrappedTimelineBucket(label=str(d), count=day_counter.get(d, 0))
            for d in range(1, days_in_month + 1)
        ]
        busiest_day = day_counter.most_common(1)[0][0] if day_counter else None
        busiest_timeline_label = f"{busiest_day} число" if busiest_day else None
    else:
        month_counter: Counter = Counter(e.watched_at.month for e in dated)
        timeline = [
            WrappedTimelineBucket(label=_MONTH_RU_ABBR[m], count=month_counter.get(m, 0))
            for m in range(1, 13)
        ]
        busiest_month = month_counter.most_common(1)[0][0] if month_counter else None
        busiest_timeline_label = _MONTH_RU_NOMINATIVE[busiest_month] if busiest_month else None

    watch_dates = sorted({e.watched_at.date() for e in dated})
    longest_streak = 0
    if watch_dates:
        run = 1
        longest_streak = 1
        for prev, nxt in zip(watch_dates, watch_dates[1:]):
            if (nxt - prev).days == 1:
                run += 1
                longest_streak = max(longest_streak, run)
            else:
                run = 1

    weekday_counter: Counter = Counter(e.watched_at.weekday() for e in dated)
    weekdays = [WrappedWeekdayCount(weekday=d, count=weekday_counter.get(d, 0)) for d in range(7)]
    weekend_count = weekday_counter.get(5, 0) + weekday_counter.get(6, 0)
    weekend_percent = round(weekend_count / len(entries) * 100, 1) if entries else 0.0

    solo_count = sum(1 for e in entries if not e.watched_with_username)
    company_count = sum(1 for e in entries if e.watched_with_username)
    solo_percent = round(solo_count / len(entries) * 100, 1) if entries else 0.0

    hour_counter: Counter = Counter(e.watched_at.hour for e in dated)
    peak_hour = hour_counter.most_common(1)[0][0] if hour_counter else None
    peak_hour_percent = 0.0
    if peak_hour is not None and dated:
        near = sum(
            c for h, c in hour_counter.items()
            if min((h - peak_hour) % 24, (peak_hour - h) % 24) <= 1
        )
        peak_hour_percent = round(near / len(dated) * 100, 1)

    genre_counter: Counter = Counter()
    for e in entries:
        for g in e.genres or []:
            genre_counter[_genre_ru(g)] += 1
    total_genre_hits = sum(genre_counter.values())
    genre_mix = []
    if total_genre_hits:
        # Show up to MAX_GENRES individual genres; anything beyond that
        # collapses into "остальное" so the list doesn't sprawl but also
        # doesn't dump half the pie into one bucket when there are only
        # a handful of distinct genres.
        MAX_GENRES = 8
        top_genres_ranked = genre_counter.most_common(MAX_GENRES)
        shown = 0
        for g, c in top_genres_ranked:
            pct = round(c / total_genre_hits * 100, 1)
            genre_mix.append(WrappedGenreShare(genre=g, count=c, percent=pct))
            shown += c
        other = total_genre_hits - shown
        if other > 0:
            genre_mix.append(WrappedGenreShare(
                genre="остальное", count=other, percent=round(other / total_genre_hits * 100, 1)
            ))
    top_genre = genre_mix[0].genre if genre_mix else None

    rated = [e for e in entries if e.rating]
    review_count = sum(1 for e in entries if e.note and e.note.strip())
    average_rating = round(sum(e.rating for e in rated) / len(rated), 1) if rated else 0.0
    full_marks_count = sum(1 for e in rated if e.rating == 10)

    rating_counter: Counter = Counter(e.rating for e in rated)
    rating_histogram = [
        WrappedRatingBucket(rating=r, count=rating_counter.get(r, 0)) for r in range(1, 11)
    ]

    top_rated_sorted = sorted(rated, key=lambda e: -e.rating)[:4]
    top_reviews = [
        WrappedReviewItem(
            title=e.title_ru or e.title_en or "—",
            rating=e.rating,
            note=e.note,
            date_label=_date_label_ru(e.watched_at) if e.watched_at else None,
            poster_url=e.poster_url,
        )
        for e in top_rated_sorted
    ]

    reviewed_with_note = [e for e in rated if e.note and e.note.strip()]
    favorite_source = (
        max(reviewed_with_note, key=lambda e: e.rating)
        if reviewed_with_note
        else (max(rated, key=lambda e: e.rating) if rated else None)
    )
    favorite_review = (
        WrappedReviewItem(
            title=favorite_source.title_ru or favorite_source.title_en or "—",
            rating=favorite_source.rating,
            note=favorite_source.note,
            date_label=_date_label_ru(favorite_source.watched_at) if favorite_source.watched_at else None,
            poster_url=favorite_source.poster_url,
        )
        if favorite_source is not None
        else None
    )

    archetype_label = _archetype_label(peak_hour, solo_percent, top_genre)

    # This account's total logged evenings vs everyone else's, this same
    # period — an honest single-query percentile rather than a fabricated
    # "top X%" claim. None (client hides the line) when there's no one
    # else on file yet to compare against, or scope=="all" (no shared
    # fixed window to compare everyone against).
    hours_percentile = None
    if start is not None and end is not None:
        all_counts = [
            c for (_uid, c) in (
                db.query(models.DiaryEntry.user_id, func.count(models.DiaryEntry.id))
                .filter(models.DiaryEntry.watched_at >= start, models.DiaryEntry.watched_at <= end)
                .group_by(models.DiaryEntry.user_id)
                .all()
            )
        ]
        if len(all_counts) > 1:
            at_or_below = sum(1 for c in all_counts if c <= len(entries))
            hours_percentile = round(at_or_below / len(all_counts) * 100)

    title_counter: Counter = Counter()
    for e in entries:
        title_counter[e.title_ru or e.title_en or "—"] += 1
    receipt_items = [
        WrappedReceiptItem(title=t, count=c)
        for t, c in sorted(title_counter.items(), key=lambda kv: (-kv[1], kv[0]))
    ]

    poster_urls: List[str] = []
    seen_posters = set()
    for e in reversed(entries):  # most recently logged first
        if e.poster_url and e.poster_url not in seen_posters:
            poster_urls.append(e.poster_url)
            seen_posters.add(e.poster_url)
        if len(poster_urls) >= 12:
            break

    return WrappedSummary(
        scope=scope,
        year=anchor_year,
        month=anchor_month,
        period_label=period_label,
        range_label=range_label,
        total_logged=len(entries),
        total_hours=round(total_hours, 1),
        first=WrappedTitleMoment(
            title=first_entry.title_ru or first_entry.title_en or "—",
            date_label=_date_label_ru(first_entry.watched_at),
            poster_url=first_entry.poster_url,
        ) if first_entry else None,
        last=WrappedTitleMoment(
            title=last_entry.title_ru or last_entry.title_en or "—",
            date_label=_date_label_ru(last_entry.watched_at),
            poster_url=last_entry.poster_url,
        ) if last_entry else None,
        days_span=days_span,
        top_directors=top_directors,
        decades=decades,
        new_count=new_count,
        rewatch_count=rewatch_count,
        timeline=timeline,
        busiest_timeline_label=busiest_timeline_label,
        longest_streak_days=longest_streak,
        weekdays=weekdays,
        weekend_percent=weekend_percent,
        solo_count=solo_count,
        company_count=company_count,
        solo_percent=solo_percent,
        peak_hour=peak_hour,
        peak_hour_percent=peak_hour_percent,
        archetype_label=archetype_label,
        genre_mix=genre_mix,
        top_genre=top_genre,
        review_count=review_count,
        average_rating=average_rating,
        full_marks_count=full_marks_count,
        top_reviews=top_reviews,
        favorite_review=favorite_review,
        rating_histogram=rating_histogram,
        hours_percentile=hours_percentile,
        receipt_items=receipt_items,
        poster_urls=poster_urls,
        is_premium=True,
        unlocked=True,
    )


# ---------------------------------------------------------------------------
# Achievements
# ---------------------------------------------------------------------------
#
# Every achievement here is computed on the fly from the person's own real
# rows — WatchlistEntry (what's marked watched, with its genre snapshot),
# DiaryEntry (notes, rewatches), ActivityEvent (streak history), and the
# account's own created_at. Nothing is a separately-tracked counter that
# could drift out of sync with what's actually logged, and nothing unlocks
# from anything other than the person's own honest logging — there's no
# admin override or manual grant path. See AchievementOut/AchievementsOut
# in schemas.py for the shape this returns.

def _normalize_title(title: Optional[str]) -> str:
    """Loose title fingerprint for matching a watched title against a TMDB
    franchise entry (a title's own stored spelling isn't always
    identically-punctuated to TMDB's) — lowercase, letters and
    digits only. Not perfect (two different films that happen to share a
    bare title would collide), but franchise entries are specific enough
    ("The Empire Strikes Back", not "Episode V") that this is a fair,
    honest read in practice rather than a loophole."""
    if not title:
        return ""
    return re.sub(r"[^a-z0-9]+", "", title.lower())


# Movie-count milestones — table stakes for "you actually use this app",
# from the very first logged evening up to a genuinely dedicated total.
_MOVIE_MILESTONES = [
    (1, "first watch", "logged your very first film"),
    (10, "warming up", "10 films logged"),
    (50, "movie buff", "50 films logged"),
    (100, "100 films", "a full hundred"),
    (250, "film scholar", "250 films logged"),
]

# Genre depth — a fixed, small set on purpose (every raw TMDB genre would be
# both noisy and prone to case/spelling drift); matched case-insensitively
# against each watched title's own genre snapshot.
_GENRE_MASTERY = [
    ("comedy", "comedy connoisseur", "10 comedies logged", 10),
    ("horror", "brave enough", "10 horror titles logged", 10),
    ("animation", "still a kid at heart", "10 animated films logged", 10),
    ("documentary", "curious mind", "10 documentaries logged", 10),
]

_GENRE_EXPLORER_TARGET = 8  # distinct genres, breadth rather than depth

# Streak milestones — longest run ever reached, not the currently-active
# streak (which resets to 0 the moment a day is missed; someone who once
# ran 40 days straight and took a week off still deserves to keep "a whole
# month" forever).
_STREAK_MILESTONES = [
    (7, "one good week", "a 7-day streak"),
    (30, "a whole month", "a 30-day streak"),
    (100, "triple digits", "a 100-day streak"),
    (365, "unbroken year", "a 365-day streak"),
]

_MEMBER_DAYS_TARGET = 365

# Level milestones — every 5th level someone's real level (see
# _compute_level below) reaches, mirrored 1:1 with the "level path"
# milestone cards in mobile/lib/screens/profile/level_detail_screen.dart
# so a level shows the exact same badge there and here. Capped at 30
# (matching the icon set in achievementIcon's 'level' case client-side)
# rather than left open-ended the way sagas are, since — unlike a
# franchise — there's no natural stopping point to a level number.
_LEVEL_MILESTONES = [5, 10, 15, 20, 25, 30]


def _rarity_for_level(level: int) -> str:
    """Rarity curve for level-milestone badges — kept in its own function
    rather than reusing `_rarity_for_target` above, since that one is
    tuned for movie-count-sized targets; a level number needs its own
    (much smaller) thresholds. Mirrored client-side by
    `levelBadgeRarityKey` in widgets/achievement_badge.dart."""
    if level >= 30:
        return "legend"
    if level >= 20:
        return "obsession"
    if level >= 10:
        return "devoted"
    return "habit"

# Badge rarity — purely a function of how hard a given badge's own
# progress_target is to reach, so it never has to be hand-assigned per
# achievement (and can't drift out of sync the way a hand-picked value
# could). Four bands, cozy names rather than game-y ones ("common" /
# "epic"), colors chosen to match SeenlyPalette on the client:
# habit -> sage, devoted -> periwinkle, obsession -> mustard,
# legend -> the accent/mustard/coral gradient. Thresholds are deliberately
# generous at the low end (most of the ~45 achievements are "habit" or
# "devoted") so "legend" stays genuinely rare — reserved for the handful
# of targets at the very top of each category (250 films, a 365-day
# streak, a full year on teamira, the largest sagas).
def _rarity_for_target(target: int) -> str:
    if target >= 250:
        return "legend"
    if target >= 50:
        return "obsession"
    if target >= 8:
        return "devoted"
    return "habit"


async def compute_achievements_for_user(db: Session, user: models.User) -> list[AchievementOut]:
    """The actual badge list for one account — pulled out of the route
    handler below so routers/friends.py can compute another account's
    badges too (for that account's pinned showcase on their friend
    profile) without duplicating this whole tally. Takes the User row
    itself (not just an id) because get_teamira_collections below needs
    it the same way GET /achievements always has.
    """
    user_id = user.id
    watched = (
        db.query(models.WatchlistEntry)
        .filter(
            models.WatchlistEntry.user_id == user_id,
            models.WatchlistEntry.status == models.WatchStatus.watched,
        )
        .all()
    )
    movies_watched = [e for e in watched if e.media_type == models.MediaType.movie]
    movie_count = len(movies_watched)

    diary_entries = (
        db.query(models.DiaryEntry)
        .filter(models.DiaryEntry.user_id == user_id)
        .all()
    )
    has_review = any(e.note and e.note.strip() for e in diary_entries)
    has_rewatch = any(e.is_rewatch for e in diary_entries)

    genre_counts: Counter = Counter()
    distinct_genres: set = set()
    for e in watched:
        for genre in e.genres or []:
            key = genre.strip().lower()
            if not key:
                continue
            genre_counts[key] += 1
            distinct_genres.add(key)

    # Longest-ever streak — same consecutive-calendar-days read as
    # get_year_stats()'s current streak above, just run across every event
    # date on file instead of stopping at the first gap from today.
    event_dates = sorted({
        e.created_at.date()
        for e in db.query(models.ActivityEvent)
        .filter(models.ActivityEvent.user_id == user_id)
        .all()
        if e.created_at
    })
    longest_streak_ever = 0
    if event_dates:
        run = 1
        longest_streak_ever = 1
        for prev, nxt in zip(event_dates, event_dates[1:]):
            gap = (nxt - prev).days
            if gap == 1:
                run += 1
                longest_streak_ever = max(longest_streak_ever, run)
            elif gap > 1:
                run = 1

    member_days = (
        (datetime.now(timezone.utc) - user.created_at).days
        if user.created_at else 0
    )

    achievements: list[AchievementOut] = []

    for target, title, caption in _MOVIE_MILESTONES:
        achievements.append(AchievementOut(
            id=f"milestone:{target}",
            category="milestone",
            icon_key="milestone",
            title=title,
            caption=caption,
            unlocked=movie_count >= target,
            progress_current=min(movie_count, target),
            progress_target=target,
            rarity=_rarity_for_target(target),
        ))

    achievements.append(AchievementOut(
        id="craft:first_review",
        category="craft",
        icon_key="review",
        title="first review",
        caption="wrote a note on a logged evening",
        unlocked=has_review,
        progress_current=1 if has_review else 0,
        progress_target=1,
        rarity=_rarity_for_target(1),
    ))
    achievements.append(AchievementOut(
        id="craft:rewatch",
        category="craft",
        icon_key="rewatch",
        title="second viewing",
        caption="logged a rewatch",
        unlocked=has_rewatch,
        progress_current=1 if has_rewatch else 0,
        progress_target=1,
        rarity=_rarity_for_target(1),
    ))
    achievements.append(AchievementOut(
        id="craft:genre_explorer",
        category="craft",
        icon_key="explorer",
        title="genre explorer",
        caption=f"watched across {_GENRE_EXPLORER_TARGET}+ different genres",
        unlocked=len(distinct_genres) >= _GENRE_EXPLORER_TARGET,
        progress_current=min(len(distinct_genres), _GENRE_EXPLORER_TARGET),
        progress_target=_GENRE_EXPLORER_TARGET,
        rarity=_rarity_for_target(_GENRE_EXPLORER_TARGET),
    ))

    for genre_key, title, caption, target in _GENRE_MASTERY:
        count = genre_counts.get(genre_key, 0)
        achievements.append(AchievementOut(
            id=f"genre:{genre_key}",
            category="genre",
            icon_key="genre",
            title=title,
            caption=caption,
            unlocked=count >= target,
            progress_current=min(count, target),
            progress_target=target,
            rarity=_rarity_for_target(target),
        ))

    # Sagas — franchise completion. Reuses the exact same cached franchise
    # snapshot GET /feed/teamira serves (see cache.TEAMIRA_TTL) rather than
    # re-resolving ~28 franchises worth of TMDB calls on every achievements
    # request. Matched by normalized title only (see _normalize_title) —
    # WatchlistEntry has no cross-source id to join on, since a franchise
    # entry logged through regular browsing and the same film logged
    # through a Teamira pick don't share an id, only a title.
    watched_titles = {_normalize_title(e.title_en or e.title_ru) for e in movies_watched}
    watched_titles.discard("")
    try:
        franchise_collections = await get_teamira_collections(current_user=user)
    except Exception:
        franchise_collections = []

    for coll in franchise_collections:
        if not coll.is_franchise or not coll.items:
            continue
        total = len(coll.items)
        matched = sum(
            1 for item in coll.items
            if _normalize_title(item.title.en or item.title.ru) in watched_titles
        )
        display_title = coll.title_en or coll.title
        achievements.append(AchievementOut(
            id=f"saga:{coll.title}",
            category="saga",
            icon_key="saga",
            title=display_title,
            caption=f"watched all {total} in the saga",
            unlocked=matched >= total,
            progress_current=matched,
            progress_target=total,
            # Sagas skip the plain target-size rarity curve: finishing an
            # entire franchise is hard regardless of how short it is (a
            # tidy 3-film trilogy is just as much a real completion as a
            # 20-film one), so every saga badge reads as "obsession" at
            # minimum rather than "habit" for the shorter ones.
            rarity="legend" if total >= 15 else "obsession",
        ))

    for target, title, caption in _STREAK_MILESTONES:
        achievements.append(AchievementOut(
            id=f"streak:{target}",
            category="devotion",
            icon_key="streak",
            title=title,
            caption=caption,
            unlocked=longest_streak_ever >= target,
            progress_current=min(longest_streak_ever, target),
            progress_target=target,
            rarity=_rarity_for_target(target),
        ))
    achievements.append(AchievementOut(
        id="devotion:member_year",
        category="devotion",
        icon_key="loyalty",
        title="one trip around the sun",
        caption=f"{_MEMBER_DAYS_TARGET} days on tanè",
        unlocked=member_days >= _MEMBER_DAYS_TARGET,
        progress_current=min(member_days, _MEMBER_DAYS_TARGET),
        progress_target=_MEMBER_DAYS_TARGET,
        rarity=_rarity_for_target(_MEMBER_DAYS_TARGET),
    ))

    # Level milestones — reuses compute_level_for_user's own level (now
    # backed by User.lifetime_sincerity_earned — see
    # app/sincerity.py::compute_level) rather than re-deriving it here,
    # so this can never drift out of sync with what the level ring on
    # the Sincerity screen actually shows.
    current_level = compute_level_for_user(db, user_id).level
    for target in _LEVEL_MILESTONES:
        achievements.append(AchievementOut(
            id=f"level:{target}",
            category="milestone",
            icon_key="level",
            title=f"level {target}",
            caption=f"reached level {target}",
            unlocked=current_level >= target,
            progress_current=min(current_level, target),
            progress_target=target,
            rarity=_rarity_for_level(target),
        ))

    return achievements


def _pinned_ids_list(user: models.User) -> list[str]:
    """User.pinned_achievement_ids is stored as a plain comma-joined
    string (see that column's docstring) — this is the one place that
    format is parsed back out, so both the route below and
    routers/friends.py stay in sync on how it's read."""
    if not user.pinned_achievement_ids:
        return []
    return [p for p in user.pinned_achievement_ids.split(",") if p]


@router.get("/achievements", response_model=AchievementsOut)
async def get_achievements(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    achievements = await compute_achievements_for_user(db, current_user)
    unlocked_count = sum(1 for a in achievements if a.unlocked)
    return AchievementsOut(
        unlocked_count=unlocked_count,
        total_count=len(achievements),
        achievements=achievements,
        pinned_ids=_pinned_ids_list(current_user),
        max_pinned=3 + current_user.bonus_pin_slots,
        bonus_pin_slots=current_user.bonus_pin_slots,
    )


@router.post("/achievements/pin", response_model=AchievementsOut)
async def pin_achievements(
    body: PinAchievementsIn,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Sets this account's badge showcase — up to 3 + bonus_pin_slots
    unlocked achievement ids (see User.bonus_pin_slots and
    app/routers/profile.py::buy_pin_slot for the paid extra slots),
    shown on the profile header and on the friend profile screen (see
    routers/friends.py::get_friend_profile). Replaces the whole set
    each call rather than adding/removing one at a time, same pattern as
    POST /profile/favorites/pick — the client always sends its full
    intended selection.
    """
    max_pinned = 3 + current_user.bonus_pin_slots
    if len(body.achievement_ids) > max_pinned:
        raise HTTPException(status_code=400, detail=f"Pin at most {max_pinned} badges")

    achievements = await compute_achievements_for_user(db, current_user)
    unlocked_ids = {a.id for a in achievements if a.unlocked}
    for aid in body.achievement_ids:
        if aid not in unlocked_ids:
            raise HTTPException(status_code=400, detail=f"Badge not unlocked: {aid}")

    current_user.pinned_achievement_ids = ",".join(body.achievement_ids)
    db.commit()

    unlocked_count = len(unlocked_ids)
    return AchievementsOut(
        unlocked_count=unlocked_count,
        total_count=len(achievements),
        achievements=achievements,
        pinned_ids=body.achievement_ids,
        max_pinned=max_pinned,
        bonus_pin_slots=current_user.bonus_pin_slots,
    )


@router.post("/achievements/buy-pin-slot", response_model=AchievementsOut)
async def buy_pin_slot(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """One more permanent badge-showcase slot for
    sincerity.PIN_SLOT_COST — see app/sincerity.py::spend_pin_slot and
    User.bonus_pin_slots. The only sincerity spend with no per-item
    target (no entry, no friend, nothing to name in the confirmation
    beyond the cost itself), so unlike settle_debt or reveal_rating this
    takes no body and no id — just "one more slot, please".
    """
    if current_user.bonus_pin_slots >= sincerity.MAX_BONUS_PIN_SLOTS:
        raise HTTPException(status_code=400, detail="Already at the maximum number of slots")
    if current_user.sincerity_balance < sincerity.PIN_SLOT_COST:
        raise HTTPException(status_code=400, detail="Not enough sincerity points")

    sincerity.spend_pin_slot(db, current_user)
    current_user.bonus_pin_slots += 1
    db.commit()

    achievements = await compute_achievements_for_user(db, current_user)
    unlocked_count = sum(1 for a in achievements if a.unlocked)
    return AchievementsOut(
        unlocked_count=unlocked_count,
        total_count=len(achievements),
        achievements=achievements,
        pinned_ids=_pinned_ids_list(current_user),
        max_pinned=3 + current_user.bonus_pin_slots,
        bonus_pin_slots=current_user.bonus_pin_slots,
    )
