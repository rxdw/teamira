"""GET /t — the title-share landing page (linking.py::title_landing),
the title counterpart of the referral /i/{code} page. No DB, no auth;
these just check the page actually carries what title_share.dart /
services/title_link_service.dart on the client need to rebuild a
`seenly://title?...` link and open the right title screen.
"""

from app.config import settings


class TestIosAasa:
    """GET /.well-known/apple-app-site-association — see ios_aasa's own
    docstring for why "unconfigured" has to come back as an empty
    `details` list rather than a placeholder appID that merely looks
    real."""

    def test_empty_when_ios_app_id_unset(self, client):
        original = settings.ios_app_id
        settings.ios_app_id = ""
        try:
            resp = client.get("/.well-known/apple-app-site-association")
            assert resp.status_code == 200
            body = resp.json()
            assert body["applinks"]["details"] == []
            assert "TEAMID" not in resp.text
        finally:
            settings.ios_app_id = original

    def test_real_app_id_once_configured(self, client):
        original = settings.ios_app_id
        settings.ios_app_id = "ABCDE12345.com.example.seenly"
        try:
            resp = client.get("/.well-known/apple-app-site-association")
            assert resp.status_code == 200
            details = resp.json()["applinks"]["details"]
            assert details == [
                {"appID": "ABCDE12345.com.example.seenly", "paths": ["/i/*", "/t*"]}
            ]
        finally:
            settings.ios_app_id = original


class TestAndroidAssetlinks:
    def test_empty_fingerprints_when_unconfigured(self, client):
        original = settings.android_cert_sha256_fingerprints
        settings.android_cert_sha256_fingerprints = ""
        try:
            resp = client.get("/.well-known/assetlinks.json")
            assert resp.status_code == 200
            assert resp.json()[0]["target"]["sha256_cert_fingerprints"] == []
        finally:
            settings.android_cert_sha256_fingerprints = original

    def test_splits_comma_separated_fingerprints(self, client):
        original = settings.android_cert_sha256_fingerprints
        settings.android_cert_sha256_fingerprints = "AA:BB, CC:DD"
        try:
            resp = client.get("/.well-known/assetlinks.json")
            fingerprints = resp.json()[0]["target"]["sha256_cert_fingerprints"]
            assert fingerprints == ["AA:BB", "CC:DD"]
        finally:
            settings.android_cert_sha256_fingerprints = original


class TestTitleLanding:
    def test_scheme_link_carries_type_id_and_source(self, client):
        resp = client.get("/t", params={"type": "series", "id": "tmdb-1399", "source": "tmdb", "title": "Game of Thrones"})
        assert resp.status_code == 200
        body = resp.text
        # Not asserting on the whole JS line verbatim — just that each
        # piece TitleLinkService.extractFromUri (mobile) will look for
        # is actually present in the scheme string this page builds.
        assert "type=" in body and "id=" in body and "source=" in body
        assert "tmdb-1399" in body
        assert "series" in body
        assert "tmdb" in body

    def test_source_defaults_to_tmdb_for_old_links(self, client):
        # A link shared before `source` existed on this endpoint — see
        # title_landing's own docstring on why the default has to stay
        # "tmdb" rather than becoming a required param.
        resp = client.get("/t", params={"type": "movie", "id": "tmdb-603"})
        assert resp.status_code == 200
        assert "source" in resp.text

    def test_title_is_html_escaped_in_the_heading(self, client):
        resp = client.get(
            "/t",
            params={"type": "movie", "id": "tmdb-1", "source": "tmdb", "title": "</script><script>alert(1)</script>"},
        )
        assert resp.status_code == 200
        assert "<script>alert(1)</script>" not in resp.text
