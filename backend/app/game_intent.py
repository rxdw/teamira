"""What a free-text Ask says about *how a game is played* — co-op, "for
two", split-screen, party, "with a friend" — as opposed to what it's about.

Why this exists
---------------
Ask Teamira's rule-based layer understood genres ("strategy", "sci-fi"),
media types and eras, and nothing about play mode. "co-op game for two"
therefore looked like a query with no signal at all, fell through to a
*title* search on IGDB ("co-op for two" matches game names, not
descriptions) and came back with whatever happened to have "co-op" in its
name — a fan mod, a brain-training cartridge, a joke simulator. See
routers/ai.py::_game_candidates for how this is now used instead: the
play-mode words become a server-side IGDB `game_modes` filter, and
IgdbAdapter.discover applies a quality gate on top.

Design notes
------------
- Pure stdlib, no app imports: parsing is deterministic string work and
  should stay testable (and importable) without a database or network.
- **Strong vs. soft phrases.** "co-op", "split screen", "multiplayer" can
  only be about games, so they count even when the query never says
  "game" ("co-op for two" alone is enough). "for two", "with a friend",
  "couch", "party" are ordinary English/Russian that show up in movie
  asks too ("что посмотреть вдвоём") — they only count when the query
  already said it wants a game, otherwise a movie night for two would
  start pulling in board-game-ish results.
- **Play mode is a filter, not a vibe.** Someone asking for co-op wants
  titles IGDB actually tags as co-operative. `GameIntent.evaluate`
  returns None for a game that isn't, and routers/ai.py drops it.
- IGDB's game-mode ids (api-docs.igdb.com/#game-mode) are stable
  reference data, same as the genre ids igdb.py already hard-codes.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import FrozenSet, Iterable, Optional, Set, Tuple

# IGDB game_modes ids.
MODE_SINGLE = 1
MODE_MULTI = 2
MODE_COOP = 3
MODE_SPLIT = 4
MODE_MMO = 5
MODE_BR = 6

# Added to a game's raw score when it has the play mode that was asked
# for, and a little extra when it has the *preferred* one (split-screen
# for a couch ask, co-op for a "for two" ask). Small on purpose: the mode
# is already a hard filter, so this only has to break ties between
# candidates that all qualify — semantic closeness and quality do the
# real ordering. See routers/ai.py's game scoring loop.
MODE_MATCH_BONUS = 15.0
MODE_PREFERRED_BONUS = 5.0

_HYPHENS = "\\-\u2010-\u2015"  # -, ‐ ‑ ‒ – — ―

# ---------------------------------------------------------------------------
# Strong: only ever about games.
# ---------------------------------------------------------------------------
_COOP = re.compile(
    rf"\bco[\s{_HYPHENS}]?op(?:s|erative)?\b"
    r"|кооп\w*"
    # "поиграть вместе" / "играть вместе" / "вместе поиграть" — three
    # words of slack either way covers "во что поиграть вдвоём вместе".
    r"|(?:поигра\w*|игра\w*)\s+(?:\w+\s+){0,3}вместе"
    r"|вместе\s+(?:\w+\s+){0,3}(?:поигра\w*|игра\w*)"
    r"|совместн\w*\s+(?:игр\w*|прохожд\w*)"
)
_SPLIT_STRONG = re.compile(
    rf"\bsplit[\s{_HYPHENS}]?screen\b|\bsplitscreen\b|\bshared screen\b"
    rf"|сплит[\s{_HYPHENS}]?скрин\w*|на одном экране"
)
_MULTI_STRONG = re.compile(
    rf"\bmulti[\s{_HYPHENS}]?player\b|мультиплеер\w*|мультиплэйер\w*"
    r"|\bpvp\b|\blan party\b"
)

# ---------------------------------------------------------------------------
# Soft: ordinary words, only meaningful once the query is about games.
# ---------------------------------------------------------------------------
_SPLIT_SOFT = re.compile(
    r"\bcouch\b|\bsofa\b|\blocal (?:multiplayer|mp|play)\b"
    r"|на диване|диванн\w*|локальн\w*"
)
# "party" alone is NOT enough — "a party-based RPG" is a single-player
# thing about a party of characters. Needs "party game(s)" or "for a party".
_PARTY = re.compile(
    rf"\bparty[\s{_HYPHENS}]?(?:games?|mode)\b|\bfor (?:a )?(?:party|parties|group|crowd)\b"
    r"|вечеринк\w*|для компани\w*"
)
_GROUP = re.compile(
    r"\bwith (?:my |our |your |the )?(?:friends|buddies|mates|pals|squad|team|family)\b"
    r"|с друзьями|с компанией|с ребятами|с семьёй|с семьей"
)

# A number that is a time span, not a head-count ("a game for 2 hours",
# "for 3 days", "for 4 year olds"). Checked with a negative lookahead so
# the head-count patterns below never fire on it.
_NOT_A_HEADCOUNT = (
    r"(?!\s*(?:h\b|hr|hrs|hour|min|minute|day|week|month|year|"
    r"ч\b|час|мин|дн|день|недел|месяц|год|лет))"
)
_PLAYERS: Tuple[Tuple[re.Pattern, int], ...] = (
    (
        re.compile(
            rf"\bfor (?:two|2)\b{_NOT_A_HEADCOUNT}"
            rf"|\b(?:two|2)[\s{_HYPHENS}]?(?:players?|persons?|people)\b"
            r"|\b2p\b|\bfor (?:a )?couples?\b|\bas a couple\b"
            r"|вдво[её]м|(?:на|для)\s+двои[хм]\b|для пары"
            r"|с (?:другом|подругой|девушкой|парнем|женой|мужем|партн[её]р\w*|братом|сестрой)\b"
        ),
        2,
    ),
    (
        re.compile(
            rf"\bfor (?:three|3)\b{_NOT_A_HEADCOUNT}"
            rf"|\b(?:three|3)[\s{_HYPHENS}]?(?:players?|people)\b"
            r"|втро[её]м|(?:на|для)\s+троих\b"
        ),
        3,
    ),
    (
        re.compile(
            rf"\bfor (?:four|4)\b{_NOT_A_HEADCOUNT}"
            rf"|\b(?:four|4)[\s{_HYPHENS}]?(?:players?|people)\b|\b4p\b"
            r"|вчетвером|(?:на|для)\s+четверых\b"
        ),
        4,
    ),
)
# "with a friend / my girlfriend / a buddy" — two people.
_WITH_PARTNER = re.compile(
    r"\bwith (?:a |my |our |your |the )?"
    r"(?:friend|buddy|mate|pal|partner|girlfriend|boyfriend|wife|husband|"
    r"brother|sister|bf|gf|bestie|roommate|kid|son|daughter)\b"
)

_STRIP_PATTERNS: Tuple[re.Pattern, ...] = (
    _COOP, _SPLIT_STRONG, _MULTI_STRONG, _SPLIT_SOFT,
    _PARTY, _GROUP, _WITH_PARTNER, *(p for p, _ in _PLAYERS),
)


def _players(t: str) -> Optional[int]:
    found = [n for pattern, n in _PLAYERS if pattern.search(t)]
    if _WITH_PARTNER.search(t):
        found.append(2)
    return max(found) if found else None


def ids_from_names(names: Iterable[str]) -> Set[int]:
    """IGDB `game_modes.name` strings -> mode ids. Matched by substring,
    case-insensitively, because the names carry decoration
    ("Massively Multiplayer Online (MMO)") and that's the only thing this
    app has on a MediaItem — the numeric id isn't carried through."""
    ids: Set[int] = set()
    for name in names:
        n = (name or "").lower()
        if "massively" in n or "mmo" in n:
            ids.add(MODE_MMO)
        elif "battle royale" in n:
            ids.add(MODE_BR)
        elif "co-op" in n or "cooperative" in n or "co-operative" in n:
            ids.add(MODE_COOP)
        elif "split" in n:
            ids.add(MODE_SPLIT)
        elif "multiplayer" in n:
            ids.add(MODE_MULTI)
        elif "single" in n:
            ids.add(MODE_SINGLE)
    return ids


