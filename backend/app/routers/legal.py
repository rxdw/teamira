"""Serves the EULA, the privacy policy, and the moderation contact
details.

Public and unauthenticated on purpose: App Store review reads these
before there's an account to read them with, and the sign-up screen has
to show the agreement *before* someone agrees to it. The privacy policy
in particular has to be reachable with no account at all — that's the
URL App Store Connect's own listing asks for.

Two representations of each text — JSON for the app, HTML for a
browser — because the App Store listing needs a URL a reviewer can open,
and Markdown rendered as text/plain in a browser is not that.
"""

from fastapi import APIRouter, Query
from fastapi.responses import HTMLResponse

from app.config import settings
from app.legal_texts import eula_for, privacy_policy_for

router = APIRouter(prefix="/legal", tags=["legal"])


@router.get("/eula")
def get_eula(lang: str = Query("en")):
    """Markdown, plus the version string the client stores against the
    account once accepted (see POST /auth/eula)."""
    return {
        "version": settings.eula_version,
        "lang": "ru" if lang.lower().startswith("ru") else "en",
        "markdown": eula_for(lang),
        "contact_email": settings.moderation_contact_email or None,
    }


@router.get("/eula.html", response_class=HTMLResponse)
def get_eula_html(lang: str = Query("en")):
    """A plain, readable page for the App Store listing's "Licence
    Agreement" URL."""
    return _render_html(eula_for(lang), title="tanè — Terms of Use")


@router.get("/privacy")
def get_privacy_policy(lang: str = Query("en")):
    """Markdown version of the privacy policy — read-only, nothing to
    accept (unlike /eula, there's no models.User column tracking
    whether someone has seen this one)."""
    return {
        "version": settings.privacy_policy_version,
        "lang": "ru" if lang.lower().startswith("ru") else "en",
        "markdown": privacy_policy_for(lang),
        "contact_email": settings.moderation_contact_email or None,
    }


@router.get("/privacy.html", response_class=HTMLResponse)
def get_privacy_policy_html(lang: str = Query("en")):
    """A plain, readable page for the App Store/Play Store listing's
    "Privacy Policy" URL — both stores require one reachable without
    signing in."""
    return _render_html(privacy_policy_for(lang), title="tanè — Privacy Policy")


def _render_html(body: str, *, title: str) -> HTMLResponse:
    """Shared renderer behind both /eula.html and /privacy.html.
    Deliberately one self-contained page with no assets: it has to
    render from a fresh container with nothing else deployed.

    Minimal Markdown handling — headings, bullets, bold and paragraphs
    are all either document uses. A Markdown library would be a
    dependency added for two endpoints.
    """
    lines = []
    in_list = False
    for raw in body.splitlines():
        line = raw.rstrip()
        if line.startswith("- "):
            if not in_list:
                lines.append("<ul>")
                in_list = True
            lines.append(f"<li>{_inline(line[2:])}</li>")
            continue
        if in_list:
            lines.append("</ul>")
            in_list = False
        if line.startswith("## "):
            lines.append(f"<h2>{_inline(line[3:])}</h2>")
        elif line.startswith("# "):
            lines.append(f"<h1>{_inline(line[2:])}</h1>")
        elif line.startswith("_") and line.endswith("_") and len(line) > 2:
            lines.append(f"<p class='meta'>{_inline(line[1:-1])}</p>")
        elif line:
            lines.append(f"<p>{_inline(line)}</p>")
    if in_list:
        lines.append("</ul>")

    return HTMLResponse(
        "<!doctype html><html><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        f"<title>{title}</title><style>"
        "body{max-width:42rem;margin:3rem auto;padding:0 1.25rem;"
        "font:16px/1.65 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;"
        "color:#2e2a26;background:#fbf7f2}"
        "h1{font-size:1.6rem;margin-bottom:.25rem}h2{font-size:1.1rem;margin-top:2rem}"
        ".meta{color:#8a8078;font-size:.85rem;margin-top:0}"
        "li{margin:.3rem 0}strong{color:#1f1b18}"
        "@media(prefers-color-scheme:dark){body{background:#171513;color:#e8e2da}"
        "strong{color:#fff}.meta{color:#9a9089}}"
        "</style></head><body>" + "\n".join(lines) + "</body></html>"
    )


def _inline(text: str) -> str:
    escaped = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    parts = escaped.split("**")
    return "".join(
        f"<strong>{p}</strong>" if i % 2 else p for i, p in enumerate(parts)
    )
