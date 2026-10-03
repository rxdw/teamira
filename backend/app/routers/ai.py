"""Ask Teamira — free text in, a ranked shortlist of real catalog titles
out. Two layers of matching, both without a per-request call to a
third-party AI API:

- Rule-based (this file, mostly unchanged from the original version):
  genre/media-type/era keyword parsing, TMDB's own similar-titles data
  for a resolved "like X" reference, and plain word overlap.
- Semantic (app/embeddings.py): a small local embedding model, run
  entirely inside this backend container, scores each candidate against
  the query by meaning rather than by shared words — see that module's
  docstring for why this is a local model and not an LLM call, and
  _semantic_scores below for how it's blended in. This is what makes
  "фильм про то, как ИИ восстаёт против человечества" find something
  like "Из машины" with zero literal word/genre overlap.

Both layers score candidates pulled from the same catalogs the rest of
the app already talks to (TMDB, IGDB — see app/adapters); nothing here
invents titles that aren't real catalog entries.

A pure mood/vibe query with no genre word, no media-type word, and no
"like X" reference ("fast-paced, keeps me hooked") gives the rule-based
layer nothing to build a candidate pool from: there's no genre-discover
call to make, and the one text-search call left (`tmdb_text`/`game`
below) is a *title* search — it matches "Interstellar", not a
description of what a good match feels like, so it comes back empty for
a phrase like that and the whole request 404s with "couldn't find a
good match for that" even though semantic scoring below would happily
rank real titles against it, if only it had something to rank. See
`_broad_pool` for how that's covered.

Games are their own pipeline (see `_game_candidates`). IGDB's `search`
only matches names, so a *description* of a game ("co-op game for two")
used to come back as whatever obscure entry had one of those words in its
title. Play-mode words are now parsed (app/game_intent.py) into a real
IGDB `game_modes` filter, genres/themes/eras go to IGDB as filters too,
and every candidate has to clear a quality gate (cover, audience, rating
— IgdbAdapter.discover) before it's ranked at all.
"""

import asyncio
import logging
import math
import re
from datetime import timedelta
from typing import Dict, List, Optional, Sequence, Set, Tuple

from fastapi import APIRouter, Depends, HTTPException
from pydantic import TypeAdapter
from sqlalchemy.orm import Session

from app import cache, embeddings, game_intent, models, ru_morph
from app.config import settings
from app.database import SessionLocal
from app.deps import get_current_user
from app.rate_limit import ai_ask_limiter
from app.schemas import AiAskRequest, AiAskResponse, AiMatchOut, MediaItem, TimeBudgetOut
from app.adapters.igdb import GameHit, IgdbAdapter
from app.adapters.google_books import GoogleBooksAdapter
from app.adapters.shikimori import ShikimoriMangaAdapter
from app.adapters.tmdb import TmdbAdapter

router = APIRouter(prefix="/ai", tags=["ai"])
logger = logging.getLogger("seenly.ai")

_games = IgdbAdapter()
_tmdb = TmdbAdapter()
_books = GoogleBooksAdapter()
_manga = ShikimoriMangaAdapter()


async def _broad_pool(db: Optional[Session]) -> List[MediaItem]:
    """The same wide movie/tv/game/book/manga pool GET /feed shows on
    Home — cached under the same "feed:discover" key (see
    app/routers/feed.py::get_feed) and refreshed once every 24h, so this
    almost always just reads what Home already warmed rather than paying
    for discover_mixed()'s ~85 TMDB calls itself. Used as the candidate
    pool for a query with no genre/media-type/reference signal at all
    (see module docstring) — semantic scoring below needs real
    candidates to rank, and "everything currently in the catalog" is a
    far better source for that than a title-text search that was never
    going to match a mood description in the first place.
    """
    async def _fetch() -> List[MediaItem]:
        pool: List[MediaItem] = []
        pool += await _tmdb.discover_mixed()
        pool += await _games.search("")
        pool += await _books.discover()
        pool += await _manga.discover()
        return pool

    payload_json = await cache.cached_dynamic(db, "feed:discover", _fetch)
    return TypeAdapter(List[MediaItem]).validate_json(payload_json)


# ---------------------------------------------------------------------------
# Query parsing — every list below is RU/EN keyword fragments matched as a
# plain substring against the lowercased query, on purpose: no NLP library,
# nothing that needs a model or a network call. "movie": TMDB's own movie
# genre names (app/adapters/tmdb.py::_MOVIE_GENRES); "tv": its TV genre
# names (_TV_GENRES) — the two tables don't line up 1:1 (there's no plain
# "Horror" on the TV side, for instance), which is why each concept keeps
# its own pair instead of one shared genre name. "game": substrings matched
# against an IGDB game's own genre names, since the IGDB adapter here only
# exposes a text search, not a genre-scoped discover call like TMDB's.
# ---------------------------------------------------------------------------
_CONCEPTS: Dict[str, Dict[str, List[str]]] = {
    "scifi": {
        "kw": ["sci-fi", "scifi", "sci fi", "фантастик", "космос", "space",
               "звездн", "инопланет", "future", "будущ"],
        "movie": ["Science Fiction"], "tv": ["Sci-Fi & Fantasy"],
        "game": ["sci-fi", "science fiction"],
    },
    "fantasy": {
        "kw": ["fantasy", "фэнтези", "фэнтэзи", "магия", "волшебств",
               "dragon", "дракон", "elves", "эльф"],
        "movie": ["Fantasy"], "tv": ["Sci-Fi & Fantasy"],
        "game": ["role-playing", "fantasy"],
    },
    "action": {
        "kw": ["action", "экшн", "боевик", "combat", "битв"],
        "movie": ["Action"], "tv": ["Action & Adventure"],
        "game": ["shooter", "hack and slash", "fighting", "tactical", "action"],
    },
    "adventure": {
        "kw": ["adventure", "приключен"],
        "movie": ["Adventure"], "tv": ["Action & Adventure"],
        "game": ["adventure"],
    },
    "comedy": {
        "kw": ["comedy", "комеди", "смешн", "funny", "юмор"],
        "movie": ["Comedy"], "tv": ["Comedy"],
        "game": ["comedy"],
    },
    "drama": {
        "kw": ["drama", "драм"],
        "movie": ["Drama"], "tv": ["Drama"],
        "game": [],
    },
    "horror": {
        "kw": ["horror", "ужас", "страшн", "хоррор"],
        "movie": ["Horror"], "tv": [],
        "game": ["survival", "horror"],
    },
    "thriller": {
        "kw": ["thriller", "триллер", "напряж"],
        "movie": ["Thriller"], "tv": [],
        "game": ["tactical", "stealth"],
    },
    "romance": {
        "kw": ["romance", "romantic", "мелодрам", "романтик", "любов"],
        "movie": ["Romance"], "tv": [],
        "game": ["romance"],
    },
    "mystery": {
        "kw": ["mystery", "detective", "детектив", "тайн", "расследован",
               "investigat"],
        "movie": ["Mystery"], "tv": ["Mystery"],
        "game": ["point-and-click", "puzzle", "mystery"],
    },
    "crime": {
        "kw": ["crime", "криминал", "преступ", "mafia", "мафи"],
        "movie": ["Crime"], "tv": ["Crime"],
        "game": [],
    },
    "animation": {
        "kw": ["animation", "animated", "мультфильм", "анимация", "cartoon",
               "мульт"],
        "movie": ["Animation"], "tv": ["Animation"],
        "game": [],
    },
    "war": {
        "kw": ["war", "война", "военн"],
        "movie": ["War"], "tv": ["War & Politics"],
        "game": ["strategy", "warfare"],
    },
    "western": {
        "kw": ["western", "вестерн", "ковбо"],
        "movie": ["Western"], "tv": ["Western"],
        "game": [],
    },
    "documentary": {
        "kw": ["documentary", "документал"],
        "movie": ["Documentary"], "tv": ["Documentary"],
        "game": [],
    },
    "family": {
        "kw": ["family", "семейн", "детск", "kids"],
        "movie": ["Family"], "tv": ["Family"],
        "game": ["kids"],
    },
    "rpg": {
        "kw": ["rpg", "ролев", "role-playing", "roleplaying"],
        "movie": [], "tv": [],
        "game": ["role-playing"],
    },
    "strategy": {
        "kw": ["strategy", "стратег"],
        "movie": [], "tv": [],
        "game": ["strategy"],
    },
    "shooter": {
        "kw": ["shooter", "шутер", "стрелялк", "fps"],
        "movie": [], "tv": [],
        "game": ["shooter"],
    },
    "racing": {
        "kw": ["racing", "гонк", "race"],
        "movie": [], "tv": [],
        "game": ["racing"],
    },
    "sport": {
        "kw": ["sport", "спорт"],
        "movie": [], "tv": [],
        "game": ["sport"],
    },
    "puzzle": {
        "kw": ["puzzle", "головоломк"],
        "movie": [], "tv": [],
        "game": ["puzzle"],
    },
    # Mood/vibe buckets — unlike everything above, these aren't genre
    # names TMDB itself uses; they're mapped to the closest real genres
    # so a mood-only query ("что-то грустное", "something uplifting")
    # still gets a genre-narrowed discover pool instead of falling all
    # the way through to the unfiltered `_broad_pool` (see that
    # function's docstring, and _semantic_scores' pool-relative
    # normalization, for why an unfiltered pool makes the displayed
    # match % basically meaningless for these queries). Kept as
    # OR-matched genres (see `similar_by_genre(match_all=...)` call
    # site below) — a mood word is a soft signal, not "must be tagged
    # both Drama AND Romance".
    "sad": {
        "kw": ["sad", "грустн", "печальн", "трогательн", "слезлив",
               "со слезами", "поплакать", "tearjerker", "melancholic",
               "melancholy", "heartbreaking", "депресс"],
        "movie": ["Drama", "Romance", "War"], "tv": ["Drama"],
        "game": [],
    },
    "feelgood": {
        "kw": ["feel-good", "feel good", "uplifting", "wholesome",
               "добр", "уютн", "поднять настроение", "light-hearted",
               "легк и приятн", "cozy"],
        "movie": ["Comedy", "Family", "Animation"], "tv": ["Comedy", "Family"],
        "game": [],
    },
    "dark": {
        "kw": ["dark", "мрачн", "жутк", "тяжел", "disturbing",
               "гнетущ", "unsettling", "bleak"],
        "movie": ["Thriller", "Crime", "Horror"], "tv": ["Crime", "Mystery"],
        "game": [],
    },
    "feelgood_nostalgic": {
        "kw": ["nostalgic", "ностальг", "детств", "childhood"],
        "movie": ["Family", "Adventure", "Animation"], "tv": ["Family"],
        "game": [],
    },
}

