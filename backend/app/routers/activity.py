from typing import List, Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from app.blocking import hidden_user_ids
from app.database import get_db
from app import models
from app.deps import get_current_user
from app.schemas import ActivityFeedOut, ActivityItem

router = APIRouter(prefix="/activity", tags=["activity"])

# Matches the page size routers/sincerity.py uses for the same
# cursor-pagination shape (see get_activity below).
_PAGE_SIZE = 40

# Maps an ActivityEvent.verb to the shelf-privacy column it's gated by
# (see models.User.privacy_watched/privacy_watching/privacy_planned) —
# "rewatched" reads as "watched" for privacy purposes, same shelf either
# way. A verb not in this map (there shouldn't be one, but a future verb
# added without updating this list) is treated as "planned" — the most
# visible-by-default-but-still-a-real-shelf choice, so a forgotten verb
# never accidentally *skips* the privacy check entirely.
_VERB_PRIVACY_FIELD = {
    "watched": "privacy_watched",
    "rewatched": "privacy_watched",
    "added to watch later": "privacy_planned",
    "marked as watched": "privacy_watched",
}


def _privacy_field_for_verb(verb: str) -> str:
    return _VERB_PRIVACY_FIELD.get(verb, "privacy_planned")


def visible_to_friend(user: models.User, verb: str) -> bool:
    """Whether `user`'s event with this verb may be shown to someone who
    is already an accepted friend of theirs — "nobody" hides it even from
    friends, "friends"/"everyone" both allow it (the two only differ for
    a non-friend viewer, see routers/friends.py::get_suggested_friends)."""
    level = getattr(user, _privacy_field_for_verb(verb), "everyone") or "everyone"
    return level != "nobody"


def visible_to_everyone(user: models.User, verb: str) -> bool:
    level = getattr(user, _privacy_field_for_verb(verb), "everyone") or "everyone"
    return level == "everyone"


def _friend_ids(db: Session, user_id: str) -> List[str]:
    """Every account with an accepted FriendRequest row against `user_id`
    — see routers/friends.py's own docstring for why "accepted" *is* the
    friendship, with no separate friendship table to keep in sync.
    """
    rows = (
        db.query(models.FriendRequest)
        .filter(
            models.FriendRequest.status == models.FriendRequestStatus.accepted,
            or_(
                models.FriendRequest.from_user_id == user_id,
                models.FriendRequest.to_user_id == user_id,
            ),
        )
        .all()
    )
    return [
        (r.to_user_id if r.from_user_id == user_id else r.from_user_id)
        for r in rows
    ]


def friend_ids(db: Session, user_id: str) -> List[str]:
    """Public alias of _friend_ids, for callers outside this module — see
    routers/diary.py::log_entry's friend-activity push trigger, which
    needs this list but has no other reason to import from activity.py."""
    return _friend_ids(db, user_id)


def item_from_event(e: models.ActivityEvent, who: str) -> ActivityItem:
    user = e.user
    return ActivityItem(
        id=e.id,
        who=who,
        text=f'{e.verb} "{e.media_title}"',
        media_type=e.media_type.value if hasattr(e.media_type, "value") else e.media_type,
        created_at=e.created_at.isoformat() if e.created_at else "",
        user_id=e.user_id,
        username=user.username if user else None,
        display_name=user.display_name if user else None,
        avatar_preset=user.avatar_preset if user else None,
        avatar_url=user.avatar_url if user else None,
        verb=e.verb,
        media_title=e.media_title,
        media_id=e.media_id,
        source=e.source,
        poster_url=e.poster_url,
        rating=e.rating,
    )


def _visible_item_or_none(e: models.ActivityEvent, current_user_id: str) -> Optional[ActivityItem]:
    """Turns one row into an ActivityItem, or None if it's a friend's
    event that friend has hidden from this shelf's privacy setting. Own
    events are always visible."""
    if e.user_id == current_user_id:
        return item_from_event(e, "You")
    if not e.user or not visible_to_friend(e.user, e.verb):
        return None
    who = e.user.display_name or e.user.username
    return item_from_event(e, who)


@router.get("", response_model=ActivityFeedOut)
def get_activity(
    before: Optional[str] = Query(
        default=None, description="activity event id to page before, for older activity"
    ),
    limit: int = Query(default=_PAGE_SIZE, ge=1, le=100),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Every own event, plus friends' events, merged into one
    chronological feed — used both by the small Home teaser card and by
    the full-screen friends activity feed (see FriendsActivityFeedScreen
    on mobile). Friends' events are filtered by that friend's own
    per-shelf privacy setting, same as their profile/collections would
    be — someone who's set a shelf to "nobody" won't show up here for
    any friend, "friends"/"everyone" both show.

    Blocking has to bite here too, not just on the profile screen: a
    standing friendship survives a block (blocking removes the
    friendship row, but a block placed on someone in a shared
    co-viewing circle doesn't dissolve the circle — see
    routers/moderation.py::block_user), and a deleted account's rows
    are still physically present for the length of its grace period.
    Either would otherwise keep showing up in this feed, so blocked/
    deleted/suspended friend ids are dropped before the query even
    runs.

    Cursor-paginated the same way GET /sincerity/me is (see
    routers/sincerity.py), with one added wrinkle: privacy filtering
    happens *after* the query runs, so a straight `limit` on the SQL
    query wouldn't reliably produce `limit` visible items. Instead this
    fetches in batches and keeps going until it has `limit + 1` visible
    items (the "+1" is the same has-more probe sincerity.py uses) or
    genuinely runs out of rows — the same over-fetch-and-filter shape
    routers/friends.py::_visible_activity_for_profile already uses for
    one profile's shelf, just looped here instead of done once.
    """
    hidden = hidden_user_ids(db, current_user.id)
    ids = [current_user.id] + [fid for fid in _friend_ids(db, current_user.id) if fid not in hidden]
    target = limit + 1

    items: List[ActivityItem] = []
    cursor = before
    exhausted = False

    while len(items) < target and not exhausted:
        # Overfetch: friend rows get thinned out by the privacy check
        # below, so asking for exactly what's still missing would make
        # this loop around far more often than necessary once a friend
        # has hidden most of their shelves.
        batch_size = (target - len(items)) * 3 + 10

        q = db.query(models.ActivityEvent).filter(models.ActivityEvent.user_id.in_(ids))
        if cursor:
            anchor = db.query(models.ActivityEvent).filter(models.ActivityEvent.id == cursor).first()
            if anchor is None:
                break
            q = q.filter(
                or_(
                    models.ActivityEvent.created_at < anchor.created_at,
                    and_(
                        models.ActivityEvent.created_at == anchor.created_at,
                        models.ActivityEvent.id < anchor.id,
                    ),
                )
            )

        rows = (
            q.order_by(models.ActivityEvent.created_at.desc(), models.ActivityEvent.id.desc())
            .limit(batch_size)
            .all()
        )
        if not rows:
            exhausted = True
            break

        for e in rows:
            item = _visible_item_or_none(e, current_user.id)
            if item is not None:
                items.append(item)
            cursor = e.id
            if len(items) >= target:
                break

        if len(rows) < batch_size:
            exhausted = True

    has_more = len(items) > limit
    return ActivityFeedOut(items=items[:limit], has_more=has_more)
