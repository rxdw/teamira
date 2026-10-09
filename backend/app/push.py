"""Push notifications — Firebase Cloud Messaging (FCM), one API for both
iOS and Android (APNs credentials are configured on the Firebase project
itself, not here — see docs/push_notifications_setup.md).

Disabled entirely, safely, when settings.firebase_credentials_json is
empty (the default): every public function below returns 0/no-ops rather
than raising, the same "just works with nothing configured" shape as
Sentry (app/main.py) and S3 avatar storage (app/storage.py). firebase_admin
itself is only ever imported from inside _firebase_app() — never at module
load — so a deployment that never sets the credential doesn't need the
package to actually be importable, only listed in requirements.txt.

Two layers:
  - `PushService` — the actual send, given a db session and a
    already-loaded `models.User`. Used directly (and tested directly)
    wherever a request already has both on hand.
  - The `notify_*_background` functions below it — one per trigger this
    app fires (see each one's own docstring for where it's called from).
    Each opens and closes its own db session rather than reusing the
    request's, and is meant to be handed to FastAPI's BackgroundTasks
    exactly as-is: `background_tasks.add_task(push.notify_match, ...)`.
    This split exists because a request-scoped `Session` (the one
    `Depends(get_db)` hands a router) isn't safe to touch from a
    BackgroundTask — FastAPI runs those after the response is already on
    the wire, by which point that session may already be mid-teardown.
    Same reasoning as app/rate_limit.py's and app/cache.py's own
    `_session(db)` helpers, just always on the "open a fresh one" side of
    that choice rather than sometimes.

Every trigger point in this app calls these only *after* its own
db.commit() has already succeeded — see each router call site's own
comment. A push describing a row that turned out to get rolled back would
be worse than not sending one at all.
"""

from __future__ import annotations

import logging
from enum import Enum
from typing import Optional

from sqlalchemy.orm import Session

from app import models
from app.bi import Bi, normalize_lang, pick, years_en
from app.config import settings
from app.database import SessionLocal

logger = logging.getLogger(__name__)


class PushCategory(str, Enum):
    """The full set this app sends, and the only valid keys in
    User.notification_prefs — see that column's own docstring in
    models.py. String-valued so a value round-trips through
    PushLog.category / the preferences JSON as plain text, not an int
    a future reordering of this enum would silently reinterpret."""
    FRIEND_ACTIVITY = "friend_activity"
    FRIEND_REQUESTS = "friend_requests"
    PARTNER_ACTIVITY = "partner_activity"
    MATCHES = "matches"
    LEVEL_UPS = "level_ups"
    STREAK_REMINDERS = "streak_reminders"
    MEMORIES = "memories"
    NEW_EPISODES = "new_episodes"
    SUBSCRIPTION = "subscription"
    PAIR_ALBUM = "pair_album"
    CO_VIEW_ROOMS = "co_view_rooms"


# Human-readable label + one-line description per category, for the
# settings screen's toggle list (GET /push/preferences echoes these back
# rather than the mobile client hand-maintaining its own copy of this
# list — see routers/push.py::get_preferences).
CATEGORY_COPY: dict[PushCategory, tuple[str, str]] = {
    PushCategory.FRIEND_ACTIVITY: ("Друзья смотрят", "Когда друг оценивает что-то новое"),
    PushCategory.FRIEND_REQUESTS: ("Заявки в друзья", "Когда кто-то хочет с вами дружить"),
    PushCategory.PARTNER_ACTIVITY: ("Партнёр", "Активность связанного аккаунта"),
    PushCategory.MATCHES: ("Совпадения", "Когда вы оба выбрали один фильм"),
    PushCategory.LEVEL_UPS: ("Уровни", "Когда вы получаете новый уровень"),
    PushCategory.STREAK_REMINDERS: ("Напоминания о серии", "Вечером, если серия под угрозой"),
    PushCategory.MEMORIES: ("Воспоминания", "«Год назад вы смотрели…»"),
    PushCategory.NEW_EPISODES: ("Новые серии", "Когда выходит серия или релиз того, что вы отслеживаете"),
    PushCategory.SUBSCRIPTION: ("Подписка", "Конец бесплатного периода, пауза и предложения по подписке"),
    PushCategory.PAIR_ALBUM: ("Наш альбом", "Записки, капсулы и годовщины вдвоём"),
    PushCategory.CO_VIEW_ROOMS: ("Смотрим вместе", "Когда вас зовут в комнату совместного просмотра"),
}


