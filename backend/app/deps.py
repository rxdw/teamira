from datetime import datetime, timezone

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from app.database import get_db
from app.security import decode_access_token
from app import models

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")

# Sent as the `error` parameter of the WWW-Authenticate header on every
# 401 this module raises, so the mobile client can tell the two apart
# without string-matching a human-readable `detail` (see
# mobile/lib/services/api_client.dart's 401 handling): "the access token
# aged out, silently refresh and retry" versus "this session is over,
# show the login screen". Without this distinction a client either
# retries forever on a revoked token or signs people out on every routine
# expiry — which is exactly what the old seven-day-token-and-no-refresh
# setup did.
ERROR_TOKEN_EXPIRED = "token_expired"
ERROR_TOKEN_REVOKED = "token_revoked"


def _unauthorized(detail: str, error: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail,
        headers={"WWW-Authenticate": f'Bearer error="{error}"'},
    )


def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> models.User:
    claims = decode_access_token(token)
    if not claims:
        # Covers a bad signature, a genuinely expired token, and a
        # refresh token presented where an access token belongs. All
        # three are reported as "expired" rather than distinguished:
        # telling an attacker which of the three went wrong is free
        # information for them, and the client's behavior — try the
        # refresh endpoint once, fall back to the login screen if that
        # also fails — is correct for every one of them.
        raise _unauthorized("Could not validate credentials", ERROR_TOKEN_EXPIRED)

    user = db.get(models.User, claims["sub"])
    if not user:
        raise _unauthorized("User not found", ERROR_TOKEN_REVOKED)

    # Revocation check. `ver` is stamped into the token at issue time;
    # bumping users.token_version (password change, "sign out
    # everywhere", password reset, account deletion) leaves every token
    # issued before that moment behind, and they fail here. Tokens minted
    # before this claim existed default to 0, which matches the
    # server_default on the column, so nobody is signed out by the deploy
    # that introduces this.
    if int(claims.get("ver", 0)) != int(user.token_version or 0):
        raise _unauthorized("Session is no longer valid — sign in again", ERROR_TOKEN_REVOKED)

    # A deletion request makes the account invisible immediately even
    # though the rows survive until the purge job runs (see
    # app/account_deletion.py). The *only* way back in is POST
    # /auth/account/restore, which authenticates with username and
    # password rather than a token precisely because this check would
    # otherwise stand in the way of someone trying to undo their own
    # deletion.
    if user.deleted_at is not None:
        raise _unauthorized("This account is scheduled for deletion", ERROR_TOKEN_REVOKED)

    return user


async def get_ws_user(token: str | None, db: Session) -> models.User | None:
    """The websocket equivalent of [get_current_user] — used by the
    session websockets in co_view_vote.py/co_view_poll.py/together.py.
    Not a `Depends` itself, unlike get_current_user: a websocket route
    still has to `await websocket.accept()` before it can send a close
    frame with a real reason, and by the time a `Depends` would raise,
    FastAPI has already decided how the handshake ends. Called plainly
    from inside each endpoint instead, right after accept(), so the
    endpoint can accept, check, and close with an explicit code (4401)
    on its own terms.

    `token` comes from a `?token=...` query parameter rather than an
    `Authorization` header — the one piece of a WebSocket handshake
    every client on every platform this app ships to can actually set
    (a browser's native WebSocket, included, unlike a header). Mirrors
    get_current_user's own checks (signature/expiry, `ver` against
    token_version, `deleted_at`) minus the parts that only make sense
    for an HTTP response (the WWW-Authenticate error code) — a
    websocket close code carries far less nuance, so the caller only
    gets a plain None back and picks its own close code.
    """
    if not token:
        return None
    claims = decode_access_token(token)
    if not claims:
        return None
    user = db.get(models.User, claims["sub"])
    if not user:
        return None
    if int(claims.get("ver", 0)) != int(user.token_version or 0):
        return None
    if user.deleted_at is not None:
        return None
    return user