_MOOD_CONCEPTS = {"sad", "feelgood", "dark", "feelgood_nostalgic"}

# IGDB ids for the server-side half of game discovery — the counterpart of
# the "game" keyword lists above, which are matched against a returned
# game's own genre/theme *names* when scoring. Ids are IGDB reference data
# (api-docs.igdb.com/#genre, /#theme), stable like the genre ids
# igdb.py's Collections shelves already hard-code. Themes matter: IGDB
# files "Science fiction", "Horror", "Fantasy", "Comedy" under `themes`,
# not `genres`, so a genre-only filter could never answer "sci-fi game".
# A concept with several ids is OR-matched (any of them qualifies);
# concepts absent here (drama, crime, the mood buckets…) simply don't
# narrow the IGDB query and are ranked semantically instead.
_GAME_FILTERS: Dict[str, Dict[str, List[int]]] = {
    "scifi": {"themes": [18]},
    "fantasy": {"genres": [12], "themes": [17]},
    "action": {"genres": [5, 25, 4, 24], "themes": [1]},
    "adventure": {"genres": [31]},
    "comedy": {"themes": [27]},
    "horror": {"themes": [19, 21]},
    "thriller": {"genres": [24], "themes": [23]},
    "romance": {"themes": [44]},
    "mystery": {"genres": [2, 9], "themes": [43]},
    "war": {"genres": [15], "themes": [39]},
    "family": {"themes": [35]},
    "rpg": {"genres": [12]},
    "strategy": {"genres": [15, 11, 16]},
    "shooter": {"genres": [5]},
    "racing": {"genres": [10]},
    "sport": {"genres": [14]},
    "puzzle": {"genres": [9]},
}

_MOVIE_KW = ["movie", "movies", "film", "фильм", "кино", "картин"]
_TV_KW = ["series", "show", "tv show", "сериал", "шоу"]
_GAME_KW = ["game", "games", "видеоигр", "игр"]

_REFERENCE_PATTERNS = [
    re.compile(r"(?:similar to|like)\s+(.{3,60})$"),
    re.compile(r"похож[а-я]*\s+на\s+(.{3,60})$"),
    re.compile(r"(?:как|типа)\s+(.{3,60})$"),
]

_STOPWORDS = {
    "the", "a", "an", "and", "with", "about", "from", "that", "this",
    "и", "с", "на", "про", "что", "как", "это", "для", "или", "но",
}

# Same Cyrillic-vs-Latin sniff as app/routers/media.py::search_media — a
# query typed in Russian needs TMDB searched in ru-RU, or a Cyrillic
# "как Интерстеллар" reference/free-text search comes back empty even
# though the title is right there in TMDB's catalog under its Russian
# aka. \u0400-\u04FF covers the Cyrillic Unicode block.
_CYRILLIC_RE = re.compile(r"[\u0400-\u04FF]")

# ---------------------------------------------------------------------------
# "Сколько у тебя времени сегодня" — the evening-shaped half of Ask tanè.
#
# This is a ranking signal, not a filter, and that distinction is the whole
# design. A hard filter on runtime produces an empty screen far too often:
# runtime is only ever populated by GET /media/detail (see MediaItem's own
# docstring), so most candidates in any freshly-built pool have no runtime
# at all. Filtering on a field that's usually null would silently throw away
# the good answers and keep only the handful that happen to have been opened
# before.
#
# So instead: titles that comfortably fit the budget get a real boost,
# titles that overrun it get a real penalty that scales with how badly, and
# titles with no runtime on file are left exactly where they were. Someone
# who says "у меня 40 минут" gets episodes and short films at the top and a
# three-hour epic pushed to the bottom — but never an empty result, and
# never a shortlist that's empty of everything the catalog didn't happen to
# have measured.
# ---------------------------------------------------------------------------

# Spoken time budgets, in the order they're tried. Russian first (this is
# the app's primary audience) and both "полтора часа" and "1.5 часа" have
# to work, because people type both.
_TIME_PATTERNS: List[Tuple[re.Pattern, float]] = [
    # "полтора часа" / "полторы серии" — worth a special case, since it's
    # the single most common way to say 90 minutes in Russian and no
    # numeric pattern will ever catch it.
    (re.compile(r"\bполтор[ая]\s*час"), 90.0),
    (re.compile(r"\bпол\s*час"), 30.0),
    (re.compile(r"\bhalf\s+an\s+hour\b"), 30.0),
    # "2 часа", "2.5 часа", "1,5 ч"
    (re.compile(r"(\d+(?:[.,]\d+)?)\s*(?:час|ч\b|hours?\b|hrs?\b|h\b)"), 60.0),
    # "40 минут", "40 мин", "40 minutes"
    (re.compile(r"(\d+)\s*(?:минут|мин\b|minutes?\b|mins?\b|m\b)"), 1.0),
    # Inverted Russian word order — "часа два", "минут сорок", "минут 45".
    # This is how people actually say an approximate amount out loud, and
    # it's the shape every number-first pattern above misses entirely.
    # Listed last so an exact "2 часа" is always matched by the precise
    # pattern above before this looser one gets a look.
    (re.compile(r"\bчас[аов]*\s*(\d+(?:[.,]\d+)?)"), 60.0),
    (re.compile(r"\bмин(?:ут[ыу]?)?\s*(\d+)"), 1.0),
]

# Spelled-out numbers, for the "минут сорок" / "часа полтора" case where
# there's no digit to capture at all. Deliberately stops at twelve plus
# the round tens — past that nobody says it in words.
_SPELLED_NUMBERS: Dict[str, float] = {
    "один": 1, "одна": 1, "полтора": 1.5, "полторы": 1.5, "полутора": 1.5, "два": 2, "две": 2, "три": 3,
    "четыре": 4, "пять": 5, "шесть": 6, "семь": 7, "восемь": 8, "девять": 9,
    "десять": 10, "одиннадцать": 11, "двенадцать": 12, "пятнадцать": 15,
    "двадцать": 20, "тридцать": 30, "сорок": 40, "пятьдесят": 50,
    "шестьдесят": 60, "девяносто": 90,
}

_SPELLED_PATTERNS: List[Tuple[re.Pattern, float]] = [
    (
        re.compile(
            r"\bчас[аов]*\s+(" + "|".join(_SPELLED_NUMBERS) + r")\b"
        ),
        60.0,
    ),
    (
        re.compile(
            r"\b(" + "|".join(_SPELLED_NUMBERS) + r")\s+час"
        ),
        60.0,
    ),
    (
        re.compile(
            r"\bмин(?:ут[ыу]?)?\s+(" + "|".join(_SPELLED_NUMBERS) + r")\b"
        ),
        1.0,
    ),
    (
        re.compile(
            r"\b(" + "|".join(_SPELLED_NUMBERS) + r")\s+минут"
        ),
        1.0,
    ),
]


def _parse_spoken_budget(q: str) -> Optional[int]:
    """Pulls a time budget out of the free text, for someone who typed it
    instead of tapping a chip ("есть часа полтора, что посмотреть").

    Returns None rather than guessing when there's no time language at
    all — a bare number in "три мушкетёра" must not become a three-minute
    budget, which is why every pattern here requires an explicit unit.
    """
    for pattern, multiplier in _TIME_PATTERNS:
        match = pattern.search(q)
        if not match:
            continue
        if not match.groups():
            return int(multiplier)
        try:
            value = float(match.group(1).replace(",", "."))
        except (TypeError, ValueError):
            continue
        minutes = int(round(value * multiplier))
        # Same sanity window as AiAskRequest.minutes_available — a parsed
        # "2000 минут" is far likelier to be a year or a typo than a
        # genuine 33-hour evening.
        if 10 <= minutes <= 720:
            return minutes

    # Nothing with a digit in it — try the spelled-out forms.
    for pattern, multiplier in _SPELLED_PATTERNS:
        match = pattern.search(q)
        if not match:
            continue
        value = _SPELLED_NUMBERS.get(match.group(1))
        if value is None:
            continue
        minutes = int(round(value * multiplier))
        if 10 <= minutes <= 720:
            return minutes
    return None


