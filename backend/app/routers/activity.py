from typing import List, Optional

from fastapi import APIRouter, Depends
from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.database import get_db
from app import models
from app.deps import get_current_user
from app.schemas import ActivityItem

router = APIRouter(prefix="/activity", tags=["activity"])

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


def item_from_event(e: models.ActivityEvent, who: str) -> ActivityItem:
    user = e.user
    return ActivityItem(
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


@router.get("", response_model=List[ActivityItem])
def get_activity(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Every own event, plus friends' events — used both by the small
    Home teaser card and by the full-screen friends activity feed (see
    FriendsActivityFeedScreen on mobile). Friends' events are filtered
    by that friend's own per-shelf privacy setting, same as their
    profile/collections would be — someone who's set a shelf to
    "nobody" won't show up here for any friend, "friends"/"everyone"
    both show.
    """
    own_events = (
        db.query(models.ActivityEvent)
        .filter(models.ActivityEvent.user_id == current_user.id)
        .order_by(models.ActivityEvent.created_at.desc())
        .limit(50)
        .all()
    )
    own_items = [item_from_event(e, "You") for e in own_events]

    friend_ids = _friend_ids(db, current_user.id)
    friend_items: List[ActivityItem] = []
    if friend_ids:
        friend_events = (
            db.query(models.ActivityEvent)
            .filter(models.ActivityEvent.user_id.in_(friend_ids))
            .order_by(models.ActivityEvent.created_at.desc())
            .limit(150)
            .all()
        )
        for e in friend_events:
            if not e.user or not visible_to_friend(e.user, e.verb):
                continue
            who = e.user.display_name or e.user.username
            friend_items.append(item_from_event(e, who))
            if len(friend_items) >= 50:
                break

    return own_items + friend_items
