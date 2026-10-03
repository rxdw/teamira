"""Taste similarity — "how similar are two people's tastes" as one 0-100
score plus a rich, human-readable breakdown (shared titles, shared
genres, a plain-language headline), never just a bare percentage. Used
in three places, all through the one scale computed here:

  - the friends screen: ranks "people you may know" and flavors the
    existing friends list itself (see routers/friends.py)
  - onboarding's "people like you" step, right after the favorites
    picker — the same WatchlistEntry rows that step already writes
    (see routers/profile.py::toggle_favorite) are all this needs, so a
    brand new account with only a handful of picked favorites already
    has a real (if low-confidence) taste profile by the time it asks
  - the co-viewing circle's "мы" tab: how well matched you and your
    circle-mates are (see routers/partner.py)

Deliberately one combined scale, not separate ones for "watched" vs
"wishlist" vs "watching" — the product asked for one number a person
can read at a glance, with everything they've reacted to feeding into
it at different weights (see _STATUS_WEIGHT below), not three scores
someone has to mentally average themselves.

Entirely self-hosted, no third-party AI call: the semantic half reuses
app/embeddings.py's local multilingual-e5-small model and the exact
same per-title CachedEmbedding cache Ask Teamira already warms (see
app/routers/ai.py) — a title that's already been searched once via Ask
Teamira is already cached here for free, and vice versa. The structured
half (genre overlap, shared titles) needs no model at all and is what
keeps this working even when fastembed isn't installed or hasn't
loaded yet (see embeddings.py's own failure-handling note) — see
_combine_scores below for exactly how the two blend, and how the
weighting shifts when the semantic half simply isn't there.
"""

from __future__ import annotations

import math
import threading
import time
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

from sqlalchemy.orm import Session

from app import cache, embeddings, models

# ---------------------------------------------------------------------------
# Taste profile — one person's weighted "what they're into", built once
# per request (see the small TTL cache at the bottom) rather than stored
# on a schedule: recomputing from a capped, indexed WatchlistEntry query
# plus mostly-cached embedding lookups is cheap enough that a dedicated
# table with its own invalidation logic would be solving a performance
# problem this doesn't actually have yet.
# ---------------------------------------------------------------------------

# How much each shelf counts toward "this is their taste" — `watched` is
# the strongest signal (they actually saw it through), `watching` is
# nearly as strong and deliberately not left out even though it's not
# "finished" (the product ask was explicit: currently-watching is a live
# taste signal, maybe the strongest one, not a lesser one), and
# `watch_later` (the wishlist) counts for real but at less than half
# weight — aspirational taste is still taste, just a softer version of
# it than something someone actually sat through. `dropped` is left out
# entirely (weight 0, and filtered out of the query below before any of
# this even runs) — a title someone bailed on isn't a positive signal,
# and treating it as a mild negative would need knowing *why* they
# dropped it (drop_reason is free text, not a sentiment), which is more
# machinery than a first version of this needs.
_STATUS_WEIGHT: Dict[models.WatchStatus, float] = {
    models.WatchStatus.watched: 1.0,
    models.WatchStatus.watching: 0.85,
    models.WatchStatus.watch_later: 0.45,
}
# Onboarding's favorites step (and the heart on any title screen) is the
# clearest first-person "I like this" signal this app has — it's not
# gated behind actually finishing something, so it gets its own bonus on
# top of whatever shelf weight the title already carries.
_FAVORITE_BONUS = 0.4
# A diary rating of 8+/10 is this app's own definition of "loved it" —
# see push.py::notify_friend_activity's identical threshold and comment.
_LOVED_IT_BONUS = 0.3
_LOVED_IT_MIN_RATING = 8

# Caps how much of one person's shelf history this reads and potentially
# embeds per profile build — bounds both the query and the embedding
# work to something that stays fast even for someone with years of
# diary history, at the cost of only ever looking at their most recently
# touched titles. Recency is a reasonable proxy for "current taste"
# anyway (someone's taste five years ago matters less to a match today
# than what they've been into lately).
_MAX_TITLES_PER_PROFILE = 250

# A profile with fewer than this many weighted titles is real but thin —
# still worth a match (this is exactly onboarding's cold-start case: a
# handful of picked favorites and nothing else yet), just labeled as
# lower-confidence rather than presented with the same certainty as a
# profile built from years of diary history. See TasteMatch.confidence.
_THIN_PROFILE_MAX = 5


