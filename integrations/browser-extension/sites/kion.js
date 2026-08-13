// KION — UNVERIFIED against the live site. Same two caveats as
// kinopoisk.js: check the player's actual iframe domain in DevTools if
// nothing gets logged, and verify JSON-LD/document.title actually carry
// the title on KION's own pages.
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

  window.SeenlyScrobbler.watch({ site: 'kion', getTitle });
})();
