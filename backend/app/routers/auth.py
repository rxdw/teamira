"""Registration, sign-in, sessions, account recovery, and account
deletion.

The four things this file gained, and the holes each one closes:

  - **A refresh path.** Login used to hand back one access token good for
    seven days, and nothing else. When it expired the app had no way to
    get another and no code that noticed (mobile's api_client.dart had no
    401 handling), so people were silently evicted mid-session. Login now
    returns a pair; POST /auth/refresh rotates it.
  - **Revocation.** Changing your password, or signing out on a phone
    you've since lost, revoked nothing. Both now bump
    `users.token_version` and mark refresh sessions revoked.
  - **Recovery.** `User` had no email column at all, so a forgotten
    password meant a permanently lost archive of years of evenings. An
    address is optional and added after signup, and reset only works once
    it's verified.
  - **Deletion and export.** Neither existed. In-app deletion has been an
    App Store requirement since June 2022 and is required by GDPR art. 17
    / 152-ФЗ regardless; export is art. 20. See app/account_deletion.py.

Three deliberate non-obvious choices are documented at their call sites
below: why registration returns a 201 with a token pair rather than
requiring a separate login, why forgot-password always answers the same
way, and why restoring a deleted account authenticates with a password
rather than a token.
"""

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from fastapi.responses import JSONResponse
from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from app import account_deletion, models, sincerity
from app.config import settings
from app.database import get_db
from app.deps import get_current_user
from app.mailer import send_deletion_scheduled, send_email_verification, send_password_reset
from app.rate_limit import (
    client_key as _client_key,
    email_verify_limiter,
    login_limiter,
    password_reset_limiter,
    refresh_limiter,
    register_limiter,
)
from app.routers.referrals import create_referral_for_signup
from app.schemas import (
    AccountDeleteRequest,
    AccountDeletionOut,
    AccountRestoreRequest,
    EmailSetRequest,
    EmailVerifyRequest,
    EulaAcceptRequest,
    LoginRequest,
    PasswordChangeRequest,
    PasswordForgotRequest,
    PasswordResetRequest,
    RefreshRequest,
    RegisterRequest,
    SessionOut,
    SimpleMessageOut,
    TokenResponse,
    UserOut,
)
from app.security import (
    create_access_token,
    generate_link_token,
    generate_refresh_token,
    hash_link_token,
    hash_password,
    hash_refresh_token,
    refresh_token_expiry,
    verify_password,
)
from app.usernames import UsernameError, normalize_email, normalize_username, validate_username

router = APIRouter(prefix="/auth", tags=["auth"])

# _client_key used to be defined here; it's now app/rate_limit.py's
# client_key (imported above under the old local name) so every router
# rate-limiting by IP — this one, media.py, reviews.py, watch.py,
# image_proxy.py — shares one implementation.


# ---------------------------------------------------------------------------
# Session issuing
# ---------------------------------------------------------------------------

def _issue_session(
    db: Session,
    user: models.User,
    request: Request,
    device_label: str | None,
    family_id: str | None = None,
) -> TokenResponse:
    """Mints an access/refresh pair and records the refresh half as a
    RefreshSession row.

    `family_id` carries across a rotation so replay detection can revoke
    an entire lineage at once — see models.RefreshSession's docstring.
    A fresh login starts a new family, because a new login genuinely is
    an independent session: signing in again on a phone whose token was
    stolen shouldn't tie the new session's fate to the compromised one.
    """
    _enforce_session_cap(db, user.id)

    refresh_raw = generate_refresh_token()
    session = models.RefreshSession(
        user_id=user.id,
        token_hash=hash_refresh_token(refresh_raw),
        family_id=family_id or generate_refresh_token()[:22],
        device_label=(device_label or "").strip()[:60] or None,
        created_ip=_client_key(request),
        expires_at=refresh_token_expiry(),
        last_used_at=datetime.now(timezone.utc),
    )
    db.add(session)
    db.commit()

    return TokenResponse(
        access_token=create_access_token(user.id, token_version=int(user.token_version or 0)),
        refresh_token=refresh_raw,
        expires_in=settings.jwt_expire_minutes * 60,
    )