def _budget_shape(minutes: int) -> str:
    """What a given budget is most likely asking for, for the caption
    only. The boundaries are deliberately fuzzy and overlapping-ish: 70
    minutes is comfortably an episode or two, 100 is a short film, and
    pretending there's a sharp line between them would make the caption
    wrong about half the time."""
    if minutes <= 70:
        return "episode"
    if minutes >= 100:
        return "movie"
    return "either"


# How far over budget a title can run before it stops being penalised
# further — past roughly double, it's equally impossible and there's no
# point ranking one impossible option above another.
_OVERRUN_CAP = 2.0


def _time_fit_bonus(item: MediaItem, minutes: int) -> float:
    """Score adjustment for one candidate against the evening's budget.

    Returns 0.0 for anything with no runtime on file — the "leave it
    exactly where it was" case that keeps this a signal rather than a
    filter. See this section's own comment above.

    The shape: a full bonus for titles that fit with a little room to
    spare, a smaller one for titles that fit exactly (finishing at the
    last possible minute is still a fit, just a tighter one), and a
    penalty proportional to the overrun for anything longer.
    """
    runtime = item.runtime_minutes
    if not runtime or runtime <= 0:
        return 0.0
    ratio = runtime / minutes
    if ratio <= 0.55:
        # Much shorter than the budget — fits, but leaves most of the
        # evening unspent. Worth surfacing (two episodes!), not worth as
        # much as something that fills the time.
        return 6.0
    if ratio <= 1.0:
        # The sweet spot: fills the evening without running over.
        return 14.0
    overrun = min(ratio, _OVERRUN_CAP) - 1.0
    return -22.0 * (overrun / (_OVERRUN_CAP - 1.0))


def _time_reasoning(item: MediaItem, minutes: int, lang_ru: bool) -> Optional[str]:
    """One short line explaining the fit, appended to whatever reasoning
    the rule-based layer already produced. Only ever written when there's
    a real runtime to talk about."""
    runtime = item.runtime_minutes
    if not runtime or runtime <= 0:
        return None
    if runtime <= minutes:
        left = minutes - runtime
        if left >= 20:
            return (
                f"{runtime} мин — останется ещё {left}"
                if lang_ru
                else f"{runtime} min — {left} to spare"
            )
        return f"{runtime} мин — как раз" if lang_ru else f"{runtime} min — just fits"
    over = runtime - minutes
    return (
        f"{runtime} мин — на {over} дольше, чем есть"
        if lang_ru
        else f"{runtime} min — {over} over"
    )



def _matched_concepts(q: str) -> List[str]:
    return [key for key, spec in _CONCEPTS.items() if any(kw in q for kw in spec["kw"])]


# A verb can say what kind of thing is wanted even when no noun does:
# "что посмотреть вечером" is never a game ask, "something to play
# tonight" never a film. Only consulted when no explicit kind word was
# used, so it can only narrow the "search everywhere" default.
_WATCH_RE = re.compile(r"\bwatch(?:ing)?\b|\bпосмотр\w*|\bсмотр\w*")
_PLAY_RE = re.compile(r"\bplay(?:ing)?\b|\bпоигра\w*|\bсыгра\w*")


def _media_kinds(q: str) -> Set[str]:
    kinds: Set[str] = set()
    if any(kw in q for kw in _MOVIE_KW):
        kinds.add("movie")
    if any(kw in q for kw in _TV_KW):
        kinds.add("tv")
    if any(kw in q for kw in _GAME_KW):
        kinds.add("game")
    if kinds:
        return kinds
    if _WATCH_RE.search(q) and not _PLAY_RE.search(q):
        return {"movie", "tv"}
    if _PLAY_RE.search(q) and not _WATCH_RE.search(q):
        return {"game"}
    return {"movie", "tv", "game"}  # unspecified -> search everywhere


def _explicit_kind(q: str) -> bool:
    return any(kw in q for kw in _MOVIE_KW + _TV_KW + _GAME_KW)


def _extract_year_and_decade(q: str) -> Tuple[Optional[int], Optional[int]]:
    """A plain 4-digit year (word-bounded, so it doesn't fire on "2010s")
    takes priority; otherwise looks for a decade ("2000s", "90s",
    "2010-х", "90-е")."""
    m = re.search(r"\b(19|20)\d{2}\b", q)
    if m:
        return int(m.group(0)), None
    m = re.search(r"\b(\d{4})[\s-]?(?:x|х|s|е)\b", q)
    if m:
        return None, int(m.group(1))
    m = re.search(r"\b(\d{2})[\s-]?(?:x|х|s|е)\b", q)
    if m:
        yy = int(m.group(1))
        decade = 1900 + yy if yy >= 30 else 2000 + yy
        return None, decade
    return None, None


def _extract_reference(q: str) -> Optional[str]:
    for pattern in _REFERENCE_PATTERNS:
        m = pattern.search(q)
        if m:
            title = m.group(1).strip(" \t\"'«».,!?")
            # Guards against Ask Teamira's own "like [a title I loved]"
            # example being submitted unedited (the client selects the
            # bracketed part on tap so typing replaces it, but a query
            # can still arrive with the literal template in it — an
            # older client build, a paste, etc.) — "[a title I loved]"
            # isn't a title to search TMDB for, it's a placeholder that
            # never got filled in, and searching for it literally would
            # just waste the lookup and then feed junk into the "not
            # found" messaging below. Treated the same as no reference
            # at all, so the query still gets a real answer via genre/
            # semantic matching on whatever's left of the sentence.
            if "[" in title or "]" in title:
                continue
            if len(title) >= 2:
                return title
    return None


def _freetext_remainder(raw_query: str, concepts: List[str], reference_title: Optional[str]) -> str:
    """What's left of the query once matched genre words, media-type
    words, and a "like X" clause are stripped out — used both as a light
    text-search fallback (for phrasing with no recognizable genre word,
    e.g. "a movie about a talking cat") and as the basis for the title-
    overlap part of scoring below."""
    q = raw_query.lower()
    if reference_title:
        q = q.replace(reference_title.lower(), " ")
    for spec in _CONCEPTS.values():
        for kw in spec["kw"]:
            q = q.replace(kw, " ")
    for kw in _MOVIE_KW + _TV_KW + _GAME_KW:
        q = q.replace(kw, " ")
    q = re.sub(r"\b(like|similar to|похож[а-я]*|на|как|типа)\b", " ", q)
    q = re.sub(r"\s+", " ", q).strip()
    return q


def _display(text) -> str:
    """Python-side equivalent of the Dart LocalizedText.display getter
    (mobile/lib/models/media_item.dart) — the pydantic LocalizedText here
    has no such property of its own. Prefers English since that's this
    endpoint's own working language regardless of the query's language."""
    if text is None:
        return ""
    return (text.en or text.ru or "").strip()


def _content_words(text: str) -> Set[str]:
    return {w for w in re.findall(r"[a-zа-яё0-9]{4,}", text.lower()) if w not in _STOPWORDS}


def _text_overlap_score(query_words: Set[str], item: MediaItem) -> int:
    if not query_words:
        return 0
    title_words = _content_words(_display(item.title))
    if query_words & title_words:
        return 15
    desc = _display(item.description)
    if desc:
        desc_words = _content_words(" ".join(desc.split()[:40]))
        if query_words & desc_words:
            return 8
    return 0


def _year_score(item_year: Optional[int], exact_year: Optional[int], decade: Optional[int]) -> int:
    if item_year is None:
        return 0
    if exact_year is not None:
        diff = abs(item_year - exact_year)
        if diff == 0:
            return 25
        if diff <= 2:
            return 15
        if diff <= 5:
            return 6
        return 0
    if decade is not None:
        if decade <= item_year <= decade + 9:
            return 25
        if abs(item_year - (decade + 5)) <= 15:
            return 10
        return 0
    return 0


# ---------------------------------------------------------------------------
# Semantic matching — app/embeddings.py (local model, no third-party AI
# call). This is what lets a query like "фильм про то, как ИИ восстаёт
# против человечества" surface something like "Из машины" even though
# they share zero genre tags and almost no literal words: genre/keyword
# matching above is a lexical filter, this is a meaning comparison.
#
# Deliberately additive, not a replacement: everything above still runs
# and still works standalone if the model failed to load (see
# app/embeddings.py's failure-handling note) — this only ever adds a
# bonus on top of the rule-based score, never gates a result on it.
# ---------------------------------------------------------------------------

_SEMANTIC_WEIGHT = 60  # now the single largest possible contributor — see
                       # the note by `scored`'s definition below for why
                       # this and _REFERENCE_BONUS were rebalanced
                       # together with decoupling the sort key from the
                       # displayed match %.
_SEMANTIC_FALLBACK_MIN_COSINE = 0.80  # last-resort-only: e5 embeddings run a
                                      # fairly compressed cosine range, so an
                                      # absolute cutoff (rather than the
                                      # pool-relative normalization used in
                                      # the main path below) needs to sit
                                      # high enough that "same rough topic"
                                      # doesn't quietly become "everything".
_SEMANTIC_BROAD_POOL_MIN_COSINE = 0.78  # pre-filter for `_broad_pool`
                                        # candidates specifically — see the
                                        # broad-pool merge site below.
                                        # Slightly looser than the
                                        # last-resort floor above since
                                        # this is the *primary* path for a
                                        # pure vibe query (mood concepts
                                        # now catch most of what used to
                                        # land here — see _CONCEPTS' mood
                                        # buckets — so what's left really
                                        # is "no genre/keyword signal at
                                        # all", not a failed rule-based
                                        # pass), not a genuine last resort.


