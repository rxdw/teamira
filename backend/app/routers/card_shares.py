"""Share cards -> sincerity points.

The one sincerity source that can't be derived from what's logged: a
diary row says an evening happened, nothing in the database says the
card for it left the app. So the client tells us (mobile's share sheet
calls this after the native share sheet reports the card went
somewhere), and we keep one row per distinct card in models.CardShare
to make the reward a one-time ledger write (see
app/sincerity.py::earn_card_share) rather than something that could be
farmed by calling this endpoint on repeat.

Because the server has no way to check the card actually reached
anyone, the reward is bounded rather than verified:

  - **Once per card.** (user_id, card_key) is unique. Re-sharing the same
    evening or title is allowed and free; it just never pays twice.
  - **A daily cap.** At most MAX_REWARDED_SHARES_PER_DAY cards per UTC day
    earn points. A share over the cap isn't recorded at all, so the same
    card can still earn on a later day -- being over the limit never
    "uses up" a card.
"""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import models, sincerity
from app.database import get_db
from app.deps import get_current_user
from app.schemas import CardShareIn, CardShareOut

router = APIRouter(prefix="/shares", tags=["shares"])

MAX_REWARDED_SHARES_PER_DAY = 2


@router.post("/card", response_model=CardShareOut)
def record_card_share(
    payload: CardShareIn,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Records that a share card left the app and pays sincerity points
    for it if it's the first time for that card and today's cap isn't
    used up.

    Always 200 for a well-formed request, including when nothing was
    paid -- a repeat share is normal use, not an error, and the client
    only needs `counted` to decide whether to show a "+points" moment.
    """
    key = payload.card_key.strip()
    level_before, _, _ = sincerity.compute_level(current_user.lifetime_sincerity_earned)

    def _not_counted(reason: str) -> CardShareOut:
        return CardShareOut(
            counted=False,
            reason=reason,
            total_points=current_user.lifetime_sincerity_earned,
            level=level_before,
        )

    if (
        db.query(models.CardShare.id)
        .filter_by(user_id=current_user.id, card_key=key)
        .first()
        is not None
    ):
        return _not_counted("already_counted")

    today = datetime.now(timezone.utc).date().isoformat()
    used_today = (
        db.query(func.count(models.CardShare.id))
        .filter_by(user_id=current_user.id, day_key=today)
        .scalar()
    ) or 0
    if used_today >= MAX_REWARDED_SHARES_PER_DAY:
        return _not_counted("daily_limit")

    db.add(models.CardShare(user_id=current_user.id, card_key=key, day_key=today))
    try:
        db.flush()
    except IntegrityError:
        # Two taps racing on the same card -- the other one won, which is
        # exactly the "already counted" answer.
        db.rollback()
        return _not_counted("already_counted")

    sincerity.earn_card_share(db, current_user, card_key=key)
    db.commit()

    level_after, _, _ = sincerity.compute_level(current_user.lifetime_sincerity_earned)
    return CardShareOut(
        counted=True,
        points_awarded=sincerity.CARD_SHARE_AWARD,
        total_points=current_user.lifetime_sincerity_earned,
        level=level_after,
        leveled_up=level_after > level_before,
    )
