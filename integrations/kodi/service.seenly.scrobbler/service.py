"""
teamira Kodi scrobbler — a background "service" addon, the same shape
Trakt's own Kodi addon takes for this. Subclasses xbmc.Player to get
called back on playback events, and once a title's actually finished (not
just started), POSTs it to teamira's generic
`/integrations/{token}/scrobble` endpoint — see
backend/app/routers/integrations.py on the server side.

Kodi library items that have been scraped (TMDB/TVDB agent attached)
carry the same TMDB/IMDB ids Plex/Jellyfin libraries do, via
InfoTagVideo.getUniqueIDs() — so identity resolution here is exactly as
reliable as the webhook integrations, for anything in a scraped library.
Unscraped/local files still get logged, just as a lightweight
title-only snapshot (same fallback the backend uses for anything else it
can't match).

REQUIRES Kodi 19 (Matrix) or newer — InfoTagVideo.getUniqueIDs() and the
season/episode getters used below were added/stabilized in that release.
On Kodi 18 (Leia) or earlier you'd need to read the older
`xbmc.getInfoLabel("VideoPlayer.something")` style API instead; not
implemented here.
"""

import json
import urllib.error
import urllib.request

import xbmc
import xbmcaddon

ADDON = xbmcaddon.Addon()

# How much of a title needs to have played before it counts as "finished"
# — mirrors the bar Kodi itself uses to decide whether to clear a
# resume point, rather than inventing a separate threshold.
WATCHED_THRESHOLD = 0.85


def _config():
    server = ADDON.getSetting("server_url").rstrip("/")
    token = ADDON.getSetting("token")
    return server, token


def _post_scrobble(payload: dict, integration: str = "kodi") -> None:
    server, token = _config()
    if not server or not token:
        xbmc.log("[teamira] scrobbler not configured — set server URL and token in this addon's settings", xbmc.LOGWARNING)
        return
    url = f"{server}/integrations/{token}/scrobble?integration={integration}"
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method="POST")
    try:
        urllib.request.urlopen(req, timeout=10)
        xbmc.log(f"[teamira] scrobbled: {payload.get('title')}", xbmc.LOGINFO)
    except urllib.error.URLError as exc:
        xbmc.log(f"[teamira] scrobble POST failed: {exc}", xbmc.LOGWARNING)


class SeenlyPlayer(xbmc.Player):
    def __init__(self):
        super().__init__()
        self._start_total_time = 0
        self._reported = False

    def onAVStarted(self):
        self._reported = False
        try:
            self._start_total_time = self.getTotalTime()
        except RuntimeError:
            self._start_total_time = 0

    def onPlayBackStopped(self):
        self._maybe_report()

    def onPlayBackEnded(self):
        self._maybe_report()

    def _maybe_report(self):
        if self._reported:
            return
        try:
            current = self.getTime()
            total = self._start_total_time or self.getTotalTime()
        except RuntimeError:
            return
        if not total or current / total < WATCHED_THRESHOLD:
            return
        self._reported = True

        try:
            info = self.getVideoInfoTag()
        except RuntimeError:
            return
        if info is None:
            return

        media_type = info.getMediaType()  # "movie" | "episode" | ...
        if media_type not in ("movie", "episode"):
            return

        unique_ids = info.getUniqueIDs() if hasattr(info, "getUniqueIDs") else {}
        payload = {
            "title": (info.getTVShowTitle() if media_type == "episode" else info.getTitle()) or "Untitled",
            "media_type": "series" if media_type == "episode" else "movie",
            "season": info.getSeason() if media_type == "episode" else None,
            "episode": info.getEpisode() if media_type == "episode" else None,
            "year": info.getYear() or None,
            "tmdb_id": unique_ids.get("tmdb"),
            "imdb_id": unique_ids.get("imdb"),
            "completed": True,
        }
        _post_scrobble(payload)


if __name__ == "__main__":
    player = SeenlyPlayer()
    monitor = xbmc.Monitor()
    xbmc.log("[teamira] scrobbler service started", xbmc.LOGINFO)
    while not monitor.abortRequested():
        if monitor.waitForAbort(2):
            break
    del player