@dataclass
class WeightedTitle:
    """One title in a person's taste profile, carrying enough of its
    WatchlistEntry snapshot to render a poster/name without a second
    fetch — same snapshot-not-reference philosophy as WatchlistEntry
    itself (see that model's own docstring)."""
    media_id: str
    source: str
    media_type: str
    title_ru: Optional[str]
    title_en: Optional[str]
    poster_url: Optional[str]
    genres: List[str]
    weight: float
    # Surfaced so a headline can say "you're both watching this RIGHT
    # NOW" rather than treating it the same as an old favorite — the
    # single strongest kind of match this app can point at.
    status: str


@dataclass
class TasteProfile:
    user_id: str
    # Keyed "source:media_id" — a dict rather than a list so shared-title
    # lookups between two profiles are a plain set intersection.
    titles: Dict[str, WeightedTitle] = field(default_factory=dict)
    # Weighted-average embedding across every title that had one, or
    # None if nothing in this profile could be embedded (fastembed
    # unavailable, or genuinely nothing on any shelf yet). Cosine
    # similarity divides by each vector's own norm, so this is left
    # un-renormalized after averaging — no need to re-unit-length it.
    vector: Optional[List[float]] = None
    # Proportions (sums to 1.0) rather than raw weights, so two people
    # with very differently sized histories still compare on equal
    # footing — someone with 300 diary entries and someone with 5
    # onboarding favorites are compared on the *shape* of their taste,
    # not its volume.
    genre_weights: Dict[str, float] = field(default_factory=dict)

    @property
    def sample_size(self) -> int:
        return len(self.titles)


def _embedding_passage(title_ru: Optional[str], title_en: Optional[str], genres: List[str]) -> str:
    """Same spirit as routers/ai.py::_embedding_passage, just built from
    a WatchlistEntry snapshot instead of a live MediaItem (no
    description snapshot exists on that row — title + genres alone is
    still plenty for the model to place a title semantically, and
    that's genuinely all a shelf entry has on file). Reads/writes the
    exact same CachedEmbedding row Ask Teamira uses (see app/cache.py's
    get_embedding/set_embedding), so a popular title is very often
    already cached by the time this ever needs it.
    """
    title = title_en or title_ru or ""
    return f"{title}. {', '.join(genres)}".strip(". ")


def compute_taste_profile(db: Session, user_id: str) -> TasteProfile:
    """Builds one person's current taste profile from their own
    WatchlistEntry rows — every shelf that carries a positive signal
    (see _STATUS_WEIGHT), most-recently-touched first, capped at
    _MAX_TITLES_PER_PROFILE. Always returns a profile, even an empty one
    (sample_size == 0) for someone with nothing logged yet — callers
    decide what an empty profile means for them (see compare() below,
    which refuses to score one).
    """
    entries = (
        db.query(models.WatchlistEntry)
        .filter(
            models.WatchlistEntry.user_id == user_id,
            models.WatchlistEntry.status.in_(list(_STATUS_WEIGHT.keys())),
        )
        .order_by(models.WatchlistEntry.updated_at.desc())
        .limit(_MAX_TITLES_PER_PROFILE)
        .all()
    )

    titles: Dict[str, WeightedTitle] = {}
    genre_raw: Dict[str, float] = {}
    missing_for_embedding: List[Tuple[str, WeightedTitle]] = []

    for e in entries:
        weight = _STATUS_WEIGHT.get(e.status, 0.0)
        if weight <= 0:
            continue
        if e.is_favorite:
            weight += _FAVORITE_BONUS
        if e.user_rating is not None and e.user_rating >= _LOVED_IT_MIN_RATING:
            weight += _LOVED_IT_BONUS

        key = f"{e.source}:{e.media_id}"
        genres = list(e.genres or [])
        wt = WeightedTitle(
            media_id=e.media_id,
            source=e.source,
            media_type=e.media_type.value if hasattr(e.media_type, "value") else str(e.media_type),
            title_ru=e.title_ru,
            title_en=e.title_en,
            poster_url=e.poster_url,
            genres=genres,
            weight=weight,
            status=e.status.value if hasattr(e.status, "value") else str(e.status),
        )
        # A title touched more than once (status changed over time,
        # re-logged, etc.) keeps only its most recent row — entries are
        # already walked most-recent-first, so the first one seen per
        # key wins and later, staler duplicates are skipped.
        if key in titles:
            continue
        titles[key] = wt
        for g in genres:
            genre_raw[g] = genre_raw.get(g, 0.0) + weight

        cached_vector = cache.get_embedding(db, e.media_id, e.source)
        if cached_vector is None:
            missing_for_embedding.append((key, wt))

    vectors: Dict[str, List[float]] = {}
    if titles and embeddings.available():
        if missing_for_embedding:
            passages = [
                _embedding_passage(wt.title_ru, wt.title_en, wt.genres)
                for _, wt in missing_for_embedding
            ]
            computed = embeddings.embed_passages(passages)
            for (key, wt), vector in zip(missing_for_embedding, computed):
                if vector is not None:
                    vectors[key] = vector
                    cache.set_embedding(db, wt.media_id, wt.source, vector)
        for key in titles:
            if key in vectors:
                continue
            cached_vector = cache.get_embedding(db, titles[key].media_id, titles[key].source)
            if cached_vector is not None:
                vectors[key] = cached_vector

    profile_vector: Optional[List[float]] = None
    if vectors:
        dims = len(next(iter(vectors.values())))
        summed = [0.0] * dims
        total_weight = 0.0
        for key, vec in vectors.items():
            w = titles[key].weight
            total_weight += w
            for i, v in enumerate(vec):
                summed[i] += v * w
        if total_weight > 0:
            profile_vector = [v / total_weight for v in summed]

    genre_total = sum(genre_raw.values())
    genre_weights = (
        {g: w / genre_total for g, w in genre_raw.items()} if genre_total > 0 else {}
    )

    return TasteProfile(
        user_id=user_id,
        titles=titles,
        vector=profile_vector,
        genre_weights=genre_weights,
    )


