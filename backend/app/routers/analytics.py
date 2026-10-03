"""First-party product analytics: the mobile app reports what people do,
this stores it, and docs/analytics.md explains how to look at it.

Why this exists rather than Firebase/PostHog/AppMetrica: the data stays in
the Postgres this app already runs on (simplest answer to 152-FZ/GDPR
"where does it live"), there is no third-party SDK to keep compiling with
every Flutter upgrade, and the mobile side talks to exactly one class
(lib/analytics/analytics.dart) — swapping in a vendor later is a change
to that file, not to 60 screens.

One endpoint, `POST /analytics/events`, takes a batch:

    {"anon_id": "...", "platform": "android", "app_version": "dev",
     "build": "release", "locale": "ru",
     "events": [{"id": "...", "name": "screen_view", "ts": "...Z",
                 "sid": "...", "screen": "DiaryScreen",
                 "props": {"nav": "push"}}, ...]}

Decisions worth knowing before changing anything here:

  - **Never 401s.** Authentication is optional: a valid access token for a
    live account attaches `user_id`; anything else (no token, expired,
    revoked, deleted account) silently means "anonymous". The client must
    never be signed out by, or start a refresh dance because of, a
    statistics call — and onboarding/login screens have no token to send.
  - **Forgiving about individual events, strict about the envelope.** One
    malformed event is dropped and counted in `rejected`; it doesn't sink
    the other 49. A malformed *envelope* is a 422, which the client treats
    as "this batch can never succeed" and discards.
  - **Idempotent.** `events[].id` is unique (see models.AnalyticsEvent), so a
    batch the phone retried after a timeout doesn't count twice.
  - **`user_id` comes only from the token**, never from the body — otherwise
    anyone could file events under someone else's account.
  - **Props are a closed, flat vocabulary** (see `_clean_props`): short
    strings, numbers, booleans. No nesting, no long text, nothing that looks
    like an e-mail address. That is enforced here, not just promised in
    docs, because "we never send note text" is a claim the server can
    check and the client can't prove.
"""

from __future__ import annotations

import math
import re
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from fastapi import APIRouter, Depends, Request, status
from fastapi.security import OAuth2PasswordBearer
from pydantic import BaseModel, Field
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app import models
from app.config import settings
from app.database import get_db
from app.rate_limit import analytics_anon_limiter, analytics_ip_limiter, client_key
from app.security import decode_access_token

router = APIRouter(prefix="/analytics", tags=["analytics"])

# auto_error=False: a missing header is "anonymous", not a 401 — see the
# module docstring.
_optional_bearer = OAuth2PasswordBearer(tokenUrl="/auth/login", auto_error=False)

MAX_EVENTS_PER_BATCH = 100
MAX_PROPS = 20
MAX_PROP_STRING = 120
# A device clock that is a few minutes fast is normal; one that is hours or
# days ahead is broken or hostile. Old events are legitimate (a phone that
# was offline for a weekend flushes its queue), but not *very* old ones.
MAX_CLOCK_SKEW_AHEAD = timedelta(minutes=5)
MAX_EVENT_AGE = timedelta(days=14)

_ID_RE = re.compile(r"^[A-Za-z0-9_-]{8,40}$")
_EVENT_NAME_RE = re.compile(r"^[a-z][a-z0-9_]{1,63}$")
# Screen names are Dart class names (TitleDetailScreen), with a couple of
# reserved forms like "(unnamed)".
_SCREEN_RE = re.compile(r"^[A-Za-z0-9_()\-.:]{1,80}$")
_PROP_KEY_RE = re.compile(r"^[a-z][a-z0-9_]{0,39}$")
_EMAILISH_RE = re.compile(r"\S+@\S+\.\S+")


class AnalyticsBatchIn(BaseModel):
    anon_id: str = Field(min_length=8, max_length=40, pattern=r"^[A-Za-z0-9_-]+$")
    platform: Optional[str] = Field(default=None, max_length=16)
    app_version: Optional[str] = Field(default=None, max_length=32)
    build: Optional[str] = Field(default=None, pattern=r"^(debug|profile|release)$")
    locale: Optional[str] = Field(default=None, max_length=8)
    # Deliberately `Any`, validated one by one in _clean_event: typing this
    # as list[dict] would make pydantic 422 the *whole batch* over a single
    # malformed item, which is exactly what this endpoint promises not to do.
    events: list[Any] = Field(default_factory=list, max_length=MAX_EVENTS_PER_BATCH)


