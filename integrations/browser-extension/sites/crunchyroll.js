// Crunchyroll — UNVERIFIED, same caveat as netflix.js. Anime almost always
// counts as "series" here rather than the default "movie" guess.
(function () {
  function getTitle() {
    const raw = document.title || '';
    const cleaned = raw.replace(/\s*[|\-–]\s*Crunchyroll\s*$/i, '').trim();
    return cleaned || null;
  }
  window.SeenlyScrobbler.watch({ site: 'crunchyroll', getTitle, getMediaType: () => 'series' });
})();
