"""Referral links without Branch/AppsFlyer/Adjust — see the design
conversation this shipped from. Real deferred deep linking (tap a link,
app isn't installed yet, land in the store, open the app fresh, and have
it *already* know which link you tapped) needs one of those paid
services because nothing else can carry data across an app install on
iOS. This module is the honest, free approximation:

- App already installed → GET /i/{code} tries the app's own custom
  URL scheme (`seenly://invite?code=...`) via a same-tab JS redirect.
  On Android, if App Links (assetlinks.json below) are set up and
  verified, the OS skips this page entirely and opens the app directly
  from the https:// link — cleaner, but needs the real cert fingerprint
  in Settings.android_cert_sha256_fingerprints.
- App not installed, Android → the Play Store link this page falls back
  to carries `&referrer=seenly_ref%3D{code}`. Google's own Play Install
  Referrer API (free, built into Play Services) lets the app read that
  referrer string on first launch — no third-party SDK needed, this is
  a real, working deferred deep link on Android specifically.
- App not installed, iOS → there's no first-party equivalent. This page
  copies the code to the clipboard before sending someone to the App
  Store; the app can check the clipboard on first open. iOS shows a
  one-time "app pasted from clipboard" system banner when it does, and
  a person who declines that prompt just doesn't get auto-credited —
  see routers/friends.py::claim_invite, which is what actually applies
  the code once the client has it by any of these routes, and stays a
  silent no-op if it's never called.

None of this requires an external account or API key; the two
/.well-known files below just need the real Android cert fingerprint
and Apple Team ID filled into Settings once those exist.
"""

from fastapi import APIRouter, Depends
from fastapi.responses import HTMLResponse, JSONResponse
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app import models

router = APIRouter(tags=["linking"])


@router.get("/i/{code}", response_class=HTMLResponse)
def invite_landing(code: str, db: Session = Depends(get_db)):
    referrer = db.query(models.User).filter_by(invite_code=code.upper()).first()
    referrer_name = referrer.display_name or referrer.username if referrer else None

    play_url = "https://play.google.com/store/apps/details"
    if settings.play_store_package:
        play_url += f"?id={settings.play_store_package}&referrer=seenly_ref%3D{code}"

    app_store_url = (
        f"https://apps.apple.com/app/id{settings.ios_app_store_id}"
        if settings.ios_app_store_id else None
    )

    intro = (
        f"{referrer_name} зовёт вас на teamira" if referrer_name else "Вас пригласили на teamira"
    )

    html = f"""<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>teamira</title>
<style>
  body {{ font-family: -apple-system, Roboto, sans-serif; background: #0f0f14; color: #fff;
         display: flex; flex-direction: column; align-items: center; justify-content: center;
         height: 100vh; margin: 0; text-align: center; padding: 24px; box-sizing: border-box; }}
  h1 {{ font-size: 22px; margin-bottom: 8px; }}
  p {{ color: #aaa; font-size: 15px; }}
  a.btn {{ margin-top: 24px; padding: 14px 28px; border-radius: 999px; background: #6c5ce7;
           color: #fff; text-decoration: none; font-weight: 600; }}
</style>
</head>
<body>
  <h1>{intro}</h1>
  <p>Открываем приложение…</p>
  <a class="btn" id="fallback-link" href="{play_url}">Установить / открыть</a>

<script>
  // Referral code this whole page exists to carry across the install
  // boundary on iOS (see this module's docstring) — the app checks the
  // clipboard for exactly this on first open.
  var code = {code!r};
  var scheme = "{settings.app_custom_scheme}://invite?code=" + encodeURIComponent(code);
  var ua = navigator.userAgent || "";
  var isIOS = /iPhone|iPad|iPod/i.test(ua);
  var isAndroid = /Android/i.test(ua);

  function goStore() {{
    if (isIOS && {"true" if app_store_url else "false"}) {{
      window.location.href = "{app_store_url or ''}";
    }} else {{
      window.location.href = "{play_url}";
    }}
  }}

  if (isIOS && navigator.clipboard) {{
    // Best-effort — some browsers only allow clipboard writes after a
    // user gesture, which a bare page load doesn't have. When it's
    // blocked, the app simply has nothing to read on first open and
    // the person falls back to typing the code by hand.
    navigator.clipboard.writeText("seenly_ref:" + code).catch(function () {{}});
  }}

  // Try to open the app itself first (works if it's already installed
  // and registered the custom scheme / this is skipped entirely on
  // Android when App Links verification is live). If nothing happens
  // in ~1.2s, assume it's not installed and fall back to the store.
  window.location.href = scheme;
  setTimeout(goStore, 1200);
</script>
</body>
</html>"""
    return HTMLResponse(html)


