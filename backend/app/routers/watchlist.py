"""Watchlist entry management that doesn't fit log_watched (which is
specifically about *logging an evening*) or feed.py's add_watchlist_status
(which is specifically the discovery-feed "like" reaction). Two
endpoints: honestly closing something out without watching it, and
paying off a stale one's upkeep — see each endpoint's own docstring.

Before drop_entry, WatchStatus.dropped existed only as an enum member —
no endpoint anywhere ever set a WatchlistEntry to it. This was the
first one, built specifically as the trigger for sincerity.py's two
closing-a-loop-honestly reasons: see drop_entry below for exactly which
one fires and why they need different rules. settle_debt is the newer
of the two, built the same way for debt_settled — see that reason's own
history in app/sincerity.py's module docstring.
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app import models, sincerity
from app.database import get_db
from app.deps import get_current_user
from app.schemas import SincerityTransactionOut, WatchlistDropIn, WatchlistDropOut

router = APIRouter(prefix="/watchlist", tags=["watchlist"])


@router.post("/drop", response_model=WatchlistDropOut)
def drop_entry(
    payload: WatchlistDropIn,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Marks one title `dropped`. Which sincerity.py reason (if any)
    fires depends entirely on the status this entry was in *before*
    this call — the honesty being rewarded is different in each case:

    - `watch_later` (never actually started) -> earn_closed_gestalt's
      "not for me" case. No reason required: the honest act here is
      admitting the title isn't happening rather than letting it sit
      forever, not explaining why.
    - `watching` (already started, gave up partway) -> earn_honest_drop,
      which requires a real, non-empty `reason` — see that function's
      own docstring for why the reason itself is the point there.
    - already `watched` or already `dropped` -> 400. There's nothing
      honest left to close: a finished title isn't "dropped", and a
      title already marked dropped can't be dropped again for more
      points (also incidentally the anti-farm guard for this endpoint).
    """
    entry = (
        db.query(models.WatchlistEntry)
        .filter(
            models.WatchlistEntry.user_id == current_user.id,
            models.WatchlistEntry.media_id == payload.media_id,
            models.WatchlistEntry.source == payload.source,
        )
        .first()
    )
    if entry is None:
        raise HTTPException(status_code=404, detail="Not on your watchlist")
    if entry.status in (models.WatchStatus.watched, models.WatchStatus.dropped):
        raise HTTPException(status_code=400, detail="Nothing to drop from this status")

    title = entry.title_en or entry.title_ru or "—"
    was_watch_later = entry.status == models.WatchStatus.watch_later
    was_watching = entry.status == models.WatchStatus.watching
    planned_since = entry.created_at

    entry.status = models.WatchStatus.dropped
    entry.drop_reason = payload.reason

    db.add(models.ActivityEvent(
        user_id=current_user.id,
        verb="dropped",
        media_title=title,
        media_type=entry.media_type,
        media_id=entry.media_id,
        source=entry.source,
        poster_url=entry.poster_url,
    ))

    award = None
    if was_watch_later:
        award = sincerity.earn_closed_gestalt(
            db, current_user,
            entry_id=entry.id,
            title=title,
            planned_since=planned_since,
            closed_honestly_as="not for me",
        )
    elif was_watching:
        award = sincerity.earn_honest_drop(
            db, current_user,
            entry_id=entry.id,
            title=title,
            reason_text=payload.reason or "",
        )

    db.commit()
    return WatchlistDropOut(
        status=entry.status.value,
        sincerity_awarded=[
            SincerityTransactionOut(
                id=award.id, delta=award.delta, reason=award.reason.value,
                note=award.note, created_at=award.created_at,
            )
        ] if award is not None else None,
    )


@router.post("/{entry_id}/settle-debt", response_model=WatchlistDropOut)
def settle_debt(
    entry_id: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Pays sincerity.DEBT_SETTLEMENT_COST once, in exchange for this one
    watch_later item never being charged stale_debt again — see
    WatchlistEntry.debt_exempt and sincerity.spend_debt_settlement.
    Reuses WatchlistDropOut as the response shape even though nothing
    here drops the entry: the client already knows how to render a
    single sincerity delta from it, and inventing a one-off schema for
    "status unchanged, here's what it cost" would just duplicate that.
    """
    entry = (
        db.query(models.WatchlistEntry)
        .filter(
            models.WatchlistEntry.id == entry_id,
            models.WatchlistEntry.user_id == current_user.id,
        )
        .first()
    )
    if entry is None:
        raise HTTPException(status_code=404, detail="Not on your watchlist")
    if entry.status != models.WatchStatus.watch_later:
        raise HTTPException(status_code=400, detail="Only a planned item can owe debt")
    if entry.debt_exempt:
        raise HTTPException(status_code=400, detail="Already settled")
    if datetime.now(timezone.utc) - entry.created_at < sincerity.STALE_DEBT_THRESHOLD:
        raise HTTPException(status_code=400, detail="Nothing owed on this one yet")
    if current_user.sincerity_balance < sincerity.DEBT_SETTLEMENT_COST:
        raise HTTPException(status_code=400, detail="Not enough sincerity points")

    title = entry.title_en or entry.title_ru or "—"
    award = sincerity.spend_debt_settlement(db, current_user, entry_id=entry.id, title=title)
    entry.debt_exempt = True
    db.commit()
    return WatchlistDropOut(
        status=entry.status.value,
        sincerity_awarded=[
            SincerityTransactionOut(
                id=award.id, delta=award.delta, reason=award.reason.value,
                note=award.note, created_at=award.created_at,
            )
        ],
    )
