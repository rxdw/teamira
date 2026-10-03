"""Sends the three transactional emails this app has: verify your
address, reset your password, and "your account is scheduled for
deletion".

Two backends, chosen by `settings.email_backend`:

  - "console" (the default): logs the message instead of sending it.
    This is what makes the whole password-recovery flow developable and
    testable with zero configuration — the reset link shows up in the
    uvicorn log, which is exactly what a developer needs and exactly
    what a production deploy must not do. main.py's on_startup logs a
    SECURITY warning, the same way it does for an unset jwt_secret, if
    this is still "console" — that check lives there, not here, so it
    fires once at boot rather than on every call to `send`.
  - "smtp": a real server. Plain `smtplib` rather than an SDK — this is
    three short messages, not a marketing pipeline, and one fewer
    dependency that can go unmaintained.

**Not currently backgrounded.** `send()` is a plain blocking call —
smtplib does real network I/O and there is no `asyncio.to_thread` (or
equivalent) at any of the three call sites in routers/auth.py. On a slow
or unreachable SMTP server this holds the request open for the full
socket timeout, which is a real latency problem worth fixing before this
carries production traffic; it does not affect correctness, since every
call site already wraps the send in try/except and treats a failure as
non-fatal (a password-reset request that couldn't send mail still
returns the same generic response as one that could — see the
enumeration note in routers/auth.py — so failing loudly at the API would
itself leak which addresses exist).
"""

from __future__ import annotations

import logging
import smtplib
import ssl
from email.message import EmailMessage

from app.config import settings

logger = logging.getLogger("uvicorn.error")


class EmailNotConfigured(RuntimeError):
    pass


def _render(subject: str, body_text: str) -> EmailMessage:
    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = settings.email_from or "tane <no-reply@localhost>"
    msg.set_content(body_text)
    return msg


def send(to_email: str, subject: str, body_text: str) -> bool:
    """Returns True if the message was handed off to a real mail server.

    False means "console backend" — the caller can use that to decide
    whether to include the link in its own response body, which is the
    difference between a usable local dev loop and a catastrophic
    production leak.
    """
    if settings.email_backend.strip().lower() != "smtp":
        logger.info(
            "[email:console] to=%s subject=%s\n---\n%s\n---",
            to_email, subject, body_text,
        )
        return False

    if not settings.smtp_host:
        raise EmailNotConfigured("EMAIL_BACKEND=smtp but SMTP_HOST is unset")

    msg = _render(subject, body_text)
    msg["To"] = to_email

    context = ssl.create_default_context()
    if settings.smtp_use_ssl:
        server = smtplib.SMTP_SSL(settings.smtp_host, settings.smtp_port, context=context, timeout=15)
    else:
        server = smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=15)
    try:
        if not settings.smtp_use_ssl and settings.smtp_use_tls:
            server.starttls(context=context)
        if settings.smtp_username:
            server.login(settings.smtp_username, settings.smtp_password)
        server.send_message(msg)
    finally:
        try:
            server.quit()
        except Exception:  # noqa: BLE001 — a failed QUIT after a sent message isn't a failure
            pass
    return True


# --- The three messages ----------------------------------------------------
#
# Written in the app's own voice (lowercase, unhurried) rather than
# corporate transactional-email register, because they're the only
# emails anyone gets from this app and they should read like they came
# from the same place the diary did. Plain text only — an HTML email
# adds a rendering surface, a tracking-pixel question, and a spam-score
# problem in exchange for nothing these three messages need.


def send_password_reset(to_email: str, username: str, link: str, ttl_minutes: int) -> bool:
    return send(
        to_email,
        "reset your tanè password",
        f"hi {username},\n\n"
        f"someone asked to reset the password for your tanè diary. if that was you, "
        f"open this link within {ttl_minutes} minutes:\n\n"
        f"{link}\n\n"
        f"if it wasn't you, you can ignore this — nothing has changed, and your "
        f"password still works.\n\n"
        f"— tanè\n",
    )


def send_email_verification(to_email: str, username: str, link: str, ttl_minutes: int) -> bool:
    return send(
        to_email,
        "confirm your email for tanè",
        f"hi {username},\n\n"
        f"confirming this address is what lets you get back into your diary if you "
        f"ever forget your password. open this link within {ttl_minutes} minutes:\n\n"
        f"{link}\n\n"
        f"if you didn't add this address to a tanè account, you can ignore this.\n\n"
        f"— tanè\n",
    )


def send_deletion_scheduled(to_email: str, username: str, purge_date: str, days: int) -> bool:
    return send(
        to_email,
        "your tanè account is scheduled for deletion",
        f"hi {username},\n\n"
        f"your account and everything in it — every evening you logged, every list, "
        f"every rating — is scheduled to be permanently deleted on {purge_date}.\n\n"
        f"until then you can change your mind: sign in with the same username and "
        f"password within {days} days and the account comes back exactly as it was. "
        f"after that date it's gone, and we won't be able to get it back.\n\n"
        f"if you didn't ask for this, sign in now and your account is restored.\n\n"
        f"— tanè\n",
    )
