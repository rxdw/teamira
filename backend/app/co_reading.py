"""Rules for reading together: a book or a manga read in the same room.

A reading room is the same room as a watching one (see app/co_view_room.py)
— same circle, guests, chat, voice, reactions, signals, "save to our list"
and joint review. What changes is only *what is kept in sync*, and everything
that can be decided without a database lives here so it can be tested
directly and the router stays a thin shell.

Design notes that shaped the rules:

* **The app never carries the text.** A reading room does not host or relay
  a single page of anybody's book. Each person opens their own copy (their
  own EPUB or CBZ on their own device, or the title on whatever official site
  they read it on); the room only keeps *where everyone is*. The one thing a
  room knows about a file is its fingerprint (`content_hash`, a SHA-256
  computed on the device), which is how two phones tell whether they hold the
  same edition and therefore whether a place on one is the same place on
  the other.

* **A place is a locator, not a page number.** Pages of a book are different
  on every screen (font, size, margins), so a place in a book is
  "chapter + paragraph" — stable for the same file everywhere:

      epub      c{chapter}:p{paragraph}     both 0-based; the paragraph
                                            may be left off (= 0)
      cbz       p{page}                      0-based page of the archive
      parallel  c{chapter}                   0-based "chapter" counter for
                                            something read elsewhere (the
                                            screen shows chapter + 1)

* **Progress is a permille (0..1000)** worked out on the device, because
  only the device knows how long the book is. It is what draws the bar, the
  partner's marker, and — scaled by `PROGRESS_STEP_MS` — what is stored in
  an event's `position_ms`. That scaling is deliberate: the moments timeline
  (app/circle_review.py::build_moments) buckets reactions by `position_ms`
  in 30-second windows, so with one permille standing in for one second a
  window is three per cent of the book. The timeline of an evening of
  reading therefore needs no code of its own.

* **Three ways to be in the room.** `own`: everybody reads at their own pace
  and sees where the others are. `together`: the circle turns the same page
  — any member of the circle can move the shared place (a room with a single
  remote is a room people quarrel in), and everyone follows it. `aloud`: one
  person reads out loud over the room's voice and everyone else follows a
  highlighted paragraph — the one place where the remote *does* have a single
  owner, because two people can't read the same line aloud. Anybody in the
  circle can take the reading over ("читать вместо …"); then they are the
  reader. Only for a book drawn from text (there is nothing to read aloud off
  a comic page or a chapter counter).

* **Marks.** Besides reactions, a place can carry a *note in the margin*
  (free text, filtered) and a *highlight* (a soft tint on a paragraph, one per
  person per paragraph, switched on and off). Both live in the room's event
  ledger; `reduce_marks` is what turns that ledger into "what is on the pages
  right now", and the server hands it to every client with the room — the
  state push only carries the last few events, so a book read over a week
  could not rebuild its margins from those.

* **A quote for the album.** In a couple's room a paragraph can be sent to the
  pair album as a *quote note*: it goes into the person's sealed note for this
  title (the album's own rule — one sealed note per person per viewing, opened
  for both when the evening is marked watched), so the quotes you each set
  aside appear when you finish the book together. A note is a sticky note, not
  a letter (`pair_album.NOTE_MAX_CHARS`), so a quote is short (`ALBUM_QUOTE_MAX_CHARS`)
  and what does not fit is refused rather than cut.

* **Free text exists in two places** — chat and margin notes — and both go
  through the content filter. Everything else is an allow-listed key.
"""

from __future__ import annotations

import re

# What a room is about: a film's clock, a place in a book (this module), or a
# real game played on everybody's own machine (app/co_play.py).
ACTIVITIES = ("watch", "read", "play")

# How the text reaches each person.
#   epub      their own DRM-free EPUB, drawn by the app
#   cbz       their own comic archive (CBZ/ZIP of images), drawn by the app
#   parallel  read anywhere else (an official site, paper); the room only
#             keeps the shared chapter counter, notes, voice and reactions
READ_KINDS = ("epub", "cbz", "parallel")

READ_MODES = ("own", "together", "aloud")

# Only text can be read aloud.
ALOUD_KINDS = ("epub",)

# A highlight event's `emoji` field: on, or off again.
HIGHLIGHT_ON = "on"
HIGHLIGHT_OFF = "off"

# What a reading room can be about. (The room's `media_type` column is the
# same enum the watching rooms use.)
READING_MEDIA_TYPES = ("book", "manga")

PROGRESS_MAX = 1000
# One permille of the book is this many "milliseconds" in the room's clock
# units; see the module docstring.
PROGRESS_STEP_MS = 1000
READ_DURATION_MS = PROGRESS_MAX * PROGRESS_STEP_MS