def _embedding_passage(item: MediaItem, extra_terms: Sequence[str] = ()) -> str:
    """The text a title is embedded from — title, genres, and the first
    chunk of its description, i.e. everything Ask Teamira already has
    cached for it. Mirrors _content_words' 40-word description cap
    below in spirit: enough text for the model to place the title
    semantically, without diluting a short title+genre signal in a much
    longer synopsis.

    Games additionally carry their IGDB themes (`extra_terms` — "Horror",
    "Science fiction"…) and play modes ("Co-operative", "Split screen"):
    an IGDB summary is often two sentences that never mention either, and
    "co-op game for two" has nothing else to match a co-op title on."""
    title = _display(item.title)
    desc = _display(item.description)
    desc_snippet = " ".join(desc.split()[:60])
    genres = ", ".join([*item.genres, *extra_terms])
    if item.media_type == "game" and item.game_modes:
        return f"{title}. {genres}. {', '.join(item.game_modes)}. {desc_snippet}".strip()
    return f"{title}. {genres}. {desc_snippet}".strip()


def _embedding_cache_source(item: MediaItem) -> str:
    """The `source` half of an embedding's cache key. Games are stored
    under a versioned source because their passage changed shape (themes
    + play modes were added — see _embedding_passage): vectors cached
    from the old title/genres/summary text stay valid for what they
    embedded but would quietly ignore the new signal forever, since
    embeddings are cached with no expiry."""
    return f"{item.source}:v2" if item.media_type == "game" else item.source


async def _semantic_raw_scores(
    db: Optional[Session],
    query_text: str,
    items: List[MediaItem],
    extra_terms: Optional[Dict[str, List[str]]] = None,
) -> Dict[str, float]:
    """Absolute cosine per "source:id" key — the shared embedding/caching
    machinery, split out from the pool-relative normalization in
    _semantic_scores below so a caller that needs an absolute floor
    (see _SEMANTIC_BROAD_POOL_MIN_COSINE) isn't stuck with only the
    normalized numbers. Cheap to call twice on overlapping item sets:
    vectors are cached forever by title id (app/cache.py::get_embedding),
    so a second call over a subset already computed here just reads
    cache, no re-embedding.
    """
    query_text = query_text.strip()
    if not query_text or not items or not embeddings.available():
        return {}

    query_vector = await asyncio.to_thread(embeddings.embed_query, query_text)
    if query_vector is None:
        return {}

    extra_terms = extra_terms or {}
    by_key: Dict[str, MediaItem] = {f"{item.source}:{item.id}": item for item in items}
    vectors: Dict[str, List[float]] = {}
    missing: List[Tuple[str, MediaItem]] = []
    for key, item in by_key.items():
        cached_vector = cache.get_embedding(db, item.id, _embedding_cache_source(item))
        if cached_vector is not None:
            vectors[key] = cached_vector
        else:
            missing.append((key, item))

    if missing:
        passages = [_embedding_passage(item, extra_terms.get(key, ())) for key, item in missing]
        computed = await asyncio.to_thread(embeddings.embed_passages, passages)
        for (key, item), vector in zip(missing, computed):
            if vector is not None:
                vectors[key] = vector
                cache.set_embedding(db, item.id, _embedding_cache_source(item), vector)

    return {key: embeddings.cosine(query_vector, vector) for key, vector in vectors.items()}


async def _semantic_scores(
    db: Optional[Session],
    query_text: str,
    items: List[MediaItem],
    extra_terms: Optional[Dict[str, List[str]]] = None,
) -> Dict[str, float]:
    """Pool-relative semantic score per "source:id" key, normalized to
    0..1 by min-max over just this request's own candidates — not an
    absolute cosine threshold. e5 cosine similarities are compressed
    (rarely below ~0.6 even for unrelated pairs), so an absolute cutoff
    would need constant re-tuning; ranking THIS query's candidates
    against each other sidesteps that entirely and degrades gracefully
    query to query. Returns {} (i.e. "no semantic signal, rule-based
    scoring alone decides") when there's no free text worth comparing,
    the model isn't available, or nothing embedded successfully.

    Pool-relative only makes sense when the pool itself is already a
    reasonable candidate set (genre/reference/keyword narrowed). See
    _SEMANTIC_BROAD_POOL_MIN_COSINE below for the absolute floor applied
    BEFORE this, specifically to `_broad_pool`-sourced candidates — this
    function still just normalizes whatever it's handed.
    """
    raw_scores = await _semantic_raw_scores(db, query_text, items, extra_terms)
    if not raw_scores:
        return {}

    lo, hi = min(raw_scores.values()), max(raw_scores.values())
    spread = hi - lo
    if spread <= 1e-6:
        return {key: 0.0 for key in raw_scores}
    return {key: (value - lo) / spread for key, value in raw_scores.items()}


# ---------------------------------------------------------------------------
# Games — candidate generation and ranking. See the module docstring, and
# IgdbAdapter.discover for the quality gate everything below sits on.
# ---------------------------------------------------------------------------

# Discovery results are stable for hours and the same few asks ("co-op game
# for two", "horror game") are repeated by many people, so they're cached by
# their *filters* (never by free text — that's unbounded). IGDB is also the
# flakiest dependency here; a warm cache keeps Ask answering through a blip.
_GAME_DISCOVER_TTL = timedelta(hours=6)
_GAME_BROAD_TTL = timedelta(hours=24)
# Below this many candidates, filters get relaxed step by step (see
# _relaxation_ladder) rather than answering from a near-empty bench. Kept
# low on purpose: for games a short list of real matches beats padding it
# with near-misses, and whatever relaxation does add is ranked below
# genuine matches (see _GAME_GENRE_MISS_PENALTY).
_GAME_POOL_MIN = 6
# Applied to a game that matched none of the genres/themes the ask named —
# only reachable through relaxation. Keeps padding under the real matches
# even when its semantic score happens to be higher.
_GAME_GENRE_MISS_PENALTY = 30.0
_BROAD_GAME_CACHE_KEY = "ask:games:v1:broad"


class _EmptyDiscovery(Exception):
    """Raised inside a cache fetch so an empty IGDB answer — which can't be
    told apart from a swallowed failure — is never stored for hours."""


def _game_cache_key(mode_ids, genre_ids, theme_ids, year_from, year_to) -> str:
    def j(values) -> str:
        return ".".join(str(v) for v in sorted(set(values)))
    return (
        f"ask:games:v1:m{j(mode_ids)}:g{j(genre_ids)}:t{j(theme_ids)}"
        f":y{year_from or ''}-{year_to or ''}"
    )


async def _cached_game_discover(
    *,
    mode_ids: Sequence[int] = (),
    genre_ids: Sequence[int] = (),
    theme_ids: Sequence[int] = (),
    year_from: Optional[int] = None,
    year_to: Optional[int] = None,
    want: int = 30,
    limit_each: int = 50,
    cache_key: Optional[str] = None,
    ttl: timedelta = _GAME_DISCOVER_TTL,
) -> List[GameHit]:
    def _direct():
        return _games.discover(
            mode_ids=mode_ids, genre_ids=genre_ids, theme_ids=theme_ids,
            year_from=year_from, year_to=year_to, want=want, limit_each=limit_each,
        )

    async def _fetch() -> List[GameHit]:
        hits = await _direct()
        if not hits:
            raise _EmptyDiscovery()
        return hits

    key = cache_key or _game_cache_key(mode_ids, genre_ids, theme_ids, year_from, year_to)
    try:
        payload = await cache.cached_dynamic(None, key, _fetch, ttl=ttl)
    except _EmptyDiscovery:
        return []
    except Exception:  # noqa: BLE001 — cache trouble must not cost the answer
        logger.warning("game discovery cache failed for %s; querying IGDB directly", key, exc_info=True)
        return await _direct()
    return TypeAdapter(List[GameHit]).validate_json(payload)


async def _broad_game_pool() -> List[GameHit]:
    """A wide, quality-gated slice of the game catalog (most-rated plus
    best-rated) for asks that describe a mood rather than name a genre,
    mode or era — the games counterpart of `_broad_pool`. Deliberately not
    `_broad_pool` itself: that one's game half is IGDB's top-rated list
    with no audience floor, i.e. one-vote 100s."""
    return await _cached_game_discover(
        want=150, limit_each=80, cache_key=_BROAD_GAME_CACHE_KEY, ttl=_GAME_BROAD_TTL,
    )


# Words that carry no information about *which game* — stripped before
# deciding whether what's left could be a title.
_TITLE_FLUFF = {
    "about", "where", "that", "this", "with", "want", "some", "something", "anything",
    "good", "best", "great", "fun", "nice", "cool", "new", "old", "play", "played",
    "playing", "recommend", "suggest", "give", "find", "show", "like", "similar",
    "tonight", "today", "please", "need", "looking", "for", "not", "too", "very",
    "really", "just", "what", "which", "have", "from", "into", "your", "you", "are",
    "can", "get", "хочу", "хочется", "что", "нибудь", "какую", "какой", "какая",
    "игру", "игры", "игра", "посоветуй", "подскажи", "порекомендуй", "найди",
    "хорошую", "хороший", "хорошая", "интересную", "интересный", "новую", "вечер",
    "сегодня", "чтобы", "который", "которая", "которую", "где", "есть", "для", "про",
    "или", "это",
}


