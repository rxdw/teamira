// The one place this extension talks to your Seenly server. Content
// scripts never fetch directly — they message here instead — because a
// fetch made from inside a streaming site's own page is subject to that
// page's Content-Security-Policy, which can silently block a cross-origin
// request with no error a content script can see. A background service
// worker's requests aren't subject to the page's CSP at all.
//
// host_permissions is "<all_urls>" in manifest.json because the server URL
// is whatever someone pastes into the popup (their own self-hosted Seenly
// backend) — it isn't known ahead of time. Narrow this to your actual
// server's origin instead before publishing this anywhere beyond your own
// browser.
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== 'seenly-scrobble') return;

  (async () => {
    const { seenlyServer, seenlyToken } = await chrome.storage.sync.get([
      'seenlyServer',
      'seenlyToken',
    ]);
    if (!seenlyServer || !seenlyToken) {
      sendResponse({ ok: false, reason: 'not configured — open the extension popup' });
      return;
    }
    const base = seenlyServer.replace(/\/$/, '');
    const url = `${base}/integrations/${seenlyToken}/scrobble?integration=${encodeURIComponent(message.integration)}`;
    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(message.payload),
      });
      sendResponse({ ok: res.ok, status: res.status });
    } catch (e) {
      sendResponse({ ok: false, reason: String(e) });
    }
  })();

  return true; // keep the message channel open for the async sendResponse above
});