def _enforce_session_cap(db: Session, user_id: str) -> None:
    """Keeps refresh_sessions from growing without bound for someone who
    reinstalls often. Revokes oldest-first past
    settings.max_sessions_per_user — the device that hasn't been used in
    longest is the one most likely to be gone."""
    live = (
        db.query(models.RefreshSession)
        .filter(
            models.RefreshSession.user_id == user_id,
            models.RefreshSession.revoked_at.is_(None),
            models.RefreshSession.rotated_at.is_(None),
        )
        .order_by(models.RefreshSession.last_used_at.asc().nullsfirst())
        .all()
    )
    overflow = len(live) - (settings.max_sessions_per_user - 1)
    for session in live[:max(0, overflow)]:
        session.revoked_at = datetime.now(timezone.utc)
        session.revoked_reason = "session_limit"


# ---------------------------------------------------------------------------
# Register / login
# ---------------------------------------------------------------------------

@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
def register(payload: RegisterRequest, request: Request, db: Session = Depends(get_db)):
    register_limiter.check(db, _client_key(request))

    try:
        display_username, normalized = validate_username(payload.username)
    except UsernameError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    # Case-insensitive, via the normalized column. The old check compared
    # `User.username == payload.username` exactly, which let "Anna" and
    # "anna" both exist while friend search and friend requests — both
    # case-insensitive — could only ever reach one of them. See
    # app/usernames.py for the full story.
    existing = (
        db.query(models.User.id)
        .filter(
            or_(
                models.User.username_lower == normalized,
                func.lower(models.User.username) == normalized,
            )
        )
        .first()
    )
    if existing:
        raise HTTPException(status_code=400, detail="Username already taken")

    try:
        password_hash = hash_password(payload.password)
    except ValueError:
        raise HTTPException(status_code=400, detail="Password is too long")

    # See friends.py's own docstring on InviteOut — a code is minted
    # lazily per account and reusable by anyone, so this is just a
    # lookup, not a one-time-use redemption. Matched case-insensitively
    # since codes are meant to be read aloud/typed by hand. An unknown
    # code (typo, or simply none entered) is silently ignored rather than
    # blocking account creation over it.
    referred_by_id = None
    code = (payload.referral_code or "").strip()
    if code:
        referrer = (
            db.query(models.User)
            .filter(
                func.upper(models.User.invite_code) == code.upper(),
                models.User.deleted_at.is_(None),
            )
            .first()
        )
        if referrer:
            referred_by_id = referrer.id

    user = models.User(
        username=display_username,
        username_lower=normalized,
        password_hash=password_hash,
        referred_by_id=referred_by_id,
        signup_ip=_client_key(request),
        # Registration is the one place acceptance is unambiguous: the
        # sign-up screen shows the agreement and the button says so. An
        # account created before the EULA existed gets prompted on next
        # launch instead (see POST /auth/eula).
        eula_version=settings.eula_version,
        eula_accepted_at=datetime.now(timezone.utc),
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    if referred_by_id:
        # See routers/referrals.py — turns the plain referred_by_id fact
        # above into the reward program's own pending Referral row.
        create_referral_for_signup(db, referrer_id=referred_by_id, referred_id=user.id, ip=_client_key(request))
        # See app/sincerity.py::earn_friend_invited — the sincerity side
        # of the same event, for the referrer.
        if referrer is not None:
            sincerity.earn_friend_invited(db, referrer, friend_name=user.username)
            db.commit()

    # A token pair straight from registration rather than a 201 that
    # sends the client back to sign in. Kept from the original design on
    # purpose: the person has just proven they know the credentials by
    # choosing them a moment ago, and a signup flow that ends at a login
    # form is a needless wall in front of the first thing they came to do.
    return _issue_session(db, user, request, payload.device_label)


# A hash of this exact password never needs to match anything real — it
# exists purely so login() below can run bcrypt's slow comparison even
# when the username doesn't exist, so "no such user" and "wrong
# password" take the same amount of time. Computed once at import time,
# not per-request (bcrypt is deliberately slow; doing this per-request
# would defeat the point of caching it).
_DUMMY_PASSWORD_HASH = hash_password("not-a-real-password-just-for-timing")


def _find_by_username(db: Session, raw: str) -> models.User | None:
    normalized = normalize_username(raw)
    return (
        db.query(models.User)
        .filter(
            or_(
                models.User.username_lower == normalized,
                func.lower(models.User.username) == normalized,
            )
        )
        .first()
    )


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest, request: Request, db: Session = Depends(get_db)):
    login_limiter.check(db, _client_key(request))
    user = _find_by_username(db, payload.username)
    # Always runs a real bcrypt comparison, even when there's no such
    # user — verify_password against a hash nobody has is exactly as
    # slow as verifying a wrong password against a real one, so a
    # response-time difference can't leak which usernames exist.
    password_ok = verify_password(payload.password, user.password_hash if user else _DUMMY_PASSWORD_HASH)
    if not user or not password_ok:
        raise HTTPException(status_code=401, detail="Invalid username or password")

    if user.deleted_at is not None:
        # Correct credentials for an account inside its deletion grace
        # window. Answering with a 403 that says exactly this — rather
        # than a generic failure — is the whole point of the grace
        # period: the person gets told their account is recoverable and
        # exactly how long they have, at the moment they're most likely
        # to want it back.
        remaining = max(0, (user.purge_after - datetime.now(timezone.utc)).days) if user.purge_after else 0
        raise HTTPException(
            status_code=403,
            detail=(
                f"This account is scheduled for deletion and will be erased in "
                f"{remaining} day(s). You can still restore it."
            ),
            headers={"X-Account-Restorable": "true"},
        )

    return _issue_session(db, user, request, payload.device_label)


