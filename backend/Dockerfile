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

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