def _pref_enabled(user: models.User, category: PushCategory) -> bool:
    """Opt-out model — a key missing from the JSON (every category, for
    every account that has never opened the notifications settings
    screen) means on. See models.User.notification_prefs's own
    docstring for why this direction and not the other."""
    prefs = user.notification_prefs or {}
    return bool(prefs.get(category.value, True))


_firebase_app_singleton = None


def _firebase_app():
    """Lazily builds (once per process) and returns the firebase_admin
    App this service sends through. Only ever called from
    PushService._send, which is itself only reached once
    settings.firebase_credentials_json has already been confirmed
    non-empty by every caller above it — so a malformed credential
    string surfaces as a clear JSONDecodeError/ValueError the first time
    a push is actually attempted, not a silent no-op."""
    global _firebase_app_singleton
    if _firebase_app_singleton is None:
        import json

        import firebase_admin
        from firebase_admin import credentials

        cred = credentials.Certificate(json.loads(settings.firebase_credentials_json))
        _firebase_app_singleton = firebase_admin.initialize_app(cred)
    return _firebase_app_singleton


class PushService:
    """Stateless — every method takes the db session and User(s) it needs
    as arguments rather than holding either. Safe to share one instance
    process-wide (see the module-level `push_service` below) since
    nothing here is per-request state."""

    def send_to_user(
        self,
        db: Session,
        user: models.User,
        category: PushCategory,
        title: str,
        body: str,
        data: Optional[dict] = None,
    ) -> int:
        """Sends to every device `user` has registered, unless push is
        unconfigured for this deployment or `user` has this category
        turned off. Returns how many devices Firebase confirmed delivery
        to (0 either way in those two skip cases — a caller that only
        cares "did this do anything" can treat 0 as "no, and that's
        fine", not as an error)."""
        if not settings.firebase_credentials_json:
            return 0
        if not _pref_enabled(user, category):
            return 0
        tokens = (
            db.query(models.PushToken)
            .filter(models.PushToken.user_id == user.id)
            .all()
        )
        if not tokens:
            return 0
        # Word it for each device. A person usually has one language across
        # devices, but a token that hasn't reported one (an old install) is
        # Russian — what every push used to be — so group by language rather
        # than assume the first token speaks for the rest.
        by_lang: dict[str, list[str]] = {}
        for t in tokens:
            by_lang.setdefault(normalize_lang(t.locale), []).append(t.token)
        sent = 0
        for lang, group in by_lang.items():
            sent += self._send(db, group, pick(title, lang), pick(body, lang), data)
        # The log keeps the Russian text (a Bi *is* that str): it is only
        # read back for "did we already send this today" checks.
        db.add(models.PushLog(user_id=user.id, category=category.value, title=str(title), body=str(body)))
        db.commit()
        return sent

    def send_to_users(
        self,
        db: Session,
        users: list[models.User],
        category: PushCategory,
        title: str,
        body: str,
        data: Optional[dict] = None,
    ) -> int:
        """Convenience for the (common) case of notifying more than one
        person about the same thing — a match, a partner link — with the
        same title/body for everyone. Each person's own preference is
        still checked individually; one side having this category off
        doesn't affect whether the other side gets it."""
        return sum(self.send_to_user(db, u, category, title, body, data) for u in users)

    def _send(
        self, db: Session, tokens: list[str], title: str, body: str, data: Optional[dict]
    ) -> int:
        from firebase_admin import messaging

        message = messaging.MulticastMessage(
            tokens=tokens,
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
        )
        try:
            response = messaging.send_each_for_multicast(message, app=_firebase_app())
        except Exception:
            # Network blip, Firebase outage, a malformed credential that
            # only fails once actually used — none of these should ever
            # take down whatever triggered the notification (a diary
            # log, a match). Logged, not raised.
            logger.exception("push send failed for %d token(s)", len(tokens))
            return 0

        # A token FCM reports as unregistered is gone for good — the
        # install was uninstalled, or the token was superseded by a
        # fresher one Firebase issued the same device (which arrives
        # here as its own *new* row via routers/push.py::register_token,
        # not as an update to this one). Every other failure (quota,
        # sender mismatch, a transient backend error) leaves the token
        # in place — it might succeed next time, and this app has no
        # basis to conclude otherwise from one failed attempt.
        dead_tokens = [
            token
            for token, result in zip(tokens, response.responses)
            if not result.success and isinstance(result.exception, messaging.UnregisteredError)
        ]
        if dead_tokens:
            db.query(models.PushToken).filter(models.PushToken.token.in_(dead_tokens)).delete(
                synchronize_session=False
            )
        return response.success_count


