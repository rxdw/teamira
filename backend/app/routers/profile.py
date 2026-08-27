import os
import re
import calendar
import uuid
from collections import Counter
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.database import get_db
from app import models
from app.deps import get_current_user
from app.routers.teamira import get_teamira_collections
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
_AVATAR_UPLOAD_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "uploads", "avatars")
_ALLOWED_AVATAR_TYPES = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}
_MAX_AVATAR_BYTES = 5 * 1024 * 1024


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

    if "display_name" in changes:
        name = (changes["display_name"] or "").strip()
        current_user.display_name = name or None

    if "status_text" in changes:
        status_text = (changes["status_text"] or "").strip()
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
    person picked from their own device. MVP local-disk storage, same
    "swap for real object storage before real launch" story as the rest
    of this backend; the returned avatar_url is already the full path
    the client hands straight to Image.network."""
    content_type = (file.content_type or "").lower()
    if content_type not in _ALLOWED_AVATAR_TYPES:
        raise HTTPException(status_code=400, detail="Use a JPEG, PNG, or WebP image")

    body = await file.read()
    if len(body) > _MAX_AVATAR_BYTES:
        raise HTTPException(status_code=400, detail="Image is larger than 5 MB")

    os.makedirs(_AVATAR_UPLOAD_DIR, exist_ok=True)
    ext = _ALLOWED_AVATAR_TYPES[content_type]
    filename = f"{current_user.id}-{uuid.uuid4().hex[:8]}.{ext}"
    with open(os.path.join(_AVATAR_UPLOAD_DIR, filename), "wb") as f:
        f.write(body)

    # An uploaded photo always wins over a previously chosen preset —
    # same mutual-exclusivity rule as update_me's preset branch above.
    current_user.avatar_url = f"/static/avatars/{filename}"
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


@router.get("/collections", response_model=CollectionsOut)
def get_collections(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Splits the WatchlistEntry rows into the shelves the app shows:
    "watch later", "watching" (mid-series, at least one episode logged
    but not completed — see models.WatchStatus.watching), and "watched"."""
    entries = (
        db.query(models.WatchlistEntry)
        .filter(models.WatchlistEntry.user_id == current_user.id)
        .order_by(models.WatchlistEntry.updated_at.desc())
        .all()
    )
    watch_later = [e for e in entries if e.status == models.WatchStatus.watch_later]
    watching = [e for e in entries if e.status == models.WatchStatus.watching]
    watched = [e for e in entries if e.status == models.WatchStatus.watched]
    return CollectionsOut(watch_later=watch_later, watching=watching, watched=watched)


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
    # least one ActivityEvent — a simple, honest read of real event dates,
    # not a stored counter that can drift out of sync.
    event_dates = {
        e.created_at.date()
        for e in db.query(models.ActivityEvent)
        .filter(models.ActivityEvent.user_id == current_user.id)
        .all()
        if e.created_at
    }
    streak = 0
    cursor = datetime.utcnow().date()
    if cursor not in event_dates:
        cursor -= timedelta(days=1)  # allow "today hasn't happened yet"
    while cursor in event_dates:
        streak += 1
        cursor -= timedelta(days=1)

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
# farmed by anything other than actually using the app. Kept independent
# of get_achievements() on purpose — that one makes a network call out to
# the Teamira/TMDB franchise data for saga badges, which this endpoint
# has no need to pay for just to draw a progress ring.
# ---------------------------------------------------------------------------

_XP_PER_WATCHED = 10       # every logged title, any media type
_XP_PER_REVIEW = 8         # a diary entry with an actual note attached
_XP_PER_REWATCH = 4        # logged a second viewing
_XP_PER_GENRE_EXPLORED = 5  # distinct genres watched across, breadth over depth
_XP_PER_STREAK_DAY = 3     # longest-ever streak, not the currently-active one
_XP_PER_FRIEND_INVITED = 30  # a friend who registered with this account's invite code

# Each level costs more than the last — level 1->2 takes 100 xp, and every
# level after that costs 40 more than the one before it, so the ring
# never feels like it stalls out but later levels still take real use to
# reach. Simple integer arithmetic on purpose — no exponents/logs needed
# just to walk a rising staircase.
_LEVEL_BASE_XP = 100
_LEVEL_XP_STEP = 40


