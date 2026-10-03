# Product analytics

The app had no analytics: no events, no screen views, nothing that could
say which of the ~80 screen classes anyone opens. Sentry existed on the
backend only, and reports errors, not behaviour. This change adds
first-party analytics end to end and a way to read it.

How to read it (the question this was written to answer) is in
[`docs/analytics.md`](docs/analytics.md). What is collected, for the
privacy policy and the store forms, is in
[`docs/privacy_data_inventory.md`](docs/privacy_data_inventory.md).

**Why first-party rather than Firebase / PostHog / AppMetrica:** the data
stays in the Postgres the app already runs on (the simplest answer to
"where does it live" under 152-FZ / GDPR); there is no third-party SDK to
keep compiling across Flutter upgrades and no new pub dependency; and the
mobile side talks to exactly one class, so swapping a vendor in later is a
change to `lib/analytics/analytics.dart`, not to 80 screens.

---

## Backend

- **`analytics_events` table** (`models.AnalyticsEvent`, migration
  `c9e4b7a21f58`). Deliberately *not* a foreign key to `users`: it takes a
  lot of inserts and is meant to be disposable. Erasure is explicit
  instead (below). `props` is JSONB on Postgres.
- **`POST /analytics/events`** (`routers/analytics.py`). Batch of up to 100.
  - Auth is *optional* and never produces a 401: a valid access token for a
    live account attaches `user_id`; anything else is "anonymous". A
    statistics call must not be able to sign someone out or start a
    refresh, and the login/onboarding screens have no token to send.
  - `user_id` is taken from the token only, never from the body.
  - Forgiving per event, strict per envelope: a malformed event is dropped
    and counted in `rejected`; a malformed envelope is a 422.
  - Idempotent: `event_id` is unique and inserts use `ON CONFLICT DO
    NOTHING`, so a batch the phone retried after a timeout doesn't count
    twice.
  - Props are enforced flat and small on the server (scalars only, strings
    cut to 120 chars, e-mail-looking strings dropped, max 20 keys). "We
    never send note text" is a claim the server can check, so it does.
  - Timestamps: future clocks clamped to now, events older than 14 days
    rejected.
  - Rate limits (`rate_limit.py`): 20 batches/minute per install and
    300/minute per IP (loose: carrier NAT puts many people behind one IP).
- **Erasure.** `account_deletion.purge_user` deletes every event carrying
  the account's `user_id` *and* every event from any device that account
  signed in on, so the pre-login events (onboarding, the login screen)
  don't survive as an orphaned trail.
