# Watch Together / co-viewing — changes in this patch

Drop these files into your project at the same relative paths (they
overwrite the originals) — nothing else needs to change, `create_all()` +
the startup migrations in `main.py` handle the two new DB columns
automatically on next backend start, no manual SQL needed.

## What changed and why

### 1. Genre filter for Watch Together
- `backend/app/models.py` — `TogetherSession.genres_filter` (JSON list).
- `backend/app/schemas.py` — `TogetherCreateRequest.genres`,
  `TogetherSessionOut.genres_filter`.
- `backend/app/routers/together.py` — `_matches_genre_filter()`, applied
  in `_build_deck()` so a network session's deck is narrowed server-side.
- `mobile/lib/screens/together/together_screen.dart` — a curated genre
  chip list (`kTogetherGenreChoices`, matching TMDB's own genre names) on
  the setup screen, multi-select. Empty selection = no narrowing. Applied
  client-side for one-phone mode, sent to the backend for network mode.

### 2. Settings: "add matches to my own list too?"
- `mobile/lib/services/coview_prefs_service.dart` (new) — a device-local
  toggle, same SharedPreferences pattern as `RitualPrefsService`.
- `mobile/lib/screens/profile/settings_screen.dart` — a "co-viewing"
  section with the toggle, same visual pattern as the other prefs rows.
- `mobile/lib/app.dart` — registers the new service as a provider.
- `backend/app/models.py` /`schemas.py`/`routers/together.py` — each
  side's choice travels with `TogetherCreateRequest.sync_to_own_list` /
  `TogetherJoinRequest.sync_to_own_list`, stored as
  `owner_sync_to_list` / `guest_sync_to_list` on the session, and
  `_add_match_to_both_lists()` only adds a match to *that* person's
  personal "watch together" list if their own flag is on.
- **Important**: this never affects the *shared* co-viewing list on a
  standing partner link — a match always lands there regardless of this
  setting. Only the personal list-add is gated.
- `mobile/lib/services/together_service.dart` — `create()`/`join()` now
  accept `genres` / `syncToOwnList`.
- `mobile/lib/models/together_session.dart` — carries `genresFilter`.

### 3. A clear "how this works" guide
- `mobile/lib/widgets/how_it_works_sheet.dart` (new) — pulled the
  existing "how co-viewing works" bottom sheet out of
  `co_viewing_screen.dart` into a shared widget, and added two more
  steps: the genre filter, and the new personal-list setting. Used from
  both the co-viewing screen (unchanged behavior) and the new "?" icon on
  Watch Together's own screen, plus an automatic one-time show the first
  time someone opens Watch Together.
- `mobile/lib/screens/partner/co_viewing_screen.dart` — now imports and
  calls the shared sheet instead of its own private copy (no behavior
  change for that screen).
- `mobile/lib/screens/together/together_screen.dart` — new "?" icon in
  the app bar + auto-show on first visit (tracked via
  `CoViewPrefsService.hasSeenGuide`).

## Confirmed behavior (matches what you described)

- **One phone, passing it back and forth**: a swipe-right is an
  immediate joint decision — no partner confirmation step, it's assumed
  you're both looking at the same screen. Lands straight in your
  "watch together" list (if the setting above is on) and on the shared
  co-viewing screen if you have a partner linked (always, regardless of
  the setting).
- **Over the network (code on two phones)**: a title only counts as a
  match once *both* of you have separately swiped right on it — nothing
  is final until your partner confirms. Same list behavior as above once
  it matches.

### 4. A soft confirmation after a one-phone "together" swipe
- `mobile/lib/screens/together/together_screen.dart` — new `_MatchPulse`
  widget: a small paper-colored badge (heart icon + "settled, together")
  that pops and fades over the deck for under a second right after a
  local "together" decision, then disappears on its own. It's layered
  over `_SwipeDeck` via a `Stack` + `IgnorePointer`, so it never blocks
  the next swipe.
- This is *not* a confirmation step and asks nothing — the one-phone
  decision was already final the instant you swiped (see "Confirmed
  behavior" above, unchanged). It's purely a warm little acknowledgment
  that the match landed, instead of the card just silently sliding away.
  Network mode (`_NetSwipeDeck`) doesn't get this — there, a swipe
  genuinely isn't final until the other phone weighs in too, so nothing
  should look "settled" yet.

### 5. Spoiler veil for descriptions and reviews
- `mobile/lib/widgets/spoiler_veil.dart` (new) — `SpoilerVeil`, a
  reusable wrapper that softly blurs its child (paper-tinted scrim +
  a floating "might give things away · tap to reveal" chip) until
  tapped. A no-op when `active` is false. Reveal state lives on the
  widget instance, so it re-veils next time you open a different
  title or reopen the sheet — nothing to remember to re-hide.
- `mobile/lib/services/spoiler_prefs_service.dart` (new) — two
  independent device-local toggles: `blurDescriptions` (default
  **off** — synopses are usually written not to spoil) and
  `blurReviews` (default **on** — other people's reviews aren't).
  Same SharedPreferences pattern as `CoViewPrefsService`.
- `mobile/lib/screens/title/title_detail_screen.dart` — the synopsis
  is now wrapped in `SpoilerVeil`, bound to `blurDescriptions`.
- `mobile/lib/widgets/reviews_sheet.dart` — each review's body text
  (not its avatar/author/rating header, not the "open on TMDB/Trakt"
  link) is wrapped in `SpoilerVeil`, bound to `blurReviews`.
- `mobile/lib/app.dart` — registers `SpoilerPrefsService` as a
  provider, same pattern as the other device-only prefs services.
- `mobile/lib/screens/profile/settings_screen.dart` — new
  "spoilers" section between "co-viewing" and "language", two
  switches in one card (matches the existing two-toggle layout used
  elsewhere in this screen).

### 6. QR code for co-viewing pairing
- Added where it fits the existing flow best: the same "co-viewing"
  sheet on Home that already generates/accepts a 6-character pairing
  code (`_PendingCodeBody` / `_JoinCodeInline` in
  `mobile/lib/screens/home/home_screen.dart`) — not Watch Together's
  own session code, which is a separate, shorter-lived thing.
- `mobile/lib/widgets/pairing_qr.dart` (new):
  - `PairingQrCode` — the pending code rendered as a small scannable
    square in a paper-toned frame (`qr_flutter`), no different
    visually from the rest of the app's card language.
  - `showPairingScanner()` — opens the camera behind a warm dark
    scrim with a rounded accent-colored viewfinder (`mobile_scanner`),
    matching the app's frame language instead of a bare native camera
    view. Pops itself the instant it reads a valid 6-character code
    (checked against the same alphabet the backend generates codes
    from — no 0/O/1/I), or `null` if the person backs out.
- `_PendingCodeBody` now shows the QR first — "if they're nearby, let
  them scan it" — with the same plain-text code underneath as a
  fallback for sharing remotely (message, read aloud, etc.); nothing
  about the existing sharing path was removed.
- `_JoinCodeInline` gained a "scan their code instead" button above
  the manual-entry field; on a successful scan it fills the field and
  submits the same way pressing "join" would.
- The sheet's content is now wrapped in a `SingleChildScrollView`
  (`_CoViewingCardState._openSheet`) so the taller QR content can't
  overflow on a smaller phone.
- New dependencies in `mobile/pubspec.yaml`: `qr_flutter: ^4.1.0`
  (pure Dart, nothing native to configure) and `mobile_scanner:
  ^5.2.3` (needs the camera). Camera permission entries added:
  `android/app/src/main/AndroidManifest.xml`
  (`android.permission.CAMERA`) and `ios/Runner/Info.plist`
  (`NSCameraUsageDescription`). Not added to macOS/Linux/Windows —
  this feature is mobile-only.

### 7. Co-viewing sheet: centered overlay instead of a bottom sheet
- `mobile/lib/screens/home/home_screen.dart` — `_openSheet()` no
  longer uses `showModalBottomSheet`. The "not linked yet" states in
  particular (just a code, or the short code-entry field) used to
  leave a small card stranded low on an otherwise-empty sheet — it
  read as something half-finished rather than an intentional screen.
- Now pushes a transparent `PageRouteBuilder` — same mechanism the
  app already uses for its other overlays (see
  `widgets/seat_picker_overlay.dart`): a `BackdropFilter` blur over
  Home plus a soft warm-ink tint, with the card centered in the
  middle of the screen instead of docked to the bottom.
- Tapping the blurred backdrop dismisses it, same as tapping the mark
  in the card's top-right corner; tapping the card itself does not.
  The `_sheetRebuild` mechanism, the code/QR/entry states themselves,
  and the linked-state content are all unchanged — only the chrome
  around them moved.
- Card width caps at 380 and the content still sits in a
  `SingleChildScrollView` (kept from the earlier QR change), so it
  scales down gracefully on a small phone and never overflows behind
  the keyboard when the code-entry field is focused.

## Not yet done / worth a check on your end
- New packages (`qr_flutter`, `mobile_scanner`) — run `flutter pub get`
  before building. `mobile_scanner` needs a real device or an emulator
  with camera support to test the scanning half; the display half
  (`PairingQrCode`) needs neither.
- I don't have a Flutter toolchain in this environment, so these files
  were only checked for balanced brackets/consistent references, not
  compiled. Run `flutter pub get && flutter analyze` before shipping.
- No existing automated tests were run against the backend changes
  (pytest wasn't present in this snapshot).

### 8. Merged in the "clickable actors" branch, plus two follow-up fixes
This project now also includes the separately-developed clickable
cast/director feature (`PersonDetailScreen`, `CastMember.personId`,
`MediaItem.directorId`, `GET /media/person`) layered on top of
everything above. Two things broke across that merge and got fixed
here:

- **Compile error**: `title_detail_screen.dart` referenced
  `MediaItem.directorId`, but the field was never added to the model
  itself. Added it to `mobile/lib/models/media_item.dart` — property,
  constructor param, and `json['director_id']` parsing — mirroring
  the existing `director` field. The backend already had
  `director_id` in `schemas.py`/`tmdb.py`; this was the one missing
  piece.
- **Duplicate-looking shelves on the "anime" tab**: filtering a
  shelf's items down to just the picked media type
  (`mobile/lib/screens/collections/collections_screen.dart`) let a
  perfectly ordinary shelf (e.g. the plain "Action" movie shelf)
  survive under the anime tab with just the 1-2 stray titles TMDB
  happens to tag as both Action and Japanese-animated — sitting right
  next to the real, dedicated "Action Anime" shelf and reading as a
  duplicate. Fixed with a minimum shelf size (4 items) after
  filtering, plus a belt-and-braces merge for any shelves that still
  end up sharing an exact title.
- Also independently found and fixed, in `backend/app/adapters/tmdb.py`:
  genre-scoped shelves (`similar_by_genre`) only fetched one TMDB
  page (~20 results) before `_diversify` capped them at 2 entries per
  apparent franchise — thin to begin with for narrow slices like the
  anime-only shelves, and easy to starve down to almost nothing when
  a couple of huge current franchises dominate that page. Now fetches
  two pages, and `_diversify` relaxes its cap a notch at a time
  rather than leaving a shelf near-empty when the pool actually had
  more to give.

### 9. Achievements screen: fixed the celebration mascot's ticket getting clipped/covering text
- `mobile/lib/screens/profile/achievements_screen.dart` — the rabbit
  mascot (shown when `unlockedCount > 0`) used to be the first item
  inside the screen's `ListView`, peeking upward with a negative
  `top` offset in a `Positioned`. Two problems with that: a
  `ListView` clips to its own viewport by default, so the part of the
  mascot reaching up toward the header was silently cut off every
  time — what was left read as a stray dark, badly-cropped shape
  rather than "a rabbit holding a ticket." And what remained still
  hung low enough to overlap the honesty note's text right below it
  ("...actually played on the reel...").
- Moved the mascot out of the `ListView` entirely and anchored it to
  the header's own `Stack` instead, painted after (so on top of) the
  header row. Nothing there clips it anymore, and it's sized/offset
  (`size: 76`, `top: -30`) to stay within the header's own height, so
  it never reaches down into the list content underneath.
- The old width-reserving `SizedBox(104)` trick in the "X of Y
  unlocked" row (there to keep text from running under the mascot)
  is gone too — that row is a plain `Text` again now that the mascot
  doesn't share its layout space.
