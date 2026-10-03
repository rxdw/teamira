"""Rules for circle reviews ("Рецензия круга"): the joint review of an
evening watched together.

Two sources open one — a finished co-view room, or an ordinary diary log
with the "watched with" toggle — and both end up in the same place: each
person writes their own rating, tags and a line, sealed from the others
until everyone has written or a week has passed. The shared verdict is then
*derived*, never stored: it is a plain function of the entries, so it can
never drift from them and needs no model call.

Premium only touches one derived part, the moments timeline (see
`build_moments`); the review itself, including the verdict, is free.
"""

from __future__ import annotations

from collections import Counter
from datetime import date, datetime, timedelta, timezone

REVIEW_TTL = timedelta(days=7)
# A second log of the same title within this window belongs to the same
# evening's review rather than starting another.
REUSE_WINDOW = timedelta(days=3)

MAX_TAGS = 6
TAG_MAX_CHARS = 24
LINE_MAX_CHARS = 280

MOMENT_WINDOW_MS = 30_000

# What a finished round of a game counts as (see co_play.ROUND_MOMENT_KEYS).
from app.co_play import ROUND_MOMENT_KEYS  # noqa: E402

# What a margin note and a highlight count as in a book's moments timeline.
MARGIN_KEY = "📝"
HIGHLIGHT_KEY = "🖍"


def _moment_key(e: dict) -> str | None:
    """The emoji an event adds to a moment, or None when it isn't one."""
    kind = e.get("kind")
    if kind in ("reaction", "emotion"):
        return e.get("emoji") or None
    if kind == "margin":
        return MARGIN_KEY
    if kind == "highlight" and e.get("emoji") == "on":
        return HIGHLIGHT_KEY
    if kind == "round":
        return ROUND_MOMENT_KEYS.get(e.get("emoji"))
    return None
MAX_MOMENTS = 5

# "The book of your evenings" (GET /partner/reviews/book) carries the whole
# circle's opened reviews in one response, so it has a ceiling. When a circle
# has more evenings than this, the newest ones make the book.
BOOK_MAX_REVIEWS = 200


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _aware(dt: datetime) -> datetime:
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def is_expired(expires_at: datetime, now: datetime | None = None) -> bool:
    return (now or utcnow()) >= _aware(expires_at)


def clean_tags(tags: list[str] | None) -> list[str]:
    """Trimmed, de-duplicated (case-insensitively), capped — the same shape
    the diary's own mood tags have."""
    out: list[str] = []
    seen: set[str] = set()
    for raw in tags or []:
        text = (raw or "").strip()
        if not text:
            continue
        if len(text) > TAG_MAX_CHARS:
            text = text[:TAG_MAX_CHARS].rstrip()
        key = text.casefold()
        if key in seen:
            continue
        seen.add(key)
        out.append(text)
        if len(out) >= MAX_TAGS:
            break
    return out


def all_done(expected_ids: list[str], done_ids: set[str]) -> bool:
    return bool(expected_ids) and all(uid in done_ids for uid in expected_ids)


def should_reveal(expected_ids: list[str], done_ids: set[str], expires_at: datetime, now: datetime | None = None) -> bool:
    return all_done(expected_ids, done_ids) or is_expired(expires_at, now)


def summarize(entries: list[dict]) -> dict:
    """The shared verdict. `entries` are dicts with `user_id`, `rating`
    (int or None), `tags` and `skipped`.

    verdict:
      unison — two or more ratings, all within one point of each other
      close  — within three points
      split  — four or more apart (the evening people argue about)
      solo   — fewer than two ratings, so nothing to compare
    shared_tags are the tags at least two people picked, most-picked first."""
    ratings = [e["rating"] for e in entries if not e.get("skipped") and e.get("rating") is not None]
    average = round(sum(ratings) / len(ratings), 1) if ratings else None
    spread = (max(ratings) - min(ratings)) if len(ratings) >= 2 else None
    if spread is None:
        verdict = "solo"
    elif spread <= 1:
        verdict = "unison"
    elif spread <= 3:
        verdict = "close"
    else:
        verdict = "split"

    counts: Counter[str] = Counter()
    display: dict[str, str] = {}
    for e in entries:
        if e.get("skipped"):
            continue
        for tag in set(t.casefold() for t in (e.get("tags") or [])):
            counts[tag] += 1
        for t in e.get("tags") or []:
            display.setdefault(t.casefold(), t)
    shared = sorted(((t, c) for t, c in counts.items() if c >= 2), key=lambda tc: (-tc[1], tc[0]))
    return {
        "average": average,
        "spread": spread,
        "verdict": verdict,
        "rated_count": len(ratings),
        "shared_tags": [display[t] for t, _ in shared],
    }


def build_moments(events: list[dict], *, window_ms: int = MOMENT_WINDOW_MS, limit: int = MAX_MOMENTS) -> list[dict]:
    """The reactions timeline: where in the film people felt something.

    `events` are dicts with `user_id`, `kind`, `emoji` and `position_ms`;
    only reactions and emotion taps count (chat and signals are
    conversation, not feeling) — and, in a book, the two things a reader does
    to a place besides reacting: a note in the margin (counted as ``MARGIN_KEY``)
    and a highlight switched on (``HIGHLIGHT_KEY``). Events are bucketed into
    fixed windows; a window is a *shared* moment when two or more different
    people reacted in it. Shared moments rank above solo ones, then by how much
    happened. The result is the top few in film order. When the events carry a
    `locator` (reading rooms) a moment names the place of its first event, so a
    book's timeline can say "chapter 4", not only "41%"."""
    buckets: dict[int, dict] = {}
    for e in events:
        key = _moment_key(e)
        if key is None or e.get("position_ms") is None:
            continue
        idx = int(e["position_ms"]) // window_ms
        b = buckets.setdefault(idx, {"users": set(), "keys": Counter(), "first": int(e["position_ms"]), "locator": None})
        if e.get("user_id"):
            b["users"].add(e["user_id"])
        b["keys"][key] += 1
        if int(e["position_ms"]) <= b["first"] or b["locator"] is None:
            b["locator"] = e.get("locator") or b["locator"]
        b["first"] = min(b["first"], int(e["position_ms"]))
    ranked = sorted(
        buckets.items(),
        key=lambda kv: (-(len(kv[1]["users"]) >= 2), -len(kv[1]["users"]), -sum(kv[1]["keys"].values()), kv[0]),
    )[:limit]
    moments = [
        {
            "position_ms": b["first"],
            "people": len(b["users"]),
            "shared": len(b["users"]) >= 2,
            "count": sum(b["keys"].values()),
            "top": b["keys"].most_common(1)[0][0],
            "keys": dict(b["keys"]),
            **({"locator": b["locator"]} if b["locator"] else {}),
        }
        for _, b in ranked
    ]
    moments.sort(key=lambda m: m["position_ms"])
    return moments


def has_printable_content(entries: list[dict]) -> bool:
    """Whether an opened review has anything worth a page in the book: at
    least one person left a rating, a tag or a line. A review where everybody
    chose to skip would print as an empty frame, so the book leaves it out.
    `entries` are dicts with `rating`, `tags`, `line` and `skipped`."""
    for e in entries:
        if e.get("skipped"):
            continue
        if e.get("rating") is not None or e.get("tags") or (e.get("line") or "").strip():
            return True
    return False


def default_expiry(now: datetime | None = None) -> datetime:
    return (now or utcnow()) + REVIEW_TTL


def evening_of(dt: datetime | None) -> date:
    return (_aware(dt) if dt else utcnow()).date()
