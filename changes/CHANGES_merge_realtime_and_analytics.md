# Merging realtime, analytics, and the P1 audit fixes

Three independent branches off the same base ("seenly-merged", the
state audited in this thread) got merged into one tree in this session:

- **mine** — the P1 audit follow-up (ENVIRONMENT guard, python-jose
  bump, docker-compose.prod.yml, CI). See CHANGES_audit_followup_p1.md.
- **realtime** — WebSocket push replacing `Timer.periodic` polling in
  co_view_vote.py/co_view_poll.py/together.py.
- **analytics** — first-party product analytics, backend + mobile. See
  CHANGES_analytics.md.

This file covers only the merge itself: what overlapped, how it was
resolved, and what was verified afterward. It does not re-describe what
each branch does on its own — the two CHANGES files above do that.

## Method

Not a blind file-by-file copy. For every file touched by more than one
branch, `git merge-file` did a real three-way merge against the shared
base, and every conflict (and, as it turned out, several *non*-conflicts
worth a second look — see below) got read and resolved by hand rather
than auto-resolved by taking "whichever version compiles."

Of 76 total changed files across all three branches, 66 didn't overlap
with anything else and were taken as-is. 10 were touched by more than
one branch:

| File | Touched by | Resolution |
|---|---|---|
| `backend/app/config.py` | mine + analytics | clean merge, non-overlapping additions |
| `backend/.env.example` | all three | clean merge + restored a block both other branches had dropped (see below) |
| `backend/app/main.py` | all three | one real conflict (same import line edited twice) |
| `backend/app/routers/linking.py` | realtime + analytics | both changes turned out to be the same regression — reverted, not merged (see below) |
| `backend/tests/test_linking.py` | realtime + analytics | same regression as linking.py, in its tests |
| `mobile/pubspec.yaml` | realtime + analytics | clean merge + restored a dropped dependency (see below) |
| `mobile/lib/main.dart` | realtime + analytics | hand-assembled (see below) |
| `mobile/lib/screens/onboarding/onboarding_screen.dart` | realtime + analytics | clean merge — both branches made the identical change |
| `mobile/lib/services/together_service.dart` | realtime + analytics | one real conflict (same import line) |
| `mobile/ios/Runner.xcodeproj/project.pbxproj` | realtime + analytics | reverted, not merged (see below) |

## The recurring pattern: both branches forked before a few base-only refinements

Four separate spots showed the exact same shape: realtime and analytics
*independently* lacked something the base state had, character-for-
character identical between the two of them. That consistency is what
gave it away — two unrelated branches don't converge on deleting the
same docstring by accident. The likely explanation is that both were
started from a point that predates a handful of small fixes already
present in the base this thread had been auditing, rather than either
branch deliberately removing any of this:

1. **`ios_aasa()` in linking.py** — base returns an empty `details`
   list when `Settings.ios_app_id` isn't configured, with a docstring
   explaining why a fabricated placeholder appID (what both branches
   had instead) is worse than an honest empty response. Reverted to
   base's version, including restoring the two dropped test classes
   (`TestIosAasa`, `TestAndroidAssetlinks`) in test_linking.py.
2. **`Runner.entitlements` + its Xcode wiring** — the file itself
   (Universal Links associated-domains entitlement) was missing from
   disk in both branches, and project.pbxproj had the matching file
   reference, group membership, and three `CODE_SIGN_ENTITLEMENTS`
   build settings all removed. Both branches' *entire* diff of
   project.pbxproj was exactly this — nothing else — so the file was
   restored by copying base's version outright rather than merging.
3. **`sentry_flutter` in pubspec.yaml + its wiring in main.dart** —
   both branches dropped the dependency and the whole
   `SentryFlutter.init(...)` wrapper around `_runApp()`, silently
   turning off crash reporting. Restored in both files.
4. **The deep-link env var block in backend/.env.example** —
   `APP_CUSTOM_SCHEME`/`PUBLIC_WEB_BASE_URL`/the Android+iOS App Links
   pairs. The settings themselves were never touched in config.py or
   linking.py (still actively used in both branches) — only their
   `.env.example` documentation vanished. Restored.

None of these four had any connection to what either branch was
actually built to do (WebSockets, analytics) — nothing in either
feature depends on the reverted behavior, which is the main reason this
reads as "stale starting point" rather than "deliberate change I'm
overriding." **Worth independently double-checking** — merges like
this are exactly where something can look resolved and not be.

One related cleanup that isn't a config regression: both branches had
also deleted `mobile/assets/onboarding/logging_demo.mp4` (a ~1.9 MB
video, unused since both replaced the widget that played it with a
poster-deck animation instead — see onboarding_screen.dart below). That
part of both diffs was correct and consistent with their own code
changes; the merged tree just hadn't picked it up yet since it started
from a copy that still had the file. Deleted here too, for the same
reason both branches already had.

## The one place both branches made the identical *addition*

`onboarding_screen.dart`'s diary card: both branches, independently,
replaced the old `_LoggingRitualDemo` screen-recording widget with a
staged two-deck poster reveal (`_revealSecondary`, a 260ms `Timer`) —
same field names, same comments, same logic, in both. Unlike the four
cases above, this reads as a genuine shared design change rather than a
gap, so it went in as-is (git merge-file resolved it with zero
conflicts, since both sides agree).

## Actual conflicts (three, all trivial)

`main.py` and `together_service.dart` each had one spot where both
branches added a new import on the exact same line — realtime's `from
app import realtime` / `import 'realtime_socket.dart'` and analytics'
new router/package import. Kept both.

## What this merge does NOT add

No new tests were written in this session, by request — analytics
already brought 35 of its own (backend/tests/test_analytics.py); the
WebSocket/realtime.py side has none of its own beyond whatever the
existing co_view_vote.py/co_view_poll.py/together.py suites already
covered before this change (those still pass, but nothing here
exercises a NOTIFY actually firing across two connections). Read
app/realtime.py and the three routers' `@router.websocket(...)`
handlers by hand as part of this merge — LISTEN/NOTIFY handling,
transaction ordering around `publish()`, and the WS auth path
(`get_ws_user`, mirroring `get_current_user`'s checks) all look sound —
but "read and looked sound" is not "tested," and this is new,
security-relevant surface (an unauthenticated-until-checked WebSocket
endpoint) that should get real coverage before it's the only thing
standing between a stale session and its two participants.

## Verification

- **Backend:** full suite run against real Postgres 16 (same version as
  docker-compose.yml's own db image) after every merge step, not just
  once at the end. Final count: **420 passed** (385 from the P1 branch
  + 35 new analytics tests — together.py/co_view_vote.py/co_view_poll.py's
  existing tests, now exercising the WebSocket-backed routers, are
  included in that 385 and still pass unmodified). `requirements.txt`
  was untouched by both realtime and analytics, so no new installs were
  needed beyond what the P1 branch already had.
- **Mobile:** no Flutter SDK available in this environment (confirmed —
  `flutter/flutter`'s own bootstrap needs a Dart SDK archive from
  Google's own storage, which this sandbox's network allowlist doesn't
  reach). Verified instead with `tree-sitter-dart`: all 306 `.dart`
  files under `mobile/lib/` parse with zero syntax errors, and every
  relative `import '...'` in that tree resolves to a real file. Also
  manually checked that `Analytics`'s actual API (`instance`, `init()`,
  `track(name, props)`) matches every call site touched by this merge.
  None of this substitutes for `flutter analyze`/`flutter test` —
  **run both before trusting this build.**