push_service = PushService()


# ---------------------------------------------------------------------------
# Background-task triggers. Each of these is what a router actually hands
# to `background_tasks.add_task(...)` — see this module's own docstring
# for why they open their own session instead of taking one as an
# argument.
# ---------------------------------------------------------------------------


def notify_match(user_ids: list[str], title_name: str, media_id: str, source: str, media_type: str) -> None:
    """Both sides of a "together" swipe session landing on the same
    title — see routers/co_view_vote.py::cast_vote, called only after
    that request's own db.commit() for the match has already succeeded.
    The single most "come back right now" moment this app has: it means
    someone else, right now, also wants to watch this. media_id/source/
    media_type are carried through so the mobile client's notification
    tap can open TitleDetailScreen directly rather than just the app's
    home tab."""
    db = SessionLocal()
    try:
        users = db.query(models.User).filter(models.User.id.in_(user_ids)).all()
        push_service.send_to_users(
            db, users, PushCategory.MATCHES,
            title=Bi("Совпадение! 🎉", "It's a match! 🎉"),
            body=Bi(f"Вы оба выбрали «{title_name}» — можно смотреть сегодня",
                    f"You both picked “{title_name}” — you can watch it tonight"),
            data={
                "type": "match", "media_id": media_id, "source": source, "media_type": media_type,
                "title": title_name,
            },
        )
    finally:
        db.close()


def notify_friend_request(user_id: str, from_display_name: str) -> None:
    """Fired right after a new FriendRequest row commits — see
    routers/friends.py::send_request. Its own category (not folded into
    FRIEND_ACTIVITY) since this one is actionable — someone waiting on
    a yes/no — where the rest of that category is passive "here's what
    a friend watched" activity someone might reasonably mute without
    wanting to miss an actual request. Tapping it is meant to land
    straight on the friends screen's incoming-requests list, not just
    the app's home tab, hence the explicit `type` in `data`.
    """
    db = SessionLocal()
    try:
        user = db.query(models.User).filter_by(id=user_id).first()
        if user is None:
            return
        push_service.send_to_user(
            db, user, PushCategory.FRIEND_REQUESTS,
            title=Bi("Новая заявка в друзья", "New friend request"),
            body=Bi(f"{from_display_name} хочет добавить вас в друзья",
                    f"{from_display_name} wants to add you as a friend"),
            data={"type": "friend_request"},
        )
    finally:
        db.close()


def notify_partner_invite(user_id: str, from_display_name: str) -> None:
    """Fired right after a new PartnerLinkInvite row commits — see
    routers/partner.py::send_invite. Uses the same PARTNER_ACTIVITY
    toggle as notify_partner_linked (below) rather than a category of
    its own — someone who's muted partner/circle notifications
    presumably doesn't want to hear about an invite into one either,
    and a dedicated toggle for a single pre-connection trigger felt
    like more settings-screen clutter than the one extra case earns.
    """
    db = SessionLocal()
    try:
        user = db.query(models.User).filter_by(id=user_id).first()
        if user is None:
            return
        push_service.send_to_user(
            db, user, PushCategory.PARTNER_ACTIVITY,
            title=Bi("Приглашение к совместному просмотру", "Invitation to watch together"),
            body=Bi(f"{from_display_name} зовёт вас в свой круг на Teamira",
                    f"{from_display_name} is inviting you into their circle on Teamira"),
            data={"type": "partner_invite"},
        )
    finally:
        db.close()


