// Shared engine every per-site script in sites/ calls into — loaded first
// on every page via manifest.json's content_scripts "js" array, so by the
// time a site script runs, window.SeenlyScrobbler is already there.
//
// A site script's whole job is answering one question — "what's the title
// right now?" — via getTitle(). This file handles finding the <video>
// element, polling its progress, deciding when something counts as
// watched, and getting that to the backend. See backend/app/schemas.py::
// ScrobblePayload and backend/app/routers/integrations.py::generic_scrobble
// for the exact shape/semantics this sends.
(function () {
  if (window.__seenlyScrobblerLoaded) return; // a frame can get this
  window.__seenlyScrobblerLoaded = true;       // script injected twice

  const COMPLETE_THRESHOLD = 0.9;   // matches WATCHED_THRESHOLD server-side
  const PROGRESS_PING_MS = 30000;   // how often to send an in-progress update
  const POLL_MS = 5000;

  function guessMediaType(title) {
    // Best-effort only — wrong here just means the backend's own title
    // match (TmdbAdapter.resolve_external_id) has a slightly worse first
    // guess to work with, nothing breaks. A site script can always pass
    // its own getMediaType() instead if it knows better (e.g. from the
    // page's own season/episode markup).
    if (!title) return 'movie';
    return /сезон|эпизод|season\s*\d+|s\d+e\d+/i.test(title) ? 'series' : 'movie';
  }

  function send(integration, payload) {
    try {
      chrome.runtime.sendMessage(
        { type: 'seenly-scrobble', integration, payload },
        (response) => {
          // chrome.runtime.lastError just means the background worker
          // wasn't reachable (extension reloading, etc) — nothing the
          // person watching needs to see, so this only goes to devtools.
          if (chrome.runtime.lastError) {
            console.debug('[seenly]', integration, chrome.runtime.lastError.message);
          } else if (response && !response.ok) {
            console.debug('[seenly]', integration, 'not sent:', response.reason || response.status);
          }
        }
      );
    } catch (e) {
      console.debug('[seenly]', integration, 'sendMessage failed', e);
    }
  }

  /**
   * @param {object} opts
   * @param {string} opts.site - the `integration` name logged server-side, e.g. "kinopoisk"
   * @param {() => (string|null)} opts.getTitle - current title, or null if unknown right now
   * @param {() => string} [opts.getMediaType] - defaults to guessMediaType(getTitle())
   * @param {() => (HTMLVideoElement|null)} [opts.video] - defaults to document.querySelector('video')
   */
  function watch({ site, getTitle, getMediaType, video }) {
    let reported = false;
    let lastPing = 0;
    let lastSrc = null;

    const findVideo = () =>
      (typeof video === 'function' ? video() : video) || document.querySelector('video');

    setInterval(() => {
      const v = findVideo();
      if (!v || !v.duration || Number.isNaN(v.duration) || v.duration === Infinity) return;

      // A new currentSrc means a new episode/title started playing (SPA
      // navigation or autoplay-next) — let it be reported again.
      const src = v.currentSrc || v.src;
      if (src && src !== lastSrc) {
        lastSrc = src;
        reported = false;
      }

      const progress = v.currentTime / v.duration;
      const title = getTitle();
      if (!title) return;
      const mediaType = getMediaType ? getMediaType() : guessMediaType(title);

      if (!reported && progress >= COMPLETE_THRESHOLD) {
        reported = true;
        send(site, { title, media_type: mediaType, progress: 1.0, completed: true });
        return;
      }

      const now = Date.now();
      if (!reported && progress > 0.02 && now - lastPing > PROGRESS_PING_MS) {
        lastPing = now;
        send(site, { title, media_type: mediaType, progress, completed: false });
      }
    }, POLL_MS);
  }

  window.SeenlyScrobbler = { watch, guessMediaType };
})();
