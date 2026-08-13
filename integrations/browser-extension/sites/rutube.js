// Rutube — the easiest of the Russian sites: an ordinary <video> element
// on the page itself (no player iframe on a separate domain to chase), and
// document.title reliably includes the video's own title. Start testing
// the whole extension here first before touching the iframe-based sites
// below (kinopoisk/ivi/okko/wink/start/kion) — if something's broken with
// the extension itself rather than a site's markup, it'll show up here
// first and be far easier to debug.
(function () {
  function getTitle() {
    const raw = document.title || '';
    const cleaned = raw.replace(/\s*[-–]\s*Rutube\s*$/i, '').trim();
    return cleaned || null;
  }
  window.SeenlyScrobbler.watch({ site: 'rutube', getTitle });
})();
