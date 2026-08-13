// Netflix — UNVERIFIED against the live site (no way to test this without
// a subscription + live session here). Netflix's own DOM classes churn
// often and aren't a safe bet to hardcode, so this leans on document.title
// instead, which Netflix does keep updated per-episode ("Title: Episode
// Name" or similar) — check what it actually shows while playing and
// adjust the regex below if it doesn't match.
(function () {
  function getTitle() {
    const raw = document.title || '';
    const cleaned = raw.replace(/\s*[-–]\s*Netflix\s*$/i, '').trim();
    return cleaned || null;
  }
  window.SeenlyScrobbler.watch({ site: 'netflix', getTitle });
})();
