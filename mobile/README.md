# teamira — mobile (Flutter)

A cozy evening diary for what you've watched (and played) — not a tracker
dashboard. Built on top of `../backend` (FastAPI).

## Why Flutter

You asked for Flutter specifically, and it's genuinely the right call here,
not just the path of least resistance:

- **One codebase, iOS + Android**, without giving up pixel-level control —
  which this UI needs. Almost nothing on these screens is a stock Material
  widget: rotated polaroids with washi tape, a dashed "not yet" border used
  as a design language, a hand-drawn Bezier thread running through a
  rewatch timeline. That's all custom-painted (`CustomPainter`,
  `ClipPath`, `Transform.rotate`), which Flutter's canvas-first widget model
  makes direct — you're not fighting a native list/table component to make
  it look hand-made.
- **The timeline widget you provided** (`bezier_timeline.dart`) is exactly
  this kind of thing — a `CustomPainter` drawing one continuous cubic-Bezier
  thread through card centers. It's now wired in at
  `lib/widgets/bezier_timeline.dart`, restyled to the palette and adapted to
  read `DiaryEntry` history straight from the backend, powering the title
  screen's "your evenings with this title" section.
- The alternative most people reach for here is React Native — also
  workable, but you'd lean on either raw `Canvas`/Skia bindings or
  SVG-through-a-bridge to get the same hand-drawn feel, where Flutter gets
  it natively. Fully native (Swift + Kotlin, two codebases) would look best
  of all three but is roughly double the work for a solo/small project.

## Setup

```bash
cd mobile
flutter pub get
flutter run
```

No configuration needed in the common case — `ApiClient` (see
`lib/services/api_client.dart`) races `10.0.2.2` (Android emulator),
`localhost`, and `127.0.0.1` against `/health` on first request and
remembers whichever answered, then re-races if a request ever fails at the
network level (e.g. you toggled a VPN). This mirrors what the backend
README documents for the API itself.

Need a specific address (real device on the same LAN, a differently-forwarded
port, a staging server)? Pass it explicitly — this becomes the *only* address
ever tried:

```bash
flutter run --dart-define=SEENLY_API_BASE_URL=http://<your-ip>:8000
```

The backend needs to actually be running first — see `../README.md` and
`../backend/.env.example` (you need a free TMDB API key for real
catalog data; without it `/media/search` and `/feed/collections` will 500).

## Architecture

```
lib/
├── main.dart, app.dart        # entry point, Provider setup, auth-gated routing
├── theme/                     # palette.dart + text_styles.dart — the one
│                               # source of truth every screen imports from
├── models/                    # plain Dart classes mirroring backend/app/schemas.py
│                               # 1:1 — same field names, same nullability
├── services/                  # one class per router: auth/media/feed/diary/profile
│                               # + api_client.dart (the only place that knows
│                               # about HTTP, base-URL discovery, and the JWT)
├── state/app_state.dart       # the one ChangeNotifier: auth status + hands
│                               # out every service via Provider
├── widgets/                   # reusable pieces: PosterTile, PolaroidCard,
│                               # HeartRating, PillChip/PrimaryButton/DashedBox,
│                               # SeenlyBottomNav, BezierTimeline/RewatchTimeline
└── screens/
    ├── auth/                  # login, register
    ├── shell/root_shell.dart  # bottom-nav host (IndexedStack, 4 tabs)
    ├── home/                  # continue watching, fresh-in-diary strip, "on this day", tonight's pick
    ├── diary/                 # search bar, "picked for you" strip, then the full log grouped by date
    ├── collections/           # editorial shelves from /feed/collections
    ├── profile/               # stats + watched/plan-to-watch toggle+grid, settings/logout
    ├── search/                # find a title, quick-log or open its page
    ├── add_entry/             # the "write a diary page" form
    └── title/                 # hybrid catalog-page + personal rewatch timeline
```

State management is deliberately just `ChangeNotifier` + `provider` — no
riverpod/bloc. The app's actual shared state is one thing (auth), and every
screen otherwise owns its own `Future`/`FutureBuilder` for its own data; that
didn't seem to earn a heavier tool.

## Screen → endpoint map

| Screen | Backend calls |
|---|---|
| Home | `GET /diary`, `GET /profile/stats/year`, `GET /feed/collections` |
| Diary | `GET /diary` (grouped client-side by calendar date) |
| Collections | `GET /feed/collections` |
| Profile | `GET /profile/collections`, `GET /profile/stats/year` |
| Search | `GET /media/search` |
| Add entry | `POST /diary` |
| Title detail | `GET /diary/media/{id}` for the timeline; `GET /media/detail` for runtime/certification/status, cast, ratings, and similar titles (TMDB-backed movies/series/anime — see below); `GET /media/search` as a last-resort backfill when arriving without a full `MediaItem` and detail can't resolve the id |

## A couple of things worth knowing about, not hiding

- **`GET /media/detail` covers movies/series/anime** —
  runtime, certification, release status, full cast, ratings, and a
  genre-matched "similar titles" shelf, all in one call, sourced from TMDB.
  It still can't help with **games** (no such data exists for them there)
  or with a title TMDB has no listing for — those cases fall back to the
  old best-effort search backfill described below. One real limitation
  worth knowing: our `MediaItem.id` alone can't tell a TV show from an
  anime (both come back as `media_type: "series"`), so a "series" detail
  call tries `/tv/{id}` first and, if that 404s, retries against `/movie/
  {id}` — an extra request sometimes, but no wrong-segment 404 either way.
- **"Similar titles" is genre-matching, not a recommendation engine** —
  TMDB's own `/similar` endpoint is used directly, which is itself
  genre/keyword-based rather than a personalized recommender; the title
  screen's "if you liked this" shelf is honestly labeled as such.
- **Reviews are real text, not just counts** — `GET /media/reviews` merges
  TMDB's own `/reviews` with Trakt's `/comments`, since TMDB alone is often
  nearly empty for a given title.
- **"Continue watching" on Home is honest, not simulated.** The backend has
  no episode-level progress tracking, so that card shows the most recently
  logged series and *when* you last logged it — no fabricated "episode 4 of
  8" progress bar. Real episode tracking would need adapter + schema work
  beyond this pass.
- **Personal collections aren't built** — during design we went back and
  forth on "my collections" vs. API-driven ones and landed on API-only
  (`/feed/collections`, editorial). So there's no "create a collection" flow
  here on purpose, not as an oversight.
- **This code hasn't been run through `flutter analyze`/`flutter test`** —
  written in an environment without the Flutter SDK available. It's been
  reviewed carefully by hand (import paths, constructor signatures, brace
  balance) and every model field matches the backend schemas verified by an
  actual end-to-end test — but please run `flutter analyze` yourself before
  you ship anything, treat this as a strong first draft rather than
  CI-verified code.
- **Token storage uses `shared_preferences`**, not `flutter_secure_storage`
  — simpler to set up with zero platform-specific config, called out here
  because it's a real tradeoff (not encrypted at rest) rather than something
  to discover later. Swapping the two calls in `ApiClient.loadToken`/
  `setToken` for `flutter_secure_storage`'s API is a small, contained change
  if you want that for a real release.
