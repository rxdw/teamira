"""Circle reviews ("Рецензия круга") — the HTTP shape; the rules and the
reasoning are in app/circle_review.py.

A review is opened automatically (see `open_review`, called when a co-view
room is saved and when an evening is logged "watched with"), each person
writes their own part, and the parts stay sealed until everyone has written
or skipped — or a week has passed. Reading is free for everyone, always.
Only the moments timeline depends on premium, and only at the moment the
review opens; see `_ensure_moments`.

The one premium *product* built on top is the PDF "book of your evenings":
the device assembles the document, this module hands it everything in a
single, premium-gated response (`GET /book`, see `book`).
"""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import List as TypingList, Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session, selectinload

from app import circle_review as rules
from app import content_filter, models, push
from app.database import get_db
from app.deps import get_current_user
from app.routers.partner import _circle_has_premium, _member_ids, get_active_link
from app.schemas import ImageFieldsModel

router = APIRouter(prefix="/partner/reviews", tags=["circle-reviews"])


# --- shapes -------------------------------------------------------------------

class ReviewEntryIn(BaseModel):
    rating: Optional[int] = Field(default=None, ge=1, le=10)
    tags: Optional[TypingList[str]] = None
    line: Optional[str] = Field(default=None, max_length=rules.LINE_MAX_CHARS * 2)


class ReviewPersonOut(BaseModel):
    user_id: str
    username: str
    display_name: Optional[str] = None
    avatar_preset: Optional[str] = None
    avatar_url: Optional[str] = None
    is_you: bool
    done: bool                      # wrote or skipped
    skipped: bool = False
    # Filled only for you, or for everyone once the review is revealed.
    rating: Optional[int] = None
    tags: TypingList[str] = Field(default_factory=list)
    line: Optional[str] = None


class SummaryOut(BaseModel):
    average: Optional[float] = None
    spread: Optional[int] = None
    verdict: str
    rated_count: int
    shared_tags: TypingList[str] = Field(default_factory=list)


class MomentOut(BaseModel):
    position_ms: int
    people: int
    shared: bool
    count: int
    top: str
    # Reading rooms: the place of the moment ("c3:p12", "p42"), so the timeline
    # of a book can say which chapter or page it was.
    locator: Optional[str] = None


class ReviewOut(ImageFieldsModel):
    id: str
    origin: str
    room_id: Optional[str] = None
    media_id: str
    media_type: str
    source: str
    title_ru: Optional[str] = None
    title_en: Optional[str] = None
    poster_url: Optional[str] = None
    year: Optional[int] = None
    watched_on: date
    status: str                      # "open" | "revealed"
    revealed: bool
    expires_at: datetime
    i_am_done: bool
    people: TypingList[ReviewPersonOut]
    summary: Optional[SummaryOut] = None
    moments: Optional[TypingList[MomentOut]] = None
    # Room-origin, revealed, nothing stored yet and this circle isn't premium:
    # the client shows the soft "unlock the timeline" card, never the data.
    moments_locked: bool = False
    created_at: datetime

    class Config:
        from_attributes = True


class BookPersonOut(BaseModel):
    user_id: str
    username: str
    display_name: Optional[str] = None
    avatar_preset: Optional[str] = None
    avatar_url: Optional[str] = None
    is_you: bool


class BookOut(BaseModel):
    """What the PDF "book of your evenings" is made of. `reviews` are opened
    ones only, oldest evening first, each with its moments already computed
    (the circle is premium by the time anyone gets here). `truncated` says the
    circle has more evenings than the book holds and the oldest were left out."""
    people: TypingList[BookPersonOut]
    reviews: TypingList[ReviewOut]
    truncated: bool = False


# --- opening (used by other routers) --------------------------------------------

def open_review(
    db: Session,
    link: models.PartnerLink,
    *,
    origin: str,
    created_by_id: str | None,
    media_id: str,
    media_type: models.MediaType,
    source: str,
    title_ru: str | None,
    title_en: str | None,
    poster_url: str | None,
    year: int | None,
    participant_ids: list[str],
    watched_at: datetime | None = None,
    room_id: str | None = None,
) -> models.CircleReview:
    """Opens the review for this evening, or returns the one already open for
    the same title (a second person logging the same evening, or a room
    finishing after someone already logged). Doesn't commit.

    The expected list only ever grows here — somebody who turns up in the
    same evening is added; nobody is taken out."""
    now = rules.utcnow()
    existing = (
        db.query(models.CircleReview)
        .filter(
            models.CircleReview.link_id == link.id,
            models.CircleReview.source == source,
            models.CircleReview.media_id == media_id,
            models.CircleReview.status == "open",
            models.CircleReview.created_at > now - rules.REUSE_WINDOW,
        )
        .order_by(models.CircleReview.created_at.desc())
        .with_for_update()
        .first()
    )
    if existing is not None:
        merged = list(existing.participant_ids or [])
        for uid in participant_ids:
            if uid not in merged:
                merged.append(uid)
        existing.participant_ids = merged
        if room_id and not existing.room_id:
            existing.room_id = room_id
            existing.origin = "room"
        return existing
    review = models.CircleReview(
        link_id=link.id, created_by_id=created_by_id, origin=origin, room_id=room_id,
        media_id=media_id, media_type=media_type, source=source,
        title_ru=title_ru, title_en=title_en, poster_url=poster_url, year=year,
        watched_on=rules.evening_of(watched_at), participant_ids=list(participant_ids),
        status="open", expires_at=rules.default_expiry(now),
    )
    db.add(review)
    db.flush()
    return review