def get_active_user(current_user: models.User = Depends(get_current_user)) -> models.User:
    """Everything except the handful of endpoints a suspended account
    must keep: reading and exporting its own diary, and deleting itself.

    A suspension (see models.User.suspended_at, set by a moderator acting
    on a report) takes away the ability to be seen by or interact with
    anyone else — it does not confiscate a personal archive. So the
    social and write endpoints depend on this, while GET /auth/me, GET
    /auth/export and DELETE /auth/account stay on get_current_user above.
    """
    if current_user.suspended_at is None:
        return current_user

    until = current_user.suspended_until
    if until is not None and until <= datetime.now(timezone.utc):
        # Expired suspension, lifted lazily on first use rather than by a
        # scheduled job — there's no other reader of this state, so a
        # cron entry would exist purely to do what this line does for
        # free at the moment it first matters.
        current_user.suspended_at = None
        current_user.suspended_until = None
        current_user.suspension_reason = None
        return current_user

    detail = "Your account is suspended"
    if current_user.suspension_reason:
        detail = f"{detail}: {current_user.suspension_reason}"
    if until is not None:
        detail = f"{detail} (until {until.date().isoformat()})"
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=detail)


def get_current_user_id(token: str = Depends(oauth2_scheme)) -> str:
    """A lighter-weight sibling of get_current_user: verifies the bearer
    token's signature/expiry and returns the subject id, but never
    touches the database. Use this (instead of get_current_user) to gate
    an endpoint behind "must be logged in" when the endpoint has no
    `db: Session = Depends(get_db)` of its own — routers/media.py's
    search_media and routers/reviews.py's media_reviews, specifically,
    which dropped `Depends(get_db)` on purpose (see search_media's own
    docstring on the pool-exhaustion incident that caused it), and
    get_current_user's own `db.get(models.User, ...)` lookup would
    quietly bring that dependency straight back for every request.

    **This does not check token revocation.** get_current_user's `ver`
    check (password change, "sign out everywhere", suspension, deletion —
    see that function above) needs the user row, which needs the
    database this function exists specifically to avoid touching. A
    token revoked one minute ago therefore still passes here for as long
    as the token itself remains valid — up to settings.jwt_expire_minutes
    (30 by default). That is a real, deliberate gap, not an oversight:
    the endpoints behind this dependency are read-only catalog lookups
    (search, title detail, reviews) that don't touch or expose any other
    person's data, so the worst a stale-but-not-yet-expired token buys
    someone is up to 30 more minutes of movie search after their session
    was supposed to end — a small residual risk, and a strict improvement
    over these endpoints having no login requirement or rate limit at
    all. Any endpoint that touches another person's data, or where a
    revoked session must stop working immediately, uses get_current_user
    or get_active_user above instead, both of which already have a `db`
    session for other reasons and get the revocation check for free.

    Endpoints that already carry `db: Session = Depends(get_db)` for
    their own purposes — routers/watch.py's watch_providers,
    routers/media.py's media_detail/media_episodes/media_person — use
    get_current_user instead of this function even though they're in the
    same "catalog read" family, since the database round trip this avoids
    isn't actually being avoided for them; using this here would only add
    an unnecessary gap in exchange for nothing.
    """
    claims = decode_access_token(token)
    if not claims:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": 'Bearer error="token_expired"'},
        )
    return claims["sub"]


def require_admin_user(current_user: models.User = Depends(get_current_user)) -> models.User:
    """Guards the Teamira-picks admin endpoints (app/routers/teamira.py)
    and the moderation queue (app/routers/moderation.py) — creating/
    editing shelves everyone sees, and acting on reports about other
    people. Same JWT login as every other endpoint (via get_current_user
    above), gated on one extra flag (`User.is_admin`) rather than a
    shared secret handed out over Slack/`.env` — an admin is now an
    actual account, so access can be granted or revoked per person, and
    every admin action is attributable to whoever was logged in when it
    happened (current_user is available to the route the same way it is
    anywhere else, not thrown away). Nobody starts admin; see
    scripts/grant_admin.py to set the first one.
    """
    if not current_user.is_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin access required")
    return current_user
