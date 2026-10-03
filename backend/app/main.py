import asyncio
import logging
import os

import httpx
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import func

from app.config import settings
from app.logging_config import configure_logging
from app.database import Base, SessionLocal, engine
from app.account_deletion import purge_due_accounts, sweep_expired_artifacts
from app.migrate import run_migrations, startup_lock
from app import realtime
from app.routers import auth, media, feed, calendar, ai, activity, profile, diary, progress, lists, together, partner, co_view_vote, co_view_poll, watch, integrations, imports, sources, teamira, reviews, friends, linking, image_proxy, premium, referrals, sincerity, recommendations, watchlist, shared_diary, challenges, card_shares, moderation, legal, analytics, push, pair_album, co_view_room, circle_review
from app.seed import seed_affiliate_providers
from app.seed_teamira_picks import seed_all_shelves as _seed_teamira_shelves

# Before anything else touches logging (including the getLogger call
# right below) — see logging_config.py's own docstring for why this
# specifically has to run at app-module import time, not any earlier or
# later, to correctly override uvicorn's own defaults when
# settings.log_format="json".
configure_logging()

# Sentry next, and still before the app is constructed: an exception
# thrown while building `app` itself (a bad router import, a middleware
# that raises during setup) is exactly the kind of startup failure this
# exists to catch, and sentry_sdk.init() with dsn="" (the default — see
# config.py) is a documented no-op, so this is always safe to call
# unconditionally rather than gating it behind an `if settings.sentry_dsn`.
if settings.sentry_dsn:
    import sentry_sdk

    sentry_sdk.init(
        dsn=settings.sentry_dsn,
        environment=settings.sentry_environment,
        traces_sample_rate=settings.sentry_traces_sample_rate,
        # Defaults left alone deliberately: sentry_sdk's own
        # LoggingIntegration only turns an ERROR-or-above log record (this
        # codebase's `logger.exception(...)` calls, mainly — see e.g.
        # routers/feed.py's own exception handling) into a reported issue;
        # a `logger.warning(...)` for an already-handled, expected
        # condition (most of this codebase's logging) only becomes a
        # breadcrumb attached to some *later* actual issue, not a
        # standalone alert of its own. That split is exactly what's
        # wanted here, so there's nothing to override.
    )

logger = logging.getLogger("uvicorn.error")

app = FastAPI(title="tanè API", version="0.1.0")

# Uploaded avatars, when Settings.avatar_storage_backend="local" (the
# default) — see app/storage.py for that backend and the S3-compatible
# alternative. Served back out at /static/avatars/<file>, which is
# exactly what LocalDiskStorage.save returns and what gets written into
# users.avatar_url. Harmless to still mount this even when the "s3"
# backend is active — it just never gets written to in that case, since
# nothing generates a /static/avatars/... URL anymore.
_UPLOADS_DIR = os.path.join(os.path.dirname(__file__), "..", "uploads")
os.makedirs(os.path.join(_UPLOADS_DIR, "avatars"), exist_ok=True)
app.mount("/static", StaticFiles(directory=_UPLOADS_DIR), name="static")