# --- helpers ------------------------------------------------------------------

def _require_link(db: Session, user: models.User) -> models.PartnerLink:
    link = get_active_link(db, user.id)
    if link is None:
        raise HTTPException(status_code=409, detail="Link with a partner first")
    return link


def _people(link: models.PartnerLink) -> dict[str, models.User]:
    return {p.id: p for p in (link.owner, link.partner, *[m.user for m in link.extra_members]) if p is not None}


def _load(db: Session, user: models.User, review_id: str, *, lock: bool = False) -> tuple[models.PartnerLink, models.CircleReview]:
    link = _require_link(db, user)
    q = db.query(models.CircleReview).filter_by(id=review_id, link_id=link.id)
    if lock:
        q = q.with_for_update()
    review = q.first()
    if review is None:
        raise HTTPException(status_code=404, detail="Рецензия не найдена")
    return link, review


def _done_ids(review: models.CircleReview) -> set[str]:
    return {e.user_id for e in review.entries}


def _moments_events(db: Session, room_id: str) -> list[dict]:
    rows = (
        db.query(models.CoViewRoomEvent)
        .filter(
            models.CoViewRoomEvent.room_id == room_id,
            models.CoViewRoomEvent.kind.in_(["reaction", "emotion", "margin", "highlight", "round"]),
        )
        .all()
    )
    return [
        {"user_id": r.user_id, "kind": r.kind, "emoji": r.emoji, "position_ms": r.position_ms, "locator": r.locator}
        for r in rows
    ]


def _ensure_moments(db: Session, link: models.PartnerLink, review: models.CircleReview) -> None:
    """Computes and stores the timeline when it can be: room-origin,
    revealed, not stored yet, circle premium *now*. Stored once, it is
    readable forever whatever happens to the subscription."""
    if review.status != "revealed" or review.moments is not None or not review.room_id:
        return
    if not _circle_has_premium(db, link):
        return
    review.moments = rules.build_moments(_moments_events(db, review.room_id))


def _maybe_reveal(db: Session, link: models.PartnerLink, review: models.CircleReview) -> bool:
    """Opens the review if everyone's in or the week is up. Returns whether
    it just opened (so the caller can tell people). Doesn't commit."""
    if review.status != "open":
        return False
    if not rules.should_reveal(list(review.participant_ids or []), _done_ids(review), review.expires_at):
        return False
    review.status = "revealed"
    review.revealed_at = rules.utcnow()
    _ensure_moments(db, link, review)
    return True


def _entry_dicts(review: models.CircleReview) -> list[dict]:
    return [
        {
            "user_id": e.user_id, "rating": e.rating, "tags": list(e.tags or []),
            "line": e.line, "skipped": bool(e.skipped),
        }
        for e in review.entries
    ]


def _review_out(db: Session, link: models.PartnerLink, review: models.CircleReview, me_id: str) -> ReviewOut:
    people = _people(link)
    by_user = {e.user_id: e for e in review.entries}
    revealed = review.status == "revealed"
    out_people: list[ReviewPersonOut] = []
    for uid in review.participant_ids or []:
        u = people.get(uid)
        if u is None:
            continue
        e = by_user.get(uid)
        show = e is not None and (revealed or uid == me_id)
        out_people.append(ReviewPersonOut(
            user_id=uid, username=u.username, display_name=u.display_name,
            avatar_preset=u.avatar_preset, avatar_url=u.avatar_url,
            is_you=uid == me_id, done=e is not None, skipped=bool(e and e.skipped),
            rating=e.rating if show else None,
            tags=list(e.tags or []) if show else [],
            line=e.line if show else None,
        ))
    summary = SummaryOut(**rules.summarize(_entry_dicts(review))) if revealed else None
    moments = None
    locked = False
    if revealed and review.room_id:
        if review.moments is not None:
            moments = [
                MomentOut(**{k: m[k] for k in ("position_ms", "people", "shared", "count", "top")}, locator=m.get("locator"))
                for m in review.moments
            ]
        else:
            locked = not _circle_has_premium(db, link)
    return ReviewOut(
        id=review.id, origin=review.origin, room_id=review.room_id,
        media_id=review.media_id, media_type=review.media_type.value, source=review.source,
        title_ru=review.title_ru, title_en=review.title_en, poster_url=review.poster_url, year=review.year,
        watched_on=review.watched_on, status=review.status, revealed=revealed, expires_at=review.expires_at,
        i_am_done=me_id in by_user, people=out_people, summary=summary,
        moments=moments, moments_locked=locked, created_at=review.created_at,
    )


