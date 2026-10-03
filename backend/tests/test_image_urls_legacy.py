"""resolve_image_url() heals legacy baked-in TMDB image URLs.

Old rows (daily feed snapshots, forever caches, diary/watchlist) can hold a
full image URL instead of a bare TMDB path: a direct image.tmdb.org link, or a
link through an older proxy base / an expired signature. Those have to be
re-issued against the *current* PUBLIC_API_BASE_URL, otherwise posters stay
broken even after the setting is right (search works, because fresh results
store bare paths).
"""
from __future__ import annotations

from urllib.parse import parse_qs, quote, urlparse

import pytest

from app import image_urls
from app.config import settings
from app.image_urls import TMDB_POSTER_BASE, resolve_image_url, verify_proxy_signature

NEW_BASE = "http://192.168.1.33:8000"
CDN = "https://image.tmdb.org/t/p/w500/abc.jpg"


@pytest.fixture(autouse=True)
def _proxy_on(monkeypatch):
    monkeypatch.setattr(settings, "public_api_base_url", NEW_BASE)


def _inner(proxied: str) -> str:
    return parse_qs(urlparse(proxied).query)["url"][0]


def test_bare_path_is_proxied_as_before():
    out = resolve_image_url("/abc.jpg", TMDB_POSTER_BASE)
    assert out.startswith(f"{NEW_BASE}/media/image-proxy?")
    assert _inner(out) == CDN


def test_direct_cdn_link_is_re_proxied():
    out = resolve_image_url(CDN, TMDB_POSTER_BASE)
    assert out.startswith(f"{NEW_BASE}/media/image-proxy?")
    assert _inner(out) == CDN


def test_old_base_and_expired_signature_are_replaced():
    stale = f"http://10.0.0.5:8000/media/image-proxy?url={quote(CDN, safe='')}&exp=1&sig=deadbeef"
    out = resolve_image_url(stale, TMDB_POSTER_BASE)
    assert out.startswith(f"{NEW_BASE}/media/image-proxy?")
    q = parse_qs(urlparse(out).query)
    assert verify_proxy_signature(q["url"][0], int(q["exp"][0]), q["sig"][0])


def test_result_is_stable_so_the_client_image_cache_keeps_hitting():
    first = resolve_image_url(CDN, TMDB_POSTER_BASE)
    assert resolve_image_url(first, TMDB_POSTER_BASE) == first


def test_without_a_proxy_a_stale_proxy_link_falls_back_to_the_cdn(monkeypatch):
    monkeypatch.setattr(settings, "public_api_base_url", "")
    stale = f"http://10.0.0.5:8000/media/image-proxy?url={quote(CDN, safe='')}&exp=1&sig=x"
    assert resolve_image_url(stale, TMDB_POSTER_BASE) == CDN


@pytest.mark.parametrize(
    "foreign",
    [
        "https://images.igdb.com/igdb/image/upload/t_cover_big/x.jpg",
        "https://covers.openlibrary.org/b/id/1-L.jpg",
        "https://i.ytimg.com/vi/x/hqdefault.jpg",
        f"{NEW_BASE}/media/image-proxy?url={quote('https://evil.example/x.jpg', safe='')}&exp=1&sig=x",
    ],
)
def test_other_sources_are_left_untouched(foreign):
    assert resolve_image_url(foreign, TMDB_POSTER_BASE) == foreign


def test_empty_values_pass_through():
    assert resolve_image_url(None, TMDB_POSTER_BASE) is None
    assert resolve_image_url("", TMDB_POSTER_BASE) == ""
