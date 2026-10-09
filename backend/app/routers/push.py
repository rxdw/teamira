"""Device registration and per-category preferences for push
notifications — see app/push.py for what actually sends them, and each
router's own call site (co_view_vote.py, partner.py, diary.py) for what
triggers one.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app import models
from app.database import get_db
from app.bi import normalize_lang
from app.deps import get_current_user
from app.push import CATEGORY_COPY, PushCategory

router = APIRouter(prefix="/push", tags=["push"])

_ALLOWED_PLATFORMS = {"ios", "android"}


class RegisterTokenIn(BaseModel):
    token: str = Field(..., min_length=8, max_length=4096)
    platform: str
    # IANA name ("Europe/Moscow") — see models.PushToken.timezone's own
    # docstring for what this is used for and why it's optional.
    timezone: Optional[str] = None
    # "ru" / "en" (or a full locale like "en-US") — the app's own interface
    # language, so pushes are worded to match it. Optional: an older client
    # simply doesn't send it and keeps getting Russian.
    locale: Optional[str] = Field(default=None, max_length=16)


class RegisterTokenOut(BaseModel):
    ok: bool = True


@router.post("/tokens", response_model=RegisterTokenOut)
def register_token(
    payload: RegisterTokenIn,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Called on every app launch once someone's signed in, and again
    whenever Firebase hands the client a refreshed token (see
    `onTokenRefresh` on the mobile side) — cheap and idempotent either
    way, so the client doesn't need to track "have I already sent this
    one" itself.

    Upserts by *token*, not by (user_id, token): the same physical
    device's token can legitimately belong to a different user than it
    used to (sign out, sign in as someone else on a shared device,
    without ever explicitly unregistering the old owner's token first —
    nothing forces a client to call DELETE /push/tokens before that
    happens). Moving the row to the new owner is correct; leaving it
    pointed at whoever registered it first would mean two accounts'
    worth of pushes land on one device, or the wrong account's."""
    platform = payload.platform.strip().lower()
    if platform not in _ALLOWED_PLATFORMS:
        platform = "android"  # unknown client string — a guess is safer than 500ing over it

    existing = db.query(models.PushToken).filter(models.PushToken.token == payload.token).first()
    if existing is not None:
        existing.user_id = current_user.id
        existing.platform = platform
        if payload.timezone:
            existing.timezone = payload.timezone
        if payload.locale:
            existing.locale = normalize_lang(payload.locale)
        existing.last_seen_at = datetime.now(timezone.utc)
    else:
        db.add(models.PushToken(
            user_id=current_user.id,
            token=payload.token,
            platform=platform,
            timezone=payload.timezone,
            locale=normalize_lang(payload.locale) if payload.locale else None,
        ))
    db.commit()
    return RegisterTokenOut()


@router.delete("/tokens/{token}", response_model=RegisterTokenOut)
def unregister_token(
    token: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Called on logout, so a shared/reset device stops getting this
    account's pushes the moment it stops being signed in as them — see
    the mobile client's sign-out flow. Scoped to the caller's own tokens
    only: deleting *a* token isn't scoped by ownership at the DB level
    (there's no reason it couldn't be), but a request authenticated as
    one account has no business removing a device it doesn't know is
    even registered to that account, let alone someone else's."""
    db.query(models.PushToken).filter(
        models.PushToken.token == token,
        models.PushToken.user_id == current_user.id,
    ).delete(synchronize_session=False)
    db.commit()
    return RegisterTokenOut()


class CategoryPref(BaseModel):
    category: str
    label: str
    description: str
    enabled: bool


class PreferencesOut(BaseModel):
    categories: list[CategoryPref]


@router.get("/preferences", response_model=PreferencesOut)
def get_preferences(
    current_user: models.User = Depends(get_current_user),
):
    """Copy (label/description) lives server-side in app/push.py's
    CATEGORY_COPY rather than duplicated in the mobile client, so the
    settings screen's toggle list is just "render whatever this
    returns" — adding a new category later means one change here, not a
    matching client release before it can be turned on for anyone."""
    prefs = current_user.notification_prefs or {}
    return PreferencesOut(categories=[
        CategoryPref(
            category=cat.value,
            label=label,
            description=description,
            enabled=bool(prefs.get(cat.value, True)),
        )
        for cat, (label, description) in CATEGORY_COPY.items()
    ])


class UpdatePreferencesIn(BaseModel):
    # Partial update — only the categories present here change; anything
    # not mentioned keeps its current value (which is "on" if it was
    # never set at all — see models.User.notification_prefs).
    categories: dict[str, bool]


@router.patch("/preferences", response_model=PreferencesOut)
def update_preferences(
    payload: UpdatePreferencesIn,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    valid = {c.value for c in PushCategory}
    prefs = dict(current_user.notification_prefs or {})
    for key, enabled in payload.categories.items():
        if key in valid:
            prefs[key] = bool(enabled)
    current_user.notification_prefs = prefs
    db.commit()
    return get_preferences(current_user)