- **Retention.** `ANALYTICS_RETENTION_DAYS` (default 400, `0` = keep
  forever), applied by `sweep_expired_artifacts`. `ANALYTICS_ENABLED=false`
  turns the endpoint into accept-and-discard (still 202, so installed apps
  don't start retrying).
- **Three reporting views** (`v_analytics_screen_views`,
  `v_analytics_daily_active`, `v_analytics_events_daily`), Postgres only, for
  Metabase / psql. `v_analytics_screen_views` derives "seconds on screen"
  as time until the next screen change or backgrounding, capped at 10
  minutes.
- **`scripts/analytics_report.py`**: plain-text report (active devices,
  ranked screens with time on screen, screens **never opened**, sheets,
  actions, onboarding funnel, activation funnel, day-1/day-7 retention,
  version/platform mix). Run with
  `docker compose exec api python -m scripts.analytics_report`.
- **`app/analytics_screens.json`**: the list of screens that *exist*
  (80), generated from the Flutter sources by
  `mobile/tools/analytics/list_screens.py` (`--check` verifies it's
  current). Analytics only sees screens that were opened; this is what
  lets the report say which ones weren't.
- **`docker-compose.yml`**: optional `metabase` service behind the
  `analytics` profile, bound to `127.0.0.1` only.
- **`tests/conftest.py`**: the schema fixture now drops the analytics
  views and `alembic_version` before `drop_all`. Postgres won't drop a
  table a view still reads, so the second run against the same test
  database failed before any test started; and because `create_all`
  rebuilds tables but not views, the migration chain has to replay on
  every session or the views would be missing on every run after the
  first. (The chain is written to be re-runnable, which is also the path a
  fresh database takes.)

## Mobile

- **`lib/analytics/analytics.dart`** — the single entry point,
  `Analytics.instance.track(name, props)`. Never throws, never blocks.
  Batched (15 s / 25 events / on background), queue persisted on background
  and capped, retry with back-off (429/5xx/offline retry; other 4xx drop),
  30-minute sessions, per-install random `anon_id`, debug/profile/release
  flag so your own debug runs can be filtered out of real numbers.
- **`AnalyticsRouteObserver`** names screens automatically. Navigation in
  this app is anonymous (`MaterialPageRoute(builder: ...)` at ~380 call
  sites), so instead of editing each one the observer waits a frame and
  finds the first widget class ending in `Screen`/`Sheet` just under the
  route's content (`RouteSettings(name:)` wins if present). Flutter's own
  `BottomSheet` wrappers are excluded by name.
- **Not routes, announced explicitly:** the four tabs (`RootShell`), the
  Home/together switch (`HomeModeShell`), and the auth-gate steps —
  login, EULA, onboarding, greeting splash — via `ScreenViewTracker` in
  `app.dart`. Popping back to the shell re-announces the current tab.
- **Events** are recorded in the services (`lib/services/*_service.dart`),
  after the successful call, so every entry point is covered by one line.
  Full list in `docs/privacy_data_inventory.md`. Onboarding reports each
  step. `AppState` reports signup/login/logout/session_expired/etc.; logout
  flushes *before* the token is cleared so the session stays attributed.
- **Opt-out:** Settings → privacy → "anonymous usage statistics". Off means
  nothing is queued or sent; turning it off also empties the queue and
  discards the `anon_id`. Deleting the account resets the identity too.
- **Localization:** two new keys (`anonymousUsageStatistics`,
  `anonymousUsageStatisticsHint`) added to both ARBs **and by hand** to both
  maps in `app_translations.dart`. Do **not** run
  `tools/l10n/generate_compat_layer.py` to do this: it does not reproduce
  the checked-in file (it would delete the hand-added genre block, ~120
  lines). That was already true before this change.
- **Test:** `test/analytics/screen_names_test.dart` covers the naming rule.

---

## Verification

- Backend: full suite on Postgres 16 — **407 passed** (372 existing + 35
  new in `tests/test_analytics.py`). The new tests cover identity, garbage
  tokens, idempotent retries, forgiveness, props privacy rules, clock
  clamping, switches, rate limiting, erasure, retention, the views, and the
  report's numbers. Two real defects were caught by them while writing:
  a non-dict item in `events` produced a 422 for the whole batch (now typed
  `list[Any]` and dropped individually), and the view/`drop_all` clash
  above.
- The five SQL queries in `docs/analytics.md` and the read-only Metabase
  role were run against Postgres. The role can read the analytics tables
  and views; `users`, other tables and any write are denied.
- **Not verified — please do before relying on it:** the Dart code has
  **not been compiled or run** (no Flutter SDK where this was written). It
  was checked with a tree-sitter Dart parser (no syntax errors in any
  changed file), all relative imports were checked to resolve, and APIs were
  reviewed by hand, but run `flutter analyze` and `flutter test` first.
  Metabase itself was not started (no Docker there).

## Known limits

- Counts are **devices**, not people (one install = one `anon_id`).
- `flutter build --obfuscate` renames classes and breaks screen names; give
  routes explicit `RouteSettings(name:)` if you enable it.
- Version shows as `dev` unless built with
  `--dart-define=SEENLY_APP_VERSION=x.y.z`.
- Bottom sheets built inline (no named class) show as `(unnamed)`.
- With the Home "together" mode active, returning to the Home tab is
  counted as `HomeScreen`.
- Default is **opt-out** (on unless switched off). See
  `docs/privacy_data_inventory.md` §5 before shipping to the EU / RU.
- The repository has no privacy policy, only an EULA. Analytics is a new
  data collection that the policy has to describe.

---

# Follow-up: Grafana dashboards

Reading the analytics used to mean one command (`analytics_report`) or a
click-it-yourself Metabase. This adds graphs that are ready on first start.

- **`grafana/`** — provisioning, not clicking. `provisioning/datasources/postgres.yml`
  wires a datasource from environment variables to the database through a
  **read-only role**; `provisioning/dashboards/dashboards.yml` loads every
  JSON in `grafana/dashboards/`; `dashboards/seenly-usage.json` is the
  dashboard itself ("Seenly — использование приложения", 17 panels): active
  devices / new / sessions / signed-in, devices and sessions per day,
  registrations and diary entries per day, ranked screens with time on
  screen, top-15 bar chart, sheets, onboarding funnel by step, actions,
  screen and action trends with pickers, share of searches with no results,
  D1/D7 retention by cohort, platform/version mix. Template variables:
  build (release/debug/profile), screen, event. Dashboards are read-only in
  the UI (`allowUiUpdates: false`): edit → Export JSON → replace the file,
  so what runs is always what's in git.
- **`docker-compose.yml`**: `grafana` service behind the existing
  `analytics` profile, bound to `127.0.0.1:3001` only (reach it through an
  SSH tunnel, never Caddy). Phoning home and background plugin installs are
  switched off (`GF_ANALYTICS_*`, `GF_PLUGINS_PREINSTALL_DISABLED`,
  `GF_NEWS_NEWS_FEED_ENABLED`); with those set, Grafana made no request to
  grafana.com in testing. Passwords come from `GRAFANA_ADMIN_PASSWORD` /
  `GRAFANA_DB_PASSWORD` (see `env.example`), with `:-` fallbacks — not `:?` —
  because Compose interpolates the whole file even for inactive profiles, and
  a required variable would break a plain `docker compose up`.
- **Migration `d4a7e1c05b92`**: four more views —
  `v_analytics_registrations_daily`, `v_analytics_diary_daily`,
  `v_analytics_premium_daily`, `v_analytics_retention`. They are views, not
  a grant on the tables, so the read-only role can be given the view alone
  and sees only dates, categories and counts (no ids, e-mails, titles).
  **Trade-off to know:** Postgres refuses `ALTER COLUMN … TYPE` / `DROP
  COLUMN` on a column a view reads, and these read `users.created_at`,
  `diary_entries.created_at`/`media_type`,
  `user_premium_state.purchased_at`/`plan_kind`/`plan_duration`. A future
  migration touching those must `DROP VIEW IF EXISTS v_analytics_…` first
  (noted in the migration header and in `docs/analytics.md`).
- **Tests** (`test_analytics.py::TestDashboardViews`): counts, that no view
  exposes an identifying column (`id`, `user_id`, `email`, `anon_id`, …), and
  retention including the case that matters — a cohort too young for day 7
  is *not* counted as "failed to return".
- **Docs:** `docs/analytics.md` gains "Способ Б. Grafana" (role SQL, `.env`,
  tunnel, running on your own computer, how to change the dashboard);
  Metabase becomes "Способ В", plain SQL "Способ Г".

## Verification (follow-up)

- Ran the **real Grafana 13.2.2** (GitHub release, not a mock) against
  Postgres 16 with this repo's provisioning files and the read-only role:
  datasource health "Database Connection OK", the dashboard loads from the
  file (17 panels), and all 18 panel queries — plus the two variable
  queries — execute through Grafana's own datasource and return the expected
  columns on synthetic data. The role can read the views and is denied on
  `users`, `diary_entries` and `user_premium_state`.
- **Not verified:** how the panels *look* (no browser available — a panel
  that renders oddly should be fixed in the UI and saved via Export), and the
  `docker compose` service itself (no Docker there; the image is
  `grafana/grafana-oss:latest` — pin it before deploying).

## GlitchTip and mobile crash reporting — plan only, no code

Documented in the launch plan (2.10.3), not applied to the repo: GlitchTip is
a separate self-hosted service (nothing in this repo needs it to run), and
the mobile side needs `sentry_flutter`, which was **not** added because it
can't be resolved from pub.dev or compiled in the environment this was
written in. The plan carries a sketch of the `main.dart` change. Note the
plan previously claimed `sentry_flutter` was already wired into
`lib/main.dart`; it is not, so no crash from a phone is reported anywhere
today.
