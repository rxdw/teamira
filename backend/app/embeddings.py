"""Local, self-hosted semantic embeddings for Ask Teamira's free-text
matching (see app/routers/ai.py) — deliberately NOT a call to any third-
party AI API (no OpenAI/Anthropic/etc). Everything here runs inside this
same backend container via `fastembed`, which wraps a quantized ONNX
model executed through onnxruntime — CPU only, no torch, no GPU
required. A short text embeds in low tens of milliseconds on an
ordinary server core, so this is cheap enough to run per-request.

Model: intfloat/multilingual-e5-small — picked for three reasons:
- Covers both of this app's query languages (RU + EN) in one model,
  rather than needing separate EN/RU models.
- Quantized ONNX build is ~120MB on disk — small enough that "don't want
  to load the server down, no beefy GPU" is a non-issue.
- e5-small still holds up reasonably on semantic-similarity benchmarks
  for its size; bigger multilingual e5 variants exist if this project's
  usage ever justifies the extra RAM/latency, see fastembed's docs.

Network note: the model weights are pulled from Hugging Face the first
time this process needs them (baked into the Docker image at build time
by backend/Dockerfile below, so a normal `docker compose up` never hits
the network for this at runtime) and cached on disk from then on — no
per-request network call, no data about the user's query ever leaves
this container.

Failure handling: if fastembed isn't installed, or the model can't load
for any reason (offline first-run with no image cache, out of disk,
etc.), every function here degrades to "no semantic signal" rather than
raising — Ask Teamira's rule-based scoring (genres/year/text overlap/
TMDB similar-titles) already works standalone and stays fully
functional; semantic matching is a bonus signal layered on top of it,
never a hard dependency.
"""

from __future__ import annotations

import logging
import math
import time
from typing import List, Optional, Sequence

logger = logging.getLogger(__name__)

_MODEL_NAME = "intfloat/multilingual-e5-small"

_model = None
_last_load_attempt: Optional[float] = None
# If the very first load fails (most commonly: the Dockerfile's build-time
# pre-download — see backend/Dockerfile — had no network access either,
# so nothing ever got baked into the image, AND this container's own
# runtime egress doesn't reach huggingface.co), a permanent "tried once,
# giving up forever" flag would mean semantic matching stays off for this
# process's entire lifetime even after whatever blocked the network gets
# fixed — the container would need a full restart to notice. Retrying
# every 10 minutes instead means a fixed DNS entry, firewall rule, or
# restored network reachability gets picked up on its own, without
# anyone having to know to bounce the service.
_RETRY_COOLDOWN_SECONDS = 600


def _get_model():
    """Lazy singleton — the model is loaded at most once per process,
    on the first request that actually needs it, not at import time
    (so a deployment without fastembed installed, or one that never
    calls Ask Teamira, never pays the load cost at all)."""
    global _model, _last_load_attempt
    if _model is not None:
        return _model
    now = time.monotonic()
    if _last_load_attempt is not None and now - _last_load_attempt < _RETRY_COOLDOWN_SECONDS:
        return None
    _last_load_attempt = now
    try:
        from fastembed import TextEmbedding
    except Exception:
        logger.error(
            "ASK TEAMIRA SEMANTIC MATCHING IS DISABLED: fastembed is not installed. "
            "Ask Teamira is still answering queries, but on rule-based genre/year/text "
            "matching alone — see app/routers/ai.py's module docstring for what that "
            "loses. `pip install -r requirements.txt` should include it; if this keeps "
            "showing up, check the image actually built with the current requirements.txt."
        )
        return None
    # intfloat/multilingual-e5-small has never actually been one of
    # fastembed's built-in models — plain `TextEmbedding(model_name=...)`
    # raises `ValueError: Model ... is not supported in TextEmbedding`
    # for it every time, unconditionally, regardless of network access
    # (that error is what was actually showing up here, not a download
    # failure — see the exc_info logged just below when this was still
    # missing). fastembed's own README covers exactly this: register the
    # model's config explicitly via `add_custom_model` first, then
    # construct it normally.
    #
    # Logged, not swallowed, when this fails: a *second* call in another
    # worker process raising "already registered" is the one genuinely
    # harmless case, but silently passing on ANY exception here — a
    # missing `fastembed.common.model_description` because an old
    # fastembed is still what's actually installed, a signature mismatch
    # against this fastembed version's own add_custom_model, etc. — was
    # exactly what made the *real* reason invisible last time: the
    # ValueError below only ever restates "not supported", regardless of
    # why registration didn't take, so whatever actually went wrong here
    # has to be visible on its own.
    try:
        from fastembed.common.model_description import ModelSource, PoolingType
        TextEmbedding.add_custom_model(
            model=_MODEL_NAME,
            pooling=PoolingType.MEAN,
            normalization=True,
            sources=ModelSource(hf=_MODEL_NAME),
            dim=384,
            model_file="onnx/model.onnx",
        )
    except Exception as exc:
        if "already" not in str(exc).lower() and "duplicate" not in str(exc).lower():
            logger.error(
                "embeddings: add_custom_model(%s) failed — %s: %s. If this is "
                "ModuleNotFoundError/ImportError for fastembed.common.model_description, "
                "the installed fastembed is still older than the 0.6.1 pinned in "
                "requirements.txt (rebuild the image WITHOUT layer cache — `docker "
                "compose build --no-cache` or equivalent — a plain restart reuses "
                "whatever was already pip-installed). Any other exception type here is "
                "this fastembed version's add_custom_model rejecting these exact "
                "arguments (pooling/normalization/sources/dim/model_file) — check that "
                "signature against the version actually installed.",
                _MODEL_NAME, type(exc).__name__, exc,
            )
    try:
        _model = TextEmbedding(model_name=_MODEL_NAME)
    except Exception:
        logger.error(
            "ASK TEAMIRA SEMANTIC MATCHING IS DISABLED: failed to load %s. Ask Teamira "
            "is still answering queries, but on rule-based genre/year/text matching "
            "alone. Unlike the previous failure mode here, this one really is either a "
            "network problem (neither the Docker build nor this running container can "
            "reach huggingface.co — the build step in backend/Dockerfile continues past "
            "a failed pre-download, echoing a warning to the build log instead of "
            "silently succeeding, so check there first) or something wrong with the "
            "`add_custom_model` registration just above (e.g. this fastembed version is "
            "old enough not to have `fastembed.common.model_description` at all — check "
            "the installed version against requirements.txt). This retry (every %ds) "
            "will keep failing the same way until whichever of those is fixed. Will keep "
            "retrying in the background — no restart needed once it's reachable.",
            _MODEL_NAME, _RETRY_COOLDOWN_SECONDS, exc_info=True,
        )
        return None
    return _model


