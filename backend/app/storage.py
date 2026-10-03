"""Where uploaded avatars (routers/profile.py::upload_avatar) actually
live. See Settings.avatar_storage_backend's own docstring for the
choice between the two backends below; this module is just their
implementation.

Both backends implement the same tiny interface — `save(filename, body,
content_type) -> url` — so upload_avatar doesn't know or care which one
is active; it just calls `get_avatar_storage().save(...)` and stores
whatever URL comes back in users.avatar_url, exactly as it always has.

Local disk was always going to be a problem the moment this backend
stops being exactly one long-lived container with exactly one disk: two
API replicas behind a load balancer each have their *own* uploads/
directory, so a photo uploaded via the replica that happened to handle
the request is simply missing when a later request for that same
avatar_url happens to land on the other one — not a 404 with a clear
cause, just a broken image half the time, worse under more replicas.
A redeploy without a persistent volume mounted loses every avatar ever
uploaded outright, container filesystems being ephemeral by design.
Switching `avatar_storage_backend` to "s3" fixes both: the bucket is
the one shared place every replica reads and writes, and it outlives
any single container's lifecycle.
"""

from __future__ import annotations

import os
from abc import ABC, abstractmethod

from app.config import settings


class AvatarStorage(ABC):
    @abstractmethod
    def save(self, filename: str, body: bytes, content_type: str) -> str:
        """Writes `body` under `filename` and returns the URL to store
        in users.avatar_url — already the full path/URL the client can
        hand straight to Image.network, same contract either backend
        honors."""


class LocalDiskStorage(AvatarStorage):
    """Today's behavior, unchanged: plain files under this container's
    own bind-mounted uploads/ directory, served back out by main.py's
    `/static` StaticFiles mount. Fine for local dev and a single
    long-lived container — see this module's own docstring for where
    it stops being fine."""

    def __init__(self, upload_dir: str):
        self._upload_dir = upload_dir

    def save(self, filename: str, body: bytes, content_type: str) -> str:
        os.makedirs(self._upload_dir, exist_ok=True)
        with open(os.path.join(self._upload_dir, filename), "wb") as f:
            f.write(body)
        return f"/static/avatars/{filename}"


class S3Storage(AvatarStorage):
    """Any S3-compatible bucket — real AWS S3, or a compatible service
    (MinIO, Cloudflare R2, DigitalOcean Spaces, Backblaze B2's S3 API)
    via `s3_endpoint_url`. boto3 is only imported here, not at module
    load time, so a deployment that never sets
    `avatar_storage_backend=s3` never needs it installed."""

    def __init__(self, *, bucket: str, region: str, endpoint_url: str,
                 access_key_id: str, secret_access_key: str, public_base_url: str):
        import boto3  # local import — see class docstring

        if not bucket or not public_base_url:
            raise RuntimeError(
                "avatar_storage_backend=s3 needs S3_BUCKET and S3_PUBLIC_BASE_URL set"
            )
        self._bucket = bucket
        self._public_base_url = public_base_url.rstrip("/")
        self._client = boto3.client(
            "s3",
            region_name=region or None,
            endpoint_url=endpoint_url or None,
            aws_access_key_id=access_key_id or None,
            aws_secret_access_key=secret_access_key or None,
        )

    def save(self, filename: str, body: bytes, content_type: str) -> str:
        key = f"avatars/{filename}"
        self._client.put_object(
            Bucket=self._bucket,
            Key=key,
            Body=body,
            ContentType=content_type,
            # Avatars are meant to be shown to anyone who can see the
            # profile they're on (see privacy_watched et al. — none of
            # that privacy story is about the avatar image file itself),
            # so this is a public bucket/object by design, not a leak.
            ACL="public-read",
        )
        return f"{self._public_base_url}/{key}"


def get_avatar_storage() -> AvatarStorage:
    """One instance per call rather than a module-level singleton — this
    only ever runs on a file upload (nowhere near hot-path traffic), and
    it keeps this fully driven by whatever `settings` say right now,
    which matters for tests that override settings per-case."""
    backend = settings.avatar_storage_backend.strip().lower()
    if backend == "s3":
        return S3Storage(
            bucket=settings.s3_bucket,
            region=settings.s3_region,
            endpoint_url=settings.s3_endpoint_url,
            access_key_id=settings.s3_access_key_id,
            secret_access_key=settings.s3_secret_access_key,
            public_base_url=settings.s3_public_base_url,
        )
    if backend != "local":
        raise RuntimeError(
            f"Unknown avatar_storage_backend {backend!r} — expected 'local' or 's3'"
        )
    upload_dir = os.path.join(os.path.dirname(__file__), "..", "uploads", "avatars")
    return LocalDiskStorage(upload_dir)