@router.get("/t", response_class=HTMLResponse)
def title_landing(id: str, type: str = "movie", title: str = ""):
    """Landing page a shared title (title_share.dart's `titleShareLink`)
    points at, instead of sending people off to an outside site like
    IMDb/TMDB — the same "honest, free approximation" of a deep link as
    /i/{code} above, just carrying a title id instead of a referral
    code. No DB lookup: the client already has the title/type/id it
    needs to build both this page's copy and the eventual in-app route,
    so there's nothing here worth a query.
    """
    play_url = "https://play.google.com/store/apps/details"
    if settings.play_store_package:
        play_url += f"?id={settings.play_store_package}"

    app_store_url = (
        f"https://apps.apple.com/app/id{settings.ios_app_store_id}"
        if settings.ios_app_store_id else None
    )

    heading = f"«{title}» — в Seenly" if title else "Открываем в Seenly"

    html = f"""<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Seenly</title>
<style>
  body {{ font-family: -apple-system, Roboto, sans-serif; background: #0f0f14; color: #fff;
         display: flex; flex-direction: column; align-items: center; justify-content: center;
         height: 100vh; margin: 0; text-align: center; padding: 24px; box-sizing: border-box; }}
  h1 {{ font-size: 22px; margin-bottom: 8px; }}
  p {{ color: #aaa; font-size: 15px; }}
  a.btn {{ margin-top: 24px; padding: 14px 28px; border-radius: 999px; background: #6c5ce7;
           color: #fff; text-decoration: none; font-weight: 600; }}
</style>
</head>
<body>
  <h1>{heading}</h1>
  <p>Открываем приложение…</p>
  <a class="btn" id="fallback-link" href="{play_url}">Установить / открыть</a>

<script>
  var scheme = "{settings.app_custom_scheme}://title?type={type}&id={id}";
  var ua = navigator.userAgent || "";
  var isIOS = /iPhone|iPad|iPod/i.test(ua);

  function goStore() {{
    if (isIOS && {"true" if app_store_url else "false"}) {{
      window.location.href = "{app_store_url or ''}";
    }} else {{
      window.location.href = "{play_url}";
    }}
  }}

  // Same "try the app, then fall back to a store after a beat" trick
  // as /i/{{code}} above.
  window.location.href = scheme;
  setTimeout(goStore, 1200);
</script>
</body>
</html>"""
    return HTMLResponse(html)


@router.get("/.well-known/assetlinks.json")
def android_assetlinks():
    """Android App Links verification. Real once
    Settings.play_store_package and .android_cert_sha256_fingerprints
    are filled in (from the release keystore) — empty fingerprints just
    make Android fall back to the /i/{code} landing page instead of
    opening the app directly, not a broken state."""
    fingerprints = [f.strip() for f in settings.android_cert_sha256_fingerprints.split(",") if f.strip()]
    return JSONResponse([
        {
            "relation": ["delegate_permission/common.handle_all_urls"],
            "target": {
                "namespace": "android_app",
                "package_name": settings.play_store_package or "com.example.seenly",
                "sha256_cert_fingerprints": fingerprints,
            },
        }
    ])


@router.get("/.well-known/apple-app-site-association")
def ios_aasa():
    """iOS Universal Links verification. Served without a .json
    extension and without auth on purpose — that's Apple's required
    path/shape. Real once Settings.ios_app_id ("TEAMID.bundle.id") is
    filled in; empty just means iOS never verifies the domain and every
    tap falls back to the /i/{code} page's own JS redirect instead."""
    app_id = settings.ios_app_id or "TEAMID.com.example.seenly"
    return JSONResponse({
        "applinks": {
            "apps": [],
            "details": [
                {"appID": app_id, "paths": ["/i/*"]}
            ],
        }
    })
