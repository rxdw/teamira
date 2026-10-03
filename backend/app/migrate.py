"""Runs this app's Alembic migrations (see migrations/) once at startup,
replacing the old `_run_startup_migrations()` that lived in main.py and
re-ran a hand-maintained list of raw `ALTER TABLE ... ADD COLUMN IF NOT
EXISTS` statements on every single process boot. That approach (see the
old comment on it, preserved in git history and in migrations/versions/
6cea28b2d137's own docstring) had three real problems this fixes:

1. No rollback. Alembic revisions can define `downgrade()` — the ones
   written from here on do (the frozen-history baseline revision is the
   one exception, and says why in its own docstring).
2. No versioning/history. `ALTER TABLE ... IF NOT EXISTS` on every boot
   meant there was no record of what had actually been applied to a
   given database short of reading main.py's source and reasoning about
   it by hand. Alembic's own `alembic_version` table now records exactly
   which revision a database is on.
3. Concurrent replicas racing the same DDL. A zero-downtime deploy
   naturally starts several replicas' `on_startup` at close to the same
   moment — with the old code, that meant several processes running the
   *exact same* `ALTER TABLE`/`ALTER TYPE ... ADD VALUE` statements
   concurrently, which the old comment on `_run_startup_migrations`
   already flagged as a real race (`ALTER TYPE ... ADD VALUE` in
   particular can't run concurrently within a transaction, which is why
   it needed its own AUTOCOMMIT connection even before this — that
   sidesteps the transaction problem, not the multi-process race).
   `run_migrations()` below wraps the whole `alembic upgrade head` call
   in a Postgres advisory lock, so only one replica actually runs it at
   a time; the others block until it's done, then find there's nothing
   left for them to do (Alembic checks the current revision before
   acting) and start up normally.

`startup_lock()` below is the same fencing pattern, generalized —
main.py's on_startup also uses it around its own one-time seed/
consolidate work (see that function), which needed the exact same
protection the moment more than one worker process became possible
(see Dockerfile's UVICORN_WORKERS): seed_affiliate_providers' own
get-or-create loop isn't atomic across processes, so two workers
booting at once could both decide a row was missing and both try to
insert it, one of them hitting a primary-key error.
"""

from __future__ import annotations

import logging
import os
from contextlib import contextmanager

from alembic import command
from alembic.config import Config
from sqlalchemy import text

from app.database import engine

logger = logging.getLogger("uvicorn.error")

# Arbitrary, fixed for the lifetime of this app — Postgres advisory
# locks are just a namespace of bigints two connections either agree on
# or don't; this one means "this app is running its Alembic migrations"
# and nothing else needs to agree on it.
_MIGRATION_ADVISORY_LOCK_KEY = 8_234_015_579_112_233

_ALEMBIC_INI = os.path.join(os.path.dirname(__file__), "..", "alembic.ini")


@contextmanager
def startup_lock(key: int):
    """Fences a one-time-at-boot block of work so only one worker
    process/replica actually runs it when several start at close to the
    same moment — everyone else blocks here until the winner finishes,
    then moves on past an already-done `with` block instead of redoing
    the work (or racing it). A no-op (no fencing at all) outside
    Postgres, same as `run_migrations` below — no concurrent replicas to
    race against there either. `key` just needs to be a distinct bigint
    per distinct piece of startup work; see `_MIGRATION_ADVISORY_LOCK_KEY`
    for this module's own."""
    if engine.dialect.name != "postgresql":
        yield
        return
    with engine.connect() as conn:
        conn.execute(text("SELECT pg_advisory_lock(:key)"), {"key": key})
        try:
            yield
        finally:
            conn.execute(text("SELECT pg_advisory_unlock(:key)"), {"key": key})


def run_migrations() -> None:
    alembic_cfg = Config(_ALEMBIC_INI)
    # migrations/env.py reads app.config.settings.database_url itself
    # and overrides whatever's in alembic.ini with it — this line is
    # belt-and-suspenders for anything that inspects alembic_cfg's
    # sqlalchemy.url directly before env.py gets a chance to run.
    alembic_cfg.set_main_option("sqlalchemy.url", str(engine.url))

    with startup_lock(_MIGRATION_ADVISORY_LOCK_KEY):
        logger.info("running database migrations…")
        command.upgrade(alembic_cfg, "head")
        logger.info("database migrations up to date")
