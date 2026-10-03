"""Blocking, reporting, and the moderator's queue.

This is the App Store Guideline 1.2 surface. An app with user-generated
content — and this one has nicknames, avatars, status lines, diary
notes, list names and a friends activity feed, all of which one person
can show another — is rejected at review without, in Apple's own
wording, a method for filtering objectionable content, a mechanism to
report it, the ability to block abusive users, and published contact
information. Guideline 1.2 also asks that reports be acted on within 24
hours.

So there are four pieces here, and they're deliberately four rather than
one:

  - **Block** (POST /moderation/blocks). Immediate, needs no review,
    symmetric in effect — see app/blocking.py. This is the one that has
    to work at 2am with nobody on call.
  - **Report** (POST /moderation/reports). Files a complaint for a human
    to read. Separate from blocking because "I don't want to see this
    person" and "someone should look at what this person is doing" are
    different asks, and forcing them together means either people block
    when they should report or the queue fills with "I just didn't like
    them".
  - **Filtering** (app/content_filter.py, called from the write paths).
    The automated first pass on names and free text.
  - **The queue** (/moderation/admin/*). Where a moderator actually acts,
    sorted by the 24-hour clock.

`due_at` is what turns the 24-hour commitment into something checkable
instead of a line in a review reply — see models.Report.

**No admin UI exists yet.** `/moderation/admin/reports` and
`.../resolve` below are complete and tested, but there is no screen
anywhere in mobile/ that calls them — a moderator's only way to work the
queue right now is curl, an API client, or a small internal tool nobody
has built. That was fine while `due_at` was a number nobody could see;
it stops being fine the moment a real person is told, correctly, that
their report gets looked at within 24 hours, because now something has
to actually be checking. Build the admin screen (or point an existing
internal tool at this router) before this carries real reports.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import models
from app.blocking import i_blocked_them
from app.config import settings
from app.database import get_db
from app.deps import get_active_user, get_current_user, require_admin_user
from app.rate_limit import report_limiter
from app.schemas import (
    BlockedUserOut,
    BlockRequest,
    ReportAdminOut,
    ReportCreateRequest,
    ReportOut,
    ReportResolveRequest,
    SimpleMessageOut,
)

router = APIRouter(prefix="/moderation", tags=["moderation"])


def _client_key(request: Request) -> str:
    return request.client.host if request.client else "unknown"


# ---------------------------------------------------------------------------
# Blocking
# ---------------------------------------------------------------------------

@router.get("/blocks", response_model=list[BlockedUserOut])
def list_blocks(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Only the accounts *this* person blocked — never the ones who
    blocked them. Showing the latter would turn a block into a
    notification, which is the one thing a block must not be."""
    rows = (
        db.query(models.UserBlock, models.User)
        .join(models.User, models.User.id == models.UserBlock.blocked_id)
        .filter(models.UserBlock.blocker_id == current_user.id)
        .order_by(models.UserBlock.created_at.desc())
        .all()
    )
    return [
        BlockedUserOut(
            user_id=u.id,
            username=u.username,
            display_name=u.display_name,
            avatar_preset=u.avatar_preset,
            avatar_url=u.avatar_url,
            blocked_at=block.created_at,
        )
        for block, u in rows
    ]


