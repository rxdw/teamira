// Hulu — UNVERIFIED, same caveat as netflix.js: leans on document.title
// rather than a DOM class that could easily be wrong today. Adjust the
// suffix regex once you've checked what Hulu's title actually looks like
// mid-playback.
(function () {
  function getTitle() {
    const raw = document.title || '';
    const cleaned = raw.replace(/\s*[-–]\s*Hulu\s*$/i, '').trim();
    return cleaned || null;
  }
  window.SeenlyScrobbler.watch({ site: 'hulu', getTitle });
})();
