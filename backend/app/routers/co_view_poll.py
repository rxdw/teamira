import json
import random
from datetime import datetime, timedelta
from typing import List

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import TypeAdapter
from sqlalchemy.orm import Session

from app import models
from app.database import get_db
from app.deps import get_current_user
from app.routers.co_view_vote import PoolSource, _build_vote_pool, _require_link
from app.routers.partner import _member_ids, add_coview_entries
from app.schemas import CoViewPollSessionOut, CoViewPollVoteRequest, MediaItem

router = APIRouter(prefix="/partner/co-viewing/poll", tags=["partner"])

# First-round shortlist size — trimmed down if the pool has fewer titles
# than this. A runoff after a tie only ever narrows *below* whatever the
# round it came from had, so this is also the largest a poll ever gets.
SHORTLIST_SIZE = 4

ROUND_DURATION = timedelta(minutes=10)

# After this many rounds still tied across the *entire* current shortlist
# (a runoff that narrowed nothing), stop reopening and just draw one of
# the tied leaders — a couple that always splits evenly would otherwise
# never land on anything.
MAX_TIE_ROUNDS = 3


def _get_active_poll(db: Session, link: models.PartnerLink) -> models.CoViewPollSession | None:
    return (
        db.query(models.CoViewPollSession)
        .filter_by(link_id=link.id, status=models.CoViewPollStatus.active)
        .order_by(models.CoViewPollSession.created_at.desc())
        .first()
    )


def _get_poll_for_link(db: Session, session_id: str, link: models.PartnerLink) -> models.CoViewPollSession:
    row = db.get(models.CoViewPollSession, session_id)
    if row is None or row.link_id != link.id:
        raise HTTPException(status_code=404, detail="Poll not found")
    return row


def _candidates(row: models.CoViewPollSession) -> List[MediaItem]:
    return TypeAdapter(List[MediaItem]).validate_json(row.candidates_json)


def _resolve_if_needed(db: Session, row: models.CoViewPollSession) -> None:
    """Called after every cast and on every poll — a poll can also resolve
    on its own once the deadline passes with nobody casting a fresh vote,
    so this can't only run inside cast_poll_vote the way cast_vote's
    inline match check can.

    Leaves `row` untouched (still active) if it's not time yet. Otherwise
    either decides it (winner set, status=done, added to the shared list)
    or — on a tie for the lead — narrows candidates_json down to just the
    tied leaders, clears this round's votes, and reopens for a runoff.
    """
    if row.status != models.CoViewPollStatus.active:
        return

    members = _member_ids(row.link)
    votes = {v.user_id: v.candidate_index for v in row.votes if v.user_id in members}
    all_voted = bool(members) and all(uid in votes for uid in members)
    deadline_passed = datetime.utcnow() >= row.deadline
    if not all_voted and not deadline_passed:
        return

    candidates = _candidates(row)
    tally = [0] * len(candidates)
    for idx in votes.values():
        if 0 <= idx < len(tally):
            tally[idx] += 1

    if sum(tally) == 0:
        # Deadline hit and nobody voted at all — don't leave the circle
        # stuck on a dead poll forever, just draw one.
        winner_idx = random.randrange(len(candidates))
    else:
        top = max(tally)
        leaders_idx = [i for i, c in enumerate(tally) if c == top]
        if len(leaders_idx) == 1:
            winner_idx = leaders_idx[0]
        elif len(leaders_idx) == len(candidates) and row.round_number >= MAX_TIE_ROUNDS:
            winner_idx = random.choice(leaders_idx)
        else:
            row.candidates_json = json.dumps(
                [candidates[i].model_dump(mode="json") for i in leaders_idx]
            )
            row.round_number += 1
            row.deadline = datetime.utcnow() + ROUND_DURATION
            for v in list(row.votes):
                db.delete(v)
            return

    winner = candidates[winner_idx]
    row.status = models.CoViewPollStatus.done
    row.winner_source = winner.source
    row.winner_media_id = winner.id
    # Already on both/everyone's own plan-to-watch shelves — this only
    # needs to land on the shared list, not re-sync anyone's personal one.
    add_coview_entries(db, row.link, [winner], added_by_id=None, sync_own_watchlist=False)