@router.post("/blocks", response_model=SimpleMessageOut, status_code=201)
def block_user(
    payload: BlockRequest,
    current_user: models.User = Depends(get_active_user),
    db: Session = Depends(get_db),
):
    """Blocks someone and tears down whatever connection already exists.

    The teardown is the part that's easy to leave out and wrong to leave
    out: a block that leaves the two accounts still friends means the
    blocked person keeps whatever a friend can see (shelves set to
    "friends", the activity feed, the friend profile) right up until
    someone notices. So the friendship row goes, pending requests in
    either direction go, and pending co-viewing invites go.

    An *active* co-viewing circle is deliberately left standing. Circles
    can have three or more people in them, and silently dissolving a
    group — taking its shared diary tagging and co-viewing list with it —
    because two of its members fell out is far more destructive than the
    problem. app/blocking.py keeps the two from seeing each other inside
    it; leaving the circle is a separate, deliberate action.
    """
    if payload.user_id == current_user.id:
        raise HTTPException(status_code=400, detail="You can't block yourself")

    target = db.get(models.User, payload.user_id)
    if target is None or target.deleted_at is not None:
        raise HTTPException(status_code=404, detail="No such account")

    if i_blocked_them(db, current_user.id, target.id):
        return SimpleMessageOut(message="Already blocked")

    db.add(models.UserBlock(blocker_id=current_user.id, blocked_id=target.id))

    db.query(models.FriendRequest).filter(
        or_(
            (models.FriendRequest.from_user_id == current_user.id)
            & (models.FriendRequest.to_user_id == target.id),
            (models.FriendRequest.from_user_id == target.id)
            & (models.FriendRequest.to_user_id == current_user.id),
        )
    ).delete(synchronize_session=False)

    db.query(models.PartnerLinkInvite).filter(
        models.PartnerLinkInvite.status == models.PartnerLinkInviteStatus.pending,
        or_(
            (models.PartnerLinkInvite.from_user_id == current_user.id)
            & (models.PartnerLinkInvite.to_user_id == target.id),
            (models.PartnerLinkInvite.from_user_id == target.id)
            & (models.PartnerLinkInvite.to_user_id == current_user.id),
        ),
    ).delete(synchronize_session=False)

    # Unseen "watch this tonight" suggestions between the two. Seen ones
    # are left: they're already part of someone's history.
    db.query(models.Suggestion).filter(
        models.Suggestion.seen == 0,
        or_(
            (models.Suggestion.sender_id == current_user.id)
            & (models.Suggestion.receiver_id == target.id),
            (models.Suggestion.sender_id == target.id)
            & (models.Suggestion.receiver_id == current_user.id),
        ),
    ).delete(synchronize_session=False)

    db.commit()
    return SimpleMessageOut(message=f"{target.username} is blocked")