def available() -> bool:
    return _get_model() is not None


# e5 models were trained with an explicit "query: " / "passage: " prefix
# baked into every input — asymmetric by design (a search query and the
# thing it's matched against aren't the same kind of text), and skipping
# this measurably hurts retrieval quality on this model family. Not a
# formatting nicety — part of how the model was trained.

def embed_query(text: str) -> Optional[List[float]]:
    return _embed_one(f"query: {text}")


def embed_passage(text: str) -> Optional[List[float]]:
    return _embed_one(f"passage: {text}")


def embed_passages(texts: Sequence[str]) -> List[Optional[List[float]]]:
    """Batched form of embed_passage — one model call per chunk of texts,
    used when scoring a whole pool of candidate titles at once rather
    than one at a time.

    Chunked rather than handed to the model in one single `embed()` call:
    ONNX Runtime allocates roughly proportional to batch size, and
    app/routers/ai.py's broad-pool fallback (a pure mood/vibe query with
    no genre/reference to narrow it down) can hand this several hundred
    titles at once on a cold cache — e.g. right after the 24h feed pool
    refreshes. One request encoding that many texts in a single batch is
    exactly the kind of memory spike that can tip over a container with
    a real memory limit (see the "Cannot allocate memory" crash this was
    written in response to). Sequential fixed-size chunks bound the peak
    regardless of how large the pool grows, at the cost of a few extra
    (still local, still cheap) model calls instead of one big one.
    """
    if not texts:
        return []
    model = _get_model()
    if model is None:
        return [None] * len(texts)
    _CHUNK_SIZE = 32
    vectors: List[Optional[List[float]]] = []
    for start in range(0, len(texts), _CHUNK_SIZE):
        chunk = texts[start:start + _CHUNK_SIZE]
        try:
            chunk_vectors = list(model.embed([f"passage: {t}" for t in chunk]))
            vectors.extend([float(x) for x in v] for v in chunk_vectors)
        except Exception:
            logger.warning("embeddings: batch encode failed for chunk at offset %d", start, exc_info=True)
            vectors.extend([None] * len(chunk))
    return vectors


def _embed_one(text: str) -> Optional[List[float]]:
    model = _get_model()
    if model is None:
        return None
    try:
        vector = next(model.embed([text]))
    except Exception:
        logger.warning("embeddings: encode failed", exc_info=True)
        return None
    return [float(x) for x in vector]


def cosine(a: Sequence[float], b: Sequence[float]) -> float:
    if not a or not b:
        return 0.0
    dot = sum(x * y for x, y in zip(a, b))
    norm_a = math.sqrt(sum(x * x for x in a))
    norm_b = math.sqrt(sum(y * y for y in b))
    if norm_a == 0.0 or norm_b == 0.0:
        return 0.0
    return dot / (norm_a * norm_b)
