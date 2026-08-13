// Kinopoisk HD — UNVERIFIED against the live site. Two open questions to
// check yourself before trusting this:
//
// 1. The player itself commonly runs inside an iframe served from a
//    separate player/CDN domain rather than kinopoisk.ru directly. If so,
//    this script (injected only into kinopoisk.ru and its subdomains, per
//    manifest.json) never sees the <video> element at all — open DevTools
//    → Elements while something is playing, find the iframe's `src`
//    domain, and add it to manifest.json's "matches" for this entry.
// 2. Title extraction tries the page's schema.org JSON-LD block first
//    (<script type="application/ld+json">, commonly present on Kinopoisk
//    title pages) since that's far more stable than any CSS class name —
//    falls back to document.title, split on the em dash Kinopoisk
//    typically uses between title and site name.
(function () {
  function fromJsonLd() {
    const nodes = document.querySelectorAll('script[type="application/ld+json"]');
    for (const node of nodes) {
      try {
        const data = JSON.parse(node.textContent);
        const entries = Array.isArray(data) ? data : [data];
        for (const entry of entries) {
          if (entry?.name && /Movie|TVSeries|TVEpisode/i.test(entry?.['@type'] || '')) {
            return entry.name;
          }
        }
      } catch (_) {
        // malformed or unrelated JSON-LD block — try the next one
      }
    }
    return null;
  }

  function getTitle() {
    return fromJsonLd() || (document.title || '').split(/[—–-]/)[0].trim() || null;
  }

  window.SeenlyScrobbler.watch({ site: 'kinopoisk', getTitle });
})();
