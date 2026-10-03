"""Password hashing, and the token pair every authenticated request runs
on.

**What changed and why.** This module used to mint one thing: an access
token with `{"sub": user_id, "exp": +7 days}` and nothing else. Three
problems came out of that shape, and all three are fixed here rather
than worked around at the call sites:

1. *Seven days, then a silent eviction.* There was no refresh path, so
   the only way to keep someone signed in was to make the one token
   long-lived — and when it finally expired the app had no idea what had
   happened (mobile's api_client.dart had no 401 handling at all), so
   screens just started showing "Could not validate credentials". The
   access token is now minutes-long and paired with a refresh token
   whose rotation the client handles transparently; see
   models.RefreshSession.
2. *Nothing could be revoked.* Changing your password, or signing out on
   a phone you no longer have, left every issued token working until it
   aged out. Tokens now carry `ver`, checked against
   `users.token_version` on every request (app/deps.py) — bumping that
   one integer invalidates every token for the account at once, with no
   denylist table and no extra query.
3. *No token identity.* Without a `jti` there was no way to talk about
   "this specific token" at all — not to revoke one session, not to
   detect a stolen refresh token being replayed. Every token now has one.

`typ` is checked, not just present: a refresh token must never be
accepted as an access token. That's the difference between a refresh
token being a credential with one narrow job and it being a second,
much longer-lived password.
"""

from __future__ import annotations

import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional

import bcrypt
from jose import jwt, JWTError

from app.config import settings

# bcrypt has a hard 72-byte input limit — enforced explicitly (rather than
# silently truncating) so a long password fails loudly at hashing time
# instead of behaving unexpectedly at verification time.
_MAX_PASSWORD_BYTES = 72

TOKEN_TYPE_ACCESS = "access"
TOKEN_TYPE_REFRESH = "refresh"


def hash_password(password: str) -> str:
    encoded = password.encode("utf-8")
    if len(encoded) > _MAX_PASSWORD_BYTES:
        raise ValueError(f"Password must be at most {_MAX_PASSWORD_BYTES} bytes")
    return bcrypt.hashpw(encoded, bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, password_hash: str) -> bool:
    encoded = password.encode("utf-8")[:_MAX_PASSWORD_BYTES]
    try:
        return bcrypt.checkpw(encoded, password_hash.encode("utf-8"))
    except ValueError:
        return False


def _now() -> datetime:
    # Timezone-aware throughout this module. The rest of the codebase
    # stores naive UTC in the database (see models' DateTime columns);
    # the conversion happens at the boundary in the routers rather than
    # here, so JWT `exp`/`iat` — which are defined as UTC epoch seconds —
    # can't pick up a local-time offset on a machine that isn't on UTC.
    return datetime.now(timezone.utc)


# --- Access tokens ---------------------------------------------------------

def create_access_token(subject: str, token_version: int = 0) -> str:
    now = _now()
    payload = {
        "sub": subject,
        "typ": TOKEN_TYPE_ACCESS,
        "ver": token_version,
        "jti": secrets.token_urlsafe(12),
        "iat": int(now.timestamp()),
        "exp": now + timedelta(minutes=settings.jwt_expire_minutes),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> Optional[dict]:
    """The full claim set, or None if the token is unusable for any
    reason (bad signature, expired, or — the important one — a refresh
    token being presented where an access token belongs).

    Returns a dict now rather than the bare `sub` string the old version
    returned, because the caller has to check `ver` against the account's
    current token_version and can't do that without the claims. Every
    call site was updated with this change; there is no caller left that
    expects a string.
    """
    try:
        claims = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except JWTError:
        return None
    # Older tokens minted before this module gained `typ` have no such
    # claim. Treating a missing `typ` as an access token keeps everyone
    # signed in across the deploy that ships this, and is safe precisely
    # because refresh tokens are new in the same deploy — nothing without
    # a `typ` can possibly be one.
    if claims.get("typ", TOKEN_TYPE_ACCESS) != TOKEN_TYPE_ACCESS:
        return None
    if not claims.get("sub"):
        return None
    return claims


# --- Refresh tokens --------------------------------------------------------
#
# Deliberately NOT a JWT. A refresh token is checked against the database
# on every use anyway (models.RefreshSession — to see whether it's been
# rotated, revoked, or replayed), so signing a claim set into it would
# buy nothing and cost the ability to make it opaque. What it is instead:
# 256 bits from `secrets.token_urlsafe`, stored only as a SHA-256 hash.
#
# SHA-256 rather than bcrypt for the stored form, which is the opposite
# of the rule for passwords and for the right reason: a password is
# low-entropy and human-chosen, so the hash has to be slow to make
# guessing it expensive. This value is full-entropy machine-generated —
# there is no guessing attack to slow down — and it's verified on every
# token refresh, where a deliberately slow hash would be a self-inflicted
# denial of service.

REFRESH_TOKEN_BYTES = 32


def generate_refresh_token() -> str:
    return secrets.token_urlsafe(REFRESH_TOKEN_BYTES)


def hash_refresh_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def refresh_token_expiry() -> datetime:
    """Naive UTC, to match what every DateTime column in models.py
    stores. The database is the only consumer of this value."""
    return (_now() + timedelta(days=settings.refresh_token_days)).replace(tzinfo=None)


# --- One-time links (password reset, email verification) -------------------
#
# Same opaque-random-plus-hash shape as refresh tokens above, same
# reasoning. Kept as its own pair of functions rather than reusing the
# refresh helpers so that changing the length or lifetime of one can
# never silently change the other.

def generate_link_token() -> str:
    return secrets.token_urlsafe(32)


def hash_link_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()
