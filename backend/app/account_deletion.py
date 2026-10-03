"""Deleting an account, and handing someone everything in it first.

Both halves of the same obligation, so they live together:

  - **Erasure.** App Store review guideline 5.1.1(v) has required
    in-app account deletion since June 2022; GDPR art. 17 and 152-ФЗ
    require it regardless of where the app is distributed. Nothing in
    this API could do it before — and, more to the point, nothing
    *could have*: not one of the 46 foreign keys in models.py carried an
    `ondelete`, so `DELETE FROM users WHERE id = ...` would have been
    refused by roughly two dozen referential-integrity constraints. That
    is fixed in models.py and in the accompanying migration; this module
    is the part that decides what "delete" actually means for data that
    isn't only yours.
  - **Portability.** GDPR art. 20. Also, unusually for a compliance
    requirement, a genuinely good feature: this app's whole value
    proposition is an archive of evenings built up over years, and
    "you can take it with you whenever you like" is a better answer to
    "what if this app disappears" than any promise.

**Two-phase deletion.** DELETE /auth/account marks the row and revokes
every session; `purge_user` destroys it after
`settings.account_purge_after_days`. The grace period isn't hedging —
it's the difference between a delete button people can actually bring
themselves to press and one they can't. The account is invisible to
everyone else from the moment of the request (see app/blocking.py::
hidden_user_ids and app/deps.py), so the delay is never visible to
anybody but the person who asked.

**What survives a purge, and why.** Three categories, each a deliberate
decision rather than an oversight:

  - *Other people's rows that mention you.* A friend's DiaryEntry with
    `watched_with_username` set is their memory of their own evening;
    it holds a snapshot of your username, not a link to your row, and it
    stays. Deleting other people's diaries because you left is not what
    anyone means by "delete my account".
  - *Moderation history.* models.Report's FKs to `users` are SET NULL,
    alone among this schema's user references. A complaint filed about an
    account has to outlive that account, or deleting yourself becomes a
    way to erase the evidence — and the person who reported you keeps
    their complaint even if *they* leave. The snapshot columns on that
    table are what keep the row meaningful once the names are gone.
  - *Aggregate counters nobody can trace back to you.* OutboundClick has
    no user_id at all by design (see its docstring) and is untouched
    here.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import or_
from sqlalchemy.orm import Session

from app import models
from app.config import settings

logger = logging.getLogger("uvicorn.error")


# ---------------------------------------------------------------------------
# Soft delete
# ---------------------------------------------------------------------------

def request_deletion(db: Session, user: models.User) -> datetime:
    """Marks the account deleted and ends every session. Returns the date
    the rows will actually be destroyed, which is what the client shows
    in its confirmation."""
    now = datetime.now(timezone.utc)
    purge_after = now + timedelta(days=settings.account_purge_after_days)

    user.deleted_at = now
    user.purge_after = purge_after
    # Every existing access token dies here, not when it expires — see
    # app/deps.py's `ver` check. Without this, a token issued five
    # minutes before the deletion request would keep working for another
    # half hour against an account that no longer exists as far as
    # everyone else is concerned.
    user.token_version = int(user.token_version or 0) + 1

    revoke_all_sessions(db, user.id, reason="account_deleted")

    # Pending outbound friend requests and co-viewing invites are
    # withdrawn immediately rather than left for the purge. They're an
    # active ask of another person — leaving them sitting in someone's
    # inbox for a month from an account that's gone is a bug, not
    # restorable state worth preserving. Accepted friendships are left
    # alone: those come back intact if the deletion is undone.
    db.query(models.FriendRequest).filter(
        models.FriendRequest.status == models.FriendRequestStatus.pending,
        or_(
            models.FriendRequest.from_user_id == user.id,
            models.FriendRequest.to_user_id == user.id,
        ),
    ).delete(synchronize_session=False)
    db.query(models.PartnerLinkInvite).filter(
        models.PartnerLinkInvite.status == models.PartnerLinkInviteStatus.pending,
        or_(
            models.PartnerLinkInvite.from_user_id == user.id,
            models.PartnerLinkInvite.to_user_id == user.id,
        ),
    ).delete(synchronize_session=False)

    db.commit()
    return purge_after


def restore(db: Session, user: models.User) -> None:
    """Undoes a deletion request inside the grace window. Nothing to
    rebuild — the rows were never touched — so this is just clearing the
    two markers. The token_version bump from `request_deletion` is
    deliberately NOT rolled back: whoever asked for the deletion had
    every session ended, and coming back should mean signing in fresh,
    not reviving whatever tokens were live at the time."""
    user.deleted_at = None
    user.purge_after = None
    db.commit()


def revoke_all_sessions(db: Session, user_id: str, reason: str, keep_session_id: str | None = None) -> int:
    """Marks every live refresh session revoked. `keep_session_id` is for
    "sign out my other devices", where the device issuing the command
    should stay signed in — without it, changing your password from your
    phone would immediately sign your phone out too, which reads as a
    bug every single time."""
    query = db.query(models.RefreshSession).filter(
        models.RefreshSession.user_id == user_id,
        models.RefreshSession.revoked_at.is_(None),
    )
    if keep_session_id:
        query = query.filter(models.RefreshSession.id != keep_session_id)
    count = query.update(
        {"revoked_at": datetime.now(timezone.utc), "revoked_reason": reason},
        synchronize_session=False,
    )
    return count


# ---------------------------------------------------------------------------
# Hard delete
# ---------------------------------------------------------------------------

def _reassign_shared_structures(db: Session, user_id: str) -> None:
    """Hands over anything jointly owned before the row disappears.

    `partner_links.owner_id` is ON DELETE CASCADE — the whole co-viewing
    circle goes when its owner does. That's the correct backstop (a link
    with no owner is not a valid row) and the wrong *outcome* whenever
    anyone else is still in the circle: their shared co-viewing list,
    their voting history, and their shared-diary tagging would all vanish
    because someone else left. So ownership moves to a remaining member
    first, and the cascade only ever fires for a circle that has nobody
    left in it.

    This is exactly the kind of thing a database constraint can't decide
    and application code has to.
    """
    links = (
        db.query(models.PartnerLink)
        .filter(models.PartnerLink.owner_id == user_id)
        .all()
    )
    for link in links:
        successor: str | None = None
        if link.partner_id and link.partner_id != user_id:
            successor = link.partner_id
        else:
            extra = (
                db.query(models.PartnerLinkMember)
                .filter(
                    models.PartnerLinkMember.link_id == link.id,
                    models.PartnerLinkMember.user_id != user_id,
                )
                .first()
            )
            if extra is not None:
                successor = extra.user_id

        if successor is None:
            # Nobody left — let the cascade take it.
            continue

        link.owner_id = successor
        if link.partner_id == successor:
            # The promoted member vacates the second seat; whoever the
            # next extra member is (if any) moves up into it, so a
            # three-person circle stays a three-person circle rather than
            # losing a seat every time someone leaves.
            promoted = (
                db.query(models.PartnerLinkMember)
                .filter(
                    models.PartnerLinkMember.link_id == link.id,
                    models.PartnerLinkMember.user_id != user_id,
                )
                .order_by(models.PartnerLinkMember.joined_at)
                .first()
            )
            link.partner_id = promoted.user_id if promoted else None
            if promoted is not None:
                db.delete(promoted)

    # The leaving account's own seat in someone else's circle.
    db.query(models.PartnerLink).filter(models.PartnerLink.partner_id == user_id).update(
        {"partner_id": None}, synchronize_session=False
    )
    db.query(models.PartnerLinkMember).filter(
        models.PartnerLinkMember.user_id == user_id
    ).delete(synchronize_session=False)

    db.flush()


def _erase_analytics(db: Session, user_id: str) -> None:
    """Deletes every analytics event tied to this account, directly (its
    user_id) or through a device it signed in on (that device's anon_id).
    See purge_user for why both."""
    device_ids = (
        db.query(models.AnalyticsEvent.anon_id)
        .filter(models.AnalyticsEvent.user_id == user_id)
        .distinct()
        .subquery()
    )
    db.query(models.AnalyticsEvent).filter(
        or_(
            models.AnalyticsEvent.user_id == user_id,
            models.AnalyticsEvent.anon_id.in_(db.query(device_ids.c.anon_id)),
        )
    ).delete(synchronize_session=False)


def purge_user(db: Session, user: models.User) -> None:
    """Destroys the account for good. Everything downstream goes with it
    through the ON DELETE CASCADE rules now on the schema — this function
    only has to handle the cases where a cascade would be *wrong*, which
    is the reassignment above plus the moderation snapshots below."""
    user_id = user.id
    username = user.username

    _reassign_shared_structures(db, user_id)

    # Product analytics (models.AnalyticsEvent) deliberately has no FK to
    # users, so the ON DELETE CASCADE rules above don't reach it — it is
    # erased explicitly. Both the rows carrying this account's id AND every
    # row from any device this account signed in on: the events a device
    # sent before login (onboarding, the login screen itself) carry only
    # the device's anon_id, and leaving those behind would keep a
    # trail that was, until a minute ago, attributable to this person.
    _erase_analytics(db, user_id)

    # Reports keep their meaning after the FKs go null — see this
    # module's docstring. Filling the snapshot in now rather than at
    # filing time for reports that predate the snapshot column.
    db.query(models.Report).filter(
        models.Report.reported_user_id == user_id,
        models.Report.reported_username_snapshot.is_(None),
    ).update({"reported_username_snapshot": username}, synchronize_session=False)

    db.delete(user)
    db.commit()
    logger.info("purged account %s (%s)", user_id, username)


def purge_due_accounts(db: Session, limit: int = 100) -> int:
    """Everything whose grace period has run out. Called from startup
    (settings.purge_on_startup) and from scripts/purge_deleted_accounts.py.

    Batched and committed per account rather than in one transaction: a
    single account that fails to delete for some unforeseen reason
    shouldn't block every other pending deletion behind it.
    """
    now = datetime.now(timezone.utc)
    due = (
        db.query(models.User)
        .filter(
            models.User.deleted_at.isnot(None),
            models.User.purge_after.isnot(None),
            models.User.purge_after <= now,
        )
        .limit(limit)
        .all()
    )
    purged = 0
    for user in due:
        try:
            purge_user(db, user)
            purged += 1
        except Exception:  # noqa: BLE001 — one bad row must not stop the rest
            db.rollback()
            logger.exception("failed to purge account %s", user.id)
    return purged


def sweep_expired_artifacts(db: Session) -> None:
    """Housekeeping for the two tables that accumulate dead rows: expired
    or revoked refresh sessions, and consumed or expired one-time links.

    Retention is deliberately not zero. A revoked session is kept for
    30 days so the "where you're signed in" screen can still answer "this
    device was signed out on the 3rd", which is the whole point of having
    that screen after a device is lost.
    """
    cutoff = datetime.now(timezone.utc) - timedelta(days=30)
    db.query(models.RefreshSession).filter(
        or_(
            models.RefreshSession.expires_at < cutoff,
            models.RefreshSession.revoked_at < cutoff,
        )
    ).delete(synchronize_session=False)
    db.query(models.AccountToken).filter(
        or_(
            models.AccountToken.expires_at < cutoff,
            models.AccountToken.consumed_at < cutoff,
        )
    ).delete(synchronize_session=False)
    # Analytics retention — see Settings.analytics_retention_days. Rides
    # along here because this is already the app's one housekeeping hook
    # (startup + scripts/purge_deleted_accounts.py) and analytics_events is
    # the table that grows fastest.
    if settings.analytics_retention_days > 0:
        analytics_cutoff = datetime.now(timezone.utc) - timedelta(days=settings.analytics_retention_days)
        db.query(models.AnalyticsEvent).filter(
            models.AnalyticsEvent.ts < analytics_cutoff
        ).delete(synchronize_session=False)
    db.commit()


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

def _iso(value: Any) -> Any:
    return value.isoformat() if isinstance(value, datetime) else value


def _row(obj: Any, *fields: str) -> dict:
    return {f: _iso(getattr(obj, f, None)) for f in fields}


def _enum(value: Any) -> Any:
    return value.value if hasattr(value, "value") else value


def build_export(db: Session, user: models.User) -> dict:
    """Everything this account holds, as one JSON document.

    Two rules shape what goes in:

      - **Readable, not a table dump.** Enum values become their strings,
        datetimes become ISO-8601, and the structure follows the app's
        own vocabulary (diary, shelves, lists) rather than the schema's.
        The obligation is to give someone their data in a usable form,
        and a raw dump of internal column names isn't that.
      - **Nothing about anyone else.** Friends appear as usernames,
        because who you're friends with is your data too — but their
        diaries, ratings and notes do not, even where this account can
        see them in the app. Someone else's evening is not yours to
        export. Same rule for the shared diary: your entries in it are
        here, your partner's are not.
    """
    watchlist = db.query(models.WatchlistEntry).filter_by(user_id=user.id).all()
    diary = (
        db.query(models.DiaryEntry)
        .filter_by(user_id=user.id)
        .order_by(models.DiaryEntry.watched_at.desc())
        .all()
    )
    episodes = db.query(models.EpisodeProgress).filter_by(user_id=user.id).all()
    lists = db.query(models.UserList).filter_by(user_id=user.id).all()
    activity = (
        db.query(models.ActivityEvent)
        .filter_by(user_id=user.id)
        .order_by(models.ActivityEvent.created_at.desc())
        .all()
    )
    sincerity = (
        db.query(models.SincerityTransaction)
        .filter_by(user_id=user.id)
        .order_by(models.SincerityTransaction.created_at.desc())
        .all()
    )
    challenges = db.query(models.ChallengeProgress).filter_by(user_id=user.id).all()
    premium = db.get(models.UserPremiumState, user.id)

    friend_rows = (
        db.query(models.FriendRequest)
        .filter(
            models.FriendRequest.status == models.FriendRequestStatus.accepted,
            or_(
                models.FriendRequest.from_user_id == user.id,
                models.FriendRequest.to_user_id == user.id,
            ),
        )
        .all()
    )
    friend_ids = [
        r.to_user_id if r.from_user_id == user.id else r.from_user_id for r in friend_rows
    ]
    friend_names = dict(
        db.query(models.User.id, models.User.username)
        .filter(models.User.id.in_(friend_ids))
        .all()
    ) if friend_ids else {}

    blocked = db.query(models.UserBlock).filter_by(blocker_id=user.id).all()
    blocked_names = dict(
        db.query(models.User.id, models.User.username)
        .filter(models.User.id.in_([b.blocked_id for b in blocked]))
        .all()
    ) if blocked else {}

    return {
        "export_format_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "note": (
            "Everything tanè holds about this account. Other people's diary "
            "entries, ratings and notes are deliberately not included, even "
            "where this account could see them in the app."
        ),
        "account": {
            **_row(
                user, "id", "username", "display_name", "status_text", "email",
                "email_verified", "created_at", "avatar_preset", "avatar_url",
                "sincerity_balance", "discoverable", "eula_version", "eula_accepted_at",
            ),
            "privacy": {
                "watched": user.privacy_watched,
                "watching": user.privacy_watching,
                "planned": user.privacy_planned,
                "favorites": user.privacy_favorites,
                "sincerity_visible_to_friends": user.sincerity_visible_to_friends,
            },
            "invite_code": user.invite_code,
            "pinned_achievement_ids": user.pinned_achievement_ids,
            "top_favorite_picks": user.top_favorite_picks or [],
        },
        "premium": _row(
            premium, "is_premium", "purchased_at", "premium_expires_at",
            "ai_asks_used", "ai_asks_month",
            "cancelled_at", "cancel_effective_at", "paused_until", "winback_used_at",
        ) | {
            "plan_kind": _enum(premium.plan_kind),
            "plan_duration": _enum(premium.plan_duration),
        } if premium else None,
        "diary": [
            _row(
                e, "id", "media_id", "source", "title_ru", "title_en", "season",
                "episode", "episodes_watched", "rating", "note", "watched_at",
                "created_at", "is_rewatch", "runtime_minutes", "year", "director",
                "country", "watched_with_username", "watched_together",
            ) | {
                "media_type": _enum(e.media_type),
                "mood_tags": e.mood_tags or [],
                "favorite_cast": e.favorite_cast or [],
                "genres": e.genres or [],
                "shared_with_circle": e.shared_link_id is not None,
            }
            for e in diary
        ],
        "shelves": [
            _row(
                e, "id", "media_id", "source", "title_ru", "title_en", "year",
                "user_rating", "note", "is_favorite", "watched_at", "drop_reason",
                "created_at", "updated_at", "runtime_minutes",
            ) | {
                "media_type": _enum(e.media_type),
                "status": _enum(e.status),
                "genres": e.genres or [],
                "mood_tags": e.mood_tags or [],
            }
            for e in watchlist
        ],
        "episode_progress": [
            _row(e, "media_id", "source", "season", "episode", "rating", "note", "watched_at")
            for e in episodes
        ],
        "lists": [
            {
                **_row(lst, "id", "name", "description", "created_at", "updated_at"),
                "items": [
                    _row(i, "media_id", "source", "title_ru", "title_en", "year", "added_at")
                    | {"media_type": _enum(i.media_type)}
                    for i in lst.items
                ],
            }
            for lst in lists
        ],
        "activity": [
            _row(a, "verb", "media_title", "media_id", "source", "rating", "created_at")
            | {"media_type": _enum(a.media_type)}
            for a in activity
        ],
        "friends": [
            {"username": friend_names.get(fid), "user_id": fid}
            for fid in friend_ids
            if friend_names.get(fid)
        ],
        "blocked": [
            {"username": blocked_names.get(b.blocked_id), "blocked_at": _iso(b.created_at)}
            for b in blocked
        ],
        "sincerity_ledger": [
            _row(t, "delta", "note", "created_at") | {"reason": _enum(t.reason)}
            for t in sincerity
        ],
        "challenges": [
            _row(c, "challenge_id", "period_key", "completed_at", "claimed_at")
            for c in challenges
        ],
    }