app.add_middleware(
    CORSMiddleware,
    # See Settings.cors_allow_origins' own docstring — this only ever
    # matters for a browser (native mobile HTTP calls aren't subject to
    # CORS), and nothing this API serves to a browser needs cookies or
    # other credentialed requests (the browser extension in
    # integrations/browser-extension authenticates via a token in the
    # URL path, not a cookie), so allow_credentials stays False even
    # when origins is still the wildcard default — the two together is
    # what browsers actually reject/what makes a wildcard genuinely
    # risky, and this app has no real use for that combination anyway.
    allow_origins=[o.strip() for o in settings.cors_allow_origins.split(",") if o.strip()],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(httpx.HTTPError)
async def httpx_error_handler(request: Request, exc: httpx.HTTPError) -> JSONResponse:
    """A safety net, not the primary error-handling story — most
    adapter code (see app/adapters/) is meant to catch its own
    httpx.HTTPError locally and turn it into something more specific
    (RuntimeError for "not configured", ValueError for "nothing came
    back", a None/empty result for "this is fine, just not found").
    This exists for the calls that don't, so a rate limit or a timeout
    on TMDB/IGDB/YouTube/etc. becomes a clean 502 instead of a bare
    500 with a stack trace in the response. Logged at warning level,
    not error — these are expected to happen sometimes (every adapter
    reaches out to someone else's API) and aren't this server's own
    bug when they do.
    """
    logger.warning("upstream request failed: %s: %s", type(exc).__name__, exc)
    return JSONResponse(
        status_code=502,
        content={"detail": "A service this depends on isn't answering right now — try again in a moment"},
    )

app.include_router(auth.router)
app.include_router(media.router)
app.include_router(feed.router)
app.include_router(calendar.router)
app.include_router(ai.router)
app.include_router(activity.router)
app.include_router(profile.router)
app.include_router(diary.router)
app.include_router(progress.router)
app.include_router(lists.router)
app.include_router(together.router)
app.include_router(partner.router)
app.include_router(co_view_vote.router)
app.include_router(co_view_poll.router)
app.include_router(watch.router)
app.include_router(reviews.router)
app.include_router(integrations.router)
app.include_router(imports.router)
app.include_router(sources.router)
app.include_router(teamira.router)
app.include_router(friends.router)
app.include_router(linking.router)
app.include_router(premium.router)
app.include_router(referrals.router)
app.include_router(image_proxy.router)
app.include_router(sincerity.router)
app.include_router(recommendations.router)
app.include_router(watchlist.router)
# Registered after partner.router on purpose — shared_diary's own prefix
# is "/partner/shared", which is strictly more specific than anything
# partner.py declares, so ordering here is cosmetic rather than load-
# bearing (FastAPI matches on the full path, not on registration order).
# Kept adjacent to it anyway so the two read together.
app.include_router(shared_diary.router)
app.include_router(challenges.router)
app.include_router(card_shares.router)
# Blocking, reporting and the moderator queue — App Store guideline
# 1.2. See routers/moderation.py's module docstring.
app.include_router(moderation.router)
# The EULA, served unauthenticated: App Store review reads it before
# there's an account to read it with, and the sign-up screen has to
# show it before anyone agrees to it.
app.include_router(legal.router)
# Product analytics ingestion — unauthenticated-tolerant by design, see
# routers/analytics.py's module docstring and docs/analytics.md.
app.include_router(analytics.router)
app.include_router(push.router)
app.include_router(pair_album.router)
app.include_router(co_view_room.router)
app.include_router(circle_review.router)


# Schema changes (new columns, indexes, enum values) now go through
# Alembic (see migrations/ and app/migrate.py::run_migrations, called
# from on_startup below) instead of a hand-maintained list of raw ALTER
# TABLE statements re-run on every process boot. See
# migrations/versions/6cea28b2d137's own docstring for the pre-Alembic
# history this replaced, and app/migrate.py's docstring for why running
# it needed a cross-process lock, not just a move to Alembic by itself.

def _consolidate_series_diary_entries(db):
    """One-time cleanup for any database that logged series the old way —
    one diary_entries row per episode/season instead of the single
    per-series row this app now keeps (see models.DiaryEntry's
    docstring). For every (user, title) with more than one such row,
    keeps the most recently watched one and deletes the rest, so old
    installs end up in the same shape a fresh one would.

    Safe to run on every startup: does nothing once a database has
    already been consolidated (the query below only ever finds groups
    with duplicates left). Deliberately leaves the survivor's
    runtime_minutes as-is rather than trying to recompute it here — it
    doesn't have the title's own per-episode runtime handy, and the next
    time this series gets logged, routers/diary.py::log_watched
    recomputes it properly anyway.
    """
    from app.models import DiaryEntry, EpisodeProgress

    groups = (
        db.query(DiaryEntry.user_id, DiaryEntry.media_id, DiaryEntry.source)
        .filter(DiaryEntry.season.isnot(None))
        .group_by(DiaryEntry.user_id, DiaryEntry.media_id, DiaryEntry.source)
        .having(func.count(DiaryEntry.id) > 1)
        .all()
    )
    if not groups:
        return
    for user_id, media_id, source in groups:
        rows = (
            db.query(DiaryEntry)
            .filter(
                DiaryEntry.user_id == user_id,
                DiaryEntry.media_id == media_id,
                DiaryEntry.source == source,
                DiaryEntry.season.isnot(None),
            )
            .order_by(DiaryEntry.watched_at.desc())
            .all()
        )
        survivor, *duplicates = rows
        survivor.episodes_watched = (
            db.query(EpisodeProgress)
            .filter_by(user_id=user_id, source=source, media_id=media_id)
            .count()
        ) or survivor.episodes_watched
        for dup in duplicates:
            db.delete(dup)
    db.commit()


async def _seed_teamira_shelves_background() -> None:
    """Fills in the hand-picked Teamira shelves (see
    app/seed_teamira_picks.py) the first time the backend boots against
    a given database, so Collections -> Teamira picks has something on
    it from day one without anyone having to remember to run that
    script by hand. Kicked off from on_startup as a background task
    (not awaited there) since this makes real network calls out to
    TMDB/IGDB/Open Library to resolve each title — awaiting it inline
    would hold up the app's own startup, and the /health endpoint,
    behind however long that round-trip takes.

    Safe to let run on every single startup: seed_all_shelves reuses an
    existing shelf/item by title rather than duplicating it (see
    _get_or_create_shelf/_seed_shelf), so a database that's already been
    seeded just does a quick set of no-op lookups. A catalog that isn't
    configured (missing TMDB_API_KEY/IGDB_*) only skips that shelf's
    items (logged, not fatal) rather than blocking the others or
    crashing the app.

    A shelf that already carries at least one item per query in its
    picks list (see _seed_shelf's own comment) skips its catalog lookups
    entirely rather than re-resolving every title just to find out it's
    already there — so on a normally-seeded database this really is a
    no-op against TMDB/IGDB/Open Library/Shikimori, not just against the
    database. The one case that still re-queries a shelf on every
    startup is a title that's never matched anything on its catalog
    (typo, not indexed, etc.) — cheap in practice since that's the
    exception, not the rule. TEAMIRA_SEED_ON_STARTUP=false (e.g. in a
    local .env) is still there as a manual override for the rare case
    that's actually a problem — e.g. iterating on a brand new shelf
    that's genuinely still resolving titles on every restart.
    """
    if os.getenv("TEAMIRA_SEED_ON_STARTUP", "true").strip().lower() in ("0", "false", "no"):
        logger.info("teamira shelf seeding skipped (TEAMIRA_SEED_ON_STARTUP=false)")
        return
    db = SessionLocal()
    try:
        await _seed_teamira_shelves(db)
    except Exception:
        logger.exception("teamira shelf seeding failed")
    finally:
        db.close()


def _insecure_defaults(settings_obj) -> list[str]:
    """Return a human-readable problem string for each insecure default
    still in effect on `settings_obj` — currently jwt_secret and
    email_backend, the two that on_startup has always warned about.

    Pulled out of on_startup as its own pure function (reads settings,
    no I/O) so both the "always log these loudly" behavior and the
    "refuse to boot under ENVIRONMENT=production" behavior below can
    share one definition of what counts as insecure, and so the check
    itself is testable without dragging in create_all()/migrations/the
    rest of startup along with it.
    """
    problems = []
    if settings_obj.jwt_secret == "change-me":
        problems.append(
            "jwt_secret is still the default 'change-me' value — every "
            "access token this server issues can be forged. Set a real "
            "JWT_SECRET in .env before this is reachable by anyone but you."
        )
    if settings_obj.email_backend.strip().lower() != "smtp":
        problems.append(
            f"EMAIL_BACKEND is '{settings_obj.email_backend}', not 'smtp' — "
            "password-reset and email-verification links are being written "
            "to this process's log instead of sent. Set EMAIL_BACKEND=smtp "
            "and the SMTP_* settings in .env before this is reachable by "
            "anyone but you."
        )
    return problems


def _enforce_startup_security(settings_obj) -> None:
    """Log, and — under ENVIRONMENT=production — raise on, whatever
    `_insecure_defaults` finds.

    Kept separate from on_startup's body (rather than inlined) so it's
    callable, and testable, without also running create_all()/
    run_migrations()/the seeding+purge block that follows it in
    on_startup — none of that needs to run for this check alone to be
    exercised, and re-running it per test would just duplicate what
    conftest.py's session-scoped fixture already does once.

    Loud, not fatal by default — a hard crash here would break the
    exact zero-config local-dev experience the rest of this file's
    defaults are built around (see database_url above). ENVIRONMENT is
    opt-in (defaults to "development") for the same reason: nothing
    here infers "production" from a hostname or a missing .env file,
    so this stays log-only unless a deployment explicitly says
    ENVIRONMENT=production (see docker-compose.prod.yml), in which
    case an insecure default becomes a refusal to boot instead of
    something that's only ever caught by someone reading the logs.
    """
    problems = _insecure_defaults(settings_obj)
    for problem in problems:
        logger.critical("SECURITY: %s", problem)
    if problems and settings_obj.environment.strip().lower() == "production":
        raise RuntimeError(
            "Refusing to start with ENVIRONMENT=production and insecure "
            "default(s): " + " | ".join(problems)
        )


@app.on_event("startup")
async def on_startup():
    _enforce_startup_security(settings)
    # create_all() has to run BEFORE run_migrations(): the baseline
    # revision (6cea28b2d137) is pure `ALTER TABLE ... ADD COLUMN IF NOT
    # EXISTS` — it assumes the tables it's altering already exist, which
    # is only true once create_all() has created them from models.py.
    # Every migration written *after* that baseline (rate_limit_hits,
    # user_premium_state, etc.) does its own CREATE TABLE/CREATE TYPE,
    # which create_all() will have already done too — those migrations
    # each guard themselves with an existence check for exactly this
    # reason (see b6c97a145511's own comment) rather than relying on
    # ordering to avoid the collision.
    Base.metadata.create_all(bind=engine)
    run_migrations()

    # Own advisory-lock key (see app/migrate.py::startup_lock), separate
    # from migrations above — needed the moment more than one worker
    # process became possible (see Dockerfile's UVICORN_WORKERS):
    # seed_affiliate_providers' get-or-create loop isn't atomic across
    # processes, and _consolidate_series_diary_entries similarly assumes
    # it's the only one running. Without this, two workers booting at
    # the same moment could both decide the same provider row is
    # missing and both try to insert it — one of them hitting a
    # primary-key error instead of starting up cleanly.
    with startup_lock(8_234_015_579_112_234):
        db = SessionLocal()
        try:
            _consolidate_series_diary_entries(db)
            # Non-affiliate starter links for the common providers, so
            # "where to watch" has somewhere real to send a tap from day one —
            # see app/seed.py and app/routers/watch.py.
            seed_affiliate_providers(db)

            # Accounts whose 30-day restore window has run out, plus the
            # dead rows in refresh_sessions/account_tokens. Inside the
            # same advisory lock as the seeding above for the same
            # reason: two workers both deciding to purge the same account
            # would have one of them fail on a row the other already
            # deleted.
            #
            # Deliberately cheap enough to run at startup (one indexed
            # query that usually returns nothing) rather than needing a
            # scheduler this deployment doesn't have. A deployment that
            # would rather run it as a real cron job sets
            # PURGE_ON_STARTUP=false and calls
            # scripts/purge_deleted_accounts.py instead — the compliance
            # obligation is that deletion actually happens, not that it
            # happens from any particular process.
            if settings.purge_on_startup:
                try:
                    purged = purge_due_accounts(db)
                    if purged:
                        logger.info("purged %d account(s) past their restore window", purged)
                    sweep_expired_artifacts(db)
                except Exception:
                    logger.exception("account purge sweep failed")
        finally:
            db.close()

    # Backgrounded, not awaited — see _seed_teamira_shelves_background's
    # own docstring for why.
    asyncio.create_task(_seed_teamira_shelves_background())

    # One LISTEN connection per worker process, feeding the co-viewing/
    # Watch Together session websockets (co_view_vote.py, co_view_poll.py,
    # together.py) — see app/realtime.py's own module docstring for why
    # this needs Postgres LISTEN/NOTIFY rather than just an in-memory
    # registry the moment UVICORN_WORKERS is more than 1.
    realtime.listener.start(asyncio.get_running_loop())


@app.on_event("shutdown")
async def on_shutdown():
    realtime.listener.stop()


@app.get("/health")
def health():
    return {"status": "ok"}
