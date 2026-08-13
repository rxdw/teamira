/**
 * Generic scrobbler content script, shared by all four watch pages (see
 * manifest.json's content_scripts.matches). Deliberately generic rather
 * than one bespoke scraper per site: it reads document.title (stripping
 * each site's own " - Netflix" / " | Hulu" style suffix) and polls the
 * page's <video> element for progress. That keeps one file working
 * across sites, but it also means the title text is a rough guess, not a
 * clean "Show Name S2E4" — good enough for a season/episode regex to
 * attempt against, but expect misses on some titles.
 *
 * THIS WILL NEED UPKEEP. Streaming sites change their page structure,
 * title format, and URL scheme without warning, and none of this can be
 * verified against the live site from outside a browser actually signed
 * into each service — if scrobbles stop showing up for one site, that
 * site's title format or watch-page URL pattern probably changed; open
 * devtools on that site's watch page (Elements tab, or just look at
 * document.title in the console) and update SUFFIXES / EPISODE_PATTERNS
 * / manifest.json's matches accordingly.
 */

const SUFFIXES = [
  / - Netflix$/i,
  / \| Hulu$/i,
  / - Watch on Disney\+.*$/i,
  / \| Crunchyroll$/i,
];

const EPISODE_PATTERNS = [
  /S(\d+)\s*[:\-]?\s*E(\d+)/i,
  /Season\s+(\d+).*Episode\s+(\d+)/i,
  /\b(\d+)x(\d+)\b/,
];

const WATCHED_THRESHOLD = 0.85;
const POLL_MS = 15000;

let reportedForSrc = null;

function cleanTitle(raw) {
  let title = raw;
  for (const re of SUFFIXES) title = title.replace(re, "");
  return title.trim();
}

function parseEpisode(title) {
  for (const re of EPISODE_PATTERNS) {
    const m = title.match(re);
    if (m) return { season: parseInt(m[1], 10), episode: parseInt(m[2], 10) };
  }
  return null;
}

function integrationForHost() {
  const h = location.hostname;
  if (h.includes("netflix")) return "netflix";
  if (h.includes("hulu")) return "hulu";
  if (h.includes("disneyplus")) return "disneyplus";
  if (h.includes("crunchyroll")) return "crunchyroll";
  return "browser-extension";
}

function maybeReport(video) {
  if (!video || !video.duration || video.currentTime / video.duration < WATCHED_THRESHOLD) return;
  const key = video.currentSrc || video.src;
  if (!key || key === reportedForSrc) return;
  reportedForSrc = key;

  const cleaned = cleanTitle(document.title);
  const ep = parseEpisode(cleaned);
  const payload = {
    // Best-effort: strip a trailing " - S2:E4"-style fragment so `title`
    // is just the show/movie name where possible. Falls back to the
    // whole cleaned string if nothing matched.
    title: (ep ? cleaned.replace(/\s*[-:|].*$/, "").trim() : "") || cleaned,
    media_type: ep ? "series" : "movie",
    season: ep ? ep.season : null,
    episode: ep ? ep.episode : null,
    completed: true,
  };
  chrome.runtime.sendMessage({ type: "seenly-scrobble", integration: integrationForHost(), payload });
}

setInterval(() => {
  const video = document.querySelector("video");
  maybeReport(video);
}, POLL_MS);
