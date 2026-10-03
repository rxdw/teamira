# iPhone updates through SideStore

The launch plan had nothing about updating the iOS app: it was Android-only
by design, while the app on the owner's phone was installed through
SideStore. The immediate gap: the server address is baked into the app at
build time (`SEENLY_API_BASE_URL`, see `lib/services/api_client.dart`), and the
iOS build was evidently made against a machine on the home network
(`NSExceptionDomains` for `192.168.1.33` in `Info.plist`) — so when the
backend goes live on a domain, a new build has to be made and installed over
the old one.

- **Building the `.ipa`** stays in Codemagic, which the project already uses
  (there is no `codemagic.yaml` in the repo, so the setup lives in the
  Codemagic UI). What has to change there is only the three build arguments
  — server address, an analytics version label, and `$BUILD_NUMBER` — and
  the code has to be pushed to the branch Codemagic builds. A GitHub Actions
  workflow written for this earlier was removed once it turned out Codemagic
  is what's in use.
- **`mobile/tools/ios/make_altstore_source.py`** (+ tests) — adds a build to a
  SideStore/AltStore source JSON, reading version, build number, minimum iOS
  and permission texts from the `.ipa` itself, putting the new version *first*
  (update detection looks at the first entry, not dates), and refusing a
  repeated build number. Standard library only. Tested on synthetic `.ipa`
  files (XML and binary plists), not on a live SideStore.
- **`docs/ios-sidestore.md`** — short runbook; the explained version is phase
  **2.13.4.2** of the launch plan, which also gets: a cutover checklist (the
  home backend and the production one are different databases — sign up again),
  the honest limits of SideStore (3 apps, 7-day signing, no Universal Links or
  push, unsuitable for a group of testers), and pointers from 2.13.4, 2.13.5,
  4.2 and 4.3.
- Noticed, not changed: `Runner.entitlements`, which the plan's 2.13.4.1
  tells you to edit, does not exist in the project; the plan now says so.