def _title_tokens(text: str) -> List[str]:
    return [
        w for w in re.findall(r"[a-zа-яё0-9']{3,}", (text or "").lower())
        if w not in _STOPWORDS and w not in _TITLE_FLUFF
    ]


def _game_title_query(freetext: str) -> Optional[str]:
    """What's left of the ask once genre/mode/kind words are gone, if it
    could plausibly be (part of) a game's name: one to five informative
    words. A long remainder is a description, and description-vs-title
    matching is exactly what produced junk before."""
    tokens = _title_tokens(freetext)
    if not tokens or len(tokens) > 5:
        return None
    return " ".join(tokens)


def _title_hit_relevant(tokens: List[str], item: MediaItem) -> bool:
    """A title-search hit is only kept when at least half of what was
    searched for literally appears in the title — IGDB's search is fuzzy,
    and a fuzzy hit that shares nothing readable with the ask is noise."""
    if not tokens:
        return False
    words = re.findall(r"[a-zа-яё0-9']+", _display(item.title).lower())
    covered = sum(1 for t in tokens if any(w == t or w.startswith(t) for w in words))
    return covered / len(tokens) >= 0.5


def _relaxation_ladder(mode_ids, genre_ids, theme_ids, year_from, year_to) -> List[dict]:
    """Filter sets to try in order when the strictest one is thin. The play
    mode is never dropped (it's what the person actually asked for and is
    re-checked per game anyway); the era goes first, then genre/theme."""
    full = dict(mode_ids=tuple(mode_ids), genre_ids=tuple(genre_ids), theme_ids=tuple(theme_ids),
                year_from=year_from, year_to=year_to)
    steps = [full]
    if year_from is not None or year_to is not None:
        steps.append({**full, "year_from": None, "year_to": None})
    if mode_ids and (genre_ids or theme_ids):
        steps.append({**full, "genre_ids": (), "theme_ids": (), "year_from": None, "year_to": None})
    unique, seen = [], set()
    for step in steps:
        marker = tuple(sorted((k, repr(v)) for k, v in step.items()))
        if marker not in seen:
            seen.add(marker)
            unique.append(step)
    return unique


async def _drop_unrelated_games(hits: List[GameHit], query_text: str) -> List[GameHit]:
    """For the broad (mood-only) pool: keep only games whose *absolute*
    cosine to the ask clears the same floor `_broad_pool` uses. Without a
    floor, min-max normalization would crown the least-unrelated game in a
    pile of unrelated ones. If the model isn't available there's nothing
    to judge relevance with, and "the most popular games regardless of
    what you asked" is worse than saying nothing matched."""
    if not hits or not query_text.strip():
        return []
    extra = {f"{h.item.source}:{h.item.id}": h.themes for h in hits}
    raw = await _semantic_raw_scores(None, query_text, [h.item for h in hits], extra)
    return [
        h for h in hits
        if raw.get(f"{h.item.source}:{h.item.id}", 0.0) >= _SEMANTIC_BROAD_POOL_MIN_COSINE
    ]


async def _game_candidates(
    *,
    query_text: str,
    intent: "game_intent.GameIntent",
    genre_ids: Sequence[int],
    theme_ids: Sequence[int],
    year_from: Optional[int],
    year_to: Optional[int],
    title_text: Optional[str],
) -> List[GameHit]:
    """Every game that could answer this ask — all already through
    IgdbAdapter.discover's quality gate.

    - Anything structured in the ask (play mode, genre/theme, era) becomes
      an IGDB filter; thin results relax step by step (_relaxation_ladder).
    - A pure mood ask gets the broad quality pool, cut down by absolute
      semantic relevance.
    - Whatever remains of the ask, if it could be a title, also gets a
      title lookup — kept only where the title really shares its words.
    """
    mode_ids = tuple(sorted(intent.required_modes))
    era = year_from is not None or year_to is not None
    structured = bool(mode_ids or genre_ids or theme_ids or era)

    async def _title_lookup() -> List[GameHit]:
        if not title_text:
            return []
        try:
            return await _games.discover(text=title_text)
        except Exception:  # noqa: BLE001
            logger.warning("game title lookup failed", exc_info=True)
            return []

    collected: Dict[str, GameHit] = {}

    def _take(hits: List[GameHit]) -> None:
        for hit in hits:
            collected.setdefault(hit.item.id, hit)

    if structured:
        ladder = _relaxation_ladder(mode_ids, genre_ids, theme_ids, year_from, year_to)
        first, title_hits = await asyncio.gather(_cached_game_discover(**ladder[0]), _title_lookup())
        _take(first)
        for step in ladder[1:]:
            if len(collected) >= _GAME_POOL_MIN:
                break
            _take(await _cached_game_discover(**step))
    else:
        broad, title_hits = await asyncio.gather(_broad_game_pool(), _title_lookup())
        _take(await _drop_unrelated_games(broad, query_text))

    tokens = _title_tokens(title_text or "")
    _take([h for h in title_hits if _title_hit_relevant(tokens, h.item)])
    return list(collected.values())


def _game_quality_bonus(item: MediaItem, hit: Optional[GameHit]) -> float:
    """0..12 — a tiebreaker among games that already passed the gate and
    fit the ask: how many people rated it (1000+ ratings = full marks) and
    how well (60 -> 0, 90 -> full). Small next to semantic closeness and
    mode/genre fit on purpose; it decides "which of two equally relevant
    games first", never "relevant vs. not"."""
    bonus = 0.0
    if hit is not None and hit.rating_count > 0:
        bonus += min(1.0, math.log10(hit.rating_count) / 3.0) * 6.0
    if item.rating:
        bonus += max(0.0, min(1.0, (item.rating * 10 - 60) / 30.0)) * 6.0
    return bonus


def _franchise_key(title: str) -> str:
    """"Borderlands 3" / "Borderlands: The Pre-Sequel" -> "borderlands";
    "Left 4 Dead 2" / "Left 4 Dead" -> "left 4 dead". Enough to stop one
    series from filling a shortlist, without pretending to be a real
    franchise database."""
    t = (title or "").lower()
    t = re.split(r"\s*:\s+|\s+[-\u2013\u2014]\s+", t)[0]
    t = re.sub(r"[\s\W]+(?:\d+|[ivx]{1,5})\s*$", "", t)
    key = re.sub(r"\W+", " ", t).strip()
    return key or (title or "").lower()


def _pick_top(rows: list, limit: int = 24, franchise_cap: int = 2) -> list:
    """The first `limit` rows of an already-sorted shortlist, letting any
    one game franchise take at most `franchise_cap` places. Only games are
    capped (row[3] is the MediaItem); movies/series pass straight through
    exactly as before."""
    picked, counts = [], {}
    for row in rows:
        item = row[3]
        if item.media_type == "game":
            key = _franchise_key(_display(item.title))
            if counts.get(key, 0) >= franchise_cap:
                continue
            counts[key] = counts.get(key, 0) + 1
        picked.append(row)
        if len(picked) >= limit:
            break
    return picked


