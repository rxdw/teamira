"""Shared fixtures for the whole backend test suite.

Real Postgres, not SQLite
-------------------------
Every test here runs against an actual local Postgres database. A few
things this app does are Postgres-specific — most notably
app/rate_limit.py's `INSERT ... ON CONFLICT DO UPDATE ... RETURNING`,
and the advisory locks in app/migrate.py — so a lighter SQLite substitute
would quietly exercise different code than what actually runs in
production. See tests/README.md for how to point this at your own local
Postgres instance; the short version is a throwaway role + database
matching the DATABASE_URL below.

Why the two `os.environ[...]` lines have to come first
--------------------------------------------------------
app/database.py builds its SQLAlchemy `engine` once, at import time,
from `app.config.settings.database_url` — not lazily per-request. That
means the environment has to already say "use the test database" before
*anything* imports app.config/app.database, including transitively
(app.main -> routers -> models -> ...). Pytest always imports each
directory's conftest.py before collecting the test modules in it, so
doing this here — before this file's own `from app...` imports below —
is what makes it safe for every test module in this package to just
`from app.main import app` normally without repeating any of this.

This deliberately does NOT read backend/.env (real, deployment-specific
secrets that a test run should never need). Plain environment variables
take precedence over a dotenv file for pydantic-settings either way, so
even if backend/.env also happens to be sitting next to wherever this
runs, these two values win regardless.
"""

from __future__ import annotations

import os
import shutil
import tempfile
import uuid
from unittest.mock import patch

os.environ["DATABASE_URL"] = (
    "postgresql+psycopg2://teamira_test:teamira_test@localhost:5432/teamira_test"
)
os.environ["JWT_SECRET"] = "test-secret-do-not-use-outside-tests"

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import event, text
from sqlalchemy.orm import sessionmaker

from app.database import Base, engine, get_db
from app.main import app
from app.migrate import run_migrations
from app.storage import LocalDiskStorage


@pytest.fixture(scope="session", autouse=True)
def _isolated_avatar_storage():
    """routers/profile.py::upload_avatar writes through
    app.storage.get_avatar_storage(), which — for the default "local"
    backend — always resolves to the real backend/uploads/avatars/
    directory relative to storage.py itself; nothing about it is
    test-aware. Without this, every run that exercises upload_avatar
    (tests/test_profile.py::TestUploadAvatar) leaves real files behind
    in that directory forever — there was nothing to clean up before
    those tests existed, since nothing exercised this endpoint at all
    (see that class's own docstring for why it's new).

    Patched on `app.routers.profile` specifically, not `app.storage`:
    profile.py does `from app.storage import get_avatar_storage`, which
    binds the name into its own module namespace at import time —
    patching app.storage's copy of the name wouldn't touch the
    reference profile.py already holds."""
    tmp_dir = tempfile.mkdtemp(prefix="teamira_test_avatars_")
    with patch("app.routers.profile.get_avatar_storage", lambda: LocalDiskStorage(tmp_dir)):
        yield
    shutil.rmtree(tmp_dir, ignore_errors=True)


@pytest.fixture(scope="session", autouse=True)
def _schema():
    """Builds the schema exactly the way app/main.py's own on_startup
    does — create_all() first, then the real Alembic chain on top of it
    (see that function's comment on why it's that order) — so the tests
    are exercising the actual migration path, not a hand-rolled stand-in
    for it. Session-scoped: this runs once, tables stick around for the
    whole run, and per-test isolation comes from `db_session` below
    rolling back its own transaction, not from recreating tables.

    Deliberately stops short of the *rest* of on_startup (affiliate
    provider seeding, the Teamira-shelves background task, ...) — this
    calls create_all()+run_migrations() directly instead of spinning up
    the app through TestClient's `with` form, so none of that other
    startup work runs here. Tests that come to depend on seeded data
    those steps normally produce should seed exactly what they need
    themselves rather than relying on this silently growing to match
    on_startup over time.
    """
    # The analytics reporting views (migration c9e4b7a21f58) depend on
    # analytics_events, and Postgres refuses to drop a table that a view
    # still reads — so on the second run against the same test database
    # drop_all() below would fail before a single test started. Views are
    # dropped first, and alembic_version with them: create_all() rebuilds
    # the tables but not the views, so the migration chain has to replay
    # (it's written to be re-runnable over an existing schema, which is
    # also exactly the path a fresh database takes) or the views would
    # silently be missing on every run after the first.
    with engine.begin() as conn:
        for (view,) in conn.execute(
            text("SELECT viewname FROM pg_views WHERE schemaname = current_schema() AND viewname LIKE 'v\\_analytics\\_%'")
        ).all():
            conn.execute(text(f'DROP VIEW IF EXISTS "{view}"'))
        conn.execute(text("DROP TABLE IF EXISTS alembic_version"))
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    run_migrations()
    yield


