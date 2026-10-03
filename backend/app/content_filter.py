"""The automated first pass over user-authored text — nicknames, status
lines, list names, diary notes.

Guideline 1.2 asks for "a method for filtering objectionable content" in
addition to reporting and blocking. This is that method, and it's
deliberately modest about what it can do. Three principles shaped it:

1. **Structure over vocabulary.** The checks that do the most work here
   don't look for particular words at all — they look for the shapes
   abuse and spam take regardless of language: invisible characters used
   to slip past filters or to spoof display order, links in fields that
   have no business containing links, contact handles in a nickname, a
   wall of the same character. Those generalize across Russian and
   English (this app is bilingual), can't be defeated by a synonym, and
   have almost no false positives.

2. **No slur list in the source tree.** The word list lives in a file
   the deployment supplies (`settings.content_blocklist_path`), one
   term per line, loaded at startup. Keeping it out of the repository
   means it can be updated without a deploy, tuned per market, and
   maintained by whoever handles moderation rather than by whoever
   handles releases. An empty or missing file just means the structural
   checks run alone — the app works, it's simply less strict.

3. **Refuse loudly, don't silently mangle.** A filter that quietly
   rewrites what someone typed produces confusing bugs and teaches
   nothing. `check()` raises with a message meant to be shown as-is.

What this deliberately does NOT do is decide anything hard. Context,
sarcasm, reclaimed language, and the difference between describing abuse
and committing it are all beyond a regex, which is exactly why the
report queue in routers/moderation.py exists and why nothing here
suspends anybody.
"""

from __future__ import annotations

import logging
import re
import unicodedata
from functools import lru_cache
from pathlib import Path

from app.config import settings

logger = logging.getLogger("uvicorn.error")


class ContentRejected(ValueError):
    """Message is meant to be shown to the person as-is."""


# Zero-width and bidirectional-override characters. Used both to defeat
# naive word filters ("b\u200bad") and to build display-order spoofs in a
# friends list; neither has a legitimate use in a nickname or a note.
_INVISIBLE = re.compile(
    "["
    "\u200b-\u200f"  # zero-width space/non-joiner/joiner, LTR/RTL marks
    "\u202a-\u202e"  # embedding/override
    "\u2066-\u2069"  # isolates
    "\ufeff"         # BOM
    "]"
)

_URL = re.compile(r"(https?://|www\.|\b[\w.-]+\.(?:com|net|org|ru|io|xyz|top|me|tk|link)\b)", re.I)

# Handles for the places people get moved off-platform to. Catching these
# in a *nickname* or *status line* is most of the anti-spam value in this
# module: the classic pattern is an account whose whole purpose is to put
# a Telegram handle in front of strangers in a friends list.
_CONTACT = re.compile(r"(?:@[A-Za-z0-9_]{4,}|t\.me/|telegram\.me/|wa\.me/|\+\d{8,15})")

_REPEATED = re.compile(r"(.)\1{7,}", re.S)


@lru_cache(maxsize=1)
def _blocklist() -> frozenset[str]:
    """One term per line, '#' comments allowed, case-insensitive.

    Cached for the process lifetime — this is read on every profile edit
    and every diary note, and re-reading a file each time would be a
    disk hit on a hot path. A change to the file therefore needs a
    restart, which is the right trade for a list that changes monthly at
    most.
    """
    path = (settings.content_blocklist_path or "").strip()
    if not path:
        return frozenset()
    try:
        raw = Path(path).read_text(encoding="utf-8")
    except OSError:
        logger.warning("content blocklist not readable at %s — structural checks only", path)
        return frozenset()
    terms = {
        line.strip().casefold()
        for line in raw.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }
    logger.info("content blocklist loaded: %d terms", len(terms))
    return frozenset(terms)


def _normalize_for_matching(text: str) -> str:
    """Folds the cheap evasions before the word list sees the text.

    NFKD then stripping combining marks turns "ｂａd" and "b\u0301ad" into
    "bad"; casefold handles case; collapsing runs of the same letter
    handles "baaaad". Homoglyph substitution across scripts (Cyrillic "а"
    for Latin "a") is *not* folded, for the same reason app/usernames.py
    doesn't: doing so would break every Russian word in the list against
    itself. That gap is real and is what the report queue covers.
    """
    decomposed = unicodedata.normalize("NFKD", text)
    stripped = "".join(ch for ch in decomposed if not unicodedata.combining(ch))
    folded = _INVISIBLE.sub("", stripped).casefold()
    return re.sub(r"(.)\1{2,}", r"\1\1", folded)


def check(
    text: str | None,
    *,
    field: str = "text",
    allow_links: bool = False,
    allow_contacts: bool = False,
) -> str | None:
    """Returns the text unchanged, or raises [ContentRejected].

    `allow_links`/`allow_contacts` default to False because the fields
    this runs on — nickname, status line, list name, diary note — have no
    use for either, and the one place a link genuinely belongs ("your
    sources", see routers/sources.py) doesn't go through this at all.
    """
    if text is None:
        return None
    if not text.strip():
        return text

    if _INVISIBLE.search(text):
        raise ContentRejected(f"Your {field} contains invisible characters — please remove them")

    if not allow_links and _URL.search(text):
        raise ContentRejected(f"Links aren't allowed in your {field}")

    if not allow_contacts and _CONTACT.search(text):
        raise ContentRejected(f"Contact handles and phone numbers aren't allowed in your {field}")

    if _REPEATED.search(text):
        raise ContentRejected(f"Your {field} repeats a character too many times")

    terms = _blocklist()
    if terms:
        haystack = _normalize_for_matching(text)
        # Word-boundary matching for single words, substring for
        # multi-word phrases. A bare substring test over everything is
        # what produces the famous false positives (the Scunthorpe
        # problem), and this app has real users with real names.
        for term in terms:
            if " " in term:
                if term in haystack:
                    raise ContentRejected(f"That {field} isn't allowed here")
            elif re.search(rf"(?<!\w){re.escape(term)}(?!\w)", haystack):
                raise ContentRejected(f"That {field} isn't allowed here")

    return text
