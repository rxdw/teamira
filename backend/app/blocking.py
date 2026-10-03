"""Who can see and reach whom.

Blocks are stored directionally (models.UserBlock: blocker -> blocked)
but enforced symmetrically. Every helper here asks "is there a block
between these two in *either* direction", never "did A block B", because
one-way enforcement leaks the block itself: if a blocked person could
still see your profile while you couldn't see theirs, the asymmetry
itself is the notification.

Every social read path imports from here rather than writing its own
join, so adding a new screen can't accidentally ship a hole. The two
shapes:

  - [is_blocked_between] for a single pair (profile screen, friend
    request, suggestion, partner invite).
  - [blocked_user_ids] for a list read (friend search, activity feed,
    "people you may know"), which needs one query and then a set
    membership test per candidate rather than N queries.

Deliberately **not** applied to a person's own historical data. A diary
entry that records watching something with someone you later blocked
stays in your diary; blocking is about what happens from now on, not a
retcon of your own archive.
"""

from __future__ import annotations

from typing import Iterable

from sqlalchemy import or_
from sqlalchemy.orm import Session

from app import models


def blocked_user_ids(db: Session, user_id: str) -> set[str]:
    """Every account `user_id` can't see and that can't see `user_id` —
    both the ones they blocked and the ones who blocked them, in one
    query."""
    rows = (
        db.query(models.UserBlock.blocker_id, models.UserBlock.blocked_id)
        .filter(
            or_(
                models.UserBlock.blocker_id == user_id,
                models.UserBlock.blocked_id == user_id,
            )
        )
        .all()
    )
    out: set[str] = set()
    for blocker_id, blocked_id in rows:
        out.add(blocked_id if blocker_id == user_id else blocker_id)
    return out


def is_blocked_between(db: Session, user_a: str, user_b: str) -> bool:
    if user_a == user_b:
        return False
    return (
        db.query(models.UserBlock.id)
        .filter(
            or_(
                (models.UserBlock.blocker_id == user_a) & (models.UserBlock.blocked_id == user_b),
                (models.UserBlock.blocker_id == user_b) & (models.UserBlock.blocked_id == user_a),
            )
        )
        .first()
        is not None
    )


def i_blocked_them(db: Session, blocker_id: str, blocked_id: str) -> bool:
    """The one place direction matters: the profile screen needs to show
    "unblock" to the person who did the blocking, and nothing at all to
    the person who was blocked."""
    return (
        db.query(models.UserBlock.id)
        .filter_by(blocker_id=blocker_id, blocked_id=blocked_id)
        .first()
        is not None
    )


def hidden_user_ids(db: Session, viewer_id: str) -> set[str]:
    """[blocked_user_ids] plus every account that shouldn't appear to
    anyone at all — deleted (still inside its restore window, so the rows
    are physically there) and suspended.

    This is the set every *list* endpoint filters against. A deleted
    account's rows survive until the purge job runs (see
    app/account_deletion.py), which is the right call for restorability
    and the wrong thing to show in a friends list in the meantime.
    """
    hidden = blocked_user_ids(db, viewer_id)
    invisible = (
        db.query(models.User.id)
        .filter(
            or_(
                models.User.deleted_at.isnot(None),
                models.User.suspended_at.isnot(None),
            )
        )
        .all()
    )
    hidden.update(row[0] for row in invisible)
    hidden.discard(viewer_id)
    return hidden


def visible_users_filter(viewer_id: str):
    """SQLAlchemy criteria for "rows about accounts a viewer is allowed
    to see", for the queries that can push the check down into SQL
    instead of filtering a fetched page in Python. Pair with a NOT IN on
    [blocked_user_ids] — kept separate because a correlated NOT EXISTS
    against user_blocks is far more expensive than one extra small
    query plus a set test.
    """
    return (
        models.User.id != viewer_id,
        models.User.deleted_at.is_(None),
        models.User.suspended_at.is_(None),
    )


def filter_out_blocked(rows: Iterable, hidden: set[str], key=lambda r: r.user_id):
    """Small convenience so feed-shaped code reads the same everywhere."""
    return [r for r in rows if key(r) not in hidden]