@pytest.fixture()
def db_session(_schema):
    """One Postgres connection + one outer transaction per test, rolled
    back at teardown no matter what happened in the test.

    Several routes (and app/rate_limit.py's check(), called from inside
    them) call `session.commit()` themselves mid-request. To let that
    keep working unmodified while still guaranteeing nothing survives
    past this fixture, the session here is bound to a SAVEPOINT
    (`begin_nested`) rather than the connection's real transaction; an
    `after_transaction_end` listener restarts a fresh SAVEPOINT every
    time app code's own commit() ends the current one. Only this
    fixture's `outer.rollback()` at teardown ever touches the real
    transaction, so none of it reaches the database for real — this is
    the standard SQLAlchemy "join a session into an external
    transaction" pattern for test suites.
    """
    connection = engine.connect()
    outer = connection.begin()

    TestingSessionLocal = sessionmaker(bind=connection, autoflush=False, autocommit=False)
    session = TestingSessionLocal()
    session.begin_nested()

    @event.listens_for(session, "after_transaction_end")
    def _restart_savepoint(sess, transaction):
        if transaction.nested and not transaction._parent.nested:
            sess.begin_nested()

    try:
        yield session
    finally:
        session.close()
        # A route that itself calls session.rollback() after catching a
        # real IntegrityError (see teamira.py::admin_add_item's duplicate-
        # item 409) can leave SQLAlchemy's own error recovery having
        # already ended this outer transaction by the time we get here —
        # rolling back an already-inactive Transaction is harmless but
        # logs a SAWarning, so check first. connection.close() below
        # rolls back anything still open regardless, so this is just
        # about keeping output clean, not a correctness gap either way.
        if outer.is_active:
            outer.rollback()
        connection.close()


@pytest.fixture()
def client(db_session):
    """TestClient wired to the real app, with its one DB dependency
    swapped for the transactional `db_session` above. Deliberately not
    used as `with TestClient(app) as c:` — that form runs the app's
    lifespan (startup/shutdown) events, and on_startup does more than
    this suite wants happening on every test (see `_schema`'s
    docstring); calling it directly still exercises real routing,
    validation, and auth, just without that extra side effect.
    """
    app.dependency_overrides[get_db] = lambda: db_session
    c = TestClient(app)
    yield c
    app.dependency_overrides.clear()


@pytest.fixture()
def register_user(client):
    """Registers a fresh account with a random username and returns a
    small helper object with everything a test usually needs next:
    `.id`, `.username`, `.token`, and `.headers` (a ready-to-use
    Authorization header dict). Call it multiple times in one test for
    distinct users — each call mints a new random username.
    """

    class _RegisteredUser:
        def __init__(self, id: str, username: str, token: str):
            self.id = id
            self.username = username
            self.token = token
            self.headers = {"Authorization": f"Bearer {token}"}

    def _make(username: str | None = None, password: str = "correct-horse-battery") -> "_RegisteredUser":
        username = username or f"u_{uuid.uuid4().hex[:12]}"
        resp = client.post(
            "/auth/register",
            json={"username": username, "password": password},
        )
        assert resp.status_code == 201, resp.text
        token = resp.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}
        me = client.get("/auth/me", headers=headers)
        assert me.status_code == 200, me.text
        return _RegisteredUser(id=me.json()["id"], username=username, token=token)

    return _make


@pytest.fixture()
def sample_media_item():
    """A minimal-but-valid MediaItem payload (see app/schemas.py) for
    tests that need to log a diary entry but don't care what the title
    actually is."""

    def _make(**overrides) -> dict:
        item = {
            "id": f"tt_{uuid.uuid4().hex[:8]}",
            "media_type": "movie",
            "external_ids": {"tmdb": "603"},
            "title": {"en": "Test Movie", "ru": "Тестовый фильм"},
            "description": {"en": "A movie used only by the test suite."},
            "source": "tmdb",
        }
        item.update(overrides)
        return item

    return _make
