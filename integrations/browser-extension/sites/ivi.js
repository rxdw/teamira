// ivi — UNVERIFIED against the live site. Same two things to check as
// kinopoisk.js: (1) whether the player lives in an iframe on a separate
// domain from ivi.ru — if so add that domain to manifest.json's "matches"
// for this entry — and (2) whether ivi's own JSON-LD (tried first, below)
// or document.title (fallback) actually carries the title while playing.
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

  window.SeenlyScrobbler.watch({ site: 'ivi', getTitle });
})();
