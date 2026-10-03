"""The shared diary — "наш дневник" — for a co-viewing circle.

What this is, precisely: a **view over the personal diaries of everyone
in the circle**, filtered to the entries they've each agreed to share.
There is no second copy of an evening anywhere. `DiaryEntry.shared_link_id`
is the whole mechanism (see that column's docstring): set, and the row
shows up here; null, and it doesn't.

Three consequences worth stating out loud, because they're the reason it
was built this way rather than as its own table:

  - Editing a rating or note in your own diary immediately changes what
    your partner sees here. No sync, no staleness, nothing to reconcile.
  - Deleting an evening removes it from both places at once, which is
    what anyone deleting an evening obviously means.
  - Unlinking a couple doesn't destroy anyone's diary — it just leaves a
    `shared_link_id` pointing at a dead link, which every query here
    filters on anyway.

Rows are grouped by (source, media_id) before they're returned, so a film
two people both logged is one card with two ratings rather than two cards
saying nearly the same thing. That grouping is the actual product here;
without it this screen is just a friends feed with extra steps.

Privacy is per-person and per-circle (models.PartnerPrefs), never
circle-wide: your partner turning notes on doesn't reveal yours. Each
person's prefs are applied to *their own* rows as those rows are
serialized for someone else — see `_person_out`.
"""

from __future__ import annotations

import calendar
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from app import models, push, sincerity
from app.database import get_db
from app.deps import get_current_user
from app.routers.partner import (
    _coview_out,
    _member_ids,
    _other_members,
    get_active_link,
)
from app.routers.premium import is_premium_account
from app.routers.profile import (
    _archetype_label,
    _date_label_ru,
    _genre_ru,
    _MONTH_RU_ABBR,
    _MONTH_RU_NOMINATIVE,
    _rarity_for_target,
    _resolve_wrapped_range,
)
from app.schemas import (
    AchievementOut,
    AchievementsOut,
    PartnerPrefsOut,
    PartnerPrefsUpdate,
    ShareDiaryEntryIn,
    SharedDiaryItemOut,
    SharedDiaryOut,
    SharedDiaryPersonOut,
    SharedPlannedOut,
    SharedStatsOut,
    WrappedDecadeBucket,
    WrappedDirectorCount,
    WrappedGenreShare,
    WrappedMonthPeriod,
    WrappedPeriodsOut,
    WrappedRatingBucket,
    WrappedReceiptItem,
    WrappedReviewItem,
    WrappedSummary,
    WrappedTimelineBucket,
    WrappedTitleMoment,
    WrappedWeekdayCount,
)

router = APIRouter(prefix="/partner/shared", tags=["shared-diary"])

# Sort fallback for a row with no watched_at. Aware, not `datetime.min`
# on its own — DiaryEntry.watched_at is now DateTime(timezone=True) (see
# app/models.py), so an aware value sorted alongside a naive one raises
# "can't compare offset-naive and offset-aware datetimes" the moment a
# group actually has an unset watched_at.
_EPOCH = datetime.min.replace(tzinfo=timezone.utc)

# How many grouped cards one page of the shared diary returns. Grouped,
# not raw rows — a page of 30 cards can be up to ~90 underlying rows for a
# three-person circle, which is why the query below over-fetches and then
# trims rather than using a plain SQL LIMIT.
_PAGE_SIZE = 30

# Rough per-media-type hour fallbacks, for shared entries with no runtime
# snapshot. Deliberately the same numbers routers/profile.py's Wrapped
# uses (_DEFAULT_HOURS) — two screens in the same app disagreeing about
# how long a game evening is would be worse than either number being
# slightly off.
_DEFAULT_HOURS = {
    models.MediaType.movie: 1.9,
    models.MediaType.series: 6.0,
    models.MediaType.anime: 2.0,
    models.MediaType.game: 10.0,
    models.MediaType.book: 6.0,
    models.MediaType.manga: 1.5,
}


# ---------------------------------------------------------------------------
# Prefs
# ---------------------------------------------------------------------------


def get_or_create_prefs(db: Session, user_id: str, link_id: str) -> models.PartnerPrefs:
    """Lazily created with defaults on first touch — nobody has a row
    until they've either opened the settings or logged an evening while
    linked. Commits, since several callers (the log path especially) want
    this to have happened regardless of whether their own transaction
    later rolls back for an unrelated reason."""
    prefs = (
        db.query(models.PartnerPrefs)
        .filter_by(user_id=user_id, link_id=link_id)
        .first()
    )
    if prefs is None:
        prefs = models.PartnerPrefs(user_id=user_id, link_id=link_id)
        db.add(prefs)
        db.commit()
        db.refresh(prefs)
    return prefs


