# Home-screen widget — iOS setup

Everything needed for the widget is done on the Flutter and Android
side (`lib/services/home_widget_service.dart`,
`android/app/src/main/kotlin/com/example/seenly/SeenlyWidgetProvider.kt`
and its resources). A WidgetKit widget is a genuinely separate Xcode
*target*, though, not just a source file the build system will pick up
on its own — creating that target is the one piece this can't do from
here, since it means editing `Runner.xcodeproj`'s project file, which
needs Xcode itself to do safely. `SeenlyWidget.swift` in this folder is
real, complete widget code — checked syntactically and against
`home_widget`'s own v0.6.0 reference example, not guessed — it's just
not wired into a build target yet.

## One-time steps, in Xcode

1. Open `ios/Runner.xcworkspace` (not the `.xcodeproj`).
2. **File > New > Target… > Widget Extension.** Product Name:
   `SeenlyWidget`. Leave "Include Configuration Intent" **unchecked**
   (this widget uses a plain `StaticConfiguration`, not an
   `IntentConfiguration`). "Activate scheme" — either choice is fine.
3. Xcode generates a `SeenlyWidget/SeenlyWidget.swift` (or
   `SeenlyWidgetBundle.swift`, naming varies by Xcode version) for the
   new target, with placeholder content. Delete that file's *content*
   and replace it with this folder's `SeenlyWidget.swift` — or delete
   the generated file outright and drag this one into the new
   `SeenlyWidget` target instead (Xcode's file inspector should show
   "SeenlyWidget" checked under Target Membership, "Runner" unchecked).
4. **App Groups**, on *both* targets (Runner, and the new SeenlyWidget
   extension): Signing & Capabilities → **+ Capability** → **App
   Groups** → add `group.com.example.seenly.widget`. This exact string
   has to match in three places, and nothing checks that they agree at
   compile time:
   - `HomeWidgetService._appGroupId` (Dart)
   - `SeenlyWidget.swift`'s `widgetGroupId`
   - both targets' entitlements, from this step
5. Set the SeenlyWidget target's deployment target to iOS 14.0 or
   higher (WidgetKit's minimum) — match Runner's own if that's already
   higher.
6. Build and run on a device or simulator running iOS 14+, then from
   the home screen: long-press → **+** (top-left) → search "tanè" → add
   the widget. It'll show whatever `HomeWidgetService` last pushed —
   open the app once first (that's what triggers the first push).

## Known rough edges, left as-is for a v1

- **One layout for both sizes.** `.supportedFamilies([.systemSmall,
  .systemMedium])` shares a single view; the "pick" state's poster
  thumbnail crowds a `.systemSmall` slot more than a dedicated small
  layout would. Worth a follow-up if the small size turns out to be
  the one people actually pick.
- **Tapping the widget just opens the app** — `.widgetURL(URL(string:
  "seenly://widget"))` and, on Android, a plain launch intent. Neither
  routes to a specific screen (e.g. straight to the co-viewing
  countdown's evening). The `widget` host is there so that routing can
  be added later without a scheme change, not because anything reads
  it yet.
- **Colors are one fixed "diary paper" set**, not the in-app skin/
  flavor/brightness choice — see `SeenlyWidgetProvider.kt`'s doc
  comment for why (the widget has no access to that runtime Flutter
  state, only whatever gets pushed).
- **No background network fetch on either native side.** The poster
  image is fetched and rendered to a local file by the Flutter side
  (`HomeWidget.renderFlutterWidget`, see `_renderPoster` in
  `home_widget_service.dart`) — both `SeenlyWidget.swift` and
  `SeenlyWidgetProvider.kt` only ever read that already-rendered file.
  A widget that's been alive since before the app was last opened
  shows whatever was pushed then, refreshed only by the timeline/
  `updatePeriodMillis` floor (~30 min) until the app runs again.