def _to_out(row: models.CoViewPollSession, current_user_id: str) -> CoViewPollSessionOut:
    candidates = _candidates(row)
    votes = {v.user_id: v.candidate_index for v in row.votes}
    counts = [0] * len(candidates)
    for idx in votes.values():
        if 0 <= idx < len(counts):
            counts[idx] += 1

    winner = None
    if row.winner_source and row.winner_media_id:
        by_key = {(i.source, i.id): i for i in candidates}
        winner = by_key.get((row.winner_source, row.winner_media_id))

    return CoViewPollSessionOut(
        id=row.id,
        status=row.status.value,
        pool_source=row.pool_source,
        round_number=row.round_number,
        deadline=row.deadline,
        candidates=candidates,
        vote_counts=counts,
        my_vote=votes.get(current_user_id),
        voted_count=len(votes),
        member_count=len(_member_ids(row.link)),
        winner=winner,
        created_at=row.created_at,
    )


@router.post("/start", response_model=CoViewPollSessionOut, status_code=201)
async def start_poll(
    source: PoolSource = Query("personal"),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Starts a head-to-head poll, or — if one's already active for this
    link — hands that one back, same "whoever taps first" reasoning as
    start_vote. Draws up to SHORTLIST_SIZE candidates from the same pool
    a swipe round or a random/reel draw would use (see _build_vote_pool);
    the whole circle then votes on the shortlist itself, on a clock,
    rather than each person swiping the pool alone.
    """
    link = _require_link(db, current_user.id)

    existing = _get_active_poll(db, link)
    if existing is not None:
        _resolve_if_needed(db, existing)
        db.commit()
        db.refresh(existing)
        return _to_out(existing, current_user.id)

    pool = await _build_vote_pool(db, link, source)
    if len(pool) < 2:
        raise HTTPException(status_code=422, detail="Need at least two titles queued to vote between")

    chosen = pool if len(pool) <= SHORTLIST_SIZE else random.sample(pool, SHORTLIST_SIZE)

    row = models.CoViewPollSession(
        link_id=link.id,
        started_by_id=current_user.id,
        pool_source=source,
        candidates_json=json.dumps(chosen),
        round_number=1,
        deadline=datetime.utcnow() + ROUND_DURATION,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return _to_out(row, current_user.id)


@router.get("/{session_id}", response_model=CoViewPollSessionOut)
def get_poll(
    session_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Polled every few seconds while a poll is open — resolves it first
    (a deadline can pass between polls with no new vote in between, so
    this can't just read the row as-is the way a plain GET normally
    would)."""
    link = _require_link(db, current_user.id)
    row = _get_poll_for_link(db, session_id, link)
    _resolve_if_needed(db, row)
    db.commit()
    db.refresh(row)
    return _to_out(row, current_user.id)


@router.post("/{session_id}/vote", response_model=CoViewPollSessionOut)
def cast_poll_vote(
    session_id: str,
    payload: CoViewPollVoteRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    link = _require_link(db, current_user.id)
    row = _get_poll_for_link(db, session_id, link)
    if row.status != models.CoViewPollStatus.active:
        raise HTTPException(status_code=409, detail="This poll is already done")

    candidates = _candidates(row)
    if not (0 <= payload.candidate_index < len(candidates)):
        raise HTTPException(status_code=422, detail="That's not one of this round's options anymore")

    existing = (
        db.query(models.CoViewPollVote)
        .filter_by(session_id=row.id, user_id=current_user.id)
        .first()
    )
    if existing is None:
        db.add(models.CoViewPollVote(
            session_id=row.id, user_id=current_user.id, candidate_index=payload.candidate_index,
        ))
    else:
        existing.candidate_index = payload.candidate_index
    db.flush()

    _resolve_if_needed(db, row)
    db.commit()
    db.refresh(row)
    return _to_out(row, current_user.id)


@router.delete("/{session_id}", status_code=204)
def end_poll(
    session_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Either side can call it off early — same as end_vote."""
    link = _require_link(db, current_user.id)
    row = _get_poll_for_link(db, session_id, link)
    db.delete(row)
    db.commit()