@dataclass(frozen=True)
class ModeFit:
    """How well one game's modes satisfy a GameIntent. `labels` are the
    plain-English fragments shown to the person ("co-op", "split
    screen") — see routers/ai.py's reasoning line."""

    bonus: float = 0.0
    labels: Tuple[str, ...] = ()


@dataclass(frozen=True)
class GameIntent:
    coop: bool = False
    split: bool = False
    multi: bool = False
    party: bool = False
    group: bool = False
    players: Optional[int] = None
    # True when the query contains vocabulary that can only be about
    # games — the caller may then treat "co-op for two" as a games ask
    # even though it never said "game".
    strong: bool = False

    @property
    def active(self) -> bool:
        return (
            self.coop or self.split or self.multi or self.party or self.group
            or (self.players is not None and self.players >= 2)
        )

    @property
    def required_modes(self) -> FrozenSet[int]:
        """Any-of set of IGDB game modes a candidate must have. Empty
        means the query put no constraint on play mode."""
        if self.coop:
            return frozenset({MODE_COOP})
        if self.split:
            return frozenset({MODE_SPLIT})
        if self.party:
            return frozenset({MODE_MULTI, MODE_SPLIT})
        if self.multi or self.group:
            return frozenset({MODE_MULTI, MODE_COOP})
        if self.players is not None and self.players >= 2:
            # "for two" doesn't say co-op or versus — either is a fair
            # answer, and the preferred set below nudges co-op/couch up.
            return frozenset({MODE_COOP, MODE_MULTI, MODE_SPLIT})
        return frozenset()

    @property
    def preferred_modes(self) -> FrozenSet[int]:
        if self.coop and self.split:
            return frozenset({MODE_SPLIT})
        if self.party:
            return frozenset({MODE_SPLIT})
        if not self.coop and not self.split and self.players is not None and self.players >= 2 \
                and not (self.multi or self.group):
            return frozenset({MODE_COOP, MODE_SPLIT})
        return frozenset()

    @property
    def small_group(self) -> bool:
        """A head-count or a co-op/couch/party ask — where an MMO or a
        battle royale (technically "multiplayer", tagged co-op too in
        some cases) is the wrong kind of answer."""
        return self.coop or self.split or self.party or (
            self.players is not None and self.players >= 2
        )

    def evaluate(self, mode_names: Iterable[str]) -> Optional[ModeFit]:
        """None when a game can't be an answer at all: it lacks every
        required mode, or it's an MMO/battle-royale for a small-group
        ask. Otherwise the score bonus and display labels."""
        if not self.active:
            return ModeFit()
        ids = ids_from_names(mode_names)
        required = self.required_modes
        if required and not (ids & required):
            return None
        if self.small_group and ids & {MODE_MMO, MODE_BR} and MODE_SPLIT not in ids:
            return None

        bonus = MODE_MATCH_BONUS if required else 0.0
        if self.preferred_modes & ids:
            bonus += MODE_PREFERRED_BONUS

        labels = []
        if MODE_COOP in ids and (self.coop or self.players or self.group or self.multi):
            labels.append("co-op")
        if MODE_SPLIT in ids and (self.split or self.party or self.coop or self.players):
            labels.append("split screen")
        if not labels and MODE_MULTI in ids:
            labels.append("multiplayer")
        return ModeFit(bonus=bonus, labels=tuple(labels))


