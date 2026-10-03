# Account lifecycle, recovery, sessions and moderation

Everything in the audit's 2.3, 2.4, 2.5, 3.2 and 3.3. Shipped as one
change because it genuinely is one: account deletion is impossible
without the foreign-key rules, the foreign-key rules are only worth
adding because deletion needs them, and the moderation and session tables
both hang off columns added to `users` here.

---

## 2.3 — Account deletion, and the 46 foreign keys that blocked it

**The blocker underneath the blocker.** Not one foreign key in
`models.py` carried an `ondelete`, so even a hand-written delete endpoint
would have been refused by roughly two dozen referential-integrity
constraints. Every one now has a rule chosen by meaning rather than
applied wholesale:

- `CASCADE` for rows that have no life without their owner or parent.
- `SET NULL` for references *to* a person from rows that belong to
  someone else or must outlive them: `referred_by_id`, a co-viewing seat,
  who started a vote, `diary_entries.shared_link_id` (a couple splitting
  up must not delete anybody's personal diary), and every reference on
  `reports`.

`passive_deletes=True` on the twelve `delete-orphan` relationships, so
Postgres does the cascade rather than SQLAlchemy loading and deleting
every child row one at a time.

**Two-phase deletion.** `DELETE /auth/account` (password required) marks
the account and revokes every session — it is invisible to everyone from
that moment. The rows are destroyed after
`ACCOUNT_PURGE_AFTER_DAYS` (30). The grace period isn't hedging: it's the
difference between a delete button people can bring themselves to press
and one they can't.

**The part a cascade can't decide.** `partner_links.owner_id` is
`CASCADE`, which is the right backstop and the wrong outcome whenever
anyone else is still in the circle — their shared co-viewing list and
voting history would vanish because someone else left. So
`_reassign_shared_structures` hands ownership to a remaining member
first, and the cascade only fires for a circle with nobody left in it.

**What deliberately survives a purge:** other people's diary entries that
mention you by name snapshot (their memory of their own evening),
moderation history (or deleting yourself becomes a way to erase the
evidence), and `OutboundClick`, which has no `user_id` at all by design.

`GET /auth/export` — the whole account as one JSON file, `Content-
Disposition: attachment`. Nothing about anyone else goes in it, even
where this account can see it in the app.

## 2.4 — Password recovery and email

`User.email` + `email_verified`, `AccountToken` (reset and verification
links, stored only as SHA-256), `app/mailer.py` with a `console` backend
for development and `smtp` for production.

Two decisions worth knowing:

- **`/auth/password/forgot` answers identically** whether or not the
  address exists. It's unauthenticated and takes an email address, so a
  distinguishing response would be a free "is this person on tanè" oracle
  for any address anyone cared to try. The UI says so out loud rather
  than letting someone wonder whether they typo'd.
- **Reset only works for a verified address.** An unverified one only
  proves somebody typed it — possibly a typo landing in a stranger's
  inbox — and mailing a reset link there is handing out the account.

## 2.5 — Moderation (App Store guideline 1.2)

- `UserBlock` — immediate, no review, **symmetric in effect**. One-way
  enforcement leaks the block itself: if a blocked person could still see
  your profile while you couldn't see theirs, the asymmetry is the
  notification. Blocking also tears down the friendship and pending
  requests, but deliberately does *not* dissolve an active co-viewing
  circle — silently destroying a three-person group's shared diary
  because two members fell out is worse than the problem.
- `Report` with `due_at = created_at + 24h`. The queue sorts by it and
  flags anything overdue, which turns Apple's 24-hour expectation into
  something checkable rather than a line in a review reply. Reports carry
  frozen snapshots of what was complained about, so editing the content
  afterwards can't make a report read as baseless.
- `app/content_filter.py` — structural checks first (invisible
  characters, links and `@handles` in a nickname, character walls), which
  generalise across Russian and English and can't be defeated by a
  synonym. The word list comes from a file the deployment supplies, not
  from this repository. Wired into nicknames, status lines, list names
  and diary notes.
- EULA in both languages, served from `/legal/eula` and
  `/legal/eula.html` (the latter for the App Store listing URL), version
  recorded on the account at registration.

**Suspension is not a sign-in block.** A suspended account can still read
and export its own diary; what it loses is the ability to reach anyone
else. Confiscating years of a personal archive over a UGC complaint is a
punishment out of proportion to the offence and one an appeal can't undo.

## 3.2 — User enumeration

`GET /friends/search` was a `LIKE '%q%'` over every username with
`min_length=1` and no limit: twenty-six requests returned essentially the
whole user table. Fixed as a set, because no single part is enough:
prefix matching, a three-character floor, `%`/`_` escaping (a bare `%`
would otherwise undo everything else in one character), a `discoverable`
opt-out, and a rate limit keyed on the caller's account.

Blocked, deleted and suspended accounts never appear anywhere —
`app/blocking.py` is imported by every social read path so a new screen
can't accidentally ship a hole.

## 3.3 — Authentication

- **Token pair.** Access tokens are 30 minutes; `POST /auth/refresh`
  rotates a long-lived refresh token. The client refreshes ahead of
  expiry and retries once on a 401.
- **Rotation with replay detection.** A refresh token presented twice
  means two parties hold it, so the whole session family is revoked. This
  is what makes a long-lived refresh token safer than the week-long
  access token it replaces rather than a rename of it.
- **Revocation.** `token_version` on the user row, stamped into every
  token. One integer write invalidates everything: password change,
  reset, "sign out everywhere", suspension, deletion. No denylist table,
  no extra query.
- **`username_lower`** with a unique index and one normalisation function
  (`app/usernames.py`, NFKC + casefold). Registration used to compare
  case-*sensitively* while friend search and friend requests compared
  case-*insensitively*, so "Anna" and "anna" could both exist and only
  one was reachable. Reserved names and invisible characters are rejected.
- **Keychain/Keystore** on the client (`flutter_secure_storage`), with a
  one-time migration of any token left in `SharedPreferences` so nobody
  is signed out by the update.
- **Global 401 handling** with single-flight refresh. The single-flight
  guard is not an optimisation: two parallel refreshes would trip the
  server's replay detection and sign the person out, and would do it only
  under load.

---

## Running it

```bash
# 1. new dependency
pip install -r backend/requirements.txt      # adds email-validator

# 2. migration — see its docstring before running against a large database
cd backend && alembic upgrade head

# 3. client
cd mobile && flutter pub get
```

New environment variables are documented in `env.example`. At minimum,
set `PUBLIC_WEB_BASE_URL` (reset links point at it) and switch
`EMAIL_BACKEND` to `smtp` before launch — `console` logs reset links to
the application log, which is a complete account takeover in production.

### Migration notes

The foreign-key rewrite is the risky part and is handled carefully:
constraint names are looked up in `pg_constraint` rather than assumed
(Postgres appends a disambiguating suffix when its conventional name is
taken), and each constraint is added `NOT VALID` then validated
separately so the row check doesn't hold an `ACCESS EXCLUSIVE` lock on
`diary_entries`.

The `username_lower` backfill uses `DISTINCT ON`: if "Anna" and "anna"
both already exist — the exact bug this fixes — a plain `UPDATE` would
collide on the new unique index. The oldest account keeps the name, the
rest are left `NULL` and findable with
`SELECT * FROM users WHERE username_lower IS NULL`. Nobody is renamed or
locked out by a migration.

---

## A correction to this document's own earlier draft

An earlier version of this file, and of app/mailer.py's docstring, made
two claims about this codebase that turned out to be false: that
routers/auth.py "refuses to pretend a mail was sent in production", and
that mail sending happens on a worker thread via `asyncio.to_thread`.
Neither was ever implemented — the docstring described a safeguard that
didn't exist. Both are now fixed:

- app/mailer.py's docstring states plainly that sending is a blocking
  call with no backgrounding, which is a real (if minor) latency issue
  worth fixing before production traffic, not a correctness one.
- main.py's on_startup now logs a `SECURITY` critical, the same shape as
  the existing `jwt_secret == "change-me"` check, whenever
  `EMAIL_BACKEND` isn't `smtp` — so leaving the console backend on by
  accident is loud rather than silent.
- routers/moderation.py's module docstring now says outright that no
  admin UI exists yet, rather than that fact living only in a chat
  reply where it's easy to lose.

## A second, more serious correction — a genuine bug, not just a comment

Asked directly "are you sure everything's good now", I went back and
tested paths I'd only asserted before, rather than re-asserting
confidence. Two things came out of that.

**A real bug in `Report`'s dedup constraint, found by testing rather than
reading.** `models.Report`'s `UniqueConstraint` on `(reporter_id,
target_type, target_id, reported_user_id)` was meant to stop one person
filing the same complaint twice. It didn't, for the single most common
report — reporting a *profile* rather than a specific note or list, where
`target_id` is `NULL` by design (see that column's own comment). SQL
never considers two `NULL`s equal, so the constraint silently allowed
unlimited duplicate profile reports from the same person. Verified by
inserting two such rows against the actual constraint before touching
anything: both inserts succeeded.

Fixed with the standard tool for this — a Postgres expression unique
index on `(reporter_id, target_type, COALESCE(target_id, ''),
reported_user_id)`, added in the migration and explained in both
`models.Report`'s and the migration's own comments. Also added the
`IntegrityError` handling `create_report` needed once a database
constraint could actually fire: a request that loses the race now gets
back the other request's report, not a 500. Both the original bug and
the fix are verified with tests in this changelog's history, including a
forced-race test that bypasses the application-level check entirely to
confirm the database constraint — not just the Python — is what closes
the gap.

**What's still genuinely unverified.** No Postgres was reachable in the
sandbox this work was done in (`apt-get install postgresql` failed on a
mirror snapshot mismatch), so the exact Postgres `CREATE UNIQUE INDEX ...
COALESCE(...)` statement was proxy-verified on SQLite, which supports the
same expression-index and `COALESCE` semantics but is not the same
database. Run the migration against a real Postgres instance and re-check
this specific index before trusting it in production. Separately, no
Flutter/Dart toolchain was available either, so every mobile-side change
across both turns is syntax- and balance-checked, never compiled. Treat
`flutter analyze` as the first thing to run, not an optional step.

## Still to do

1. **Run this migration against real Postgres, specifically for the new
   expression index.** Only proxy-verified on SQLite — see above.
2. **Build verification.** The Dart changes are syntax- and
   balance-checked but were never compiled — `flutter analyze` first.
3. **Admin UI for the moderation queue.** The API is complete
   (`/moderation/admin/reports`, `.../resolve`); there's no screen, so
   triage is currently curl or a small internal tool. Worth building
   before launch, since the 24-hour commitment is now visible to users.
4. **The blocklist file.** `CONTENT_BLOCKLIST_PATH` is empty, so only the
   structural checks run. Populate it per market.
5. **`MODERATION_CONTACT_EMAIL`.** App Store review expects published
   contact information for content complaints.
6. **iOS Keychain accessibility.** Tokens use
   `first_unlock_this_device`, so they do **not** restore from an iCloud
   backup. Correct for security, but it means restoring an iPhone lands
   the person at the login screen — which is exactly why the recovery
   email should be asked for more than once.