@router.delete("/blocks/{user_id}", status_code=204)
def unblock_user(
    user_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Unblocking restores visibility, not the friendship — that has to
    be asked for again. Quietly re-friending people on unblock would
    undo a decision nobody made twice."""
    row = db.query(models.UserBlock).filter_by(
        blocker_id=current_user.id, blocked_id=user_id
    ).first()
    if row is None:
        raise HTTPException(status_code=404, detail="That account isn't blocked")
    db.delete(row)
    db.commit()


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

_TARGET_TYPES = {t.value for t in models.ReportTargetType}
_REASONS = {r.value for r in models.ReportReason}


def _snapshot_target(db: Session, target_type: str, target_id: str | None, user: models.User) -> str | None:
    """Freezes what's being complained about at filing time.

    Without this, the obvious attack on a moderation queue is: post
    something abusive, wait to be reported, edit it to something bland
    before anyone opens the queue, and the report reads as a false
    accusation. The snapshot also keeps the report meaningful after the
    content — or the whole account — is deleted.
    """
    try:
        if target_type == models.ReportTargetType.user.value:
            return "\n".join(
                filter(None, [
                    f"username: {user.username}",
                    f"display_name: {user.display_name or '—'}",
                    f"status_text: {user.status_text or '—'}",
                    f"avatar: {user.avatar_url or user.avatar_preset or '—'}",
                ])
            )
        if not target_id:
            return None
        if target_type == models.ReportTargetType.diary_entry.value:
            entry = db.get(models.DiaryEntry, target_id)
            if entry is None:
                return None
            title = entry.title_ru or entry.title_en or entry.media_id
            return f"title: {title}\nnote: {entry.note or '—'}\nmood_tags: {entry.mood_tags or []}"
        if target_type == models.ReportTargetType.activity_event.value:
            event = db.get(models.ActivityEvent, target_id)
            return None if event is None else f"{event.verb}: {event.media_title}"
        if target_type == models.ReportTargetType.list.value:
            lst = db.get(models.UserList, target_id)
            return None if lst is None else f"name: {lst.name}\ndescription: {lst.description or '—'}"
    except Exception:  # noqa: BLE001 — a snapshot failing must never block a report
        return None
    return None


@router.post("/reports", response_model=ReportOut, status_code=201)
def create_report(
    payload: ReportCreateRequest,
    request: Request,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Files a complaint.

    Available to a suspended account (get_current_user, not
    get_active_user) on purpose: someone under a moderation decision can
    still be on the receiving end of abuse, and taking away their ability
    to say so would be a straightforward way to weaponise a false report.
    """
    report_limiter.check(db, _client_key(request))

    if payload.target_type not in _TARGET_TYPES:
        raise HTTPException(status_code=400, detail="Unknown report target")
    if payload.reason not in _REASONS:
        raise HTTPException(status_code=400, detail="Unknown report reason")
    if payload.reported_user_id == current_user.id:
        raise HTTPException(status_code=400, detail="You can't report yourself")

    target_user = db.get(models.User, payload.reported_user_id)
    if target_user is None:
        raise HTTPException(status_code=404, detail="No such account")

    target_id = payload.target_id if payload.target_type != models.ReportTargetType.user.value else None

    # This SELECT-then-insert has a TOCTOU race under two truly
    # concurrent identical requests (double-tap during a network retry,
    # say) — it is not by itself what guarantees one report per
    # (reporter, target). The actual guarantee is a database-level
    # constraint: on Postgres, an expression unique index on
    # (reporter_id, target_type, COALESCE(target_id, ''), reported_user_id)
    # — see migrations/versions/a7d3f1e08b45 and models.Report's own
    # __table_args__ comment for why a plain UniqueConstraint doesn't
    # work here (target_id is NULL for every `user`-type report, and SQL
    # never considers two NULLs equal). This check exists so the common,
    # non-racing case gets back the existing report instead of a
    # duplicate-key error.
    existing = (
        db.query(models.Report)
        .filter_by(
            reporter_id=current_user.id,
            target_type=models.ReportTargetType(payload.target_type),
            target_id=target_id,
            reported_user_id=target_user.id,
        )
        .first()
    )
    if existing is not None:
        # Not an error. The person did what they meant to do, the
        # complaint is on file, and an error here just teaches people
        # their report didn't go through.
        return _report_out(existing, target_user.username)

    report = models.Report(
        reporter_id=current_user.id,
        reported_user_id=target_user.id,
        target_type=models.ReportTargetType(payload.target_type),
        target_id=target_id,
        reason=models.ReportReason(payload.reason),
        details=(payload.details or "").strip() or None,
        target_snapshot=_snapshot_target(db, payload.target_type, target_id, target_user),
        reported_username_snapshot=target_user.username,
        due_at=datetime.now(timezone.utc) + timedelta(hours=settings.report_sla_hours),
    )
    db.add(report)
    try:
        db.commit()
    except IntegrityError:
        # Lost the race described above: another request for the exact
        # same (reporter, target) committed between our SELECT and our
        # INSERT. The database did its job — this just turns that into
        # the same "here's your existing report" response the common
        # case gets, instead of a raw 500.
        db.rollback()
        existing = (
            db.query(models.Report)
            .filter_by(
                reporter_id=current_user.id,
                target_type=models.ReportTargetType(payload.target_type),
                target_id=target_id,
                reported_user_id=target_user.id,
            )
            .first()
        )
        if existing is not None:
            return _report_out(existing, target_user.username)
        raise  # Some other integrity error — don't swallow it silently.
    db.refresh(report)
    return _report_out(report, target_user.username)


def _report_out(report: models.Report, reported_username: str | None) -> ReportOut:
    return ReportOut(
        id=report.id,
        target_type=report.target_type.value,
        target_id=report.target_id,
        reason=report.reason.value,
        details=report.details,
        status=report.status.value,
        created_at=report.created_at,
        due_at=report.due_at,
        resolved_at=report.resolved_at,
        action_taken=report.action_taken,
        reported_username=reported_username or report.reported_username_snapshot,
    )


@router.get("/reports", response_model=list[ReportOut])
def list_my_reports(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """What this person reported and what came of it. Closing the loop
    matters more than it looks: a report flow that never says anything
    back trains people to stop using it, and "we looked at this" is most
    of what someone wants after reporting abuse."""
    rows = (
        db.query(models.Report)
        .filter(models.Report.reporter_id == current_user.id)
        .order_by(models.Report.created_at.desc())
        .limit(50)
        .all()
    )
    return [_report_out(r, r.reported_username_snapshot) for r in rows]


# ---------------------------------------------------------------------------
# Moderator queue
# ---------------------------------------------------------------------------

@router.get("/admin/reports", response_model=list[ReportAdminOut])
def admin_list_reports(
    status_filter: str = Query("pending", alias="status"),
    limit: int = Query(50, ge=1, le=200),
    _admin: models.User = Depends(require_admin_user),
    db: Session = Depends(get_db),
):
    """The queue, oldest deadline first.

    Sorted by `due_at` rather than `created_at` so the ordering *is* the
    24-hour commitment — whatever is closest to breaching is at the top,
    and `overdue` marks anything that already has.
    """
    query = db.query(models.Report)
    if status_filter != "all":
        try:
            query = query.filter(models.Report.status == models.ReportStatus(status_filter))
        except ValueError:
            raise HTTPException(status_code=400, detail="Unknown status filter")

    rows = query.order_by(models.Report.due_at.asc().nullslast()).limit(limit).all()

    reporter_ids = {r.reporter_id for r in rows if r.reporter_id}
    names = dict(
        db.query(models.User.id, models.User.username)
        .filter(models.User.id.in_(reporter_ids))
        .all()
    ) if reporter_ids else {}

    now = datetime.now(timezone.utc)
    out = []
    for r in rows:
        base = _report_out(r, r.reported_username_snapshot)
        out.append(ReportAdminOut(
            **base.model_dump(),
            reporter_username=names.get(r.reporter_id),
            reported_user_id=r.reported_user_id,
            target_snapshot=r.target_snapshot,
            overdue=bool(
                r.status == models.ReportStatus.pending and r.due_at is not None and r.due_at < now
            ),
        ))
    return out


_ACTIONS = {"none", "content_removed", "user_suspended", "user_banned"}


@router.post("/admin/reports/{report_id}/resolve", response_model=ReportAdminOut)
def admin_resolve_report(
    report_id: str,
    payload: ReportResolveRequest,
    admin: models.User = Depends(require_admin_user),
    db: Session = Depends(get_db),
):
    """Closes a report and applies whatever was decided.

    Suspension is not a sign-in block — see app/deps.py::get_active_user.
    A suspended account can still read and export its own diary; what it
    loses is the ability to be seen by or reach anyone else. Confiscating
    years of someone's personal archive over a UGC complaint is a
    punishment out of all proportion to the offence and one an appeal
    can't undo after the fact.

    Removing content deletes the reported row outright rather than
    hiding it. A soft-delete flag would need every read path in the app
    to learn about it, which is exactly the kind of change that ships
    with three places forgotten.
    """
    if payload.action_taken not in _ACTIONS:
        raise HTTPException(status_code=400, detail="Unknown action")

    report = db.get(models.Report, report_id)
    if report is None:
        raise HTTPException(status_code=404, detail="No such report")
    if report.status != models.ReportStatus.pending:
        raise HTTPException(status_code=400, detail="That report is already resolved")

    if payload.action_taken == "content_removed":
        _remove_target(db, report)
    elif payload.action_taken in ("user_suspended", "user_banned"):
        target = db.get(models.User, report.reported_user_id) if report.reported_user_id else None
        if target is not None:
            target.suspended_at = datetime.now(timezone.utc)
            target.suspended_until = (
                datetime.now(timezone.utc) + timedelta(days=payload.suspend_days)
                if payload.action_taken == "user_suspended" and payload.suspend_days
                else None
            )
            target.suspension_reason = (payload.note or "").strip()[:200] or report.reason.value
            # Ends every session immediately — a suspension that only
            # takes effect at next sign-in isn't a suspension.
            target.token_version = int(target.token_version or 0) + 1
            db.query(models.RefreshSession).filter(
                models.RefreshSession.user_id == target.id,
                models.RefreshSession.revoked_at.is_(None),
            ).update(
                {"revoked_at": datetime.now(timezone.utc), "revoked_reason": "suspended"},
                synchronize_session=False,
            )

    report.status = (
        models.ReportStatus.dismissed
        if payload.action_taken == "none"
        else models.ReportStatus.actioned
    )
    report.action_taken = payload.action_taken
    report.resolution_note = (payload.note or "").strip() or None
    report.resolved_at = datetime.now(timezone.utc)
    report.resolved_by_id = admin.id
    db.commit()
    db.refresh(report)

    base = _report_out(report, report.reported_username_snapshot)
    return ReportAdminOut(
        **base.model_dump(),
        reporter_username=None,
        reported_user_id=report.reported_user_id,
        target_snapshot=report.target_snapshot,
        overdue=False,
    )


def _remove_target(db: Session, report: models.Report) -> None:
    """Deletes the specific piece of content a report was about.

    A report against the *account* (target_type "user") removes the
    offending profile fields — display name, status line, avatar —
    rather than the account, since the account itself isn't content and
    deleting it is what suspension/ban is for.
    """
    if report.target_type == models.ReportTargetType.user:
        user = db.get(models.User, report.reported_user_id) if report.reported_user_id else None
        if user is not None:
            user.display_name = None
            user.status_text = None
            user.avatar_url = None
            user.avatar_preset = None
        return

    if not report.target_id:
        return

    model = {
        models.ReportTargetType.diary_entry: models.DiaryEntry,
        models.ReportTargetType.activity_event: models.ActivityEvent,
        models.ReportTargetType.list: models.UserList,
    }.get(report.target_type)
    if model is None:
        return

    row = db.get(model, report.target_id)
    if row is None:
        return
    if model is models.DiaryEntry:
        # The evening itself is the person's own record of their life;
        # only the free text someone complained about goes.
        row.note = None
        row.mood_tags = []
        return
    db.delete(row)
