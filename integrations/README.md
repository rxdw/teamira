# Auto-tracking integrations

This is what lets teamira log a watch on its own instead of waiting for a
manual entry — the thing Trakt uses to pull ahead of
manual-logging-only apps. Everything here talks to one backend module,
`backend/app/routers/integrations.py` — read that file's module docstring
first; this README is the practical, per-integration companion to it.

**Not all four sources below are equally easy or equally durable.** Two
are official, stable APIs. Two are best-effort scrapers that will need
occasional upkeep. Know which is which before you rely on any of them.

| Source | Mechanism | Stability |
|---|---|---|
| Plex | official webhook | stable — Plex's own feature |
| Jellyfin | official "Webhook" plugin | stable — official plugin |
| Kodi | addon + player callbacks | stable — Kodi's own Python API |
| Netflix / Hulu / Disney+ / Crunchyroll | browser extension, page-scraping | fragile — no official API exists |

## How to get your token

Open the teamira app: **Settings → auto-tracking**. That screen shows a
ready-made URL for Plex and Jellyfin, and a separate server-URL + token
pair for Kodi and the browser extension (both of which want those two
values entered separately in their own settings). There's a "rotate
token" button there too, for if a URL/token ever leaks.

## Plex

1. Requires Plex Pass (webhooks are a Plex Pass feature).
2. Plex web app → **Settings → Webhooks → Add Webhook**.
3. Paste the Plex URL from teamira's auto-tracking screen. Done.

Plex sends a `media.scrobble` event once you've watched past its own
configured threshold (a Plex-side setting, usually ~90%) — that's the only
event type this integration acts on; play/pause/resume are ignored on
purpose so a single sitting isn't double-counted.

## Jellyfin

1. Install the official **Webhook** plugin (Dashboard → Plugins →
   Catalog → Notifications → Webhook).
2. Add a new webhook destination, paste the Jellyfin URL from teamira.
3. Under "Notification Type", enable **Playback Stop** and **Item Marked
   Played**. Leave everything else off — those are the only two events
   the backend acts on.

Jellyfin's webhook plugin lets you customize exactly which fields it
sends. This integration expects the commonly-documented defaults
(`ItemType`, `Name`, `SeriesName`, `SeasonNumber`, `EpisodeNumber`,
`Provider_tmdb`, `Provider_imdb`). If matches aren't landing, open the
plugin's webhook template in Jellyfin and compare field names against
`backend/app/routers/integrations.py::_parse_jellyfin_payload` — community
plugin field names have moved before and aren't guaranteed as stable as
Plex's built-in payload.

## Kodi

See `kodi/service.seenly.scrobbler/`. This is a "service" addon — the same
shape Trakt's own Kodi addon takes — that subscribes to Kodi's own
playback events and posts a scrobble once a title's actually finished.

**Install:**
1. Zip the `service.seenly.scrobbler/` folder (the zip's top level should
   be the folder itself, containing `addon.xml`).
2. Kodi → Settings → Add-ons → Install from zip file.
3. Open the addon's settings and paste the server URL + token from teamira.

**Requires Kodi 19 (Matrix) or newer** — the video-info APIs this uses
(`InfoTagVideo.getUniqueIDs()`, season/episode getters) were added/
stabilized in that release. Works best with a scraped library (TMDB/TVDB
metadata attached); unscraped files still get logged, just without a
catalog match on the teamira side.

## Browser extension (Netflix, Hulu, Disney+, Crunchyroll)

See `browser-extension/`. **Read this section before relying on it** —
this is the one integration with no official API behind it at all.

**How it actually works:** a content script runs on each site's watch
page, reads `document.title` (stripping that site's own " - Netflix" /
" | Hulu" style suffix), and polls the page's `<video>` element for
playback progress. Once you're past ~85% of the runtime, it sends a
scrobble. There's no title/episode metadata API involved anywhere in this
path — it's a plain text guess, parsed with a couple of regexes for
"S2E4"-style patterns.

**Install (unpacked, since this isn't published to a store):**
1. Chrome → `chrome://extensions` → enable Developer mode.
2. "Load unpacked" → select the `browser-extension/` folder.
3. Click the extension icon → paste the server URL + token from teamira.

**This will need upkeep.** Netflix, Hulu, Disney+, and Crunchyroll can
each change their page structure, title format, or watch-page URL pattern
at any time, with no notice — and there's no way to verify any of this
against the live sites from outside a browser actually signed into each
service. If scrobbles quietly stop appearing for one specific site:

1. Open that site's watch page, open devtools, and check
   `document.title` in the console while something plays.
2. Compare it against `SUFFIXES` / `EPISODE_PATTERNS` in `content.js` and
   adjust.
3. Also check the URL bar against `manifest.json`'s
   `content_scripts.matches` — if the watch-page URL pattern changed, the
   content script won't even be injected.

This is exactly the ongoing maintenance cost Trakt absorbs to keep
its own scrobbler working — expect the same here, not a one-time
build.