def shared_link_id_for_log(
    db: Session, user_id: str, *, watched_together: bool
) -> Optional[str]:
    """Called from routers/diary.py::log_watched to decide whether a
    brand-new evening lands in the shared diary.

    `watched_together=True` always shares, regardless of the person's
    `auto_share_logs` setting. That isn't an oversight: an evening logged
    *from the co-viewing screen* is one the other person was demonstrably
    present for, and hiding it from them would produce a shared diary
    that's missing evenings they personally remember — which reads as a
    bug, not as privacy. The setting governs solo evenings, which is the
    case it was written for ("не записывать свой фильм в общий дневник").

    Returns None (don't share) for anyone with no active link, which is
    almost everyone — so the common path is one indexed query and out.
    """
    link = get_active_link(db, user_id)
    if link is None:
        return None
    if watched_together:
        return link.id
    prefs = get_or_create_prefs(db, user_id, link.id)
    return link.id if prefs.auto_share_logs else None


@router.get("/prefs", response_model=PartnerPrefsOut)
def get_prefs(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    link = get_active_link(db, current_user.id)
    if link is None:
        # Not an error: Settings shows these controls greyed out with a
        # "свяжитесь с партнёром, чтобы включить" hint rather than hiding
        # them, so it needs the defaults to render against.
        return PartnerPrefsOut()
    prefs = get_or_create_prefs(db, current_user.id, link.id)
    return PartnerPrefsOut(
        auto_share_logs=prefs.auto_share_logs,
        share_ratings=prefs.share_ratings,
        share_notes=prefs.share_notes,
    )


@router.patch("/prefs", response_model=PartnerPrefsOut)
def update_prefs(
    payload: PartnerPrefsUpdate,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    link = get_active_link(db, current_user.id)
    if link is None:
        raise HTTPException(status_code=409, detail="Link with a partner first")
    prefs = get_or_create_prefs(db, current_user.id, link.id)
    if payload.auto_share_logs is not None:
        prefs.auto_share_logs = payload.auto_share_logs
    if payload.share_ratings is not None:
        prefs.share_ratings = payload.share_ratings
    if payload.share_notes is not None:
        prefs.share_notes = payload.share_notes
    db.commit()
    db.refresh(prefs)
    return PartnerPrefsOut(
        auto_share_logs=prefs.auto_share_logs,
        share_ratings=prefs.share_ratings,
        share_notes=prefs.share_notes,
    )


# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------


def _person_out(
    entry: models.DiaryEntry,
    user: models.User,
    prefs: models.PartnerPrefs | None,
    viewer_id: str,
    *,
    viewer_has_own_entry: bool,
    unlocked_entry_ids: set,
) -> SharedDiaryPersonOut:
    """One member's side of a card. Their own prefs are applied here, as
    their row is serialized — never at query time, so the same row can be
    rendered differently for its owner (who always sees everything of
    their own) and for everyone else.

    `viewer_has_own_entry`/`unlocked_entry_ids` are what decide
    `rating_hidden` for someone else's row: the rating starts veiled the
    moment the viewer hasn't logged their own take on this title yet
    (see app/sincerity.py's spoiler_unlock/formed_own_opinion pair), and
    stays veiled only until either they rate it themselves or they pay
    to reveal this exact entry (routers/shared_diary.py::reveal_rating).
    Never applied to the viewer's own row (`is_me`) or on top of an
    already-privacy-hidden one — this is a *when*, not an *whether*,
    veil, and stacking it onto a rating the person chose to keep private
    would just be confusing.
    """
    is_me = user.id == viewer_id
    show_rating = is_me or prefs is None or prefs.share_ratings
    show_note = is_me or (prefs is not None and prefs.share_notes)
    rating_hidden = (
        show_rating
        and not is_me
        and entry.rating is not None
        and not viewer_has_own_entry
        and entry.id not in unlocked_entry_ids
    )
    return SharedDiaryPersonOut(
        user_id=user.id,
        username=user.username,
        display_name=user.display_name,
        avatar_preset=user.avatar_preset,
        avatar_url=user.avatar_url,
        rating=entry.rating if (show_rating and not rating_hidden) else None,
        rating_hidden=rating_hidden,
        note=entry.note if show_note else None,
        watched_at=entry.watched_at.isoformat() if entry.watched_at else "",
        entry_id=entry.id,
        is_me=is_me,
    )


def _group(
    db: Session,
    rows: List[models.DiaryEntry],
    users: Dict[str, models.User],
    prefs: Dict[str, models.PartnerPrefs],
    viewer_id: str,
) -> List[SharedDiaryItemOut]:
    """Collapse per-person rows into one card per title.

    Grouped strictly by (source, media_id) and NOT by date: two people
    watching the same film together rarely log it at the exact same
    timestamp (one logs it that night, the other the next morning), and
    grouping by day would split the card in half at midnight for no
    reason a person would recognize. The consequence — a rewatch months
    later merging into the same card as the original — is handled by
    taking the newest watched_at as the card's date and letting each
    person's own row keep its real one, which is visible on the card.
    """
    buckets: Dict[tuple, List[models.DiaryEntry]] = defaultdict(list)
    for r in rows:
        buckets[(r.source, r.media_id)].append(r)

    # One batched lookup for the whole page rather than one per row —
    # see app/sincerity.py::has_unlocked_reveal for the single-entry
    # version this mirrors.
    entry_ids = [r.id for r in rows]
    unlocked_entry_ids = (
        {
            row.related_entry_id
            for row in db.query(models.SincerityTransaction.related_entry_id)
            .filter(
                models.SincerityTransaction.user_id == viewer_id,
                models.SincerityTransaction.reason == models.SincerityReason.spoiler_unlock,
                models.SincerityTransaction.related_entry_id.in_(entry_ids),
            )
            .all()
        }
        if entry_ids
        else set()
    )

    items: List[SharedDiaryItemOut] = []
    for (source, media_id), group in buckets.items():
        group.sort(key=lambda r: r.watched_at or _EPOCH, reverse=True)
        newest = group[0]
        viewer_has_own_entry = any(r.user_id == viewer_id for r in group)
        people = [
            _person_out(
                r, users[r.user_id], prefs.get(r.user_id), viewer_id,
                viewer_has_own_entry=viewer_has_own_entry,
                unlocked_entry_ids=unlocked_entry_ids,
            )
            for r in group
            if r.user_id in users
        ]
        ratings = [p.rating for p in people if p.rating is not None]
        items.append(SharedDiaryItemOut(
            media_id=media_id,
            source=source,
            media_type=newest.media_type.value if newest.media_type else "movie",
            title_ru=newest.title_ru,
            title_en=newest.title_en,
            poster_url=newest.poster_url,
            backdrop_url=newest.backdrop_url,
            year=newest.year,
            genres=newest.genres or [],
            runtime_minutes=newest.runtime_minutes,
            watched_at=newest.watched_at.isoformat() if newest.watched_at else "",
            watched_together=any(bool(r.watched_together) for r in group),
            people=people,
            # Only meaningful with at least two visible ratings — one
            # person's score disagrees with nothing.
            rating_gap=(max(ratings) - min(ratings)) if len(ratings) >= 2 else None,
        ))

    items.sort(key=lambda i: i.watched_at, reverse=True)
    return items


def _shared_rows(
    db: Session,
    link: models.PartnerLink,
    *,
    before: Optional[datetime] = None,
    since: Optional[datetime] = None,
    limit: Optional[int] = None,
) -> List[models.DiaryEntry]:
    q = (
        db.query(models.DiaryEntry)
        .filter(models.DiaryEntry.shared_link_id == link.id)
        .filter(models.DiaryEntry.user_id.in_(_member_ids(link)))
    )
    if before is not None:
        q = q.filter(models.DiaryEntry.watched_at < before)
    if since is not None:
        q = q.filter(models.DiaryEntry.watched_at >= since)
    q = q.order_by(models.DiaryEntry.watched_at.desc())
    if limit is not None:
        q = q.limit(limit)
    return q.all()


def _users_and_prefs(db: Session, link: models.PartnerLink):
    member_ids = _member_ids(link)
    users = {
        u.id: u
        for u in db.query(models.User).filter(models.User.id.in_(member_ids)).all()
    }
    prefs = {
        p.user_id: p
        for p in db.query(models.PartnerPrefs).filter_by(link_id=link.id).all()
    }
    return users, prefs


def _require_link(db: Session, user_id: str) -> models.PartnerLink:
    link = get_active_link(db, user_id)
    if link is None:
        raise HTTPException(status_code=409, detail="Link with a partner first")
    return link


# ---------------------------------------------------------------------------
# Diary
# ---------------------------------------------------------------------------


@router.get("/diary", response_model=SharedDiaryOut)
def shared_diary(
    before: Optional[str] = Query(
        default=None, description="ISO watched_at to page before, for older evenings"
    ),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """One page of the circle's shared evenings, newest first.

    Cursor-paginated on watched_at rather than offset-paginated: this list
    grows from the top as people log things, and an offset cursor would
    silently repeat or skip a card every time it did. Follows the shape
    routers/sincerity.py already uses.

    Over-fetches deliberately — `_PAGE_SIZE * 3 + 1` raw rows for up to
    _PAGE_SIZE grouped cards, since a card can absorb one row per member.
    The +1 is what tells us whether there's an older page at all without
    a second COUNT query.
    """
    link = _require_link(db, current_user.id)
    cursor = None
    if before:
        try:
            cursor = datetime.fromisoformat(before)
        except ValueError:
            cursor = None

    member_count = max(1, len(_member_ids(link)))
    rows = _shared_rows(db, link, before=cursor, limit=_PAGE_SIZE * member_count + 1)
    users, prefs = _users_and_prefs(db, link)
    items = _group(db, rows, users, prefs, current_user.id)

    next_before = None
    if len(items) > _PAGE_SIZE:
        items = items[:_PAGE_SIZE]
        next_before = items[-1].watched_at

    return SharedDiaryOut(
        items=items,
        next_before=next_before,
        member_usernames=[u.username for u in _other_members(link, current_user.id)],
    )


@router.post("/diary/{entry_id}/share", response_model=SharedDiaryOut)
def set_entry_shared(
    entry_id: str,
    payload: ShareDiaryEntryIn,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Per-entry override of the auto-share setting — "добавить этот вечер
    в наш дневник" from your own diary card, or "убрать из общего" from
    the shared one.

    Only ever touches your own rows: `user_id` is part of the lookup, so
    there's no way to unshare a partner's evening even by guessing an id.

    Unsharing an evening that was watched *together* is refused. The
    other person was there; removing it from the shared diary doesn't make
    it private, it just makes the shared diary wrong. Deleting the entry
    outright (from your own diary) is still available and does what it
    says.
    """
    link = _require_link(db, current_user.id)
    entry = (
        db.query(models.DiaryEntry)
        .filter_by(id=entry_id, user_id=current_user.id)
        .first()
    )
    if entry is None:
        raise HTTPException(status_code=404, detail="Not found")
    if not payload.shared and entry.watched_together:
        raise HTTPException(
            status_code=400,
            detail="This evening was watched together — delete it instead of hiding it",
        )
    entry.shared_link_id = link.id if payload.shared else None
    db.commit()
    return shared_diary(before=None, current_user=current_user, db=db)


@router.post("/diary/{entry_id}/reveal-rating", response_model=SharedDiaryOut)
def reveal_rating(
    entry_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Pay sincerity.SPOILER_UNLOCK_COST to see one circle-mate's rating
    on `entry_id` before rating that title yourself — the other half of
    the veil in `_person_out`'s `rating_hidden`. Peeking here is what
    withholds app/sincerity.py::earn_formed_own_opinion when you later
    log your own rating for the same title (see that function's own
    docstring) — the trade is real in both directions, not just a
    cosmetic unlock.

    404s rather than 400s on "nothing to reveal" (already unlocked, no
    rating there, or not actually a circle-mate's entry) — the client
    only ever shows this button when `rating_hidden` was true for this
    exact entry_id, so reaching here in any of those states means the
    button was stale, not that the person did something wrong.
    """
    link = _require_link(db, current_user.id)
    entry = (
        db.query(models.DiaryEntry)
        .filter(
            models.DiaryEntry.id == entry_id,
            models.DiaryEntry.shared_link_id == link.id,
            models.DiaryEntry.user_id != current_user.id,
            models.DiaryEntry.rating.isnot(None),
        )
        .first()
    )
    if entry is None:
        raise HTTPException(status_code=404, detail="Nothing to reveal here")
    if sincerity.has_unlocked_reveal(db, current_user.id, entry_id):
        return shared_diary(before=None, current_user=current_user, db=db)
    if current_user.sincerity_balance < sincerity.SPOILER_UNLOCK_COST:
        raise HTTPException(status_code=400, detail="Not enough sincerity points")

    title = entry.title_en or entry.title_ru or "—"
    sincerity.spend_spoiler_unlock(db, current_user, title=title, entry_id=entry_id)
    db.commit()
    return shared_diary(before=None, current_user=current_user, db=db)


# ---------------------------------------------------------------------------
# Planned
# ---------------------------------------------------------------------------


@router.get("/planned", response_model=SharedPlannedOut)
def shared_planned(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The co-viewing queue, with the free-tier ceiling reported alongside
    it. The client shows "3 из 5" from these numbers rather than knowing
    the limit itself — see routers/partner.py::CO_VIEW_FREE_LIMIT for why
    the server owns that number."""
    from app.routers.partner import CO_VIEW_FREE_LIMIT

    link = _require_link(db, current_user.id)
    planned = (
        db.query(models.CoViewEntry)
        .filter_by(link_id=link.id, status=models.CoViewStatus.planned)
        .order_by(models.CoViewEntry.created_at.desc())
        .all()
    )
    premium = is_premium_account(db, current_user.id)
    return SharedPlannedOut(
        planned=[_coview_out(e) for e in planned],
        limit=None if premium else CO_VIEW_FREE_LIMIT,
        used=len(planned),
        is_premium=premium,
    )


@router.post("/planned/{entry_id}/nudge", response_model=SharedPlannedOut)
def nudge(
    entry_id: str,
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Pay sincerity.NUDGE_COST to send every other circle-mate one push
    notification about a co-viewing plan that's gone stale — see
    sincerity.spend_nudge and push.py::notify_nudge. Deliberately the
    lightest spend in the whole economy: it doesn't touch the plan
    itself or unlock anything, just pokes the people who haven't gotten
    to it yet. Returns the same shape as GET /planned since nothing
    about the queue actually changes — only the balance did.
    """
    link = _require_link(db, current_user.id)
    entry = (
        db.query(models.CoViewEntry)
        .filter(
            models.CoViewEntry.id == entry_id,
            models.CoViewEntry.link_id == link.id,
            models.CoViewEntry.status == models.CoViewStatus.planned,
        )
        .first()
    )
    if entry is None:
        raise HTTPException(status_code=404, detail="Not in your shared plans")
    if datetime.now(timezone.utc) - entry.created_at < sincerity.NUDGE_STALE_THRESHOLD:
        raise HTTPException(status_code=400, detail="Too soon to nudge about this one")
    if sincerity.has_nudged_recently(db, current_user.id, entry.id):
        raise HTTPException(status_code=400, detail="Already nudged recently")
    if current_user.sincerity_balance < sincerity.NUDGE_COST:
        raise HTTPException(status_code=400, detail="Not enough sincerity points")

    title = entry.title_ru or entry.title_en or "—"
    sincerity.spend_nudge(db, current_user, title=title, entry_id=entry.id)
    db.commit()

    actor_name = current_user.display_name or current_user.username
    for other in _other_members(link, current_user.id):
        background_tasks.add_task(push.notify_nudge, other.id, actor_name, title)

    return shared_planned(current_user=current_user, db=db)


# ---------------------------------------------------------------------------
# Stats — "наш год"
# ---------------------------------------------------------------------------


@router.get("/stats", response_model=SharedStatsOut)
def shared_stats(
    period: str = Query(default="year", pattern="^(year|all)$"),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The couple's own Wrapped, on the same screen as their diary.

    Computed from exactly the rows /diary would return — never a separate
    aggregate — so every number here describes evenings the person can
    scroll to and check. That property is worth more than the small
    efficiency of a SQL-side aggregation: a stat you can't trace back to a
    card is a stat people quietly stop believing.
    """
    link = _require_link(db, current_user.id)
    since = None
    if period == "year":
        now = datetime.now(timezone.utc)
        since = datetime(now.year, 1, 1, tzinfo=timezone.utc)
        label = str(now.year)
    else:
        label = "за всё время"

    rows = _shared_rows(db, link, since=since)
    users, prefs = _users_and_prefs(db, link)
    items = _group(db, rows, users, prefs, current_user.id)

    together = [i for i in items if i.watched_together]

    hours = 0.0
    for i in together:
        if i.runtime_minutes:
            hours += i.runtime_minutes / 60.0
        else:
            try:
                hours += _DEFAULT_HOURS[models.MediaType(i.media_type)]
            except (ValueError, KeyError):
                hours += 1.9

    genre_counts: Dict[str, int] = defaultdict(int)
    for i in items:
        for g in i.genres:
            key = g.strip()
            if key:
                genre_counts[key] += 1
    top_genres = [g for g, _ in sorted(genre_counts.items(), key=lambda kv: -kv[1])[:5]]

    # Per-member averages, only across ratings actually visible on the
    # cards — so this number never implies knowledge of a score the person
    # chose not to share.
    sums: Dict[str, List[int]] = defaultdict(list)
    for i in items:
        for p in i.people:
            if p.rating is not None:
                sums[p.username].append(p.rating)
    averages = {u: round(sum(v) / len(v), 1) for u, v in sums.items() if v}

    rated_both = [i for i in items if i.rating_gap is not None]
    biggest = max(rated_both, key=lambda i: i.rating_gap) if rated_both else None
    if biggest is not None and (biggest.rating_gap or 0) < 2:
        # A one-point difference isn't a disagreement, it's rounding.
        biggest = None

    def _min_rating(item: SharedDiaryItemOut) -> int:
        vals = [p.rating for p in item.people if p.rating is not None]
        return min(vals) if vals else 0

    both_loved = [i for i in rated_both if _min_rating(i) >= 8]
    best = max(both_loved, key=_min_rating) if both_loved else None

    # Longest run of consecutive calendar days with at least one shared
    # evening on it.
    days = sorted({i.watched_at[:10] for i in items if i.watched_at})
    longest = 0
    if days:
        parsed = [datetime.fromisoformat(d).date() for d in days]
        run = longest = 1
        for prev, nxt in zip(parsed, parsed[1:]):
            if (nxt - prev) == timedelta(days=1):
                run += 1
                longest = max(longest, run)
            else:
                run = 1

    planned_count = (
        db.query(models.CoViewEntry)
        .filter_by(link_id=link.id, status=models.CoViewStatus.planned)
        .count()
    )

    # "кто чаще предлагает" — deliberately NOT built from `items` above:
    # those are the shared *diary* (evenings watched together), this is
    # the co-viewing *inbox* (everything ever added to it, planned or
    # already watched). The question is who reaches for the app to
    # suggest something, not who watched more, so it's keyed on
    # created_at (when it was added) rather than watched_at — a
    # still-planned entry has no watched_at to filter on yet.
    added_by_q = db.query(models.CoViewEntry).filter(models.CoViewEntry.link_id == link.id)
    if since is not None:
        added_by_q = added_by_q.filter(models.CoViewEntry.created_at >= since)
    added_by_counts: Dict[str, int] = defaultdict(int)
    for entry in added_by_q.all():
        if entry.added_by_id and entry.added_by_id in users:
            added_by_counts[users[entry.added_by_id].username] += 1

    return SharedStatsOut(
        period=period,
        period_label=label,
        evenings_together=len(together),
        evenings_shared_total=len(items),
        hours_together=round(hours, 1),
        top_genres=top_genres,
        average_ratings=averages,
        biggest_disagreement=biggest,
        best_shared_pick=best,
        longest_streak_days=longest,
        first_evening_at=items[-1].watched_at if items else None,
        planned_count=planned_count,
        added_by_counts=dict(added_by_counts),
    )


# ---------------------------------------------------------------------------
# Couple achievements — "наши вехи"
#
# Same spirit as compute_achievements_for_user in routers/profile.py:
# everything below is computed fresh from the circle's own rows every time
# this is called, nothing stored or separately tracked that could drift out
# of sync with what's actually been logged together, and nothing unlocks
# from anything other than the circle's own honest history. Deliberately
# reuses AchievementOut/AchievementsOut wholesale rather than a parallel
# couple-specific shape, so the client's existing badge widget and
# unlock-celebration overlay (widgets/achievement_badge.dart,
# widgets/achievement_unlock_overlay.dart) work on this completely
# unmodified — a couple achievement IS an achievement, just scored off the
# link instead of one person's own rows.
# ---------------------------------------------------------------------------

# Evening-count milestones — same shape as profile.py's _MOVIE_MILESTONES,
# scaled down: a couple logs far fewer *shared* evenings than one person
# logs solo entries, so 100 is already the "genuinely dedicated" top tier
# here rather than 250.
_COUPLE_EVENING_MILESTONES = [
    (1, "the first one", "logged your first evening together"),
    (10, "into a habit", "10 evenings together"),
    (25, "quarter century", "25 evenings together"),
    (50, "half a hundred", "50 evenings together"),
    (100, "a hundred nights", "100 evenings together"),
]

_COUPLE_GENRE_TARGET = 5  # distinct genres watched *together* — breadth, not depth

# Consecutive-day streaks on shared evenings specifically — deliberately
# much lower targets than profile.py's own _STREAK_MILESTONES (7/30/100/365),
# since those are about logging *anything* daily and this is about both
# people clearing an evening together on consecutive nights, a much
# higher bar per day.
_COUPLE_STREAK_MILESTONES = [
    (3, "three in a row", "a 3-day streak together"),
    (7, "a week straight", "a 7-day streak together"),
]

# Days since the circle itself was linked (PartnerLink.created_at) — the
# couple's own answer to profile.py's _MEMBER_DAYS_TARGET, broken into
# three tiers instead of one so there's something to reach well before
# the one-year mark.
_COUPLE_DAYS_MILESTONES = [
    (30, "one month in", "30 days linked"),
    (100, "a hundred days linked", "100 days linked"),
    (365, "a full year", "a full year linked"),
]


def compute_couple_achievements_for_link(db: Session, link: models.PartnerLink) -> List[AchievementOut]:
    """The circle's own badge shelf, parallel to compute_achievements_for_user
    but scored off the link rather than one account. Always all-time (unlike
    /stats, which can be year-scoped) — a badge that could un-unlock itself
    on January 1st would be a strange kind of achievement."""
    users, prefs = _users_and_prefs(db, link)
    rows = _shared_rows(db, link)
    # viewer_id only gates which ratings/notes are visible on each card —
    # irrelevant to the counts below, which never look at rating or note.
    items = _group(db, rows, users, prefs, link.owner_id)
    together = [i for i in items if i.watched_together]

    evening_count = len(together)

    distinct_genres = {g.strip().lower() for i in together for g in i.genres if g.strip()}

    days = sorted({i.watched_at[:10] for i in together if i.watched_at})
    longest_streak = 0
    if days:
        parsed = [datetime.fromisoformat(d).date() for d in days]
        run = longest_streak = 1
        for prev, nxt in zip(parsed, parsed[1:]):
            if (nxt - prev) == timedelta(days=1):
                run += 1
                longest_streak = max(longest_streak, run)
            else:
                run = 1

    days_linked = (
        (datetime.now(timezone.utc) - link.created_at).days if link.created_at else 0
    )

    achievements: List[AchievementOut] = []

    for target, title, caption in _COUPLE_EVENING_MILESTONES:
        achievements.append(AchievementOut(
            id=f"couple:evenings:{target}",
            category="milestone",
            icon_key="milestone",
            title=title,
            caption=caption,
            unlocked=evening_count >= target,
            progress_current=min(evening_count, target),
            progress_target=target,
            rarity=_rarity_for_target(target),
        ))

    achievements.append(AchievementOut(
        id="couple:genre_explorer",
        category="genre",
        icon_key="explorer",
        title="well-rounded",
        caption=f"watched together across {_COUPLE_GENRE_TARGET}+ different genres",
        unlocked=len(distinct_genres) >= _COUPLE_GENRE_TARGET,
        progress_current=min(len(distinct_genres), _COUPLE_GENRE_TARGET),
        progress_target=_COUPLE_GENRE_TARGET,
        rarity=_rarity_for_target(_COUPLE_GENRE_TARGET),
    ))

    for target, title, caption in _COUPLE_STREAK_MILESTONES:
        achievements.append(AchievementOut(
            id=f"couple:streak:{target}",
            category="devotion",
            icon_key="streak",
            title=title,
            caption=caption,
            unlocked=longest_streak >= target,
            progress_current=min(longest_streak, target),
            progress_target=target,
            rarity=_rarity_for_target(target),
        ))

    for target, title, caption in _COUPLE_DAYS_MILESTONES:
        achievements.append(AchievementOut(
            id=f"couple:days:{target}",
            category="devotion",
            icon_key="loyalty",
            title=title,
            caption=caption,
            unlocked=days_linked >= target,
            progress_current=min(days_linked, target),
            progress_target=target,
            rarity=_rarity_for_target(target),
        ))

    return achievements


@router.get("/achievements", response_model=AchievementsOut)
def shared_achievements(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """GET /partner/shared/achievements — the "мы" tab's badge shelf.
    Mirrors GET /profile/achievements' own shape exactly (see
    compute_couple_achievements_for_link's docstring for why), so the
    client can drive both with the same Achievement model and the same
    unlock-celebration flow."""
    link = _require_link(db, current_user.id)
    achievements = compute_couple_achievements_for_link(db, link)
    unlocked_count = sum(1 for a in achievements if a.unlocked)
    return AchievementsOut(
        unlocked_count=unlocked_count,
        total_count=len(achievements),
        achievements=achievements,
    )


# ---------------------------------------------------------------------------
# Wrapped for two — "наш враппед"
#
# The couple's own answer to GET /profile/wrapped/summary. Deliberately its
# own function rather than a refactor of get_wrapped_summary in profile.py:
# that endpoint is live and load-bearing, and the couple data source differs
# enough (typically two DiaryEntry rows per evening, one per person, not
# one) that threading couple-only branches through it would risk the
# personal path for everyone to serve a feature only linked accounts see.
# Reuses that endpoint's exact WrappedSummary schema and
# _resolve_wrapped_range helper instead, so the client's existing wrapped
# screen (see wrapped_screen.dart / custom_wrapped_service.dart) renders
# this completely unmodified.
# ---------------------------------------------------------------------------


def compute_couple_wrapped_periods(db: Session, link: models.PartnerLink) -> WrappedPeriodsOut:
    """Powers the couple wrapped's own period picker — every (year) and
    (year, month) this circle actually has a *together* evening logged in,
    same reasoning as get_wrapped_periods."""
    rows = (
        db.query(
            func.extract("year", models.DiaryEntry.watched_at),
            func.extract("month", models.DiaryEntry.watched_at),
        )
        .filter(
            models.DiaryEntry.shared_link_id == link.id,
            models.DiaryEntry.user_id.in_(_member_ids(link)),
            models.DiaryEntry.watched_together == 1,
            models.DiaryEntry.watched_at.isnot(None),
        )
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


def compute_couple_wrapped_summary(
    db: Session,
    link: models.PartnerLink,
    scope: str,
    year: Optional[int],
    month: Optional[int],
) -> WrappedSummary:
    """The couple's own wrapped, same shape as get_wrapped_summary's
    WrappedSummary. Scoped to evenings marked watched_together
    specifically — not every row with this link's shared_link_id, since
    an auto-shared solo evening is still one person's own evening, not
    "ours".

    Two DiaryEntry rows typically exist per shared evening, one per
    person, and are handled two different ways below:
      - "how many evenings, what genres, when" facts are deduplicated to
        one row per (source, media_id) — the same grouping _group() uses
        for the shared diary itself — keeping whichever row was logged
        most recently as that evening's representative, so a shared
        evening isn't counted twice just because both of you logged it.
      - rating/review facts (average rating, histogram, top reviews)
        deliberately stay UNdeduplicated: two people's ratings of the
        same evening are two real opinions, not one fact logged twice,
        and folding them into a single number would lose exactly the
        "did you agree" texture a couple's own wrapped should have. One
        side effect worth knowing: if you both rated and reviewed the
        same evening, its title can appear twice in top_reviews/
        favorite_review — once per person's note — since
        WrappedReviewItem carries no reviewer identity to tell those
        apart by. Left as is rather than widening that schema for
        personal wrapped's sake too.

    Fields with no honest couple-shaped answer are left at a fixed,
    truthful value rather than stretched to fit: solo_count/
    company_count/solo_percent are always 0/N/0% (this data is
    watched_together by definition, so there's no "solo" split left to
    report), and hours_percentile is always None — "vs everyone else"
    has no equivalent population of couples to compare against.
    """
    if scope not in ("month", "year", "all"):
        raise HTTPException(status_code=400, detail="scope must be month, year, or all")
    if scope == "month" and month is not None and not (1 <= month <= 12):
        raise HTTPException(status_code=400, detail="month must be 1-12")

    now = datetime.now(timezone.utc)
    start, end, anchor_year, anchor_month, period_label, fixed_range_label = _resolve_wrapped_range(
        scope, year, month, now
    )

    q = (
        db.query(models.DiaryEntry)
        .filter(models.DiaryEntry.shared_link_id == link.id)
        .filter(models.DiaryEntry.user_id.in_(_member_ids(link)))
    )
    if start is not None:
        q = q.filter(models.DiaryEntry.watched_at >= start)
    if end is not None:
        q = q.filter(models.DiaryEntry.watched_at <= end)
    all_rows = [r for r in q.order_by(models.DiaryEntry.watched_at.asc()).all() if r.watched_together]

    if not all_rows:
        return WrappedSummary(
            scope=scope, year=anchor_year, month=anchor_month,
            period_label=period_label, range_label=fixed_range_label or "—",
            total_logged=0, total_hours=0.0, unlocked=True,
        )

    # One representative row per shared evening — see docstring above.
    buckets: Dict[tuple, List[models.DiaryEntry]] = defaultdict(list)
    for r in all_rows:
        buckets[(r.source, r.media_id)].append(r)
    entries: List[models.DiaryEntry] = []
    for group in buckets.values():
        group.sort(key=lambda r: r.watched_at or _EPOCH, reverse=True)
        entries.append(group[0])
    entries.sort(key=lambda e: e.watched_at or _EPOCH)

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
    top_directors = [WrappedDirectorCount(name=n, count=c) for n, c in director_counter.most_common(4)]

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

    # Always fully "in company" by construction — see docstring.
    solo_count = 0
    company_count = len(entries)
    solo_percent = 0.0

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
        # collapses into "остальное", same as get_wrapped_summary.
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

    # Deliberately from all_rows (both people's own rows), not the
    # deduplicated `entries` above — see docstring.
    rated = [e for e in all_rows if e.rating]
    review_count = sum(1 for e in all_rows if e.note and e.note.strip())
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

    # solo_percent is always 0 here, so this always resolves to the
    # ", в компании" branch — which is exactly right for a couple.
    archetype_label = _archetype_label(peak_hour, solo_percent, top_genre)

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
        hours_percentile=None,
        receipt_items=receipt_items,
        poster_urls=poster_urls,
        is_premium=True,
        unlocked=True,
    )


@router.get("/wrapped/periods", response_model=WrappedPeriodsOut)
def shared_wrapped_periods(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    link = _require_link(db, current_user.id)
    return compute_couple_wrapped_periods(db, link)


@router.get("/wrapped/summary", response_model=WrappedSummary)
def shared_wrapped_summary(
    scope: str = "year",           # "month" | "year" | "all"
    year: Optional[int] = None,
    month: Optional[int] = None,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    link = _require_link(db, current_user.id)
    return compute_couple_wrapped_summary(db, link, scope, year, month)