# "Read to the end" from here on; the client offers the finishing ritual.
READ_DONE_PERMILLE = 970

MAX_UNITS = 100_000          # chapters or pages; anything bigger is a bug
MAX_CHAPTER = 9_999
MAX_PARAGRAPH = 99_999
MAX_PAGE = 99_999

MARGIN_MAX_CHARS = 400
QUOTE_MAX_CHARS = 240
ALBUM_QUOTE_MAX_CHARS = 160
# How many marks a room hands to its clients at most — a book read for a year
# should not make every state push the size of the book.
MARKS_LIMIT = 2000

_HASH = re.compile(r"^[0-9a-f]{64}$")
_EPUB = re.compile(r"^c(\d{1,4})(?::p(\d{1,5}))?$")
_CBZ = re.compile(r"^p(\d{1,5})$")
_PARALLEL = re.compile(r"^c(\d{1,4})$")


def is_reading(activity: str | None) -> bool:
    return activity == "read"


def normalize_hash(raw: str | None) -> str:
    """A lowercase hex SHA-256, or ValueError with a message that is safe to
    show the person."""
    text = (raw or "").strip().lower()
    if not _HASH.match(text):
        raise ValueError("Не удалось определить файл — откройте его ещё раз")
    return text


def normalize_reading(
    kind: str | None, content_hash: str | None, units: int | None,
) -> tuple[str, str | None, int | None]:
    """Validates how a room reads. Returns (kind, hash or None, units or None).

    A file kind needs the file's fingerprint (it is the only way two devices
    can tell they hold the same edition); `parallel` has no file and so no
    fingerprint — one that is sent anyway is dropped."""
    kind = (kind or "").strip().lower()
    if kind not in READ_KINDS:
        raise ValueError("Неизвестный способ чтения")
    digest: str | None = None
    if kind != "parallel":
        digest = normalize_hash(content_hash)
    count: int | None = None
    if units is not None:
        if not isinstance(units, int) or isinstance(units, bool) or units < 1 or units > MAX_UNITS:
            raise ValueError("Странная длина книги")
        count = units
    return kind, digest, count


def normalize_mode(raw: str | None, kind: str | None = None) -> str:
    """A reading mode; with the room's `kind` given, also whether that kind
    allows it (reading aloud needs text)."""
    mode = (raw or "").strip().lower()
    if mode not in READ_MODES:
        raise ValueError("Неизвестный режим чтения")
    if mode == "aloud" and kind is not None and kind not in ALOUD_KINDS:
        raise ValueError("Вслух можно читать только книгу с текстом")
    return mode


def has_shared_place(mode: str | None) -> bool:
    """Whether the room keeps one place everybody follows."""
    return mode in ("together", "aloud")


def normalize_highlight(raw: str | None) -> str:
    key = (raw or "").strip().lower()
    if key not in (HIGHLIGHT_ON, HIGHLIGHT_OFF):
        raise ValueError("Подсветка бывает включённой или выключенной")
    return key


def normalize_locator(kind: str, raw: str | None) -> str:
    """The canonical spelling of a place for this kind of reading, or
    ValueError. Canonical so that "the same place" is always the same string:
    leading zeros are dropped and an EPUB place always names its paragraph."""
    text = (raw or "").strip().lower()
    if kind == "epub":
        m = _EPUB.match(text)
        if m:
            chapter, para = int(m.group(1)), int(m.group(2) or 0)
            if chapter <= MAX_CHAPTER and para <= MAX_PARAGRAPH:
                return f"c{chapter}:p{para}"
    elif kind == "cbz":
        m = _CBZ.match(text)
        if m and int(m.group(1)) <= MAX_PAGE:
            return f"p{int(m.group(1))}"
    elif kind == "parallel":
        m = _PARALLEL.match(text)
        if m and int(m.group(1)) <= MAX_CHAPTER:
            return f"c{int(m.group(1))}"
    raise ValueError("Не похоже на место в книге")


def start_locator(kind: str) -> str:
    """The very beginning, for a kind of reading."""
    return {"epub": "c0:p0", "cbz": "p0", "parallel": "c0"}[kind]


def locator_key(kind: str, locator: str | None) -> tuple[int, int]:
    """Where a place sits in reading order, for comparing two places:
    (chapter, paragraph) or (page, 0). An unreadable place sorts first."""
    try:
        canon = normalize_locator(kind, locator)
    except ValueError:
        return (-1, -1)
    nums = [int(n) for n in re.findall(r"\d+", canon)]
    return (nums[0], nums[1] if len(nums) > 1 else 0)