# ---------------------------------------------------------------------------
# Comparing two profiles — one 0-100 score, blended from three signals,
# plus everything needed to explain *why* rather than just stating the
# number (see the module docstring's "never just a bare percentage").
# ---------------------------------------------------------------------------

@dataclass
class SharedTitle:
    media_id: str
    source: str
    media_type: str
    title_ru: Optional[str]
    title_en: Optional[str]
    poster_url: Optional[str]


@dataclass
class TasteMatch:
    overall: int  # 0-100, the one scale every surface shows
    headline: str  # a plain-language reason, e.g. "you're both watching «X» right now"
    basis: str  # short honest caveat on how much data this rests on
    # "new" (very thin data on one or both sides — e.g. someone just
    # finished onboarding), "some" (a real but modest history), "solid"
    # (plenty of overlapping signal) — lets the UI soften its own
    # confidence (a smaller ring, a gentler claim) without needing to
    # re-derive it from sample sizes itself.
    confidence: str
    shared_titles: List[SharedTitle] = field(default_factory=list)
    shared_genres: List[str] = field(default_factory=list)


# e5 cosine similarities run compressed to begin with (see
# routers/ai.py's own _SEMANTIC_FALLBACK_MIN_COSINE comment on this),
# and averaging many titles into one profile vector compresses the
# range further still — two genuinely unrelated taste profiles rarely
# cosine below ~0.7 against each other, and even a near-identical pair
# rarely clears ~0.97. An empirical floor/ceiling remap onto 0-100 (not
# a raw cosine-as-percent read-off) is what keeps the displayed number
# meaningful instead of every pair reading as "70%+ similar."
_SEMANTIC_FLOOR = 0.75
_SEMANTIC_CEILING = 0.97

# How the three signals blend when all three are available. Semantic
# carries the most weight since it's the only one that can catch "same
# vibe, different titles" (two people who both love moody sci-fi but
# have watched almost nothing in common) — genre overlap is a coarser
# but zero-cost-to-trust structural signal, and the shared-title bonus
# is capped low on purpose: two people who've both merely watched a
# handful of the same blockbusters shouldn't outscore two people whose
# entire taste vector points the same direction.
_SEMANTIC_WEIGHT = 0.5
_GENRE_WEIGHT = 0.35
_SHARED_TITLE_WEIGHT = 0.15
# Same three signals, renormalized, for the (common — see embeddings.py's
# own failure-handling note) case where no semantic vector exists on one
# or both sides.
_GENRE_WEIGHT_NO_SEMANTIC = 0.7
_SHARED_TITLE_WEIGHT_NO_SEMANTIC = 0.3

# A shared-title bonus of "4 percentage points per shared title, capped
# at 20" — generous enough that even 2-3 shared titles register clearly
# (exactly onboarding's cold-start scale), without a couple who happen
# to share ten mainstream blockbusters maxing the whole score out on
# that alone.
_SHARED_TITLE_POINTS = 4.0
_SHARED_TITLE_CAP = 20.0