NONE = GameIntent()


def parse(text: str, *, games_explicit: bool) -> GameIntent:
    """Reads play-mode intent out of a lowercased query.

    `games_explicit` is whether the query already said it wants games
    ("game", "игра", ...) — the gate for the soft phrases described in
    the module docstring."""
    t = (text or "").lower()
    coop = bool(_COOP.search(t))
    split_strong = bool(_SPLIT_STRONG.search(t))
    multi_strong = bool(_MULTI_STRONG.search(t))
    strong = coop or split_strong or multi_strong
    if not strong and not games_explicit:
        return NONE
    return GameIntent(
        coop=coop,
        split=split_strong or bool(_SPLIT_SOFT.search(t)),
        multi=multi_strong,
        party=bool(_PARTY.search(t)),
        group=bool(_GROUP.search(t)),
        players=_players(t),
        strong=strong,
    )


def strip(text: str) -> str:
    """The text with every play-mode phrase removed. What's left is the
    part of the query that's about *what* the game is (genre, subject,
    a title) — used so "co-op for two" doesn't leak into title search,
    text-overlap scoring, or genre keyword matching ("мультиплеер"
    starts with "мульт", which the animation concept would otherwise
    happily claim)."""
    out = (text or "").lower()
    for pattern in _STRIP_PATTERNS:
        out = pattern.sub(" ", out)
    return re.sub(r"\s+", " ", out).strip()