def notify_partner_linked(user_ids: list[str], other_display_names: dict[str, str]) -> None:
    """Fired once, the moment a partner-link invite is accepted — see
    routers/partner.py::accept_invite. `other_display_names` maps each
    user_id to *the other* person's name, since the two pushes are
    mirror images of each other (each side needs to see the other
    person's name, not their own)."""
    db = SessionLocal()
    try:
        users = {u.id: u for u in db.query(models.User).filter(models.User.id.in_(user_ids)).all()}
        for uid, other_name in other_display_names.items():
            user = users.get(uid)
            if user is None:
                continue
            push_service.send_to_user(
                db, user, PushCategory.PARTNER_ACTIVITY,
                title=Bi("Теперь вы вместе на Teamira 💛", "You're together on Teamira 💛"),
                body=Bi(f"Вы и {other_name} связали аккаунты — общий дневник уже ждёт",
                        f"You and {other_name} are linked — your shared diary is waiting"),
                data={"type": "partner_linked"},
            )
    finally:
        db.close()


def notify_friend_activity(
    friend_ids: list[str], actor_display_name: str, title_name: str, rating: Optional[int],
    media_id: str, source: str, media_type: str,
) -> None:
    """A friend logged something new — see routers/diary.py::log_entry,
    called only for the interactive "I just watched this" endpoint, never
    for imports/integrations/co-viewing's own log call (see that call
    site's own comment on why: a CSV import replaying two years of
    Letterboxd history is not two years of "come see what they watched"
    moments, it's one settings action). `friend_ids` has already been
    filtered by the caller down to whoever this account's privacy
    settings and current friendships actually allow seeing this event —
    this function trusts that list rather than re-deriving it.
    media_id/source/media_type let the notification tap open
    TitleDetailScreen directly."""
    if not friend_ids:
        return
    db = SessionLocal()
    try:
        users = db.query(models.User).filter(models.User.id.in_(friend_ids)).all()
        # Rating is 1-10 (see schemas.DiaryEntryCreate.rating and
        # widgets/heart_rating.dart's own "9/10 looks warmer than 3/10"
        # comment on the mobile side — not the 1-5 scale it might look
        # like from the half-heart rendering) — 8+ is a genuine "loved
        # it," worth leading the push with, not just "logged something."
        if rating is not None and rating >= 8:
            body = Bi(f"{actor_display_name} оценил(а) «{title_name}» на {rating}/10 — стоит взглянуть?",
                      f"{actor_display_name} rated “{title_name}” {rating}/10 — worth a look?")
        elif rating is not None:
            body = Bi(f"{actor_display_name} посмотрел(а) «{title_name}»",
                      f"{actor_display_name} watched “{title_name}”")
        else:
            body = Bi(f"{actor_display_name} добавил(а) «{title_name}» в дневник",
                      f"{actor_display_name} added “{title_name}” to their diary")
        push_service.send_to_users(
            db, users, PushCategory.FRIEND_ACTIVITY,
            title=Bi(f"{actor_display_name} смотрит", f"{actor_display_name} is watching"),
            body=body,
            data={
                "type": "friend_activity", "media_id": media_id, "source": source, "media_type": media_type,
                "title": title_name,
            },
        )
    finally:
        db.close()


def notify_level_up(user_id: str, new_level: int) -> None:
    """Level crossed upward within the same request that caused it (see
    routers/diary.py::log_entry's before/after compare — level itself is
    a derived read, computed fresh from history every time, never a
    stored counter to increment; see profile.py::compute_level_for_user).
    """
    db = SessionLocal()
    try:
        user = db.query(models.User).filter(models.User.id == user_id).first()
        if user is None:
            return
        push_service.send_to_user(
            db, user, PushCategory.LEVEL_UPS,
            title=Bi(f"Уровень {new_level}! 🎬", f"Level {new_level}! 🎬"),
            body=Bi("Ваш киновкус растёт — загляните в профиль, что нового открылось",
                    "Your movie taste is growing — peek at your profile to see what's new"),
            data={"type": "level_up", "level": new_level},
        )
    finally:
        db.close()


