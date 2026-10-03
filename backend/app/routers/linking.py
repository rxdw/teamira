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

import html
import json
from urllib.parse import quote

from fastapi import APIRouter, Depends
from fastapi.responses import HTMLResponse, JSONResponse
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app import models
from app.invite_copy import build_landing_intro

router = APIRouter(tags=["linking"])


def _js_string(value: str) -> str:
    """Safely embeds `value` as a string literal inside an inline
    <script> block. json.dumps() alone gets the JS-string-escaping
    right (quotes, backslashes, control characters) but knows nothing
    about HTML — if `value` contains a literal "</script>", the HTML
    parser ends the script block right there, before any JS engine
    ever sees it, no matter how correctly the JS string around it was
    escaped. Escaping "</" to "<\\/" sidesteps that: a backslash before
    "/" is a no-op in a JS string (decodes to the same "/"), but it's
    no longer the literal three characters "</" the HTML tokenizer is
    scanning for. Every value embedded in a <script> block on this
    page's two routes should go through this, not json.dumps() alone —
    see invite_landing/title_landing below, and the test in this
    project that specifically checks a "</script><script>..." payload
    against both of them.
    """
    return json.dumps(value).replace("</", "<\\/")


@router.get("/i/{code}", response_class=HTMLResponse)
def invite_landing(code: str, db: Session = Depends(get_db)):
    referrer = db.query(models.User).filter_by(invite_code=code.upper()).first()
    referrer_name = referrer.display_name or referrer.username if referrer else None

    play_url = "https://play.google.com/store/apps/details"
    if settings.play_store_package:
        play_url += f"?id={settings.play_store_package}&referrer=seenly_ref%3D{quote(code, safe='')}"

    app_store_url = (
        f"https://apps.apple.com/app/id{settings.ios_app_store_id}"
        if settings.ios_app_store_id else None
    )

    intro = build_landing_intro(referrer_name=referrer_name)
    # Escaped/encoded up front, before `html` below gets reassigned to
    # the response body string and shadows the `html` module import.
    # play_url/app_store_url each appear in two different contexts
    # further down — an HTML attribute (href="...") and a JS string
    # literal (window.location.href = "...") — and HTML-escaping and
    # JS-string-escaping are not interchangeable, so each gets its own
    # safe form for its own context rather than one "safe" version
    # reused in both.
    intro_safe = html.escape(intro)
    play_url_attr = html.escape(play_url)
    play_url_js = _js_string(play_url)
    app_store_url_attr = html.escape(app_store_url) if app_store_url else ""
    app_store_url_js = _js_string(app_store_url or "")
    # json.dumps, not repr() — this is going into a <script> block, a
    # JS context, not a Python one; repr() doesn't know it needs to
    # escape "</script>" or JS-significant characters, so a crafted
    # {code} could break out of the string literal (or the script tag
    # entirely) and run arbitrary JS in anyone's browser who opens a
    # crafted /i/<code> link — this endpoint needs no valid referral
    # code or logged-in session to reach.
    code_js = _js_string(code)

    page_html = f"""<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>tanè</title>
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
  <h1>{intro_safe}</h1>
  <p>Открываем приложение…</p>
  <a class="btn" id="fallback-link" href="{play_url_attr}">Установить / открыть</a>

<script>
  // Referral code this whole page exists to carry across the install
  // boundary on iOS (see this module's docstring) — the app checks the
  // clipboard for exactly this on first open.
  var code = {code_js};
  var scheme = "{settings.app_custom_scheme}://invite?code=" + encodeURIComponent(code);
  var ua = navigator.userAgent || "";
  var isIOS = /iPhone|iPad|iPod/i.test(ua);
  var isAndroid = /Android/i.test(ua);

  function goStore() {{
    if (isIOS && {"true" if app_store_url else "false"}) {{
      window.location.href = {app_store_url_js};
    }} else {{
      window.location.href = {play_url_js};
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
    return HTMLResponse(page_html)


@router.get("/t", response_class=HTMLResponse)
def title_landing(id: str, type: str = "movie", source: str = "tmdb", title: str = ""):
    """Landing page a shared title (title_share.dart's `titleShareLink`)
    points at, instead of sending people off to an outside site like
    IMDb/TMDB — the same "honest, free approximation" of a deep link as
    /i/{code} above, just carrying a title id (and its source — "tmdb" |
    "igdb" | "google_books" | "shikimori_manga", same values
    /media/detail's own `source` query param takes) instead of a
    referral code. No DB lookup: the client already has everything this
    page's copy and the eventual in-app route need, so there's nothing
    here worth a query.

    `source` used to be missing from this link entirely — `id` alone
    (e.g. "tmdb-603") looks like it encodes the source as a prefix, but
    that's an implementation detail of a couple of adapters, not
    something worth parsing back out client-side when the sender already
    has the real value sitting on the MediaItem. Defaults to "tmdb" only
    so an old cached/shared link from before this param existed still
    resolves to something plausible rather than 400ing outright — new
    links (see title_share.dart) always send it explicitly.
    """
    play_url = "https://play.google.com/store/apps/details"
    if settings.play_store_package:
        play_url += f"?id={settings.play_store_package}"

    app_store_url = (
        f"https://apps.apple.com/app/id{settings.ios_app_store_id}"
        if settings.ios_app_store_id else None
    )

    heading = f"«{title}» — в Seenly" if title else "Открываем в Seenly"
    # Escaped/encoded up front, before `html` below gets reassigned to
    # the response body string and shadows the `html` module import.
    # id/type/source/title are all plain query params here — nothing
    # stops someone from putting "</script><script>...</script>" in
    # `title` and sharing that /t?... link as if it were an ordinary
    # shared title (this endpoint needs no login and does no DB lookup
    # to reach), so every one of them needs escaping for the context it
    # actually lands in below — HTML text/attribute vs. JS string
    # literal aren't the same escaping, so each gets its own safe form.
    heading_safe = html.escape(heading)
    play_url_attr = html.escape(play_url)
    play_url_js = _js_string(play_url)
    app_store_url_js = _js_string(app_store_url or "")
    type_js = _js_string(type)
    id_js = _js_string(id)
    source_js = _js_string(source)

    page_html = f"""<!doctype html>
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
  <h1>{heading_safe}</h1>
  <p>Открываем приложение…</p>
  <a class="btn" id="fallback-link" href="{play_url_attr}">Установить / открыть</a>

<script>
  var scheme = "{settings.app_custom_scheme}://title?type=" + encodeURIComponent({type_js}) + "&id=" + encodeURIComponent({id_js}) + "&source=" + encodeURIComponent({source_js});
  var ua = navigator.userAgent || "";
  var isIOS = /iPhone|iPad|iPod/i.test(ua);

  function goStore() {{
    if (isIOS && {"true" if app_store_url else "false"}) {{
      window.location.href = {app_store_url_js};
    }} else {{
      window.location.href = {play_url_js};
    }}
  }}

  // Same "try the app, then fall back to a store after a beat" trick
  // as /i/{{code}} above.
  window.location.href = scheme;
  setTimeout(goStore, 1200);
</script>
</body>
</html>"""
    return HTMLResponse(page_html)


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
    tap falls back to the /i/{code} or /t page's own JS redirect
    instead.
    "/t*" (not just the exact "/t") because a real shared-title link
    always carries a query string ("/t?type=...&id=...&source=..."),
    and Apple's own path-matching treats the query string as part of
    what "/t" alone would need to match exactly.

    An empty `details` list — not a placeholder like
    "TEAMID.com.example.seenly" — is what "unconfigured" looks like on
    the wire here, mirroring android_assetlinks()'s empty fingerprint
    list just above. A fabricated appID fails Apple's verification no
    differently, but it *reads* like a real (if broken) setup to anyone
    inspecting the response later, including whoever eventually fills
    in Settings.ios_app_id and then can't tell whether a stale response
    they're still seeing is Apple's own AASA cache or a leftover bug."""
    if not settings.ios_app_id:
        return JSONResponse({"applinks": {"apps": [], "details": []}})
    return JSONResponse({
        "applinks": {
            "apps": [],
            "details": [
                {"appID": settings.ios_app_id, "paths": ["/i/*", "/t*"]}
            ],
        }
    })


# ---------------------------------------------------------------------------
# Account-recovery landing pages
#
# The two links app/mailer.py sends point here. Both pages do the same
# two things in the same order, and the order is the point:
#
#   1. Try to hand off to the app, which is where the person actually
#      wants to end up — it can sign them straight in afterwards, and the
#      reset form there is the one they'll recognise.
#   2. Fall back to doing the job in the browser, because plenty of people
#      open mail on a laptop where the app isn't installed at all. A
#      recovery flow that only works on the phone has a hole in it on
#      exactly the setups most likely to need it.
#
# Both call the same API this server already exposes (POST
# /auth/password/reset, POST /auth/email/verify) with fetch, rather than
# duplicating any logic here. These pages are a form and a fetch call;
# every rule about token expiry, single use, and session revocation lives
# in routers/auth.py and is enforced there regardless of which client
# calls it.
# ---------------------------------------------------------------------------

_RECOVERY_PAGE_CSS = """
:root{--bg:#fbf7f2;--paper:#fff;--ink:#2e2a26;--muted:#8a8078;--accent:#c4756a;--border:#eee6dc}
@media(prefers-color-scheme:dark){:root{--bg:#171513;--paper:#211e1b;--ink:#e8e2da;--muted:#9a9089;--border:#2e2a26}}
*{box-sizing:border-box}
body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
background:var(--bg);color:var(--ink);padding:1.5rem;
font:16px/1.6 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif}
.card{background:var(--paper);border-radius:16px;padding:2rem;max-width:26rem;width:100%}
h1{font-size:1.35rem;margin:0 0 .35rem}
p{color:var(--muted);font-size:.9rem;margin:0 0 1.25rem}
label{display:block;font-size:.75rem;color:var(--muted);margin:0 0 .35rem;
letter-spacing:.04em;text-transform:lowercase}
input{width:100%;padding:.75rem .9rem;margin-bottom:1rem;border:1px solid var(--border);
border-radius:10px;background:var(--bg);color:var(--ink);font-size:1rem}
button{width:100%;padding:.85rem;border:0;border-radius:10px;background:var(--accent);
color:#fff;font-size:.95rem;cursor:pointer}
button:disabled{opacity:.55;cursor:default}
.msg{font-size:.85rem;margin-top:1rem;min-height:1.2rem}
.msg.err{color:var(--accent)}
.open-app{display:block;text-align:center;margin-top:1.1rem;font-size:.8rem;color:var(--accent)}
"""


def _recovery_page(title: str, body_html: str, script: str) -> HTMLResponse:
    return HTMLResponse(
        "<!doctype html><html><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        f"<title>{title}</title><style>{_RECOVERY_PAGE_CSS}</style></head>"
        f"<body><div class='card'>{body_html}</div><script>{script}</script></body></html>"
    )


@router.get("/reset-password", response_class=HTMLResponse)
def reset_password_page(token: str = ""):
    """Where a password-reset email lands.

    The token is read from the query string by the page's own script and
    never rendered into the HTML — it goes straight into the fetch body.
    That keeps it out of anything that scrapes page text, and out of the
    `Referer` header sent to any resource the page loads (there aren't
    any, but that's a property worth not depending on).
    """
    scheme = settings.app_custom_scheme or "seenly"
    body = """
      <h1>set a new password</h1>
      <p>choose something you'll remember. this signs you out on every
      device — you'll sign in again with the new one.</p>
      <label for='pw'>new password</label>
      <input id='pw' type='password' autocomplete='new-password'>
      <label for='pw2'>repeat it</label>
      <input id='pw2' type='password' autocomplete='new-password'>
      <button id='go'>save the new password</button>
      <div class='msg' id='msg'></div>
      <a class='open-app' id='app' href='#'>open in the tanè app instead</a>
    """
    script = f"""
      const token = new URLSearchParams(location.search).get('token') || '';
      document.getElementById('app').href =
        {_js_string(scheme)} + '://reset-password?token=' + encodeURIComponent(token);
      const msg = document.getElementById('msg');
      const go = document.getElementById('go');
      go.onclick = async () => {{
        const pw = document.getElementById('pw').value;
        const pw2 = document.getElementById('pw2').value;
        msg.className = 'msg';
        if (pw.length < 6) {{ msg.className = 'msg err';
          msg.textContent = 'password needs at least 6 characters'; return; }}
        if (pw !== pw2) {{ msg.className = 'msg err';
          msg.textContent = "the two passwords don't match"; return; }}
        go.disabled = true;
        try {{
          const res = await fetch('/auth/password/reset', {{
            method: 'POST', headers: {{'Content-Type': 'application/json'}},
            body: JSON.stringify({{token: token, new_password: pw}}),
          }});
          const data = await res.json();
          if (res.ok) {{
            msg.textContent = data.message;
            go.style.display = 'none';
          }} else {{
            msg.className = 'msg err';
            msg.textContent = data.detail || 'that link is no longer valid';
            go.disabled = false;
          }}
        }} catch (e) {{
          msg.className = 'msg err';
          msg.textContent = 'could not reach the server — try again';
          go.disabled = false;
        }}
      }};
    """
    return _recovery_page("tanè — set a new password", body, script)


@router.get("/verify-email", response_class=HTMLResponse)
def verify_email_page(token: str = ""):
    """Where an address-confirmation email lands.

    Confirms on page load rather than behind a button. The one-time token
    is already in the URL, so a click adds no security and one more step
    between someone and a working recovery address is one more place to
    lose them. The POST is still a POST — see routers/auth.py's note on
    why verification isn't a GET: a mail scanner that follows every link
    would otherwise burn the token before the person ever opened it.
    """
    body = """
      <h1>confirming your address…</h1>
      <p id='sub'>one moment.</p>
      <div class='msg' id='msg'></div>
    """
    script = """
      const token = new URLSearchParams(location.search).get('token') || '';
      const msg = document.getElementById('msg');
      const sub = document.getElementById('sub');
      (async () => {
        try {
          const res = await fetch('/auth/email/verify', {
            method: 'POST', headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({token: token}),
          });
          const data = await res.json();
          document.querySelector('h1').textContent =
            res.ok ? 'all set' : "that link didn't work";
          sub.textContent = res.ok ? (data.message || '')
            : (data.detail || 'request a fresh link from the app');
          if (!res.ok) msg.className = 'msg err';
        } catch (e) {
          document.querySelector('h1').textContent = 'could not reach the server';
          sub.textContent = 'try opening the link again in a moment';
        }
      })();
    """
    return _recovery_page("tanè — confirm your email", body, script)
