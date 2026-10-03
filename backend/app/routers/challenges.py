"""Weekly and yearly challenges — see app/challenges.py for the catalog,
the periods, and why progress is recomputed rather than stored.

This router is deliberately thin: three endpoints, no logic of its own
beyond translating challenge state into the wire shape and handling the
two things a person can actually *do* (collect a reward, dismiss a
completion banner).
"""

from __future__ import annotations

from datetime import date, datetime, timezone
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app import challenges as catalog
from app import models, sincerity
from app.database import get_db
from app.deps import get_current_user
from app.schemas import ChallengeClaimOut, ChallengeOut, ChallengesOut

router = APIRouter(prefix="/challenges", tags=["challenges"])


def _out(state: catalog.ChallengeState, lang: str) -> ChallengeOut:
    c = state.challenge
    ru = lang == "ru"
    return ChallengeOut(
        id=c.id,
        cadence=c.cadence,
        icon_key=c.icon_key,
        title=c.title_ru if ru else c.title_en,
        caption=c.caption_ru if ru else c.caption_en,
        rule=(c.rule_ru if ru else c.rule_en) or "",
        current=state.current,
        target=c.target,
        progress=min(1.0, state.current / c.target) if c.target else 0.0,
        completed=state.completed,
        claimed=state.claimed,
        points=c.points,
        days_left=state.days_left,
        period_key=state.period_key,
        completed_at=state.completed_at,
    )


@router.get("", response_model=ChallengesOut)
def get_challenges(
    lang: str = "ru",
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Everything live right now, with this account's progress in each.

    Writes on a GET, which is worth flagging: `catalog.evaluate` records
    the moment a challenge first crosses its target. That has to happen
    on read because there's no scheduler in this backend (see
    app/challenges.py's docstring and routers/referrals.py, which solves
    the same constraint the same way) — and it has to be recorded at all
    because a completion timestamp is the one part of challenge state
    that genuinely can't be recomputed later from diary rows that may
    since have been edited.

    The write is idempotent: a challenge already carrying a completed_at
    is left alone, so repeated polling from Home doesn't churn rows.
    """
    today = date.today()
    states = catalog.evaluate(db, current_user.id, today)
    db.commit()

    weekly = [_out(s, lang) for s in states if s.challenge.cadence == "weekly"]
    yearly = [_out(s, lang) for s in states if s.challenge.cadence == "yearly"]
    announce = [_out(s, lang) for s in states if s.needs_announcement]

    _, week_end = catalog.week_bounds(today)
    return ChallengesOut(
        # Nearly-done first within each group: the one at 2/3 is the one
        # worth a tap tonight, and burying it under an untouched 0/3 is
        # how a challenge card becomes wallpaper. Completed-but-unclaimed
        # sorts above everything, since there's a reward sitting there.
        weekly=sorted(weekly, key=_sort_key),
        yearly=sorted(yearly, key=_sort_key),
        to_announce=announce,
        claimable_count=sum(1 for s in states if s.completed and not s.claimed),
        week_ends_at=week_end.isoformat(),
    )


def _sort_key(c: ChallengeOut):
    if c.completed and not c.claimed:
        return (0, 0.0)
    if c.completed:
        return (2, 0.0)          # done and collected — bottom of the list
    return (1, -c.progress)      # in progress, closest to done first


@router.post("/{challenge_id}/claim", response_model=ChallengeClaimOut)
def claim_challenge(
    challenge_id: str,
    lang: str = "ru",
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Collect a finished challenge's sincerity points.

    Re-evaluates before paying out rather than trusting the id alone — so
    a claim can't be forged for something that was never finished, and
    can't be replayed for something already collected. Both of those are
    checked against the stored row, not against the recomputed progress,
    which matters for the edge case where someone completed a challenge
    and then deleted a diary entry: they finished it, the completion is
    recorded, and the reward is still theirs.
    """
    today = date.today()
    states = catalog.evaluate(db, current_user.id, today)
    db.commit()

    pkey = None
    state = None
    for s in states:
        if s.challenge.id == challenge_id:
            state = s
            pkey = s.period_key
            break
    if state is None:
        raise HTTPException(status_code=404, detail="No such challenge running right now")
    if not state.completed:
        raise HTTPException(status_code=409, detail="Not finished yet")

    row = (
        db.query(models.ChallengeProgress)
        .filter_by(user_id=current_user.id, challenge_id=challenge_id, period_key=pkey)
        .first()
    )
    if row is None:
        raise HTTPException(status_code=409, detail="Not finished yet")
    if row.claimed_at is not None:
        raise HTTPException(status_code=409, detail="Already collected")

    level_before, _, _ = sincerity.compute_level(current_user.lifetime_sincerity_earned)

    row.claimed_at = datetime.now(timezone.utc)
    # Claiming also counts as seeing it — otherwise Home would keep
    # announcing a challenge the person has demonstrably just interacted
    # with.
    row.seen_at = row.seen_at or datetime.now(timezone.utc)
    sincerity.earn_challenge_claimed(
        db, current_user,
        challenge_id=challenge_id,
        title=state.challenge.title_ru,
        points=state.challenge.points,
    )
    db.commit()

    level_after, _, _ = sincerity.compute_level(current_user.lifetime_sincerity_earned)
    state.claimed = True
    return ChallengeClaimOut(
        challenge=_out(state, lang),
        points_awarded=state.challenge.points,
        total_points=current_user.lifetime_sincerity_earned,
        level=level_after,
        leveled_up=level_after > level_before,
    )


@router.post("/seen", status_code=204)
def mark_seen(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Acknowledges every completion banner currently pending, so Home
    stops announcing them. Separate from claiming on purpose: dismissing
    the "готово!" toast must not quietly collect the reward, or people
    lose XP by swiping a notification away.
    """
    rows = (
        db.query(models.ChallengeProgress)
        .filter(
            models.ChallengeProgress.user_id == current_user.id,
            models.ChallengeProgress.completed_at.isnot(None),
            models.ChallengeProgress.seen_at.is_(None),
        )
        .all()
    )
    now = datetime.now(timezone.utc)
    for r in rows:
        r.seen_at = now
    db.commit()