def notify_nudge(user_id: str, actor_name: str, title: str) -> None:
    """Someone spent sincerity.NUDGE_COST to poke a circle-mate about a
    stale shared plan (see models.CoViewEntry, app/sincerity.py::spend_nudge)
    — routers/shared_diary.py::nudge schedules this once per other
    member right after the spend commits. Deliberately plain: this
    isn't a "your friend did a thing" activity update, it's someone
    specifically asking to be watched with, so it says exactly that.
    """
    db = SessionLocal()
    try:
        user = db.query(models.User).filter(models.User.id == user_id).first()
        if user is None:
            return
        push_service.send_to_user(
            db, user, PushCategory.FRIEND_ACTIVITY,
            title=Bi(f"{actor_name} напоминает 👋", f"{actor_name} nudges you 👋"),
            body=Bi(f"«{title}» всё ещё в общих планах — может, пора?",
                    f"“{title}” is still in your shared plans — maybe it's time?"),
            data={"type": "coview_nudge", "title": title},
        )
    finally:
        db.close()


def notify_recommendation_resolved(
    user_id: str, friend_display_name: str, title: str, hit: bool, amount: int
) -> None:
    """A staked recommendation (see models.Recommendation,
    app/sincerity.py's spend_recommendation_stake/resolve_recommendation_stake)
    just resolved because the friend logged their own rating for the
    title — routers/diary.py::log_entry schedules this the moment that
    happens. `user_id` here is always the *staker*, never the friend who
    just rated something: the friend doesn't need a push telling them
    they just did the thing they're looking at the confirmation for."""
    db = SessionLocal()
    try:
        user = db.query(models.User).filter(models.User.id == user_id).first()
        if user is None:
            return
        if hit:
            title_text = Bi("Ставка сыграла 🎯", "Your bet paid off 🎯")
            body = Bi(f"{friend_display_name} оценил(а) «{title}» почти как ты и говорил(а) — +{amount} очков искренности",
                      f"{friend_display_name} rated “{title}” almost exactly as you said — +{amount} sincerity points")
        else:
            title_text = Bi("Не в этот раз", "Not this time")
            body = Bi(f"{friend_display_name} оценил(а) «{title}» иначе — ставка сгорела",
                      f"{friend_display_name} rated “{title}” differently — the bet is gone")
        push_service.send_to_user(
            db, user, PushCategory.FRIEND_ACTIVITY,
            title=title_text,
            body=body,
            data={"type": "recommendation_resolved", "hit": hit, "title": title},
        )
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Pair album (routers/pair_album.py, scripts/send_scheduled_push.py). Every
# text here is deliberately discreet: a lock-screen banner is read by
# whoever is holding the phone, so it says that a note *exists* and never
# what it says.
# ---------------------------------------------------------------------------

def _send_album_push(user_id: str, title: str, body: str, data: dict) -> None:
    db = SessionLocal()
    try:
        user = db.query(models.User).filter_by(id=user_id).first()
        if user is None or getattr(user, "deleted_at", None) is not None:
            return
        push_service.send_to_user(db, user, PushCategory.PAIR_ALBUM, title=title, body=body, data=data)
    finally:
        db.close()


def notify_album_note(user_id: str, from_name: str, title_name: str) -> None:
    """A partner left a sealed note on a title's card — fired once, when the
    note is first created (not on every edit)."""
    _send_album_push(
        user_id,
        title=Bi("Вам оставили записку ✉️", "You've got a note ✉️"),
        body=Bi(f"{from_name} написал(а) вам к «{title_name}» — она откроется после просмотра",
                f"{from_name} left you a note on “{title_name}” — it opens after you watch"),
        data={"type": "pair_album_note"},
    )


def notify_album_reveal(user_id: str, from_name: str, title_name: str) -> None:
    """The evening was marked watched and the caller's note is now readable
    for the other side."""
    _send_album_push(
        user_id,
        title=Bi("Записка открылась 💌", "The note is open 💌"),
        body=Bi(f"«{title_name}» просмотрен — посмотрите, что написал(а) {from_name}",
                f"“{title_name}” is watched — see what {from_name} wrote"),
        data={"type": "pair_album_reveal"},
    )


def notify_capsule_created(user_id: str, from_name: str, opens_label: str) -> None:
    _send_album_push(
        user_id,
        title=Bi("Капсула для двоих 🕰️", "A capsule for two 🕰️"),
        body=Bi(f"{from_name} запечатал(а) капсулу — она откроется {opens_label}. Напишите своё письмо",
                f"{from_name} sealed a capsule — it opens {opens_label}. Write your letter"),
        data={"type": "pair_album_capsule"},
    )


