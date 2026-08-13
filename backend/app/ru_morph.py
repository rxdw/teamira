"""Best-effort Russian case normalization for Ask Teamira's "like X"
reference matching (see app/routers/ai.py) — NOT an AI/ML model. This is
`pymorphy3`, a dictionary+rules Russian morphological analyzer (a fork
of the long-standing pymorphy2): it looks up a word form in a
dictionary of known Russian inflections and returns its lemma, the same
kind of tool a spell-checker or a search engine's query normalizer
uses, not a trained neural network.

Why this exists: a person describing what they want almost never types
a title in the nominative case Russian dictionaries (and TMDB's own
Russian aka titles) use — "фильм похожий на мандалорца" puts
"Мандалорец" in the genitive/accusative ("мандалорца"), because that's
just how the sentence is grammatically built. TMDB's search does plain
text matching, not Russian morphological analysis, so a query in the
wrong case can come back completely empty even though the title is
right there in the catalog under its nominative name. This closes
exactly that gap — nothing more: it maps one inflected word to its
dictionary form, used only as an extra search variant alongside the
original unmodified text, never a guess at meaning.
"""

from __future__ import annotations

import logging
from typing import Optional

logger = logging.getLogger(__name__)

_morph = None
_load_attempted = False


def _get_morph():
    global _morph, _load_attempted
    if _morph is not None:
        return _morph
    if _load_attempted:
        return None
    _load_attempted = True
    try:
        import pymorphy3
    except Exception:
        logger.warning("ru_morph: pymorphy3 not installed — Russian case normalization disabled")
        return None
    try:
        _morph = pymorphy3.MorphAnalyzer()
    except Exception:
        logger.warning("ru_morph: failed to load the analyzer — Russian case normalization disabled", exc_info=True)
        return None
    return _morph


def normalize_to_nominative(text: str) -> Optional[str]:
    """Word-by-word lemmatization to nominative singular (nouns) / base
    form (other parts of speech). Returns None — not the original text
    — when the analyzer isn't available, or the result is identical to
    the input (e.g. it was already nominative), so callers can skip a
    redundant duplicate search rather than re-querying with the exact
    same string twice."""
    morph = _get_morph()
    if morph is None:
        return None
    words = text.split()
    if not words:
        return None
    normalized_words = []
    for word in words:
        try:
            parses = morph.parse(word)
        except Exception:
            parses = None
        normalized_words.append(parses[0].normal_form if parses else word)
    normalized = " ".join(normalized_words)
    if normalized.strip().lower() == text.strip().lower():
        return None
    return normalized
