"""Staked recommendations — "I bet you'll rate this N" between friends,
backed by sincerity points. The feature app/sincerity.py's
recommendation_stake/accurate_recommendation/stake_forfeited/
stake_expired reasons were written for from the start, but had no
endpoint anywhere calling them until this file (see
models.Recommendation's own docstring for the full lifecycle).

Only two things happen here: staking (create) and reading your own
stakes (list, which also sweeps for anything that's quietly expired).
Resolution itself — the exciting part, where a stake turns into a hit
or a miss — happens from routers/diary.py::log_watched, the moment the
recipient logs a rating for the recommended title; there's no
"resolve" endpoint in this file because nobody ever calls it directly,
the same way nobody calls "close a loop honestly" directly either.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app import models, sincerity
from app.database import get_db
from app.deps import get_current_user
from app.routers.friends import _accepted_link
from app.schemas import RecommendationCreate, RecommendationOut, RecommendationsOut

router = APIRouter(prefix="/recommendations", tags=["recommendations"])

# A person's inbox of "someone's staking on you" shouldn't grow forever
# if they never log any of it — same "small, bounded" reasoning as
# apply_stale_planned_decay_for_user's watch_later shelf. In practice
# nobody has more than a handful of live stakes at once.
_MAX_PENDING_PER_DIRECTION = 50


def _out(rec: models.Recommendation, users: dict, viewer_id: str) -> RecommendationOut:
    staker = users[rec.staker_id]
    recipient = users[rec.recipient_id]
    return RecommendationOut(
        id=rec.id,
        staker_id=rec.staker_id,
        staker_username=staker.username,
        recipient_id=rec.recipient_id,
        recipient_username=recipient.username,
        source=rec.source,
        media_id=rec.media_id,
        title=rec.title,
        predicted_rating=rec.predicted_rating,
        staked_amount=rec.staked_amount,
        status=rec.status.value,
        actual_rating=rec.actual_rating,
        created_at=rec.created_at,
        resolved_at=rec.resolved_at,
        is_mine=rec.staker_id == viewer_id,
    )


def _sweep_expired(db: Session, recs: List[models.Recommendation]) -> bool:
    """Lazily resolves any still-pending row past RECOMMENDATION_EXPIRY —
    same "recompute on read, no scheduler in this backend" shape as
    app/sincerity.py::apply_stale_planned_decay. Only ever touches rows
    already loaded for this request, so it's a plain in-memory age check
    per row, not a second query. Returns whether anything changed, so
    the caller knows whether to commit.
    """
    now = datetime.now(timezone.utc)
    changed = False
    for rec in recs:
        if rec.status != models.RecommendationStatus.pending:
            continue
        if now - rec.created_at < sincerity.RECOMMENDATION_EXPIRY:
            continue
        staker = db.query(models.User).filter(models.User.id == rec.staker_id).first()
        recipient = db.query(models.User).filter(models.User.id == rec.recipient_id).first()
        if staker is None:
            continue
        sincerity.expire_recommendation_stake(
            db, staker,
            friend_name=recipient.username if recipient is not None else "friend",
            title=rec.title,
            staked_amount=rec.staked_amount,
        )
        rec.status = models.RecommendationStatus.expired
        rec.resolved_at = now
        changed = True
    return changed


@router.post("", response_model=RecommendationOut, status_code=201)
def create_recommendation(
    payload: RecommendationCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Stakes `payload.stake` points on `payload.friend_id` rating
    `payload.title` close to `payload.predicted_rating` — see
    app/sincerity.py::spend_recommendation_stake for the ledger side.
    The cost is taken right now, up front, same as a real bet: nothing
    here is refunded just because the friend hasn't watched it yet (see
    _sweep_expired above for the one case where it eventually is).
    """
    if payload.friend_id == current_user.id:
        raise HTTPException(status_code=400, detail="Can't stake a recommendation to yourself")
    if _accepted_link(db, current_user.id, payload.friend_id) is None:
        raise HTTPException(status_code=403, detail="Not friends with this person")

    friend = db.query(models.User).filter(models.User.id == payload.friend_id).first()
    if friend is None:
        raise HTTPException(status_code=404, detail="Friend not found")

    stake = max(sincerity.MIN_RECOMMENDATION_STAKE, min(sincerity.MAX_RECOMMENDATION_STAKE, payload.stake))
    if current_user.sincerity_balance < stake:
        raise HTTPException(status_code=400, detail="Not enough sincerity points")

    existing_pending = (
        db.query(models.Recommendation)
        .filter(
            models.Recommendation.staker_id == current_user.id,
            models.Recommendation.recipient_id == payload.friend_id,
            models.Recommendation.source == payload.source,
            models.Recommendation.media_id == payload.media_id,
            models.Recommendation.status == models.RecommendationStatus.pending,
        )
        .first()
    )
    if existing_pending is not None:
        raise HTTPException(status_code=400, detail="Already staked on this title for this friend")

    sincerity.spend_recommendation_stake(
        db, current_user,
        friend_id=payload.friend_id,
        friend_name=friend.username,
        title=payload.title,
        amount=stake,
    )
    rec = models.Recommendation(
        staker_id=current_user.id,
        recipient_id=payload.friend_id,
        source=payload.source,
        media_id=payload.media_id,
        title=payload.title,
        predicted_rating=payload.predicted_rating,
        staked_amount=stake,
    )
    db.add(rec)
    db.commit()
    db.refresh(rec)
    return _out(rec, {current_user.id: current_user, friend.id: friend}, current_user.id)


@router.get("", response_model=RecommendationsOut)
def list_recommendations(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Everything the current person has staked (outgoing) or has been
    staked on (incoming), newest first, resolved and pending mixed
    together — the Sincerity screen's own history already tells the
    ledger side of a resolved one, so this list exists mainly to surface
    the *pending* ones nowhere else in the app can show.
    """
    outgoing = (
        db.query(models.Recommendation)
        .filter(models.Recommendation.staker_id == current_user.id)
        .order_by(models.Recommendation.created_at.desc())
        .limit(_MAX_PENDING_PER_DIRECTION)
        .all()
    )
    incoming = (
        db.query(models.Recommendation)
        .filter(models.Recommendation.recipient_id == current_user.id)
        .order_by(models.Recommendation.created_at.desc())
        .limit(_MAX_PENDING_PER_DIRECTION)
        .all()
    )
    if _sweep_expired(db, outgoing) | _sweep_expired(db, incoming):
        db.commit()

    user_ids = {r.staker_id for r in outgoing + incoming} | {r.recipient_id for r in outgoing + incoming}
    users = {u.id: u for u in db.query(models.User).filter(models.User.id.in_(user_ids)).all()}

    return RecommendationsOut(
        outgoing=[_out(r, users, current_user.id) for r in outgoing if r.staker_id in users and r.recipient_id in users],
        incoming=[_out(r, users, current_user.id) for r in incoming if r.staker_id in users and r.recipient_id in users],
    )