@router.post("/ask", response_model=AiAskResponse)
async def ask_ai(
    payload: AiAskRequest,
    current_user: models.User = Depends(get_current_user),
):
    """"Ask Teamira" on Home — a free-text description in, a ranked
    shortlist out. Mock only in the sense that there's no model call
    behind it (see module docstring); the catalog hits and scores are
    real, not randomly picked, which is why this doesn't cache the
    response the way the old single-pick version did — arbitrary user
    text isn't a repeatable cache key any more than /media/search's is.

    Requires a signed-in account and a generous per-account hourly cap
    (see rate_limit.ai_ask_limiter) — this used to accept anyone,
    signed in or not, with no limit at all, which meant the embedding
    work below (real local compute — see app/embeddings.py) had no
    real ceiling on it. This is NOT the app's actual "3 free asks a
    month" premium limit — that one is checked separately, by the
    client calling POST /premium/ai-ask before it calls this endpoint
    (see routers/premium.py) — this cap exists purely so this endpoint
    specifically can't be hammered by a signed-in-but-abusive script; it
    isn't a monetization control on its own.

    No `db: Session = Depends(get_db)` for the whole request here —
    same reasoning as routers/media.py::search_media and this module's
    other fan-out-shaped endpoints. Everything below that touches `db`
    (the broad-pool cache, per-item embedding cache reads/writes) is
    passed `db=None` and opens its own short-lived session per touch
    (see app/cache.py's `_session`) rather than holding one pooled
    connection for this whole request — which, unlike a typical route,
    can run a genuinely long chain of TMDB/IGDB calls plus CPU-bound
    embedding work (each individually dispatched via asyncio.to_thread,
    see app/embeddings.py) before it's done. The one genuinely
    transactional DB use here — the rate-limit check itself, an atomic
    UPSERT — gets its own short-lived session right at the top instead,
    before any of that starts.
    """
    with SessionLocal() as rl_db:
        ai_ask_limiter.check(rl_db, current_user.id)
    raw_query = payload.query.strip()
    if not raw_query:
        raise HTTPException(status_code=400, detail="query is empty")
    q = raw_query.lower()

    if not settings.tmdb_api_key and not (settings.igdb_client_id and settings.igdb_client_secret):
        raise HTTPException(
            status_code=503,
            detail="No catalog sources are configured yet (need TMDB_API_KEY and/or IGDB_CLIENT_ID/SECRET)",
        )

    # How a game should be *played* ("co-op", "for two", "split screen") is
    # its own kind of signal, parsed before anything genre-shaped so those
    # words neither leak into genre/title matching ("мультиплеер" starts
    # with "мульт" — an animation keyword) nor get lost: they become an
    # IGDB game-mode filter below. See app/game_intent.py.
    intent = game_intent.parse(q, games_explicit=any(kw in q for kw in _GAME_KW))
    q_topic = game_intent.strip(q) if intent.active else q

    concepts = _matched_concepts(q_topic)
    kinds = _media_kinds(q)
    if intent.strong and not _explicit_kind(q):
        kinds = {"game"}  # "co-op for two" can only be about games
    exact_year, decade = _extract_year_and_decade(q)
    reference_title = _extract_reference(q_topic)
    freetext = _freetext_remainder(q_topic if intent.active else raw_query, concepts, reference_title)
    # With play-mode words removed, an empty remainder must stay empty:
    # falling back to the raw query would hand words like "game" to the
    # text-overlap scorer and boost every title that happens to contain it.
    query_words = _content_words(freetext or ("" if intent.active else raw_query))
    tmdb_language = "ru-RU" if _CYRILLIC_RE.search(q) else None

    movie_genre_targets = sorted({g for c in concepts for g in _CONCEPTS[c]["movie"]})
    tv_genre_targets = sorted({g for c in concepts for g in _CONCEPTS[c]["tv"]})
    game_kw_targets = sorted({g for c in concepts for g in _CONCEPTS[c]["game"]})

    # "like Interstellar" / "как Ведьмак" — resolve the referenced title so
    # its own genres (in its own segment — no cross movie<->tv translation,
    # see the comment further down) can widen the genre search, and (when
    # the query didn't otherwise say "movie"/"game"/etc.) so its media type
    # picks the search scope instead of searching all three blindly.
    reference_item: Optional[MediaItem] = None
    ref_genres_movie: List[str] = []
    ref_genres_tv: List[str] = []
    reference_similar_ids: Set[str] = set()
    movie_pool: List[MediaItem] = []
    tv_pool: List[MediaItem] = []
    game_pool: List[MediaItem] = []
    # Per-game extras from IGDB discovery (rating count, themes), by
    # "source:id" — see GameHit.
    game_hits: Dict[str, GameHit] = {}

    if reference_title:
        # Try the query's own language first, then the other one — a
        # reference is very often a locally fan-translated name (e.g. a RU
        # nickname for a Turkish/Korean show) that TMDB never registered as
        # an alias, while the title *does* exist there under its original-
        # language name. One search alone silently drops these; the second
        # attempt is what actually finds most of them.
        hits: List[MediaItem] = []
        search_variants = [reference_title]
        # A reference extracted out of a Russian sentence ("похож на
        # мандалорца") is almost never in the nominative case TMDB's own
        # Russian aka titles use ("Мандалорец") — see app/ru_morph.py for
        # why. Only worth attempting for Cyrillic text; a Latin-script
        # reference has no Russian case ending to strip.
        if _CYRILLIC_RE.search(reference_title):
            normalized_reference = ru_morph.normalize_to_nominative(reference_title)
            if normalized_reference:
                search_variants.append(normalized_reference)
        for variant in search_variants:
            for lang in ([tmdb_language, None] if tmdb_language else [None, "ru-RU"]):
                try:
                    lang_hits, _ = await _tmdb.catalog_search(variant, language=lang)
                except Exception:
                    lang_hits = []
                if lang_hits:
                    hits = lang_hits
                    break
            if hits:
                break
        # "games like Portal" resolves against TMDB, which has no games — it
        # finds a *film* called Portal. Treating that as the reference
        # would pull films into a games-only ask, so it isn't one.
        if hits and kinds == {"game"} and hits[0].media_type != "game":
            hits = []
        if hits:
            reference_item = hits[0]
            if not _explicit_kind(q):
                kinds = {"game"} if reference_item.media_type == "game" else {"movie", "tv"}
            # Whatever the query literally said ("movie"/"фильм" etc.), a
            # reference that actually resolved to a series shouldn't be
            # locked out of using TMDB's own similar-titles signal for it —
            # that's the single best signal this endpoint has access to,
            # worth widening the scope for even when the wording was
            # (probably casually) movie-specific.
            ref_kind_guess = "game" if reference_item.media_type == "game" else (
                "tv" if reference_item.media_type in ("series", "anime") else "movie"
            )
            kinds = kinds | {ref_kind_guess}
            # Only the reference's OWN genres, in its OWN segment — not
            # translated into the other segment's genre names. That
            # translation used to launch a whole discover-by-genre call in
            # the *other* segment (e.g. a TV reference pulling movies via
            # translated genres), which turned out to be too blunt a
            # signal: two generic genres like Drama+Family match a huge
            # fraction of everything in that segment (nearly every family
            # movie ever made carries both), so a TV reference used to
            # flood movie results with big unrelated titles at a
            # confident-looking score. `kinds` above already widens to the
            # reference's own segment, and that segment gets the real
            # signal (its own genres + TMDB's own similar-titles data
            # below) — cross-segment recommendations from a reference
            # alone just don't have a reliable signal, so this no longer
            # manufactures one.
            if reference_item.media_type == "movie":
                ref_genres_movie = list(reference_item.genres)
            elif reference_item.media_type in ("series", "anime"):
                ref_genres_tv = list(reference_item.genres)

            # TMDB's own "similar titles" data for the resolved reference —
            # a real per-title similarity signal (collaborative/editorial),
            # much sharper than a plain genre-AND. Only worth fetching for
            # a kind the request actually wants, and only for movie/tv
            # (games have no such endpoint here).
            ref_segment_kind = (
                "movie" if reference_item.media_type == "movie"
                else "tv" if reference_item.media_type in ("series", "anime")
                else None
            )
            ref_tmdb_id = reference_item.external_ids.tmdb
            if ref_tmdb_id and ref_segment_kind and ref_segment_kind in kinds:
                try:
                    similar = await _tmdb.similar_titles(
                        ref_tmdb_id, reference_item.media_type, language=tmdb_language
                    )
                except Exception:
                    similar = []
                for item in similar:
                    reference_similar_ids.add(f"{item.source}:{item.id}")
                    (movie_pool if item.media_type == "movie" else tv_pool).append(item)

    movie_genre_calls = sorted({*movie_genre_targets, *ref_genres_movie})
    tv_genre_calls = sorted({*tv_genre_targets, *ref_genres_tv})

    tasks: List[Tuple[str, object]] = []
    # A reference's own genres should widen recall (OR), not narrow it
    # (AND) — see similar_by_genre's match_all docstring. Only relevant
    # when a reference actually contributed to the call: a plain
    # "sci-fi and fantasy movie" ask with no reference still wants its
    # explicitly-named genres ANDed together as before.
    #
    # Same OR logic for a mood-only query ("что-то грустное" -> Drama,
    # Romance, War): a mood word maps to several genres that each
    # independently signal the mood, not a combination the title has to
    # satisfy all at once — requiring Drama AND Romance AND War would
    # throw out most genuinely sad films that only carry one of those
    # tags. AND stays the default the moment a *non-mood* concept is
    # also in play (e.g. "sad sci-fi movie"), since that's back to an
    # explicit multi-genre ask like "sci-fi and fantasy movie" above.
    non_mood_concepts = [c for c in concepts if c not in _MOOD_CONCEPTS]
    mood_only = bool(concepts) and not non_mood_concepts
    genre_match_all = reference_item is None and not mood_only
    if "movie" in kinds and movie_genre_calls:
        tasks.append(("movie_genre", _tmdb.similar_by_genre(
            "movie", movie_genre_calls, language=tmdb_language, match_all=genre_match_all,
        )))
    if "tv" in kinds and tv_genre_calls:
        tasks.append(("tv_genre", _tmdb.similar_by_genre(
            "tv", tv_genre_calls, language=tmdb_language, match_all=genre_match_all,
        )))
    if ("movie" in kinds or "tv" in kinds) and freetext:
        tasks.append(("tmdb_text", _tmdb.catalog_search(freetext, language=tmdb_language)))
    if "game" in kinds:
        game_genre_ids = sorted({i for c in concepts for i in _GAME_FILTERS.get(c, {}).get("genres", [])})
        game_theme_ids = sorted({i for c in concepts for i in _GAME_FILTERS.get(c, {}).get("themes", [])})
        game_year_from = decade if decade is not None else (exact_year - 2 if exact_year is not None else None)
        game_year_to = (decade + 9) if decade is not None else (exact_year + 2 if exact_year is not None else None)
        tasks.append(("game", _game_candidates(
            query_text=raw_query,
            intent=intent,
            genre_ids=game_genre_ids,
            theme_ids=game_theme_ids,
            year_from=game_year_from,
            year_to=game_year_to,
            title_text=_game_title_query(freetext),
        )))

    if tasks:
        gathered = await asyncio.gather(*(t[1] for t in tasks), return_exceptions=True)
        for (label, _), result in zip(tasks, gathered):
            if isinstance(result, Exception):
                continue
            if label == "movie_genre":
                movie_pool.extend(result)
            elif label == "tv_genre":
                tv_pool.extend(result)
            elif label == "tmdb_text":
                items, _ = result
                for item in items:
                    (movie_pool if item.media_type == "movie" else tv_pool).append(item)
            elif label == "game":
                for hit in result:
                    game_hits[f"{hit.item.source}:{hit.item.id}"] = hit
                    game_pool.append(hit.item)

    # A pure mood/vibe query — no recognized genre word, no reference
    # title, nothing for any of the genre-discover/title-search calls
    # above to have latched onto — leaves every pool above empty (see
    # module docstring). The only signal left is semantic meaning, which
    # needs real candidates to rank against, so widen to the same broad
    # catalog pool GET /feed shows on Home rather than surfacing an
    # honest-but-useless "couldn't find a good match for that". Left
    # alone whenever a concept/reference/game-genre DID match something,
    # so an already-working query doesn't pay for this pool too.
    #
    # The FULL pool is used here on purpose, not a random subset of it —
    # a subset can only ever rank what happened to survive the cut, so
    # the one title that's actually the best semantic fit for "weird and
    # mind-bending" could easily just not be in it. The cost this avoids
    # (embedding whatever in the pool isn't cached yet) isn't a per-query
    # cost worth trading match quality for: embeddings are cached by
    # title id with no expiry (see app/cache.py::get_embedding), so once
    # any query — vibe or otherwise — has caused a given title to get
    # embedded, every later query reuses that vector for free, forever.
    # Only the pool refreshing every 24h (see _broad_pool) reintroduces
    # a handful of new titles worth embedding; it's never the same
    # multi-hundred-item cold start twice.
    #
    # Movies/series only: games have their own broad pool (see
    # _game_candidates) with an audience floor this feed pool lacks, and a
    # games-only ask shouldn't pay for the ~85-call TMDB mixed pool at all.
    if (
        not concepts and reference_item is None and not movie_genre_calls
        and not tv_genre_calls and not game_kw_targets
        and ("movie" in kinds or "tv" in kinds)
    ):
        broad = await _broad_pool(None)
        broad = [
            item for item in broad
            if (item.media_type == "movie" and "movie" in kinds)
            or (item.media_type in ("series", "anime") and "tv" in kinds)
        ]
        # Pre-filter by an ABSOLUTE cosine floor before this pool ever
        # reaches the pool-relative normalization in _semantic_scores.
        # `_broad_pool` is Home's entire mixed discover feed — hundreds
        # of popular titles with no relation to the query beyond "it's
        # in the catalog". Normalizing relative to that pool means the
        # single least-unrelated title in a pile of unrelated ones still
        # comes out at the top of the 0..1 range and gets displayed as a
        # confident-looking match % (see the "что-то грустное" case this
        # was written against: a horror film and a Christmas cartoon
        # both showing ~55% "match" purely because they were the least
        # bad of an unfiltered pool). Filtering on the RAW cosine first —
        # same style of absolute cutoff already used in the last-resort
        # fallback below (_SEMANTIC_FALLBACK_MIN_COSINE) — means only
        # titles genuinely close to the query survive into that pool at
        # all, so whatever normalization happens afterward is relative
        # to an already-decent shortlist, not to noise.
        #
        # Only applies here, never to the rule-based genre/reference
        # pools above: those already have a real non-semantic reason to
        # be candidates (matched genre, TMDB's own similar-titles data),
        # so their semantic score is additive polish, not the sole
        # gatekeeper the way it is for a pure vibe query with nothing
        # else to go on.
        if broad and raw_query.strip() and embeddings.available():
            broad_raw = await _semantic_raw_scores(None, raw_query, broad)
            broad = [
                item for item in broad
                if broad_raw.get(f"{item.source}:{item.id}", 0.0) >= _SEMANTIC_BROAD_POOL_MIN_COSINE
            ]
        for item in broad:
            if item.media_type == "movie":
                movie_pool.append(item)
            elif item.media_type in ("series", "anime"):
                tv_pool.append(item)

    def _reasoning(matched_genres: List[str], year_hit: bool, via_reference: bool, semantic_hit: bool, mode_labels: Sequence[str] = ()) -> Optional[str]:
        bits = []
        if via_reference and reference_item is not None:
            ref_title = _display(reference_item.title) or "your reference"
            bits.append(f"similar to {ref_title}")
        if matched_genres:
            bits.append("genres: " + ", ".join(matched_genres[:3]))
        if mode_labels:
            bits.append("modes: " + ", ".join(mode_labels))
        if year_hit:
            bits.append("era matches")
        if semantic_hit:
            bits.append("matches what you described")
        return "; ".join(bits) if bits else None

    # Sort key vs. displayed match % are deliberately two different
    # numbers now. Clamping straight to the 30-98 range shown to the user
    # BEFORE sorting used to mean: any item with a strong genre match (up
    # to 60) plus the reference bonus already hit the 98 ceiling on its
    # own, regardless of semantic score — so ties got broken by
    # insertion order, which for reference-similar_titles-sourced items
    # is TMDB's OWN mediocre similarity ranking (a well-known weak point
    # of that endpoint: it leans heavily on shared genre/era rather than
    # real thematic closeness, which is exactly why "like Interstellar"
    # used to surface generic Star Trek/Back to the Future entries ahead
    # of genuinely closer films). Sorting on the raw, unclamped sum lets
    # a high semantic score actually outrank a merely-genre-matched one,
    # even when both would display the same capped percentage.
    #
    # A tied raw_score is common (e.g. "2/3 genres + reference bonus" and
    # "3/3 genres, no reference" can land on the same integer sum) — and
    # ties used to fall back to insertion order, i.e. whichever pool a
    # title happened to be fetched from first (TMDB's similar-titles list
    # is appended before genre-discover results — see reference_item
    # resolution above), not anything about how good the match actually
    # is. semantic_component is carried as an explicit secondary sort
    # key so a tie resolves toward the title that's actually closer in
    # meaning, not toward whichever fetch happened to run first.
    scored: List[Tuple[float, float, int, MediaItem, Optional[str]]] = []
    seen: Set[str] = set()

    def _add(item: MediaItem, raw_score: float, matched: List[str], year_hit: bool, via_reference: bool, semantic_hit: bool = False, semantic_component: float = 0.0, mode_labels: Sequence[str] = ()):
        key = f"{item.source}:{item.id}"
        if key in seen:
            return
        seen.add(key)
        display_score = max(30, min(98, round(raw_score)))
        scored.append((raw_score, semantic_component, display_score, item, _reasoning(matched, year_hit, via_reference, semantic_hit, mode_labels)))

    # A bonus for a title TMDB itself flagged as similar to the
    # reference — real similarity data, not a genre guess, so it still
    # counts for more than a plain genre match. Deliberately smaller than
    # it used to be (was 40): TMDB's own "similar" endpoint leans on
    # genre/era more than real theme/plot closeness (see note above), so
    # it shouldn't be able to single-handedly outweigh a strong semantic
    # score the way a flat +40 on top of a genre match could.
    _REFERENCE_BONUS = 20

    # Semantic pass over the whole candidate pool at once (one batched
    # embedding call for whatever isn't already cached) — see
    # _semantic_scores' docstring above for why this is pool-relative
    # rather than an absolute cutoff, and why it's skipped entirely for
    # queries with no real free text (a bare "фантастика 90-х" has
    # nothing semantic to compare against; genre+year already cover it).
    # The full original sentence, not `freetext` — freetext deliberately
    # strips out exactly the genre/media-type words ("sci-fi", "game",
    # "стратегия"...) that a short query's semantic meaning usually rides
    # on, so a query built entirely from recognized keywords (e.g. "2010s
    # sci-fi game") used to leave freetext as just "2010s" and hand that
    # bare fragment to the embedding model instead of the actual ask.
    semantic_query_text = raw_query
    all_candidates = (
        [i for i in movie_pool if i.media_type == "movie"]
        + [i for i in tv_pool if i.media_type in ("series", "anime")]
        + game_pool
    )
    semantic_scores = await _semantic_scores(
        None, semantic_query_text, all_candidates,
        {key: hit.themes for key, hit in game_hits.items()},
    )
    # Normalized (pool-relative, see _semantic_scores) — only the
    # top slice of this query's own candidates counts as a genuine
    # semantic hit worth mentioning in `reasoning`, not merely "better
    # than the pool's worst match".
    _SEMANTIC_HIT_THRESHOLD = 0.6

    def _semantic_bonus(item: MediaItem) -> Tuple[float, bool]:
        normalized = semantic_scores.get(f"{item.source}:{item.id}", 0.0)
        return normalized * _SEMANTIC_WEIGHT, normalized >= _SEMANTIC_HIT_THRESHOLD

    for item in movie_pool:
        if item.media_type != "movie":
            continue
        via_ref = f"{item.source}:{item.id}" in reference_similar_ids
        matched = [g for g in item.genres if g in movie_genre_calls]
        genre_score = (len(matched) / len(movie_genre_calls)) * 60 if movie_genre_calls else 0
        ys = _year_score(item.year, exact_year, decade)
        bonus = _REFERENCE_BONUS if via_ref else 0
        semantic_bonus, semantic_hit = _semantic_bonus(item)
        raw_score = genre_score + ys + _text_overlap_score(query_words, item) + bonus + semantic_bonus
        _add(item, raw_score, matched, ys > 0, via_ref, semantic_hit, semantic_bonus)

    for item in tv_pool:
        if item.media_type not in ("series", "anime"):
            continue
        via_ref = f"{item.source}:{item.id}" in reference_similar_ids
        matched = [g for g in item.genres if g in tv_genre_calls]
        genre_score = (len(matched) / len(tv_genre_calls)) * 60 if tv_genre_calls else 0
        ys = _year_score(item.year, exact_year, decade)
        bonus = _REFERENCE_BONUS if via_ref else 0
        semantic_bonus, semantic_hit = _semantic_bonus(item)
        raw_score = genre_score + ys + _text_overlap_score(query_words, item) + bonus + semantic_bonus
        _add(item, raw_score, matched, ys > 0, via_ref, semantic_hit, semantic_bonus)

    # Genre fit is per *concept* ("sci-fi", "shooter"), not per keyword: a
    # concept lists several alternative spellings/tags and any one of them
    # counts — dividing by the keyword count instead meant a perfect
    # sci-fi game could never score above half. Terms are the game's genre
    # AND theme names (IGDB keeps sci-fi/horror/fantasy under themes).
    game_concepts = [c for c in concepts if _CONCEPTS[c]["game"]]
    for item in game_pool:
        hit = game_hits.get(f"{item.source}:{item.id}")
        # The play mode is a hard requirement, not a vibe: a game that
        # isn't co-op is not an answer to a co-op ask, however similar its
        # description reads. (And an MMO isn't an answer to "for two".)
        mode_fit = intent.evaluate(item.game_modes)
        if mode_fit is None:
            continue
        terms = [t.lower() for t in [*item.genres, *(hit.themes if hit else [])]]
        matched_concepts = [
            c for c in game_concepts
            if any(kw in term for kw in _CONCEPTS[c]["game"] for term in terms)
        ]
        matched = [
            name for name in [*item.genres, *(hit.themes if hit else [])]
            if any(kw in name.lower() for c in matched_concepts for kw in _CONCEPTS[c]["game"])
        ]
        genre_score = (len(matched_concepts) / len(game_concepts)) * 60 if game_concepts else 0
        if game_concepts and not matched_concepts:
            genre_score -= _GAME_GENRE_MISS_PENALTY
        ys = _year_score(item.year, exact_year, decade)
        semantic_bonus, semantic_hit = _semantic_bonus(item)
        raw_score = (
            genre_score + ys + _text_overlap_score(query_words, item) + semantic_bonus
            + mode_fit.bonus + _game_quality_bonus(item, hit)
        )
        _add(item, raw_score, matched, ys > 0, False, semantic_hit, semantic_bonus, mode_fit.labels)

    # The referenced title is what the person described their taste *by*,
    # not a recommendation of it back to them.
    if reference_item is not None:
        ref_key = f"{reference_item.source}:{reference_item.id}"
        scored = [row for row in scored if f"{row[3].source}:{row[3].id}" != ref_key]

    # Last resort: whatever was tried above came back empty (an unusual
    # phrasing with no recognizable genre word, a reference title that
    # doesn't resolve on TMDB, etc.) — one more direct text search before
    # giving up.
    #
    # The query text used here matters a lot: searching the *whole*
    # sentence ("movie similar to X" / "фильм похожий на X") almost never
    # matches a real title, because words like "similar"/"похожий" aren't
    # part of any title — so that used to be the only signal fed into a
    # floor score every hit got regardless of relevance (i.e. every
    # leftover catalog result was shown as "a match" with a fabricated
    # minimum ~35%, which is exactly why an unresolved reference used to
    # surface a handful of unrelated popular titles instead of an honest
    # "nothing found"). `reference_title` alone — just the title text,
    # none of the surrounding phrasing — is a far more targeted query when
    # one was extracted, so it's tried first; and a hit is only kept when
    # it actually shares a word with what was searched for, never on a
    # floor score alone.
    if not scored:
        fallback_query = reference_title or freetext or raw_query
        # Same case-normalization as the reference resolution above — if a
        # Cyrillic reference never resolved even with it, still worth
        # trying the lemmatized form directly against /search here too.
        if reference_title and _CYRILLIC_RE.search(fallback_query):
            fallback_query = ru_morph.normalize_to_nominative(fallback_query) or fallback_query
        async def _no_games() -> List[GameHit]:
            return []

        # Same quality-gated lookup as the main path (not the raw fuzzy
        # `search`), and only when games were asked for at all — a movie
        # ask used to fall back to whatever game had a similar name.
        fallback_tasks = [
            _tmdb.catalog_search(fallback_query, language=tmdb_language),
            _games.discover(text=fallback_query) if "game" in kinds else _no_games(),
        ]
        fallback_results = await asyncio.gather(*fallback_tasks, return_exceptions=True)
        fallback_words = _content_words(fallback_query)
        tmdb_fallback, games_fallback = fallback_results
        fallback_items: List[MediaItem] = []
        if not isinstance(tmdb_fallback, Exception):
            fallback_items.extend(tmdb_fallback[0])
        if not isinstance(games_fallback, Exception):
            for hit in games_fallback:
                if intent.evaluate(hit.item.game_modes) is None:
                    continue  # wrong play mode for what was asked
                fallback_items.append(hit.item)

        # Same semantic pass as the main path, but this branch only ever
        # runs when literal text/genre matching found NOTHING — exactly
        # the case a keyword filter can't handle (e.g. "фильм про ИИ,
        # который восстаёт против человечества" sharing no real words
        # with "Из машины"). An absolute cosine cutoff is used here
        # instead of the pool-relative one above, since keeping "an
        # honest nothing found" for a genuinely unrelated query matters
        # more than it does in the main path, where rule-based hits
        # already anchor the pool.
        fallback_semantic_query = raw_query  # see semantic_query_text above
        fallback_query_vector = None
        if fallback_semantic_query.strip() and embeddings.available():
            fallback_query_vector = await asyncio.to_thread(embeddings.embed_query, fallback_semantic_query)

        for item in fallback_items:
            overlap = _text_overlap_score(fallback_words, item)
            semantic_cosine = 0.0
            if fallback_query_vector is not None:
                item_vector = cache.get_embedding(None, item.id, _embedding_cache_source(item))
                if item_vector is None:
                    item_vector = await asyncio.to_thread(embeddings.embed_passage, _embedding_passage(item))
                    if item_vector is not None:
                        cache.set_embedding(None, item.id, _embedding_cache_source(item), item_vector)
                if item_vector is not None:
                    semantic_cosine = embeddings.cosine(fallback_query_vector, item_vector)
            semantic_hit = semantic_cosine >= _SEMANTIC_FALLBACK_MIN_COSINE
            if overlap == 0 and not semantic_hit:
                continue  # no actual relation to what was asked for — don't fabricate a match
            semantic_bonus = max(0.0, semantic_cosine - 0.6) * 100 if semantic_hit else 0.0
            _add(item, 35 + overlap + semantic_bonus, [], False, False, semantic_hit, semantic_bonus)
        if reference_item is not None:
            ref_key = f"{reference_item.source}:{reference_item.id}"
            scored = [row for row in scored if f"{row[3].source}:{row[3].id}" != ref_key]

    if not scored:
        if reference_title:
            detail = (
                f"couldn't find \"{reference_title}\" in the catalog — try its original-language "
                "title, or describe the genre/vibe instead"
            )
        else:
            detail = "couldn't find a good match for that — try different words"
        raise HTTPException(status_code=404, detail=detail)

    # Sort by the raw (unclamped) score first, semantic_component second
    # as an explicit tiebreaker — see `scored`'s definition above for why
    # neither is the same number shown to the user as the match %.
    #
    # The time budget, when there is one, is folded into the raw score
    # here rather than earlier — everything above is about *what* the
    # person wants, and this is about whether it fits tonight. Keeping the
    # two separate means a query with no budget takes a code path that is
    # byte-for-byte what it was before this existed.
    budget_minutes = payload.minutes_available or _parse_spoken_budget(q)
    budget_source = "chip" if payload.minutes_available else "text"
    time_budget_out = None
    time_budget_relaxed = False

    if budget_minutes:
        lang_ru = bool(_CYRILLIC_RE.search(raw_query))
        adjusted = []
        for raw_score, semantic_component, display_score, item, reasoning in scored:
            bonus = _time_fit_bonus(item, budget_minutes)
            line = _time_reasoning(item, budget_minutes, lang_ru)
            merged = reasoning
            if line:
                merged = f"{reasoning} · {line}" if reasoning else line
            adjusted.append((raw_score + bonus, semantic_component, display_score, item, merged))
        scored = adjusted
        time_budget_out = TimeBudgetOut(
            minutes=budget_minutes,
            source=budget_source,
            shape=_budget_shape(budget_minutes),
        )

    scored.sort(key=lambda row: (row[0], row[1]), reverse=True)
    # Was capped at 12 — too tight once a query has a genuinely deep
    # bench of good matches (e.g. a mood/genre query against a wide
    # catalog can easily have #12 still sitting at ~83% raw-equivalent
    # score, meaning real matches were being cut off, not noise). 24
    # isn't a principled number either, just a wider shelf; nothing
    # downstream (schema, mobile list rendering) assumes a fixed count,
    # so this is the only place list length is decided.
    top = _pick_top(scored, limit=24)

    if budget_minutes:
        # Honesty check on the shortlist actually being returned: if none
        # of the top few fit the stated budget, say so rather than let
        # someone with forty minutes scroll a list of three-hour films
        # wondering whether the app heard them.
        head = top[:6]
        time_budget_relaxed = not any(
            item.runtime_minutes and item.runtime_minutes <= budget_minutes
            for _r, _s, _d, item, _reason in head
        )

    results = [
        AiMatchOut(item=item, match=display_score, reasoning=reasoning)
        for _raw_score, _semantic_component, display_score, item, reasoning in top
    ]
    return AiAskResponse(
        results=results,
        is_mock=True,
        time_budget=time_budget_out,
        time_budget_relaxed=time_budget_relaxed,
    )