@router.post("/refresh", response_model=TokenResponse)
def refresh(payload: RefreshRequest, request: Request, db: Session = Depends(get_db)):
    """Trades a refresh token for a fresh pair, rotating the refresh half.

    Every branch below that isn't the happy path returns the same 401, on
    purpose: the client's correct response to all of them is identical
    (drop the tokens, show the login screen), and distinguishing "expired"
    from "revoked" from "replayed" for the caller only helps someone
    probing with stolen tokens.
    """
    refresh_limiter.check(db, _client_key(request))

    token_hash = hash_refresh_token(payload.refresh_token)
    session = db.query(models.RefreshSession).filter_by(token_hash=token_hash).first()

    invalid = HTTPException(
        status_code=401,
        detail="Session expired — sign in again",
        headers={"WWW-Authenticate": 'Bearer error="token_revoked"'},
    )
    if session is None:
        raise invalid

    if session.rotated_at is not None:
        # Replay. This token was already exchanged, so two parties hold
        # it — the legitimate device and whoever took a copy — and
        # there's no way to tell which one just called. Revoking the
        # whole family is the OAuth 2.0 security BCP's answer: both are
        # forced to sign in with a password, which the thief can't. The
        # cost is that a device with flaky connectivity that retries a
        # refresh it had actually completed gets signed out; that's a
        # rare annoyance traded against a stolen token being usable for
        # two months.
        db.query(models.RefreshSession).filter(
            models.RefreshSession.family_id == session.family_id,
            models.RefreshSession.revoked_at.is_(None),
        ).update(
            {"revoked_at": datetime.now(timezone.utc), "revoked_reason": "rotation_reuse"},
            synchronize_session=False,
        )
        db.commit()
        raise invalid

    if session.revoked_at is not None or session.expires_at <= datetime.now(timezone.utc):
        raise invalid

    user = db.get(models.User, session.user_id)
    if user is None or user.deleted_at is not None:
        raise invalid

    session.rotated_at = datetime.now(timezone.utc)
    session.last_used_at = datetime.now(timezone.utc)

    new_raw = generate_refresh_token()
    new_session = models.RefreshSession(
        user_id=user.id,
        token_hash=hash_refresh_token(new_raw),
        family_id=session.family_id,
        device_label=session.device_label,
        created_ip=_client_key(request),
        expires_at=refresh_token_expiry(),
        last_used_at=datetime.now(timezone.utc),
    )
    db.add(new_session)
    db.flush()
    session.replaced_by_id = new_session.id
    db.commit()

    return TokenResponse(
        access_token=create_access_token(user.id, token_version=int(user.token_version or 0)),
        refresh_token=new_raw,
        expires_in=settings.jwt_expire_minutes * 60,
    )