def _semantic_percent(cosine: float) -> float:
    pct = (cosine - _SEMANTIC_FLOOR) / (_SEMANTIC_CEILING - _SEMANTIC_FLOOR)
    return max(0.0, min(1.0, pct)) * 100


def _genre_overlap_percent(a: Dict[str, float], b: Dict[str, float]) -> float:
    if not a or not b:
        return 0.0
    keys = set(a) | set(b)
    dot = sum(a.get(k, 0.0) * b.get(k, 0.0) for k in keys)
    norm_a = math.sqrt(sum(v * v for v in a.values()))
    norm_b = math.sqrt(sum(v * v for v in b.values()))
    if norm_a == 0.0 or norm_b == 0.0:
        return 0.0
    return max(0.0, min(1.0, dot / (norm_a * norm_b))) * 100


def _shared_title_percent(count: int) -> float:
    return min(_SHARED_TITLE_CAP, count * _SHARED_TITLE_POINTS)


def _display_title(t) -> str:
    """Same 'prefer English, fall back to Russian' pick as the mobile
    client's own WatchlistEntry.displayTitle — kept consistent so a
    server-written headline never disagrees with what the client would
    have shown for the same title."""
    if t.title_en and t.title_en.strip():
        return t.title_en
    return t.title_ru or "это"


def _headline(
    a: TasteProfile, b: TasteProfile, shared: List[SharedTitle], shared_genres: List[str]
) -> str:
    """Picks the single best "why you're a match" line, in priority
    order from most specific/actionable down to a generic fallback —
    see the module docstring's "never just a bare percentage." Only
    ever reads from `shared`/`shared_genres`, which are already ranked
    (see compare() below), so this just walks priority tiers rather
    than re-deriving anything.
    """
    shared_by_key = {f"{t.source}:{t.media_id}": t for t in shared}

    watching_now = [
        t for t in shared
        if a.titles[f"{t.source}:{t.media_id}"].status == "watching"
        and b.titles[f"{t.source}:{t.media_id}"].status == "watching"
    ]
    if watching_now:
        return f"вы оба сейчас смотрите «{_display_title(watching_now[0])}»"

    loved_by_both = [
        t for t in shared
        if a.titles[f"{t.source}:{t.media_id}"].weight >= _STATUS_WEIGHT[models.WatchStatus.watched] + _LOVED_IT_BONUS
        and b.titles[f"{t.source}:{t.media_id}"].weight >= _STATUS_WEIGHT[models.WatchStatus.watched] + _LOVED_IT_BONUS
    ]
    if loved_by_both:
        return f"вы оба обожаете «{_display_title(loved_by_both[0])}»"

    if len(shared) >= 2:
        first, second = shared[0], shared[1]
        return (
            f"у вас {len(shared)} общих тайтла — «{_display_title(first)}» и «{_display_title(second)}»"
            if len(shared) == 2
            else f"у вас {len(shared)} общих тайтлов, включая «{_display_title(first)}» и «{_display_title(second)}»"
        )
    if len(shared) == 1:
        return f"у вас есть общий тайтл — «{_display_title(shared[0])}»"

    if shared_genres:
        if len(shared_genres) == 1:
            return f"похожий вкус в жанре «{shared_genres[0]}»"
        return f"похожий вкус — {', '.join(shared_genres[:2])}"

    return "в целом похожие вкусы в кино и сериалах"


def _confidence(a: TasteProfile, b: TasteProfile) -> str:
    smallest = min(a.sample_size, b.sample_size)
    if smallest <= _THIN_PROFILE_MAX:
        return "new"
    if smallest <= _THIN_PROFILE_MAX * 6:
        return "some"
    return "solid"


def _basis(a: TasteProfile, b: TasteProfile, confidence: str) -> str:
    smallest = min(a.sample_size, b.sample_size)
    if confidence == "new":
        return "на основе всего нескольких тайтлов — точнее станет, когда посмотрите ещё"
    return f"на основе {smallest}+ тайтлов в дневниках и списках"


