# Backend tests

Runs against a **real local Postgres**, not SQLite — a few things this
app does (`app/rate_limit.py`'s `INSERT ... ON CONFLICT DO UPDATE ...
RETURNING`, the advisory locks in `app/migrate.py`) are Postgres-specific,
so a lighter substitute would quietly test different behavior than what
actually runs in production.

## One-time setup

You need a Postgres server running locally (the same `postgres:16-alpine`
version `docker-compose.yml` already uses is the safest match, but any
recent Postgres works). Create a throwaway role + database for tests —
these credentials are hardcoded in `tests/conftest.py` on purpose, so
this test database is never mistaken for a real one:

```bash
sudo -u postgres psql -c "CREATE USER teamira_test WITH PASSWORD 'teamira_test' SUPERUSER;"
sudo -u postgres psql -c "CREATE DATABASE teamira_test OWNER teamira_test;"
```

(Already running Postgres via `docker-compose.yml` instead? Run those
same two lines with `docker compose exec db psql -U seenly -d seenly -c "..."`
instead of `sudo -u postgres psql`.)

Then install the test dependencies (on top of the app's own
`requirements.txt`):

```bash
cd backend
pip install -r requirements-dev.txt
```

## Running

```bash
cd backend
python -m pytest tests/ -v
```

Use `python -m pytest`, not a bare `pytest`, unless `backend/` is
already importable some other way (e.g. installed with `pip install
-e .`) — `python -m` is what puts `backend/` on `sys.path` so `from app
import ...` resolves inside the test files.

With coverage:

```bash
python -m pytest tests/ --cov=app --cov-report=term-missing
```

## How isolation works

Every test gets the real FastAPI app wired up through `TestClient`, but
the one `Depends(get_db)` every route uses is swapped for a session
bound to a single Postgres connection + transaction that's always rolled
back at the end of the test (`db_session` in `conftest.py`) — including
anything route code itself committed along the way (several routes,
and `RateLimiter.check()`, call `session.commit()` mid-request; see
`db_session`'s docstring for how a SAVEPOINT is restarted under each of
those so the outer rollback still undoes everything).

Practically: tests can freely register users, log diary entries, trip
rate limits, etc. without any manual cleanup, and without one test's
data ever being visible to another — `test_isolation_sanity.py` exists
specifically to prove that rollback is actually happening rather than
just assuming the pattern works.

Schema setup (`Base.metadata.create_all()` then the real `alembic
upgrade head`, via `app.migrate.run_migrations()`) happens once per test
*session*, not per test — mirroring `app/main.py`'s own `on_startup`
exactly for those two calls, but deliberately stopping there rather than
also running the rest of `on_startup` (affiliate-provider seeding, the
Teamira-shelves background task). A test that ends up needing data one
of those normally seeds should seed exactly what it needs itself rather
than this fixture silently growing to replicate all of `on_startup`.

## What's covered so far

- `test_security.py` — password hashing (`hash_password`/`verify_password`)
  and JWT handling (`create_access_token`/`decode_access_token`) in
  isolation: round-trips, tampered/expired/wrong-algorithm tokens, the
  72-byte bcrypt limit.
- `test_auth.py` — `/auth/register`, `/auth/login`, `/auth/me` through
  real HTTP: validation errors, duplicate usernames, wrong-password
  handling, and that both limiters `routers/auth.py` wires up
  (5/minute register, 10/minute login) actually 429 once tripped.
- `test_rate_limit.py` — `RateLimiter` itself, more precisely than is
  practical through HTTP alone: independent buckets per key and per
  limiter name, and that a new time window really does reset the count.
- `test_diary_ownership.py` — the thing worth being most paranoid about:
  that one user genuinely cannot read, edit, or delete another user's
  diary entry by id, not just that the UI doesn't expose a way to try.
- `test_friends.py` — the friend request lifecycle (send/accept/
  decline/cancel/remove, can't friend yourself or double-request,
  strangers can't act on a request that isn't theirs), search, and —
  the part worth being paranoid about here — that a profile's
  everyone/friends/nobody shelf privacy actually gates who sees it
  depending on the viewer, not just cosmetic.
- `test_partner.py` — both ways into a co-viewing circle (a /pair code
  and a direct /invite), that a stranger can't accept or decline
  someone else's invite, and that unlinking is symmetric for both
  sides. Only the pairing/invite lifecycle — the co-viewing
  suggest/plan/bulk-add endpoints past that are untested.
- `test_profile.py` — `GET`/`PATCH /profile/me` (identity fields,
  privacy-level validation), favoriting a title, and that the
  watch-later/watching/watched shelves reflect what's actually been
  logged and don't leak between accounts. `profile.py` is a big router
  (avatar upload, stats, wrapped, achievements, level) — most of it is
  still untested.
- `test_teamira_admin.py` — the admin-only curated-collections CRUD in
  `routers/teamira.py` (create/rename/delete a shelf, add/remove an
  item), gated on `User.is_admin` rather than a bearer token alone —
  proves that gate holds (403 for a normal account, 401 with no token
  at all) and, via a pre-warmed cache row, exercises adding an item
  without a live TMDB call. `GET /feed/teamira`/`/feed/today-pick` and
  the franchise half of that module are untested.
- `test_feed_react.py` — `POST /feed/react`, the one endpoint in
  `feed.py` that's local-DB-only; `like`/`watched`/`skip` land on the
  right shelf (or none). The rest of `feed.py` (`/feed`, `/movies`,
  `/for-you`, `/collections`) pulls live from TMDB/IGDB/Google
  Books/Shikimori and isn't covered.
- `test_media_detail.py` — `GET /media/detail`, "the single most-visited
  screen after Home" per its own docstring, also served from a
  pre-warmed cache row rather than a live adapter call. `/media/search`,
  `/media/episodes`, `/media/person`, and a genuinely cold `/media/detail`
  miss all still need a real adapter and aren't covered.
- `test_isolation_sanity.py` — not app behavior, a check on the test
  suite's own isolation (see above).
- `test_sincerity.py` — the sincerity-points ledger (app/sincerity.py):
  every earn_*/spend_* function's edge cases (staleness thresholds,
  the revised-rating cooldown, a stake hit vs a miss) tested directly
  against the ledger, plus the two HTTP endpoints
  (`GET /sincerity/me`, `PATCH /sincerity/privacy`) and the one router
  that actually triggers an award today (`POST /watchlist/drop`).
  `spend_spoiler_unlock`/`spend_debt_settlement` and the recommendation-
  stake functions have direct unit coverage but no router calls them
  yet — see routers/sincerity.py's own module docstring.
- `test_challenges.py` — app/challenges.py's `evaluate()` (called with a
  fixed date, the same way test_rate_limit.py fixes time.time(), rather
  than depending on whatever week it happens to be) for both cadences:
  progress computation, hitting the target, and that a completion
  timestamp survives the diary entries that earned it being deleted
  afterwards. Plus the three HTTP endpoints
  (`GET /challenges`, claim, seen) — claim/seen can't take an injected
  date, so those tests ask the real catalog what's live *today* and
  seed a ChallengeProgress row directly rather than depending on real-
  time date math.
- `test_shared_diary.py` — the "наш дневник" shared view
  (routers/shared_diary.py): whether a solo evening lands in it at all
  (`auto_share_logs` vs `watched_with_partner`), that each person's
  rating/note visibility follows *their own* prefs regardless of who's
  looking, that two people logging the same title collapse into one
  card with a computed rating_gap, and that unsharing a together-
  watched evening is refused. `shared_planned`/`shared_stats` are only
  covered by the unlinked-account 409 gating check, not their actual
  content.

That's real coverage on the highest-stakes modules (auth, tokens, rate
limiting, cross-user data access, privacy settings, admin gating, the
new sincerity ledger, challenge completion, shared-diary privacy) plus
two ways of testing an adapter-backed endpoint without a live call —
`ai.py` (including the new time-budget parsing), `co_view_vote.py`,
`referrals.py`, `imports.py`, `integrations.py`, `together.py`, most of
`profile.py` (avatar upload, stats, wrapped, achievements, level), and
the live-adapter paths of `feed.py`/`media.py`/`teamira.py` are still
untested. Same shape of test (register one or two users via the
`register_user` fixture, hit the router's endpoints, assert on status
codes/ownership — or, for an adapter-backed GET, seed
`app.cache.set_static_title` first the way `test_teamira_admin.py`/
`test_media_detail.py` do, or call the underlying pure function directly
with an explicit date/time the way `test_sincerity.py`/`test_challenges.py`
do) extends to any of them; there's just a lot of surface area left.
