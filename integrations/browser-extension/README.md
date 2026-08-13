# Seenly Auto-Tracking — browser extension

Manifest V3 extension. Injects a small script into each supported
streaming site, watches the `<video>` element, and POSTs a scrobble to
your Seenly server once something's finished — see
`backend/app/routers/integrations.py::generic_scrobble` for what happens
on the other end.

## Install (unpacked, for your own use)

1. `chrome://extensions` (or `edge://extensions`) → enable **Developer mode**.
2. **Load unpacked** → pick this folder (`integrations/browser-extension/`).
3. Click the extension's icon → paste your **server** address and
   **token** (Seenly app → Settings → auto-tracking → same pair used for
   Plex/Jellyfin/Kodi) → **save**.
4. Open a supported site and watch something to the end.

No build step — it's plain JS, loads as-is.

## Status per site — what's real vs. best-effort

Nothing below has been tested against a live logged-in session (no
accounts/subscriptions available here to test with) — treat all of it as
a first draft to verify, not a finished integration. If a site doesn't
log anything, open DevTools → Console on that tab first; every failed
send logs a `[seenly] ...` line explaining why (not configured, network
error, etc).

| Site | Player location | Title source | Confidence |
|---|---|---|---|
| **Rutube** | plain `<video>` on the page | `document.title` | Start here — simplest case, good first test of the extension itself |
| Kinopoisk HD | possibly a separate-domain iframe — **check DevTools** | JSON-LD → `document.title` | Untested |
| ivi | possibly a separate-domain iframe — **check DevTools** | JSON-LD → `document.title` | Untested |
| Okko | possibly a separate-domain iframe — **check DevTools** | JSON-LD → `document.title` | Untested |
| Wink | possibly a separate-domain iframe — **check DevTools** | JSON-LD → `document.title` | Untested |
| START | possibly a separate-domain iframe — **check DevTools** | JSON-LD → `document.title` | Untested |
| KION | possibly a separate-domain iframe — **check DevTools** | JSON-LD → `document.title` | Untested |
| Netflix / Hulu / Disney+ / Crunchyroll | on-domain | `document.title` | Untested — these sites' markup also changes often, budget for re-checking every so often |

## If a site's player lives in an iframe on another domain

`manifest.json`'s `content_scripts` entries only inject into frames whose
URL matches that entry's `matches` list — a same-domain frame is already
covered by the `*://*.<site>.ru/*` wildcard, but a **separate** CDN/player
domain isn't. To fix:

1. Open the site, start playing something, DevTools → **Elements** → find
   the `<iframe>` wrapping the player → note its `src` domain.
2. Add that domain to the relevant entry's `"matches"` array in
   `manifest.json` (keep `"all_frames": true` — it's already set for every
   Russian-service entry).
3. Reload the extension (`chrome://extensions` → refresh icon) and retest.

## Adding another site

1. Add a `content_scripts` entry to `manifest.json` — copy an existing RU
   entry as a starting point (`all_frames: true` if you're not sure the
   player is same-domain).
2. Add `sites/<name>.js` — copy `sites/okko.js` as a template, it's the
   generic JSON-LD-first pattern used by every RU site here.
3. No backend changes needed — `integration` is a free-text label, not a
   fixed list (see the docstring at the top of
   `backend/app/routers/integrations.py`).

## Not handled here

- **Series/episode metadata** (season/episode numbers) — every scrobble
  sends just a title + a movie/series guess (`lib/seenly-scrobbler.js`'s
  `guessMediaType`). Good enough for the backend's own title-matching, but
  someone bingeing a season will get one log per episode, not tracked
  progress through the season the way a Plex/Jellyfin webhook (which
  carries real season/episode numbers) does.
- **Monetization** — this extension only sends scrobble events, nothing
  to do with the referral-link side of the app. See
  `docs/auto-tracking-and-monetization-guide.md` for that.