def clamp_progress(value: int | None) -> int:
    try:
        v = int(value or 0)
    except (TypeError, ValueError):
        return 0
    return max(0, min(PROGRESS_MAX, v))


def progress_to_ms(progress: int | None) -> int:
    """The permille as the room's clock units (an event's `position_ms`)."""
    return clamp_progress(progress) * PROGRESS_STEP_MS


def ms_to_progress(position_ms: int | None) -> int:
    return clamp_progress(int(position_ms or 0) // PROGRESS_STEP_MS)


def same_edition(room_hash: str | None, member_hash: str | None) -> bool | None:
    """True/False once both sides have a fingerprint; None while either is
    unknown (nothing to compare — also always the case for `parallel`)."""
    if not room_hash or not member_hash:
        return None
    return room_hash == member_hash


def reached_the_end(progress: int | None) -> bool:
    return clamp_progress(progress) >= READ_DONE_PERMILLE


def clean_quote(raw: str | None) -> str | None:
    """A short passage a note is pinned to: whitespace collapsed, cut to the
    limit on a word boundary when it can be. Never more than a line or two of
    the book — enough to find the place again, not a copy of the text."""
    text = " ".join((raw or "").split())
    if not text:
        return None
    if len(text) <= QUOTE_MAX_CHARS:
        return text
    cut = text[: QUOTE_MAX_CHARS - 1]
    space = cut.rfind(" ")
    if space >= QUOTE_MAX_CHARS // 2:
        cut = cut[:space]
    return cut.rstrip(" ,;:-—") + "…"


def clean_album_quote(raw: str | None) -> str:
    """A short quote for the album: whitespace collapsed, at most
    ALBUM_QUOTE_MAX_CHARS, cut on a word boundary with an ellipsis when it must
    be. ValueError (safe to show) when there is nothing in it."""
    text = " ".join((raw or "").split())
    if not text:
        raise ValueError("Выделите абзац, который хотите отложить в альбом")
    if len(text) <= ALBUM_QUOTE_MAX_CHARS:
        return text
    cut = text[: ALBUM_QUOTE_MAX_CHARS - 1]
    space = cut.rfind(" ")
    if space >= ALBUM_QUOTE_MAX_CHARS // 2:
        cut = cut[:space]
    return cut.rstrip(" ,;:-—") + "…"


def add_quote_to_note(existing: str | None, quote: str, *, max_chars: int) -> str:
    """The text of a person's sealed album note once `quote` is added to it.
    Quotes are set in guillemets and separated by a blank line; a quote that is
    already in the note is not added twice. ValueError (safe to show) when
    there is no room left — the album never cuts what somebody set aside."""
    piece = f"«{quote}»"
    current = (existing or "").strip()
    if piece in current:
        return current
    joined = f"{current}\n\n{piece}" if current else piece
    if len(joined) > max_chars:
        raise ValueError("В записке не осталось места — то, что поместилось, уже в альбоме")
    return joined


def reduce_marks(events: list[dict]) -> list[dict]:
    """What is written on the pages right now, from the room's event ledger.

    `events` are dicts with `seq`, `user_id`, `kind`, `emoji`, `locator`,
    `body`, `quote`, `position_ms`, in any order. Margin notes all stay. A highlight is
    per person per place and the latest word wins: switched on it shows,
    switched off again it is gone. Anything without a place is ignored.
    The result is in ledger order (oldest first), at most MARKS_LIMIT of the
    newest."""
    ordered = sorted(events, key=lambda e: e.get("seq") or 0)
    marks: dict[object, dict] = {}
    for e in ordered:
        loc = e.get("locator")
        if not loc:
            continue
        kind = e.get("kind")
        if kind == "margin":
            marks[("m", e.get("seq"))] = {
                "seq": e["seq"], "user_id": e.get("user_id"), "kind": "margin",
                "locator": loc, "body": e.get("body"), "quote": e.get("quote"),
                "position_ms": e.get("position_ms"),
            }
        elif kind == "highlight":
            key = ("h", e.get("user_id"), loc)
            if e.get("emoji") == HIGHLIGHT_ON:
                marks[key] = {
                    "seq": e["seq"], "user_id": e.get("user_id"), "kind": "highlight",
                    "locator": loc, "body": None, "quote": None,
                    "position_ms": e.get("position_ms"),
                }
            else:
                marks.pop(key, None)
    out = sorted(marks.values(), key=lambda m: m["seq"])
    return out[-MARKS_LIMIT:]
