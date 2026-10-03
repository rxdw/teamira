"""Sincerity points — read-side API for the merged Sincerity screen (level
ring, spendable balance, and the transaction history the level ring's
breakdown used to lack — see app/sincerity.py's module docstring for
that merge) and the one privacy toggle in Settings. The actual
earning/spending logic lives in app/sincerity.py and is called from the
routers that own each triggering event — this file only exposes what's
already on the ledger, plus the privacy flag that governs whether GET
/friends/profile includes the balance for someone else's profile, and
the "what's settleable right now" list the Sincerity screen's own
settle-debt button reads from.
"""

from datetime import datetime, timezone
from typing import List

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app import models, sincerity
from app.database import get_db
from app.deps import get_current_user
from app.schemas import (
    SincerityBalanceOut,
    SincerityPrivacyUpdate,
    SincerityStaleItemOut,
    SincerityTransactionOut,
)

router = APIRouter(prefix="/sincerity", tags=["sincerity"])

_PAGE_SIZE = 30


def _stale_items(db: Session, user: models.User) -> List[SincerityStaleItemOut]:
    """Every still-watch_later item old enough to owe stale_debt (exempt
    or not, oldest first) — what the Sincerity screen's settle-debt
    section renders. Same shelf apply_stale_planned_decay_for_user
    already walks on this same request, so this is cheap: normally a
    handful of rows at most.
    """
    now = datetime.now(timezone.utc)
    planned = (
        db.query(models.WatchlistEntry)
        .filter(
            models.WatchlistEntry.user_id == user.id,
            models.WatchlistEntry.status == models.WatchStatus.watch_later,
        )
        .all()
    )
    items = []
    for entry in planned:
        age = now - entry.created_at
        if age < sincerity.STALE_DEBT_THRESHOLD:
            continue
        items.append(SincerityStaleItemOut(
            entry_id=entry.id,
            title=entry.title_en or entry.title_ru or "—",
            poster_url=entry.poster_url,
            age_days=age.days,
            debt_exempt=entry.debt_exempt,
            settle_cost=sincerity.DEBT_SETTLEMENT_COST,
        ))
    items.sort(key=lambda i: i.age_days, reverse=True)
    return items


@router.get("/me", response_model=SincerityBalanceOut)
def get_my_sincerity(
    before: str | None = Query(default=None, description="transaction id to page before, for older history"),
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    # See app/sincerity.py::apply_stale_planned_decay's own docstring —
    # no scheduler exists in this backend, so stale-planned debt is
    # recomputed lazily here, the same "recompute on read" shape
    # routers/referrals.py uses for its own pending-verification sweep.
    # Cheap and safe to run on every call: it's a no-op for any entry
    # not actually due.
    if sincerity.apply_stale_planned_decay_for_user(db, user):
        db.commit()
    q = db.query(models.SincerityTransaction).filter(models.SincerityTransaction.user_id == user.id)
    if before:
        anchor = db.query(models.SincerityTransaction).filter(models.SincerityTransaction.id == before).first()
        if anchor is not None:
            q = q.filter(models.SincerityTransaction.created_at < anchor.created_at)
    rows = q.order_by(models.SincerityTransaction.created_at.desc()).limit(_PAGE_SIZE + 1).all()
    has_more = len(rows) > _PAGE_SIZE
    rows = rows[:_PAGE_SIZE]
    level, points_into_level, points_for_next_level = sincerity.compute_level(
        user.lifetime_sincerity_earned
    )
    return SincerityBalanceOut(
        balance=user.sincerity_balance,
        visible_to_friends=user.sincerity_visible_to_friends,
        level=level,
        lifetime_earned=user.lifetime_sincerity_earned,
        points_into_level=points_into_level,
        points_for_next_level=points_for_next_level,
        history=[
            SincerityTransactionOut(
                id=row.id,
                delta=row.delta,
                reason=row.reason.value,
                note=row.note,
                created_at=row.created_at,
            )
            for row in rows
        ],
        has_more=has_more,
        # Only on the first page — this isn't part of the paginated
        # history, so there's no reason to resend it on every "load
        # older" scroll.
        stale_items=_stale_items(db, user) if not before else [],
    )


@router.patch("/privacy", response_model=SincerityBalanceOut)
def update_sincerity_privacy(
    body: SincerityPrivacyUpdate,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """Purely a display toggle — see User.sincerity_visible_to_friends'
    own docstring. Never affects earning, spending, or the balance
    itself, only whether GET /friends/profile hands it to someone else.
    """
    user.sincerity_visible_to_friends = body.visible_to_friends
    db.commit()
    return get_my_sincerity(before=None, db=db, user=user)