def compare(a: TasteProfile, b: TasteProfile) -> Optional[TasteMatch]:
    """The one entry point every surface calls. Returns None — not a 0%
    match — when either side has nothing on any shelf yet: an empty
    profile carries no information about taste at all, and scoring it
    as "0% similar" would be a false claim of *opposite* taste rather
    than an honest "nothing to compare yet." Callers should treat None
    as "hide/deprioritize this pair," exactly the same as no match data
    existing at all.
    """
    if a.sample_size == 0 or b.sample_size == 0:
        return None

    shared_keys = set(a.titles) & set(b.titles)
    shared_ranked = sorted(
        shared_keys,
        key=lambda k: a.titles[k].weight + b.titles[k].weight,
        reverse=True,
    )
    shared_titles = [
        SharedTitle(
            media_id=a.titles[k].media_id,
            source=a.titles[k].source,
            media_type=a.titles[k].media_type,
            title_ru=a.titles[k].title_ru,
            title_en=a.titles[k].title_en,
            poster_url=a.titles[k].poster_url,
        )
        for k in shared_ranked[:12]
    ]

    shared_genre_keys = set(a.genre_weights) & set(b.genre_weights)
    shared_genres_ranked = sorted(
        shared_genre_keys,
        key=lambda g: min(a.genre_weights[g], b.genre_weights[g]),
        reverse=True,
    )[:5]

    genre_pct = _genre_overlap_percent(a.genre_weights, b.genre_weights)
    title_pct = _shared_title_percent(len(shared_keys))

    if a.vector is not None and b.vector is not None:
        semantic_pct = _semantic_percent(embeddings.cosine(a.vector, b.vector))
        overall = (
            semantic_pct * _SEMANTIC_WEIGHT
            + genre_pct * _GENRE_WEIGHT
            + title_pct * _SHARED_TITLE_WEIGHT
        )
    else:
        # No semantic signal on one or both sides — degrade to the
        # structural signals alone rather than silently zeroing out a
        # third of the score (see embeddings.py's own "never a hard
        # dependency" philosophy, applied here the same way).
        overall = genre_pct * _GENRE_WEIGHT_NO_SEMANTIC + title_pct * _SHARED_TITLE_WEIGHT_NO_SEMANTIC

    overall_int = int(round(max(0.0, min(100.0, overall))))
    confidence = _confidence(a, b)

    return TasteMatch(
        overall=overall_int,
        headline=_headline(a, b, shared_titles, shared_genres_ranked),
        basis=_basis(a, b, confidence),
        confidence=confidence,
        shared_titles=shared_titles,
        shared_genres=shared_genres_ranked,
    )


# ---------------------------------------------------------------------------
# Small in-process cache — a taste profile is read (and its missing
# embeddings computed) by potentially several endpoints in quick
# succession for the same viewer (the friends screen loads the accepted
# list and the suggestions list back to back; onboarding's reveal step
# calls this right after the favorites step wrote the very data it
# reads). A short TTL avoids redoing that work per call without ever
# risking a stale profile surviving more than a few minutes — nothing
# here is safety-critical enough to need real invalidation on write.
# Not shared across processes/workers; each one builds its own, which is
# fine at the scale this cache exists to help with.
# ---------------------------------------------------------------------------

_PROFILE_CACHE: Dict[str, Tuple[float, TasteProfile]] = {}
_PROFILE_CACHE_LOCK = threading.Lock()
_PROFILE_TTL_SECONDS = 300.0


def get_taste_profile_cached(db: Session, user_id: str) -> TasteProfile:
    now = time.monotonic()
    with _PROFILE_CACHE_LOCK:
        cached = _PROFILE_CACHE.get(user_id)
        if cached is not None and now - cached[0] < _PROFILE_TTL_SECONDS:
            return cached[1]
    profile = compute_taste_profile(db, user_id)
    with _PROFILE_CACHE_LOCK:
        _PROFILE_CACHE[user_id] = (now, profile)
    return profile


def invalidate_taste_profile(user_id: str) -> None:
    """Not currently wired to any write path — the TTL above already
    bounds staleness to a few minutes, which is fine for a taste match
    (nobody needs it to update mid-session the instant they log
    something). Exposed for callers that would rather force a fresh
    read right after a bulk write (e.g. finishing an import) than wait
    out the TTL."""
    with _PROFILE_CACHE_LOCK:
        _PROFILE_CACHE.pop(user_id, None)


def taste_match_between(db: Session, user_id_a: str, user_id_b: str) -> Optional[TasteMatch]:
    """Convenience for a single pair (a friend-profile detail view, a
    co-viewing circle member) — see compare() for what None means."""
    a = get_taste_profile_cached(db, user_id_a)
    b = get_taste_profile_cached(db, user_id_b)
    return compare(a, b)
