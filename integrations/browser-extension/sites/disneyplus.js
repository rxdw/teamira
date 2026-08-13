// Disney+ — UNVERIFIED, same caveat as netflix.js.
(function () {
  function getTitle() {
    const raw = document.title || '';
    const cleaned = raw.replace(/\s*[|\-–]\s*Disney\+?\s*$/i, '').trim();
    return cleaned || null;
  }
  window.SeenlyScrobbler.watch({ site: 'disneyplus', getTitle });
})();
