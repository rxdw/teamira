FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends gcc libpq-dev && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Pre-download the local embedding model (app/embeddings.py) into the
# image at build time, so a running container never needs network access
# to Hugging Face for this — it's already on disk the first time Ask
# Teamira asks for it. If this step fails (e.g. building with no network
# at all), the build still continues and the app still runs — but Ask
# Teamira falls back to rule-based-only matching (no semantic layer)
# until this succeeds, either on a later rebuild or via this same
# retry-with-cooldown logic at runtime (see embeddings.py). The `echo`
# makes that failure something a person actually sees in the build log,
# rather than a silently-swallowed `|| true` that looks identical to a
# healthy build.
#
# The `add_custom_model` call mirrors app/embeddings.py::_get_model
# exactly — intfloat/multilingual-e5-small has never been one of
# fastembed's own built-in models, so a bare `TextEmbedding(model_name=
# 'intfloat/multilingual-e5-small')` here raises `ValueError: Model ...
# is not supported` unconditionally, even with perfect network access.
# If both this and _get_model's copy of this ever drift, that ValueError
# is what comes back, not a download failure — see embeddings.py's own
# comment on this for the full explanation.
RUN python -c "\
from fastembed import TextEmbedding; \
from fastembed.common.model_description import ModelSource, PoolingType; \
TextEmbedding.add_custom_model(model='intfloat/multilingual-e5-small', pooling=PoolingType.MEAN, normalization=True, sources=ModelSource(hf='intfloat/multilingual-e5-small'), dim=384, model_file='onnx/model.onnx'); \
TextEmbedding(model_name='intfloat/multilingual-e5-small')" \
    && echo "embeddings: model pre-downloaded OK" \
    || echo "WARNING: embeddings model pre-download FAILED (no network during build?) — Ask Teamira will run without semantic matching until this succeeds"

COPY . .

ENV PYTHONUNBUFFERED=1

EXPOSE 8000

# UVICORN_WORKERS defaults to 1 — today's exact behavior, unchanged.
# Bump it (e.g. UVICORN_WORKERS=4 in docker-compose.yml/.env) to run
# several worker processes instead of one. That matters specifically
# for POST /ai/ask: its embedding inference (app/embeddings.py, backing
# Ask Teamira's semantic-search layer) is CPU-bound model inference —
# already off the event loop via asyncio.to_thread (see routers/ai.py),
# so it doesn't block other requests *within* a process, but a single
# process is still bounded by that process's own CPU allocation.
# Splitting across worker processes is what actually adds more CPU to
# throw at it, at the cost of each worker loading its own separate copy
# of the embedding model into memory (see this file's own model-
# preload step above) — plan container memory accordingly before
# raising this. This was NOT safe to turn on until recently: the old
# in-process rate limiter/cache lock (see app/rate_limit.py,
# app/cache.py) and the old raw-SQL startup migrations (see
# app/migrate.py) all assumed exactly one process: See:
# - app/migrate.py + main.py's on_startup, `startup_lock` : Alembic
#   migrations and the one-time seed/consolidate work only ever run once,
#   even when several workers boot at the same moment.
# - app/rate_limit.py, app/cache.py: rate limits and the cache-refresh
#   lock are Postgres-backed now, so they mean the same thing regardless
#   of which worker process a given request lands on.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers ${UVICORN_WORKERS:-1}"]
