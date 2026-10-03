# Audit follow-up (P1 items 4–7)

Implements 4 of the 5 P1 items from the audit review: the ENVIRONMENT
production guard, the python-jose upgrade, docker-compose.prod.yml, and
CI. Item 8 (dedicated tests for moderation.py/premium.py/lists.py/
progress.py/activity.py/co_view_poll.py/image_proxy.py) was explicitly
deferred — no test-writing happened for that item.

Every change below was verified against the real test suite in a local
sandbox (Postgres 16, the same version docker-compose.yml uses) before
being called done — not just written and assumed correct.

## 4. ENVIRONMENT=production fail-fast guard

- `app/config.py` — new `environment: str = "development"` setting.
  Defaults to "development" on purpose: nothing about the zero-config
  local-dev experience the rest of this file's defaults are built
  around changes unless a deployment opts in explicitly.
- `app/main.py` — the jwt_secret/email_backend insecure-default checks
  that used to only `logger.critical(...)` are now factored into two
  small functions:
  - `_insecure_defaults(settings_obj) -> list[str]` — pure, returns a
    problem string per insecure default found. No I/O.
  - `_enforce_startup_security(settings_obj)` — logs each problem at
    critical (same as before), and additionally **raises RuntimeError**
    if `settings_obj.environment == "production"` and any problems were
    found. `on_startup()` now just calls this as its first line.
  - Kept separate from `on_startup`'s create_all()/run_migrations()/
    seeding+purge block on purpose, so the guard is testable (and, in
    production, fails) *before* any of that runs — not after a possibly
    slow migration/seed pass.
- `backend/.env.example` — documents the new `ENVIRONMENT` var at the
  top of the file.
- `backend/tests/test_startup_guard.py` (new) — 9 tests: `_insecure_defaults`
  in isolation (both problems, either alone, case/whitespace tolerance
  on EMAIL_BACKEND), then `_enforce_startup_security` against the real
  `settings` object via monkeypatch — production+insecure raises with
  the right detail in the message, development+insecure does not raise,
  production+real-secrets does not raise.

**Nothing changes for local dev** — `ENVIRONMENT` isn't set anywhere in
`docker-compose.yml` (dev), so it stays at the "development" default and
behavior is identical to before this change. Only `docker-compose.prod.yml`
(below) sets `ENVIRONMENT=production`.

## 5. python-jose 3.3.0 → 3.5.0

- `backend/requirements.txt` — version bump only, no code changes.
  3.3.0 is affected by CVE-2024-33663 (algorithm confusion with
  ECDSA/OpenSSH-format keys); this app's own JWT usage is pure
  symmetric HS256 with an explicit `algorithms=[...]` allow-list and no
  asymmetric keys anywhere in that flow, so it's very unlikely to have
  been exploitable here specifically — but pinning a version with a
  public CVE is still what trips Dependabot/Snyk/`pip-audit` the moment
  any of those are wired up, for zero functional benefit over the fix.
  Full suite re-run after the bump: unchanged pass count plus the 9 new
  tests, nothing jose-related broke.

## 6. docker-compose.prod.yml

- New file at repo root, alongside the existing (now implicitly
  "dev") `docker-compose.yml`. Differences are documented inline in
  the file itself; short version: no code volume mount, no `--reload`,
  Postgres not published to the host, API bound to `127.0.0.1:8000`
  (assumes a reverse proxy in front), Postgres credentials required via
  `${VAR:?...}` (compose refuses to run at all if unset — no silent
  fallback to the seenly/seenly dev default), `ENVIRONMENT=production`
  set explicitly so item 4's guard is actually active.
- `.env.prod.example` (new) — template for the root-level `.env` this
  compose file reads for its `${POSTGRES_USER}`/`${POSTGRES_PASSWORD}`/
  `${POSTGRES_DB}` substitution. Deliberately separate from
  `backend/.env`, which still carries everything else (JWT_SECRET,
  third-party API keys, SMTP_*) exactly as before.
- `.gitignore` — added `!.env.prod.example` next to the existing
  `!.env.example`/`!backend/.env.example` negations; without it the
  new example file would have been silently caught by the blanket
  `.env.*` ignore rule and never committed. Verified with
  `git check-ignore` both ways (the example file is *not* ignored, a
  real `.env`-shaped file still is).

## 7. CI (GitHub Actions)

- `.github/workflows/backend-tests.yml` (new) — real `postgres:16-alpine`
  service container (matches `tests/README.md`'s own reasoning for why
  SQLite isn't a safe substitute here), installs
  `requirements.txt`+`requirements-dev.txt`, runs
  `python -m pytest tests/ -v`. Path-filtered to `backend/**` so a
  mobile-only PR doesn't trigger it.
- `.github/workflows/mobile-tests.yml` (new) — `flutter pub get`,
  `flutter analyze`, `flutter test`. Path-filtered to `mobile/**`.
  Uses the `stable` channel (matches this project's own
  `.metadata`/`pubspec.yaml` — no Flutter version is pinned locally
  either, so this isn't a new inconsistency, just an existing one
  inherited by CI too; worth revisiting if CI ever breaks on a stable
  bump before the code does).
- `mobile/test/widget_test.dart` **deleted**. This was still the
  default `flutter create` counter-app smoke test
  (`import 'package:teamira/main.dart'; ... MyApp() ...`) — `MyApp`
  hasn't existed since `main.dart` was rebuilt around `_runApp()` /
  `app.dart`'s `SeenlyApp`, so this file no longer compiled and would
  have failed `flutter analyze`/`flutter test` immediately, on an
  unrelated 15-year-old leftover, regardless of anything else in the
  suite. Removed rather than fixed, per this session's "no new tests
  yet" instruction — replacing it with a real smoke test against
  `SeenlyApp` is exactly the kind of thing item 8's mobile-side
  equivalent should pick up later.

## Explicitly not done this session

**Item 8** (dedicated backend tests for `moderation.py`, `premium.py`,
`lists.py`, `progress.py`, `activity.py`, `co_view_poll.py`,
`image_proxy.py`) — deferred by request. `backend-tests.yml` above will
run whatever exists for these today (i.e. nothing dedicated, per the
original audit) the moment it's added later; no further CI wiring
should be needed when that happens.