class AnalyticsBatchOut(BaseModel):
    accepted: int
    rejected: int


def _clean_props(raw: Any) -> Optional[dict[str, Any]]:
    """Flat dict of short scalars, or None. Anything that doesn't fit is
    dropped silently (the event itself is still kept)."""
    if not isinstance(raw, dict):
        return None
    out: dict[str, Any] = {}
    for key, value in raw.items():
        if len(out) >= MAX_PROPS:
            break
        if not isinstance(key, str) or not _PROP_KEY_RE.match(key):
            continue
        if value is None or isinstance(value, bool):
            out[key] = value
        elif isinstance(value, (int, float)):
            if isinstance(value, float) and not math.isfinite(value):
                continue
            out[key] = value
        elif isinstance(value, str):
            if _EMAILISH_RE.search(value):
                continue
            out[key] = value[:MAX_PROP_STRING]
        # lists / dicts: dropped on purpose — see module docstring.
    return out or None


def _parse_ts(value: Any) -> Optional[datetime]:
    if not isinstance(value, str):
        return None
    try:
        ts = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    return ts.astimezone(timezone.utc)


def _clean_event(raw: dict[str, Any], now: datetime) -> Optional[dict[str, Any]]:
    """One event in the shape the table wants, or None if it can't be
    salvaged. `anon_id` and the envelope fields are added by the caller."""
    event_id = raw.get("id")
    name = raw.get("name")
    sid = raw.get("sid")
    if not (isinstance(event_id, str) and _ID_RE.match(event_id)):
        return None
    if not (isinstance(name, str) and _EVENT_NAME_RE.match(name)):
        return None
    if not (isinstance(sid, str) and _ID_RE.match(sid)):
        return None

    ts = _parse_ts(raw.get("ts"))
    if ts is None:
        return None
    if now - ts > MAX_EVENT_AGE:
        return None
    if ts - now > MAX_CLOCK_SKEW_AHEAD:
        ts = now

    screen = raw.get("screen")
    if screen is not None and not (isinstance(screen, str) and _SCREEN_RE.match(screen)):
        screen = None

    return {
        "event_id": event_id,
        "ts": ts,
        "session_id": sid,
        "name": name,
        "screen": screen,
        "props": _clean_props(raw.get("props")),
    }


def _optional_user_id(
    token: Optional[str] = Depends(_optional_bearer),
    db: Session = Depends(get_db),
) -> Optional[str]:
    """The signed-in account's id, or None. Never raises — see the module
    docstring. One primary-key lookup per *batch* (not per event)."""
    if not token:
        return None
    claims = decode_access_token(token)
    if not claims:
        return None
    user = db.get(models.User, claims["sub"])
    if user is None or user.deleted_at is not None:
        return None
    if int(claims.get("ver", 0)) != int(user.token_version or 0):
        return None
    return user.id


@router.post("/events", response_model=AnalyticsBatchOut, status_code=status.HTTP_202_ACCEPTED)
def ingest_events(
    payload: AnalyticsBatchIn,
    request: Request,
    db: Session = Depends(get_db),
    user_id: Optional[str] = Depends(_optional_user_id),
) -> AnalyticsBatchOut:
    if not settings.analytics_enabled:
        # Answer "fine" rather than an error: see Settings.analytics_enabled.
        return AnalyticsBatchOut(accepted=0, rejected=0)

    analytics_ip_limiter.check(db, client_key(request))
    analytics_anon_limiter.check(db, payload.anon_id)

    now = datetime.now(timezone.utc)
    rows = []
    rejected = 0
    for raw in payload.events:
        cleaned = _clean_event(raw, now) if isinstance(raw, dict) else None
        if cleaned is None:
            rejected += 1
            continue
        cleaned.update(
            anon_id=payload.anon_id,
            user_id=user_id,
            platform=payload.platform,
            app_version=payload.app_version,
            build=payload.build,
            locale=payload.locale,
        )
        rows.append(cleaned)

    accepted = 0
    if rows:
        # ON CONFLICT DO NOTHING on the unique event_id: a retried batch
        # inserts only what the first attempt didn't. rowcount is therefore
        # the number of *new* rows, which is what "accepted" should mean.
        result = db.execute(
            pg_insert(models.AnalyticsEvent).values(rows).on_conflict_do_nothing(index_elements=["event_id"])
        )
        db.commit()
        accepted = result.rowcount if result.rowcount is not None and result.rowcount >= 0 else len(rows)
    return AnalyticsBatchOut(accepted=accepted, rejected=rejected)
