from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # Purely a self-declaration the app trusts, not something it infers
    # from hostname/DEBUG flags/etc. Defaults to "development" so the
    # zero-config local-dev experience the rest of this file's defaults
    # are built around is completely untouched unless someone opts in.
    # The only thing this currently gates is on_startup's insecure-
    # defaults check in main.py: set ENVIRONMENT=production there and a
    # leftover jwt_secret="change-me" or EMAIL_BACKEND!=smtp refuses to
    # boot instead of just logging critical. See that check for why a
    # log-only warning isn't enough on its own.
    environment: str = "development"
    database_url: str = "postgresql+psycopg2://seenly:seenly@db:5432/seenly"
    jwt_secret: str = "change-me"
    jwt_algorithm: str = "HS256"
    # Access-token lifetime. Was 60 * 24 * 7 — a full week — because
    # there was no refresh path and a short-lived token would simply have
    # thrown people out. Now that POST /auth/refresh exists and the
    # mobile client refreshes transparently on a 401 (see
    # api_client.dart), this can be what an access token is supposed to
    # be: short enough that a leaked one is a small window, long enough
    # that a normal session isn't refreshing constantly.
    jwt_expire_minutes: int = 30
    # How long a signed-in device stays signed in without ever entering a
    # password again. Rotated on every use, so this is a sliding window
    # in practice, not a hard 60-day clock from first login — see
    # models.RefreshSession.
    refresh_token_days: int = 60
    # How many devices one account can be signed in on at once. The
    # oldest session is revoked when a new login pushes past this,
    # which keeps refresh_sessions from growing without bound for
    # someone who reinstalls the app weekly.
    max_sessions_per_user: int = 10

    # --- Email (account recovery) -----------------------------------------
    # "console" logs the message to the uvicorn log instead of sending
    # it — zero-config local development, and a hard leak in production,
    # which is why routers/auth.py refuses to return a reset link in a
    # response body unless this is console. Set to "smtp" and fill in the
    # host below for a real deployment; see app/mailer.py.
    email_backend: str = "console"
    email_from: str = "tanè <no-reply@localhost>"
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_username: str = ""
    smtp_password: str = ""
    smtp_use_tls: bool = True
    smtp_use_ssl: bool = False
    # How long a password-reset link stays usable. Short on purpose:
    # long enough to walk to a computer, short enough that a link sitting
    # in an abandoned mailbox isn't a standing key to the account.
    password_reset_ttl_minutes: int = 60
    email_verify_ttl_minutes: int = 60 * 24

    # --- Account deletion --------------------------------------------------
    # The grace period between "delete my account" and the rows actually
    # being destroyed. Long enough to undo a decision made at 2am, short
    # enough to be an honest answer to "delete my data" under GDPR art.
    # 17 and 152-ФЗ — both of which allow a reasonable operational delay,
    # neither of which allows indefinite retention. The account is
    # invisible to everyone from the moment of the request; this only
    # governs when the rows go. See app/account_deletion.py.
    account_purge_after_days: int = 30
    # Whether the purge job runs from this process's own startup. Leave
    # on for a single-container deployment; turn off and run
    # scripts/purge_deleted_accounts.py from cron if you'd rather it be
    # a scheduled job with its own logs and alerting.
    purge_on_startup: bool = True

    # --- Moderation (App Store guideline 1.2) ------------------------------
    # Apple asks for objectionable content to be acted on within 24
    # hours. This is what models.Report.due_at is computed from and what
    # the admin queue sorts and flags against, so the commitment is
    # visible in the product rather than living in someone's head.
    report_sla_hours: int = 24
    # Bumped whenever the EULA text in app/legal_texts.py changes in a
    # way that needs re-acceptance. Compared against
    # models.User.eula_version; a mismatch makes the client show the
    # agreement again.
    eula_version: str = "2026-09-01"
    # Same idea as eula_version, but nothing gates on this one — the
    # privacy policy is published, not accepted, so there's no
    # models.User column tracking it. It exists purely so the document
    # itself (app/legal_texts.py::privacy_policy_for) can show which
    # version someone is reading, same as the EULA does.
    privacy_policy_version: str = "2026-09-01"
    # One term per line, '#' comments allowed — see app/content_filter.py
    # for why the list lives in a file the deployment supplies rather
    # than in this repository. Empty/missing means the structural checks
    # (invisible characters, links and contact handles in a nickname,
    # character walls) run on their own, which is still most of the
    # anti-spam value.
    content_blocklist_path: str = ""
    # Shown in-app and required by App Store review as published contact
    # information for content complaints. Leave empty and the support
    # screen simply points at the in-app report flow instead.
    moderation_contact_email: str = ""

    # Comma-separated list of origins the browser-facing bits of this
    # API (mainly linking.py's landing pages) may be fetched from —
    # mobile's own native HTTP calls aren't subject to CORS at all, so
    # this only matters for anything actually loaded in a browser.
    # "*" is fine paired with allow_credentials=False (see main.py) for
    # local development; set this to the real site(s) before serving
    # any credentialed browser request in production.
    cors_allow_origins: str = "*"

    # Comma-separated IPs/CIDRs of reverse proxies this backend trusts to
    # set X-Forwarded-For truthfully — e.g. "127.0.0.1,10.0.0.0/8" for an
    # nginx/load balancer on the same host or Docker network. Empty (the
    # default) means none: app/rate_limit.py::client_key ignores
    # X-Forwarded-For entirely and uses the TCP peer address, which is
    # correct as long as nothing sits between this app and the internet
    # (today's docker-compose.yml exposes the api container's port
    # directly — no proxy in front yet). The moment a real reverse proxy
    # or TLS terminator is added in front of this app (see the docker-
    # compose.prod.yml audit finding), request.client.host becomes that
    # proxy's own address for every request, and every caller shares one
    # rate-limit bucket, unless this is set to that proxy's address —
    # set it then, not before: trusting X-Forwarded-For from a source
    # this app can't actually verify is worse than not trusting it at
    # all, since it turns rate limiting into something any caller can
    # bypass just by setting the header themselves.
    trusted_proxy_ips: str = ""

    igdb_client_id: str = ""
    igdb_client_secret: str = ""
    # Books run on Google Books (developers.google.com/books) — see
    # app/adapters/google_books.py's module docstring. Optional: an empty
    # key just means requests go out on Google's shared anonymous quota
    # (1,000/day per IP) instead of a raised one — get a free key at
    # console.cloud.google.com (enable "Books API") for anything beyond
    # local dev.
    google_books_api_key: str = ""

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

    # Unused — kept only so an existing .env that still sets
    # TEAMIRA_ADMIN_KEY (from before Teamira-picks admin access moved to
    # User.is_admin + normal JWT login, see app/deps.py::require_admin_user
    # and scripts/grant_admin.py) doesn't crash Settings() at startup.
    # SettingsConfigDict has no explicit `extra=` here, and pydantic-
    # settings' actual default is "forbid" — removing this field outright
    # makes every route fail at import time for anyone with the old key
    # still in their .env, not harmlessly ignore the stray var. Safe to
    # delete once you've confirmed no deployed .env references it anymore.
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

    # This API's own public base URL, e.g. "https://api.yourdomain.com" —
    # used ONLY to build image-proxy URLs (see routers/image_proxy.py and
    # adapters/tmdb.py::_proxied) that point back at this same server,
    # for image CDNs blocked in some regions (image.tmdb.org is blocked
    # by some ISPs in Russia, for example) where a phone can reach this
    # API directly but can't reach the CDN directly. Empty (the default)
    # means poster/backdrop/profile URLs stay exactly what they've always
    # been — a direct link to the CDN — so nothing changes for anyone who
    # hasn't set this up, and no image traffic flows through this server
    # unless it's deliberately turned on.
    public_api_base_url: str = ""

    # Signs the `sig`/`exp` query params app/image_urls.py::_proxied adds
    # to every /media/image-proxy URL it builds, so that endpoint can stay
    # unauthenticated (it has to — it's loaded directly by the client's
    # image widget, e.g. Flutter's Image.network, which can't attach an
    # Authorization header) while still not being an open proxy anyone who
    # finds the server's address can point at arbitrary TMDB image paths.
    # Empty (the default) falls back to jwt_secret in app/image_urls.py
    # rather than leaving image-proxy unsigned — set a distinct value in
    # production so rotating one secret doesn't also invalidate every
    # logged-in session's tokens.
    image_proxy_secret: str = ""

    # Cap on app/routers/image_proxy.py's on-disk cache, in bytes. That
    # cache never expires an entry on its own — a TMDB image path never
    # changes once published, so "cached forever" was the whole point —
    # which means nothing ever shrinks it, and it grows for as long as
    # the catalog does. 2 GiB is comfortably more than a single-region
    # deployment's poster/backdrop set is likely to reach for a while;
    # raise it if disk is cheap and cache misses (a redeploy without a
    # persistent volume, a fresh replica) are the thing worth avoiding.
    image_proxy_cache_max_bytes: int = 2 * 1024 * 1024 * 1024

    # Where uploaded avatars (routers/profile.py::upload_avatar) actually
    # live — see app/storage.py for the two backends this selects
    # between and why local disk was never going to survive real
    # deployment. "local" (the default) keeps today's behavior exactly:
    # plain files under this container's own uploads/ directory, fine
    # for local dev and a single long-lived container, silently loses
    # avatars the moment there's more than one API replica (each with
    # its own disk) or a redeploy without a persistent volume. Set to
    # "s3" to write through to any S3-compatible bucket instead — AWS
    # S3 itself, or a self-hosted/compatible one (MinIO, Cloudflare R2,
    # DigitalOcean Spaces, Backblaze B2's S3 API) — which is what makes
    # this stateless-safe: any replica can serve any avatar, because
    # none of them are the one holding the only copy.
    avatar_storage_backend: str = "local"
    # Required when avatar_storage_backend="s3". s3_endpoint_url stays
    # empty for real AWS S3 (boto3 already knows AWS's endpoints from
    # s3_region alone) and only needs setting for an S3-compatible
    # service with its own endpoint (e.g. MinIO's
    # "http://minio:9000", R2's "https://<account>.r2.cloudflarestorage.com").
    s3_bucket: str = ""
    s3_region: str = "auto"
    s3_endpoint_url: str = ""
    s3_access_key_id: str = ""
    s3_secret_access_key: str = ""
    # What upload_avatar hands back as avatar_url once a file lands in
    # the bucket — the bucket's own public base URL (a CDN domain in
    # front of it, a public R2/Spaces URL, S3's own virtual-hosted-style
    # URL). Required when avatar_storage_backend="s3": unlike the local
    # backend (whose /static/avatars/... path is always the same,
    # served by this API itself), there's no one right way to derive a
    # public URL from a bucket name across every S3-compatible provider,
    # so this asks for it directly rather than guessing.
    s3_public_base_url: str = ""

    # --- Observability -------------------------------------------------
    #
    # Empty (the default) disables Sentry entirely — sentry_sdk.init()
    # with dsn="" is itself a documented no-op, not something this app
    # has to special-case. Set this to a real DSN in any environment
    # where "a request 500'd at 3am" should page someone instead of
    # scrolling past in a log nobody's watching.
    sentry_dsn: str = ""
    # Sentry's own grouping/filtering key for "which deployment sent
    # this" — separate from anything else in this file since it's purely
    # a Sentry-side label, not a value this app's own code branches on
    # anywhere.
    sentry_environment: str = "development"
    # Fraction of requests Sentry also captures full performance traces
    # for, independent of error reporting (errors are always captured
    # regardless of this). 0.0 (the default) means tracing is off and
    # only errors are sent — reasonable to start with, since traces are
    # the part of a Sentry bill that scales with traffic rather than
    # with how often something actually breaks.
    sentry_traces_sample_rate: float = 0.0

    # "text" (the default) leaves logging exactly as it's always been —
    # uvicorn's own readable, colored console output, nothing in this
    # app touches it. "json" reconfigures every logger this app and
    # uvicorn itself use to instead emit one JSON object per line
    # (timestamp, level, logger name, message, exception if any) — see
    # app/logging_config.py. Meant for a deployment whose logs go
    # somewhere that parses structure out of them (CloudWatch, Datadog,
    # an ELK stack) rather than a terminal a person is reading directly;
    # local development has no reason to want this.
    log_format: str = "text"

    # --- Product analytics ---------------------------------------------
    #
    # First-party: the mobile app batches events to POST /analytics/events
    # and they land in the `analytics_events` table (see
    # app/routers/analytics.py and docs/analytics.md). False turns the
    # endpoint into a no-op that still answers 202, so an app that is
    # already out in the world doesn't start retrying because someone
    # flipped this switch on the server.
    analytics_enabled: bool = True
    # Rows older than this are deleted by the housekeeping sweep
    # (app/account_deletion.py::sweep_expired_artifacts — runs at startup
    # when PURGE_ON_STARTUP=true, or from scripts/purge_deleted_accounts.py).
    # 0 keeps everything forever, which is fine for a small app and a bad
    # idea for a big one: this is the fastest-growing table in the schema.
    analytics_retention_days: int = 400

    # --- Push notifications (app/push.py) -------------------------------
    #
    # The full JSON contents of a Firebase service-account key file (the
    # thing Firebase's console downloads as "generate new private key"),
    # not a path — this app already reads every other secret straight
    # from an env var/`.env`, so a push credential shouldn't be the one
    # exception that expects a file to exist on whatever machine runs
    # this. Empty (the default) disables push entirely:
    # app/push.py::PushService checks this before importing
    # firebase_admin at all, the same lazy-import-only-if-configured
    # pattern app/storage.py uses for boto3 — a deployment that never
    # sets this never needs firebase-admin installed to actually work,
    # only present in requirements.txt.
    firebase_credentials_json: str = ""

    # --- Voice for co-view rooms (LiveKit, self-hosted) --------------------
    # Audio only, free for everyone. Empty url/key/secret means "voice isn't
    # set up here": rooms still work with chat and reactions, and the
    # voice-token endpoint answers 503. See docs/co_view_rooms_voice.md.
    livekit_url: str = ""  # wss://rtc.example.com
    livekit_api_key: str = ""
    livekit_api_secret: str = ""


    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False)


settings = Settings()