def _compute_level(total_xp: int) -> tuple[int, int, int]:
    """Returns (level, xp_into_current_level, xp_needed_for_next_level)."""
    level = 1
    remaining = max(total_xp, 0)
    needed = _LEVEL_BASE_XP
    while remaining >= needed:
        remaining -= needed
        level += 1
        needed += _LEVEL_XP_STEP
    return level, remaining, needed


def compute_level_for_user(db: Session, user_id: str) -> LevelOut:
    """The actual GET /level implementation, pulled out so other routers
    (routers/friends.py, for the level shown next to each friend) can get
    someone's level without duplicating this whole well-by-well tally.
    """
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

    total_xp = (
        watched_total * _XP_PER_WATCHED
        + reviews_written * _XP_PER_REVIEW
        + rewatches_logged * _XP_PER_REWATCH
        + len(distinct_genres) * _XP_PER_GENRE_EXPLORED
        + longest_streak_ever * _XP_PER_STREAK_DAY
        + invites_count * _XP_PER_FRIEND_INVITED
    )

    level, xp_into_level, xp_for_next_level = _compute_level(total_xp)

    return LevelOut(
        level=level,
        xp=total_xp,
        xp_into_level=xp_into_level,
        xp_for_next_level=xp_for_next_level,
        progress=xp_into_level / xp_for_next_level if xp_for_next_level else 0.0,
        watched_count=watched_total,
        xp_from_watched=watched_total * _XP_PER_WATCHED,
        reviews_count=reviews_written,
        xp_from_reviews=reviews_written * _XP_PER_REVIEW,
        rewatch_count=rewatches_logged,
        xp_from_rewatches=rewatches_logged * _XP_PER_REWATCH,
        genres_count=len(distinct_genres),
        xp_from_genres=len(distinct_genres) * _XP_PER_GENRE_EXPLORED,
        longest_streak_ever=longest_streak_ever,
        xp_from_streak=longest_streak_ever * _XP_PER_STREAK_DAY,
        invites_count=invites_count,
        xp_from_invites=invites_count * _XP_PER_FRIEND_INVITED,
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

    now = datetime.utcnow()
    if period == "month":
        start = datetime(now.year, now.month, 1)
        period_label = f"{_MONTH_NAMES[now.month]} {now.year}"
    else:
        start = datetime(now.year, 1, 1)
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
    "all time" has no fixed calendar bound to print up front."""
    if scope == "month":
        y = year or now.year
        m = month or now.month
        m = min(max(m, 1), 12)
        start = datetime(y, m, 1)
        last_day = calendar.monthrange(y, m)[1]
        end = datetime(y, m, last_day, 23, 59, 59)
        period_label = f"{_MONTH_RU_NOMINATIVE[m]} {y}"
        range_label = f"01.{m:02d} — {last_day:02d}.{m:02d}"
        return start, end, y, m, period_label, range_label
    if scope == "all":
        return None, now, now.year, None, "за всё время", None
    # "year" (default)
    y = year or now.year
    start = datetime(y, 1, 1)
    end = datetime(y, 12, 31, 23, 59, 59)
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

    now = datetime.utcnow()
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
        (datetime.utcnow() - user.created_at).days
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
        franchise_collections = await get_teamira_collections(current_user=user, db=db)
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
        caption=f"{_MEMBER_DAYS_TARGET} days on teamira",
        unlocked=member_days >= _MEMBER_DAYS_TARGET,
        progress_current=min(member_days, _MEMBER_DAYS_TARGET),
        progress_target=_MEMBER_DAYS_TARGET,
        rarity=_rarity_for_target(_MEMBER_DAYS_TARGET),
    ))

    # Level milestones — reuses compute_level_for_user's own well (watched
    # count, reviews, rewatches, genre breadth, streak, invites) rather
    # than re-tallying total_xp itself, so this can never drift out of
    # sync with what the level ring on the profile header actually shows.
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
    )


@router.post("/achievements/pin", response_model=AchievementsOut)
async def pin_achievements(
    body: PinAchievementsIn,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Sets this account's badge showcase — up to 3 unlocked achievement
    ids, shown on the profile header and on the friend profile screen
    (see routers/friends.py::get_friend_profile). Replaces the whole set
    each call rather than adding/removing one at a time, same pattern as
    POST /profile/favorites/pick — the client always sends its full
    intended selection.
    """
    if len(body.achievement_ids) > 3:
        raise HTTPException(status_code=400, detail="Pin at most 3 badges")

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
    )