@router.post("/logout", status_code=204)
def logout(payload: RefreshRequest, db: Session = Depends(get_db)):
    """Ends one device's session. Unauthenticated on purpose — it takes
    the refresh token as proof, which means it still works when the
    access token has already expired, which is exactly the state an app
    being signed out of is usually in. Presenting a token that doesn't
    resolve is a no-op rather than an error: the caller wanted to be
    signed out, and it is."""
    session = (
        db.query(models.RefreshSession)
        .filter_by(token_hash=hash_refresh_token(payload.refresh_token))
        .first()
    )
    if session is not None and session.revoked_at is None:
        session.revoked_at = datetime.now(timezone.utc)
        session.revoked_reason = "logout"
        db.commit()
    return Response(status_code=204)


@router.get("/sessions", response_model=list[SessionOut])
def list_sessions(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """"Where you're signed in" — every live device, plus recently
    revoked ones so a lost phone's sign-out is visible after the fact."""
    rows = (
        db.query(models.RefreshSession)
        .filter(
            models.RefreshSession.user_id == current_user.id,
            models.RefreshSession.rotated_at.is_(None),
        )
        .order_by(models.RefreshSession.last_used_at.desc().nullslast())
        .limit(30)
        .all()
    )
    return [
        SessionOut(
            id=s.id,
            device_label=s.device_label,
            created_at=s.created_at,
            last_used_at=s.last_used_at,
            expires_at=s.expires_at,
            revoked=s.revoked_at is not None,
            revoked_reason=s.revoked_reason,
        )
        for s in rows
    ]


@router.post("/sessions/revoke-others", response_model=SimpleMessageOut)
def revoke_other_sessions(
    payload: RefreshRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """"Sign out everywhere else." Takes the caller's own refresh token so
    the device issuing the command can be spared — see
    account_deletion.revoke_all_sessions' `keep_session_id`."""
    mine = (
        db.query(models.RefreshSession)
        .filter_by(token_hash=hash_refresh_token(payload.refresh_token), user_id=current_user.id)
        .first()
    )
    count = account_deletion.revoke_all_sessions(
        db, current_user.id, reason="logout_all", keep_session_id=mine.id if mine else None
    )
    db.commit()
    return SimpleMessageOut(message=f"Signed out of {count} other device(s)")


# ---------------------------------------------------------------------------
# Password
# ---------------------------------------------------------------------------

@router.post("/password", response_model=TokenResponse)
def change_password(
    payload: PasswordChangeRequest,
    request: Request,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Requires the current password even though the caller is already
    authenticated — a phone left unlocked on a table shouldn't be enough
    to lock its owner out of their own account.

    Every other session dies here (token_version bump + session
    revocation) and the caller gets a brand-new pair back, which is why
    this returns tokens rather than a 204: the change would otherwise
    invalidate the very token that made the request.
    """
    if not verify_password(payload.current_password, current_user.password_hash):
        raise HTTPException(status_code=401, detail="Current password is incorrect")
    if payload.current_password == payload.new_password:
        raise HTTPException(status_code=400, detail="That's the password you already have")

    try:
        current_user.password_hash = hash_password(payload.new_password)
    except ValueError:
        raise HTTPException(status_code=400, detail="Password is too long")

    current_user.token_version = int(current_user.token_version or 0) + 1
    account_deletion.revoke_all_sessions(db, current_user.id, reason="password_change")
    db.commit()

    return _issue_session(db, current_user, request, payload.device_label)


@router.post("/password/forgot", response_model=SimpleMessageOut)
def forgot_password(payload: PasswordForgotRequest, request: Request, db: Session = Depends(get_db)):
    """Always answers the same way, whether or not the address belongs to
    an account.

    This costs a little usability — someone who typos their address gets
    a cheerful "check your mail" and no mail — and buys the thing that
    matters more: this endpoint is unauthenticated and takes an email
    address, so a distinguishing response would turn it into a free
    "is this person on tanè" oracle for any address anyone cares to try.
    The generic answer is the standard practice for exactly that reason.

    Reset is also restricted to *verified* addresses. An unverified one
    only proves someone typed it — possibly a typo landing on a
    stranger's inbox — and mailing a password-reset link to an address
    nobody has proven they own is handing out the account.
    """
    password_reset_limiter.check(db, _client_key(request))
    generic = SimpleMessageOut(
        message="If that address is on a tanè account, a reset link is on its way."
    )

    email = normalize_email(payload.email)
    user = (
        db.query(models.User)
        .filter(
            models.User.email == email,
            models.User.email_verified.is_(True),
            models.User.deleted_at.is_(None),
        )
        .first()
    )
    if user is None:
        return generic

    raw = generate_link_token()
    db.add(models.AccountToken(
        user_id=user.id,
        purpose=models.AccountTokenPurpose.password_reset,
        token_hash=hash_link_token(raw),
        email=email,
        expires_at=datetime.now(timezone.utc) + timedelta(minutes=settings.password_reset_ttl_minutes),
        created_ip=_client_key(request),
    ))
    # Any earlier unused reset link for this account stops working the
    # moment a new one is requested. Otherwise "I clicked request three
    # times" leaves three live keys to the account in an inbox.
    db.query(models.AccountToken).filter(
        models.AccountToken.user_id == user.id,
        models.AccountToken.purpose == models.AccountTokenPurpose.password_reset,
        models.AccountToken.consumed_at.is_(None),
        models.AccountToken.token_hash != hash_link_token(raw),
    ).update({"consumed_at": datetime.now(timezone.utc)}, synchronize_session=False)
    db.commit()

    base = settings.public_web_base_url.rstrip("/") or f"{settings.app_custom_scheme}://reset"
    link = f"{base}/reset-password?token={raw}"
    try:
        send_password_reset(email, user.username, link, settings.password_reset_ttl_minutes)
    except Exception:  # noqa: BLE001
        # A mail failure must not change the response — see the docstring.
        # Logged by the mailer; the person can try again.
        pass
    return generic


@router.post("/password/reset", response_model=SimpleMessageOut)
def reset_password(payload: PasswordResetRequest, db: Session = Depends(get_db)):
    token = (
        db.query(models.AccountToken)
        .filter_by(
            token_hash=hash_link_token(payload.token),
            purpose=models.AccountTokenPurpose.password_reset,
        )
        .first()
    )
    if token is None or token.expires_at <= datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="That reset link has expired — request a new one")
    if token.consumed_at is not None:
        raise HTTPException(status_code=400, detail="That reset link was already used")

    user = db.get(models.User, token.user_id)
    if user is None or user.deleted_at is not None:
        raise HTTPException(status_code=400, detail="That reset link is no longer valid")

    try:
        user.password_hash = hash_password(payload.new_password)
    except ValueError:
        raise HTTPException(status_code=400, detail="Password is too long")

    token.consumed_at = datetime.now(timezone.utc)
    # A reset is the response to "someone may have my password", so every
    # existing session goes — including, especially, whoever's session
    # prompted the reset in the first place.
    user.token_version = int(user.token_version or 0) + 1
    account_deletion.revoke_all_sessions(db, user.id, reason="password_change")
    db.commit()
    return SimpleMessageOut(message="Password changed — sign in with your new one.")


# ---------------------------------------------------------------------------
# Email
# ---------------------------------------------------------------------------

@router.post("/email", response_model=SimpleMessageOut)
def set_email(
    payload: EmailSetRequest,
    request: Request,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Adds or changes the recovery address and sends a confirmation link.

    Requires the account password. An address is the one credential that
    can be traded for the account itself (via reset), so being able to
    set it from an unlocked phone without knowing the password would make
    the password irrelevant.
    """
    email_verify_limiter.check(db, _client_key(request))
    if not verify_password(payload.password, current_user.password_hash):
        raise HTTPException(status_code=401, detail="Password is incorrect")

    email = normalize_email(payload.email)
    taken = (
        db.query(models.User.id)
        .filter(models.User.email == email, models.User.id != current_user.id)
        .first()
    )
    if taken:
        # Unlike forgot-password above, this is fine to answer honestly:
        # the caller is authenticated, so the leak is "this address is in
        # use by *someone*" to a known account holder, and the
        # alternative — silently accepting an address that will never
        # verify — is a worse failure.
        raise HTTPException(status_code=400, detail="That address is already on another account")

    current_user.email = email
    current_user.email_verified = False
    db.commit()

    raw = generate_link_token()
    db.add(models.AccountToken(
        user_id=current_user.id,
        purpose=models.AccountTokenPurpose.email_verify,
        token_hash=hash_link_token(raw),
        email=email,
        expires_at=datetime.now(timezone.utc) + timedelta(minutes=settings.email_verify_ttl_minutes),
        created_ip=_client_key(request),
    ))
    db.commit()

    base = settings.public_web_base_url.rstrip("/") or f"{settings.app_custom_scheme}://verify"
    try:
        send_email_verification(
            email, current_user.username,
            f"{base}/verify-email?token={raw}",
            settings.email_verify_ttl_minutes,
        )
    except Exception:  # noqa: BLE001
        pass
    return SimpleMessageOut(message=f"Confirmation link sent to {email}")


@router.post("/email/verify", response_model=SimpleMessageOut)
def verify_email(payload: EmailVerifyRequest, db: Session = Depends(get_db)):
    """The link in the mail points at the web landing page, which calls
    this. Kept as a POST rather than a GET so a mail client's link
    prefetcher — or a corporate scanner that follows every URL in every
    incoming message — can't consume the one-time token before the
    person ever sees it."""
    row = (
        db.query(models.AccountToken)
        .filter_by(
            token_hash=hash_link_token(payload.token),
            purpose=models.AccountTokenPurpose.email_verify,
        )
        .first()
    )
    if row is None or row.expires_at <= datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="That link has expired — request a new one")
    if row.consumed_at is not None:
        raise HTTPException(status_code=400, detail="That address is already confirmed")

    user = db.get(models.User, row.user_id)
    if user is None:
        raise HTTPException(status_code=400, detail="That link is no longer valid")
    # Only ever confirms the address the link was mailed to — see
    # models.AccountToken.email. If the person has since typed a
    # different address into settings, an old link must not silently
    # confirm it.
    if normalize_email(user.email or "") != row.email:
        raise HTTPException(status_code=400, detail="That link was for a different address")

    user.email_verified = True
    row.consumed_at = datetime.now(timezone.utc)
    db.commit()
    return SimpleMessageOut(message="Email confirmed — you can recover your account with it now.")


# ---------------------------------------------------------------------------
# EULA
# ---------------------------------------------------------------------------

@router.post("/eula", response_model=SimpleMessageOut)
def accept_eula(
    payload: EulaAcceptRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Records acceptance for accounts that predate the agreement, or
    that need to re-accept after settings.eula_version changes. New
    accounts record it at registration instead."""
    current_user.eula_version = payload.version or settings.eula_version
    current_user.eula_accepted_at = datetime.now(timezone.utc)
    db.commit()
    return SimpleMessageOut(message="Thanks — agreement recorded.")


# ---------------------------------------------------------------------------
# Account: me / export / delete / restore
# ---------------------------------------------------------------------------

@router.get("/me", response_model=UserOut)
def me(current_user: models.User = Depends(get_current_user)):
    return UserOut.model_validate(current_user, from_attributes=True).model_copy(update={
        "eula_current": current_user.eula_version == settings.eula_version,
    })


@router.get("/export")
def export_my_data(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Everything this account holds, as one downloadable JSON file
    (GDPR art. 20). Deliberately available to a suspended account too —
    see app/deps.py::get_active_user — since a moderation decision about
    how someone behaves toward other people is not a reason to withhold
    their own archive from them.

    Streamed as an attachment rather than a plain body so the phone's
    share sheet treats it as a file, which is what makes it useful.
    """
    payload = account_deletion.build_export(db, current_user)
    filename = f"tane-export-{current_user.username}-{datetime.now(timezone.utc).date().isoformat()}.json"
    return JSONResponse(
        content=payload,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.delete("/account", response_model=AccountDeletionOut)
def delete_account(
    payload: AccountDeleteRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """In-app account deletion — App Store guideline 5.1.1(v), GDPR art.
    17, 152-ФЗ. Requires the password: this is the single most
    destructive action in the app, and an unlocked phone shouldn't be
    enough to trigger it.

    The account becomes invisible to everyone immediately and every
    session ends; the rows are destroyed after
    settings.account_purge_after_days. See app/account_deletion.py for
    what survives and why.
    """
    if not verify_password(payload.password, current_user.password_hash):
        raise HTTPException(status_code=401, detail="Password is incorrect")

    email = current_user.email if current_user.email_verified else None
    username = current_user.username

    purge_after = account_deletion.request_deletion(db, current_user)

    if email:
        # The one piece of the flow that isn't in the app: if someone
        # else got hold of the account and deleted it, the real owner's
        # only warning is in their inbox.
        try:
            send_deletion_scheduled(
                email, username, purge_after.date().isoformat(),
                settings.account_purge_after_days,
            )
        except Exception:  # noqa: BLE001
            pass

    return AccountDeletionOut(
        deleted_at=datetime.now(timezone.utc),
        purge_after=purge_after,
        restore_days=settings.account_purge_after_days,
        message=(
            f"Your account is deleted. Everything in it is erased for good on "
            f"{purge_after.date().isoformat()} — until then, signing in restores it."
        ),
    )


@router.post("/account/restore", response_model=TokenResponse)
def restore_account(payload: AccountRestoreRequest, request: Request, db: Session = Depends(get_db)):
    """Undoes a deletion request inside the grace window.

    Authenticates with username and password rather than a token, and
    has to: `request_deletion` revoked every token the account had, and
    app/deps.py refuses any token belonging to a deleted account anyway.
    Requiring a live session to undo a deletion would make the grace
    period unusable for the exact case it exists for.
    """
    login_limiter.check(db, _client_key(request))
    user = _find_by_username(db, payload.username)
    password_ok = verify_password(payload.password, user.password_hash if user else _DUMMY_PASSWORD_HASH)
    if not user or not password_ok:
        raise HTTPException(status_code=401, detail="Invalid username or password")
    if user.deleted_at is None:
        raise HTTPException(status_code=400, detail="That account isn't scheduled for deletion")

    account_deletion.restore(db, user)
    return _issue_session(db, user, request, payload.device_label)
