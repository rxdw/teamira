from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str = "postgresql+psycopg2://seenly:seenly@db:5432/seenly"
    jwt_secret: str = "change-me"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60 * 24 * 7

    igdb_client_id: str = ""
    igdb_client_secret: str = ""
    # Books run on Open Library (openlibrary.org) — no key of any kind, so
    # there's nothing to configure here.

    # "Where to watch" (see app/adapters/tmdb.py) — free key from
    # themoviedb.org/settings/api. This is availability data only, not a
    # monetization deal by itself; see app/routers/watch.py's docstring.
    tmdb_api_key: str = ""

    # Second written-reviews source alongside TMDB (see app/adapters/trakt.py
    # and app/routers/reviews.py) — free app-level Client ID from
    # https://app.trakt.tv/settings/apps/api, no OAuth needed for these
    # read-only calls. Empty means reviews just fall back to TMDB-only.
    trakt_client_id: str = ""

    # "Your sources" (app/adapters/youtube.py, app/routers/sources.py) —
    # link-based import of public YouTube playlists/channels/videos.
    # Read-only, app-level key from console.cloud.google.com (enable
    # "YouTube Data API v3"), no per-user OAuth — same "public data only"
    # shape as tmdb_api_key above. Empty means source imports for YouTube
    # links fail with a clear "not configured" error rather than a silent 500.
    youtube_api_key: str = ""

    # Twitch half of "your sources" (app/adapters/twitch.py) — a Twitch
    # "application" (dev.twitch.tv/console/apps) gets both of these; the
    # adapter trades them for a short-lived app access token (client
    # credentials grant) itself, so this is still read-only/no per-user
    # login, just two values instead of tmdb's one.
    twitch_client_id: str = ""
    twitch_client_secret: str = ""

    # Shared secret for the Teamira-picks admin endpoints (app/routers/teamira.py)
    # — there's no user-role/admin-flag system in this app, so a single header
    # key is the whole auth story here. Empty means the admin endpoints always
    # reject (see app/deps.py::require_teamira_admin), never "open by accident".
    teamira_admin_key: str = ""

    # Referral links (routers/linking.py) — the no-external-service
    # "compromise" version: GET /i/{code} tries the app's own custom
    # scheme first, and falls back to whichever store link it has. These
    # start empty/placeholder on purpose (this app has no real store
    # listing yet); the landing page still works with them empty, it
    # just has nowhere useful to send someone who doesn't have the app.
    app_custom_scheme: str = "seenly"
    play_store_package: str = ""       # e.g. "com.example.seenly"
    ios_app_store_id: str = ""         # numeric App Store id, once published
    # Android App Links (assetlinks.json) needs the release signing
    # cert's SHA-256 fingerprint — `keytool -list -v -keystore
    # your.keystore` — to prove this domain and that APK are the same
    # people. Comma-separated if you sign with more than one cert
    # (debug + release) during development.
    android_cert_sha256_fingerprints: str = ""
    # iOS Universal Links (apple-app-site-association) needs the Apple
    # Team ID + bundle id together as "TEAMID.bundle.id".
    ios_app_id: str = ""
    # The domain GET /friends/invite's share_text points people at
    # (routers/linking.py's /i/{code} landing page lives here). Empty
    # means share_text just falls back to a bare code with no link — see
    # routers/friends.py::get_invite.
    public_web_base_url: str = ""

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False)


settings = Settings()
