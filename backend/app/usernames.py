"""One place that decides what a username is allowed to be, and what
two usernames being "the same" means.

This used to be spread across three files that quietly disagreed with
each other:

  - `schemas.RegisterRequest` stripped whitespace and rejected control
    characters, but compared nothing.
  - `routers/auth.py::register` checked for an existing account with
    `User.username == payload.username` — case *sensitively*.
  - `routers/friends.py::send_request` looked the target up with
    `func.lower(...) == ...casefold()` — case *insensitively*, as did
    invite-code matching in the same file.

So "Anna" and "anna" could both register, and then a friend request to
either of them resolved to whichever row the database happened to
return first. One of those two accounts was effectively unreachable
while still consuming the name. Worse, it's a ready-made impersonation
kit: register "Аnna" with a Cyrillic А and you have a profile
indistinguishable from someone else's in a friends list.

`normalize_username` is the single answer to "are these the same name",
and `models.User.username_lower` stores its output with a unique index
so the database enforces it rather than trusting every call site to
remember. The display form the person typed is kept untouched in
`username`.
"""

from __future__ import annotations

import re
import unicodedata

# Deliberately generous on scripts (Cyrillic and Latin names are both
# entirely normal here — see the mobile app's LocaleService) and strict
# on everything else. Letters, digits, and a few separators people
# actually use in handles; nothing that can be mistaken for structure.
_ALLOWED_PUNCT = set("._-")

MIN_USERNAME_LENGTH = 3
MAX_USERNAME_LENGTH = 24

# Names that would let an account impersonate the app, a system notice,
# or a staff member. Matched against the normalized form, so "Admin",
# "ADMIN" and "admin" are all covered by the one entry. Substring-style
# lookalikes (e.g. "admin_official") are deliberately NOT blocked — a
# blanket substring ban catches far more innocent names than abusive
# ones, and impersonation of that shape is what the report flow is for.
RESERVED_USERNAMES = frozenset(
    {
        "admin", "administrator", "moderator", "mod", "staff", "support",
        "help", "helpdesk", "team", "teamira", "tane", "seenly", "official",
        "system", "root", "superuser", "owner", "security", "billing",
        "payments", "noreply", "no-reply", "postmaster", "webmaster",
        "abuse", "legal", "privacy", "info", "contact", "api", "null",
        "undefined", "anonymous", "deleted", "deleted-user", "me", "you",
    }
)


class UsernameError(ValueError):
    """Raised with a message meant to be shown to the person as-is."""


def normalize_username(raw: str) -> str:
    """The canonical form of `raw` — what goes in `username_lower` and
    what every lookup compares against.

    NFKC first, then casefold. The order matters and both steps do real
    work:

      - NFKC collapses compatibility forms, so the fullwidth "ａｄｍｉｎ"
        and a handful of other lookalike encodings normalize to plain
        ASCII rather than sailing past the reserved-name list.
      - `casefold()` rather than `lower()`: German "ß" lowercases to
        itself but casefolds to "ss", so "STRAßE" and "strasse" compare
        equal the way a person would expect. `lower()` gets that wrong.

    Note this does NOT attempt to fold Cyrillic/Latin homoglyphs into
    each other (Cyrillic "а" stays distinct from Latin "a"). Doing so
    would make half the Russian alphabet unusable in usernames, which is
    a much bigger cost than it's worth here — visually-confusable
    impersonation is handled by the report flow, not by banning a
    language.
    """
    return unicodedata.normalize("NFKC", raw).strip().casefold()


def validate_username(raw: str) -> tuple[str, str]:
    """Returns `(display, normalized)` or raises [UsernameError].

    `display` is what the person typed, trimmed; `normalized` is what
    uniqueness is judged on.
    """
    display = unicodedata.normalize("NFKC", raw).strip()

    if not display:
        raise UsernameError("Username can't be blank")

    # Length is measured on the display form. Counting Unicode code
    # points rather than bytes, so a Russian name isn't silently allowed
    # half the length of an English one.
    if len(display) < MIN_USERNAME_LENGTH:
        raise UsernameError(f"Username must be at least {MIN_USERNAME_LENGTH} characters")
    if len(display) > MAX_USERNAME_LENGTH:
        raise UsernameError(f"Username must be at most {MAX_USERNAME_LENGTH} characters")

    for ch in display:
        if ch.isalnum() or ch in _ALLOWED_PUNCT:
            continue
        category = unicodedata.category(ch)
        if category.startswith("C"):
            # Control, format (including the RTL/LTR overrides and
            # zero-width joiners used to build display-order spoofs),
            # surrogate, private-use, unassigned.
            raise UsernameError("Username can't contain invisible or control characters")
        raise UsernameError("Username can only use letters, digits, and . _ -")

    # A name made entirely of separators is technically inside the rules
    # above and useless in practice.
    if not any(ch.isalnum() for ch in display):
        raise UsernameError("Username needs at least one letter or digit")

    # Runs of separators are the cheapest impersonation trick that
    # survives the checks above ("anna" vs "an..na" reads the same at a
    # glance in a crowded friends list).
    if re.search(r"[._-]{2,}", display):
        raise UsernameError("Username can't have two separators in a row")
    if display[0] in _ALLOWED_PUNCT or display[-1] in _ALLOWED_PUNCT:
        raise UsernameError("Username can't start or end with . _ -")

    normalized = normalize_username(display)
    if normalized in RESERVED_USERNAMES:
        raise UsernameError("That username is reserved")

    return display, normalized


def normalize_email(raw: str) -> str:
    """Case-folded, trimmed. Stricter than the RFC (which says the local
    part is case-sensitive) and deliberately so — no mail provider in
    practice treats it as case-sensitive, and matching that expectation
    avoids "I typed it with a capital and now it says no such account"
    lockouts on the one flow that exists to rescue people.
    """
    return unicodedata.normalize("NFKC", raw).strip().casefold()