def _notify_revealed(background_tasks: BackgroundTasks, review: models.CircleReview) -> None:
    title = review.title_ru or review.title_en or "фильм"
    for uid in review.participant_ids or []:
        background_tasks.add_task(push.notify_review_ready, uid, title)


# --- endpoints ----------------------------------------------------------------

@router.get("/pending", response_model=TypingList[ReviewOut])
def pending(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Reviews still waiting for *you* — what the soft "оценим вместе?" card
    on the evening screen reads."""
    link = get_active_link(db, current_user.id)
    if link is None:
        return []
    rows = (
        db.query(models.CircleReview)
        .filter(models.CircleReview.link_id == link.id, models.CircleReview.status == "open")
        .order_by(models.CircleReview.created_at.desc())
        .limit(20)
        .all()
    )
    out = []
    for r in rows:
        if current_user.id not in (r.participant_ids or []):
            continue
        if current_user.id in _done_ids(r) or rules.is_expired(r.expires_at):
            continue
        out.append(_review_out(db, link, r, current_user.id))
    return out


@router.get("/by-title", response_model=Optional[ReviewOut])
def by_title(
    source: str = Query(...),
    media_id: str = Query(...),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The latest review of a title for this circle — how a diary entry or
    the album's book page finds "our review" of it."""
    link = get_active_link(db, current_user.id)
    if link is None:
        return None
    review = (
        db.query(models.CircleReview)
        .filter_by(link_id=link.id, source=source, media_id=media_id)
        .order_by(models.CircleReview.created_at.desc())
        .first()
    )
    if review is None or current_user.id not in (review.participant_ids or []):
        return None
    if _maybe_reveal(db, link, review):
        db.commit()
    _ensure_moments(db, link, review)
    db.commit()
    return _review_out(db, link, review, current_user.id)


@router.get("/by-room/{room_id}", response_model=Optional[ReviewOut])
def by_room(
    room_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    link = get_active_link(db, current_user.id)
    if link is None:
        return None
    review = (
        db.query(models.CircleReview)
        .filter_by(link_id=link.id, room_id=room_id)
        .order_by(models.CircleReview.created_at.desc())
        .first()
    )
    if review is None or current_user.id not in (review.participant_ids or []):
        return None
    if _maybe_reveal(db, link, review):
        db.commit()
    return _review_out(db, link, review, current_user.id)


@router.get("", response_model=TypingList[ReviewOut])
def list_reviews(
    limit: int = Query(20, ge=1, le=50),
    before: Optional[datetime] = None,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The circle's reviews, newest first, for "our book"."""
    link = get_active_link(db, current_user.id)
    if link is None:
        return []
    q = db.query(models.CircleReview).filter(models.CircleReview.link_id == link.id)
    if before is not None:
        q = q.filter(models.CircleReview.created_at < before)
    rows = q.order_by(models.CircleReview.created_at.desc()).limit(limit).all()
    changed = False
    out = []
    for r in rows:
        if current_user.id not in (r.participant_ids or []):
            continue
        changed = _maybe_reveal(db, link, r) or changed
        out.append(_review_out(db, link, r, current_user.id))
    if changed:
        db.commit()
    return out


@router.get("/book", response_model=BookOut)
def book(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Everything the PDF "book of your evenings" needs, in one request.

    Premium for the circle (one member's plan is enough, same rule as the
    moments timeline): 402 otherwise, which the client answers with the
    upsell sheet. Reading single reviews stays free — what the plan buys is
    the book.

    Declared before `/{review_id}` on purpose: otherwise "book" would be
    taken for a review id.

    Only what everyone can already see goes in: opened reviews the caller
    took part in, and only those where somebody actually wrote something.
    Reviews that have run out their week but were never looked at are opened
    here, exactly as `list_reviews` does. Moments of room evenings that
    opened while the circle was still free are computed now — the plan
    unlocks the past, same as on the single review screen."""
    link = _require_link(db, current_user)
    if not _circle_has_premium(db, link):
        raise HTTPException(status_code=402, detail="Книга ваших вечеров открывается с подпиской")

    rows = (
        db.query(models.CircleReview)
        .options(selectinload(models.CircleReview.entries))
        .filter(models.CircleReview.link_id == link.id)
        .order_by(models.CircleReview.watched_on.desc(), models.CircleReview.created_at.desc())
        .all()
    )
    changed = False
    chosen: list[models.CircleReview] = []
    for r in rows:
        if current_user.id not in (r.participant_ids or []):
            continue
        changed = _maybe_reveal(db, link, r) or changed
        if r.status != "revealed" or not rules.has_printable_content(_entry_dicts(r)):
            continue
        before = r.moments
        _ensure_moments(db, link, r)
        changed = (r.moments is not before) or changed
        chosen.append(r)
        if len(chosen) > rules.BOOK_MAX_REVIEWS:
            break
    if changed:
        db.commit()

    truncated = len(chosen) > rules.BOOK_MAX_REVIEWS
    newest_first = chosen[: rules.BOOK_MAX_REVIEWS]
    return BookOut(
        people=[
            BookPersonOut(
                user_id=u.id, username=u.username, display_name=u.display_name,
                avatar_preset=u.avatar_preset, avatar_url=u.avatar_url, is_you=u.id == current_user.id,
            )
            for u in _people(link).values()
        ],
        reviews=[_review_out(db, link, r, current_user.id) for r in reversed(newest_first)],
        truncated=truncated,
    )


@router.get("/{review_id}", response_model=ReviewOut)
def get_review(
    review_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    link, review = _load(db, current_user, review_id)
    if current_user.id not in (review.participant_ids or []):
        raise HTTPException(status_code=403, detail="Вы не были на этом вечере")
    if _maybe_reveal(db, link, review):
        db.commit()
    else:
        before = review.moments
        _ensure_moments(db, link, review)
        if review.moments is not before:
            db.commit()
    return _review_out(db, link, review, current_user.id)


@router.put("/{review_id}/mine", response_model=ReviewOut)
def put_mine(
    review_id: str,
    payload: ReviewEntryIn,
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Write (or rewrite, until the review opens) your own part."""
    tags = rules.clean_tags(payload.tags)
    line = (payload.line or "").strip() or None
    if line is not None:
        if len(line) > rules.LINE_MAX_CHARS:
            raise HTTPException(status_code=400, detail=f"Слишком длинно — не больше {rules.LINE_MAX_CHARS} символов")
        try:
            content_filter.check(line, field="review_line")
        except content_filter.ContentRejected as exc:
            raise HTTPException(status_code=400, detail=str(exc))
    for t in tags:
        try:
            content_filter.check(t, field="review_tag")
        except content_filter.ContentRejected as exc:
            raise HTTPException(status_code=400, detail=str(exc))
    if payload.rating is None and not tags and line is None:
        raise HTTPException(status_code=400, detail="Добавьте оценку, теги или пару слов — или пропустите")

    link, review = _load(db, current_user, review_id, lock=True)
    if current_user.id not in (review.participant_ids or []):
        raise HTTPException(status_code=403, detail="Вы не были на этом вечере")
    if review.status != "open":
        raise HTTPException(status_code=409, detail="Рецензия уже открыта — её можно только читать")
    entry = next((e for e in review.entries if e.user_id == current_user.id), None)
    if entry is None:
        entry = models.CircleReviewEntry(review_id=review.id, user_id=current_user.id)
        db.add(entry)
        review.entries.append(entry)
    entry.rating = payload.rating
    entry.tags = tags
    entry.line = line
    entry.skipped = False
    db.flush()
    opened = _maybe_reveal(db, link, review)
    db.commit()
    db.refresh(review)
    if opened:
        _notify_revealed(background_tasks, review)
    return _review_out(db, link, review, current_user.id)


@router.post("/{review_id}/skip", response_model=ReviewOut)
def skip_mine(
    review_id: str,
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """"Не хочу оценивать": counts as done so the others aren't kept waiting."""
    link, review = _load(db, current_user, review_id, lock=True)
    if current_user.id not in (review.participant_ids or []):
        raise HTTPException(status_code=403, detail="Вы не были на этом вечере")
    if review.status != "open":
        raise HTTPException(status_code=409, detail="Рецензия уже открыта — её можно только читать")
    entry = next((e for e in review.entries if e.user_id == current_user.id), None)
    if entry is None:
        entry = models.CircleReviewEntry(review_id=review.id, user_id=current_user.id)
        db.add(entry)
        review.entries.append(entry)
    entry.rating = None
    entry.tags = []
    entry.line = None
    entry.skipped = True
    db.flush()
    opened = _maybe_reveal(db, link, review)
    db.commit()
    db.refresh(review)
    if opened:
        _notify_revealed(background_tasks, review)
    return _review_out(db, link, review, current_user.id)