def notify_capsule_letter(user_id: str, from_name: str) -> None:
    _send_album_push(
        user_id,
        title=Bi("В капсулу добавили письмо 🕰️", "A letter was added to the capsule 🕰️"),
        body=Bi(f"{from_name} запечатал(а) своё письмо — теперь в капсуле два",
                f"{from_name} sealed their letter — now there are two in the capsule"),
        data={"type": "pair_album_capsule"},
    )



# ---------------------------------------------------------------------------
# Co-view rooms (routers/co_view_room.py).
# ---------------------------------------------------------------------------

def notify_room_invite(user_id: str, from_name: str, title_name: str, activity: str = "watch") -> None:
    """Someone opened a room and is waiting in it (to watch, or to read)."""
    db = SessionLocal()
    try:
        user = db.query(models.User).filter_by(id=user_id).first()
        if user is None or getattr(user, "deleted_at", None) is not None:
            return
        headline = {
            "read": Bi(f"{from_name} зовёт читать вместе 📖", f"{from_name} invites you to read together 📖"),
            "play": Bi(f"{from_name} зовёт играть вместе 🎮", f"{from_name} invites you to play together 🎮"),
        }.get(activity, Bi(f"{from_name} зовёт смотреть вместе 🍿", f"{from_name} invites you to watch together 🍿"))
        push_service.send_to_user(
            db, user, PushCategory.CO_VIEW_ROOMS,
            title=headline,
            body=Bi(f"«{title_name}» — комната уже открыта, заходите",
                    f"“{title_name}” — the room is already open, come in"),
            data={"type": "co_view_room"},
        )
    finally:
        db.close()


def notify_review_invite(user_id: str, from_name: str, title_name: str) -> None:
    """Someone logged an evening "watched with" — ask the others for their part."""
    db = SessionLocal()
    try:
        user = db.query(models.User).filter_by(id=user_id).first()
        if user is None or getattr(user, "deleted_at", None) is not None:
            return
        push_service.send_to_user(
            db, user, PushCategory.PARTNER_ACTIVITY,
            title=Bi("Оценим вместе? 💬", "Review it together? 💬"),
            body=Bi(f"{from_name} записал(а) «{title_name}» — добавьте и свою оценку",
                    f"{from_name} logged “{title_name}” — add your rating too"),
            data={"type": "circle_review"},
        )
    finally:
        db.close()


def notify_review_ready(user_id: str, title_name: str) -> None:
    """Everyone has written — the joint review is open. Never says what anyone wrote."""
    db = SessionLocal()
    try:
        user = db.query(models.User).filter_by(id=user_id).first()
        if user is None or getattr(user, "deleted_at", None) is not None:
            return
        push_service.send_to_user(
            db, user, PushCategory.PARTNER_ACTIVITY,
            title=Bi("Рецензия открылась ✨", "The review is open ✨"),
            body=Bi(f"«{title_name}» — посмотрите, как вы оценили вечер",
                    f"“{title_name}” — see how you rated the evening"),
            data={"type": "circle_review"},
        )
    finally:
        db.close()


def notify_room_guest_invite(user_id: str, from_name: str, title_name: str, activity: str = "watch") -> None:
    """A friend invited this person into their watching (or reading) room."""
    db = SessionLocal()
    try:
        user = db.query(models.User).filter_by(id=user_id).first()
        if user is None or getattr(user, "deleted_at", None) is not None:
            return
        push_service.send_to_user(
            db, user, PushCategory.CO_VIEW_ROOMS,
            title={
                "read": Bi(f"{from_name} зовёт вас читать 📖", f"{from_name} invites you to read 📖"),
                "play": Bi(f"{from_name} зовёт вас играть 🎮", f"{from_name} invites you to play 🎮"),
            }.get(activity, Bi(f"{from_name} зовёт вас смотреть 🍿", f"{from_name} invites you to watch 🍿")),
            body=Bi(f"«{title_name}» — комната открыта, заходите",
                    f"“{title_name}” — the room is open, come in"),
            data={"type": "co_view_room_guest"},
        )
    finally:
        db.close()
