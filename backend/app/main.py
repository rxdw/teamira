import asyncio
import logging
import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import func, text

from app.database import Base, SessionLocal, engine
from app.routers import auth, media, feed, ai, activity, profile, diary, progress, lists, together, partner, co_view_vote, co_view_poll, watch, integrations, imports, sources, teamira, reviews, friends, linking, image_proxy
from app.seed import seed_affiliate_providers
from app.seed_teamira_picks import seed_all_shelves as _seed_teamira_shelves

logger = logging.getLogger("uvicorn.error")

app = FastAPI(title="teamira API", version="0.1.0")

# Uploaded avatars (see routers/profile.py::upload_avatar) — plain local
# disk storage under the backend's own bind-mounted directory, same "MVP,
# swap for real object storage before real launch" story as the rest of
# this file. Served back out at /static/avatars/<file>, which is exactly
# what gets written into users.avatar_url.
_UPLOADS_DIR = os.path.join(os.path.dirname(__file__), "..", "uploads")
os.makedirs(os.path.join(_UPLOADS_DIR, "avatars"), exist_ok=True)
app.mount("/static", StaticFiles(directory=_UPLOADS_DIR), name="static")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # tighten before real production launch
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(media.router)
app.include_router(feed.router)
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
app.include_router(image_proxy.router)


# MVP stand-in for Alembic (see the "MVP" note on on_startup below):
# create_all() only ever creates *missing tables*, it never alters an
# existing one — so a column added to a model after someone's database
# already has that table (like diary_entries.season/episode below) needs
# its own ALTER TABLE, or it silently never shows up on any database that
# existed before this change shipped. `ADD COLUMN IF NOT EXISTS` makes
# this safe to run on every startup, on a brand-new database and an
# already-migrated one alike.
_STARTUP_COLUMN_MIGRATIONS = [
    "ALTER TABLE diary_entries ADD COLUMN IF NOT EXISTS season INTEGER",
    "ALTER TABLE diary_entries ADD COLUMN IF NOT EXISTS episode INTEGER",
    # A series now only ever gets one diary_entries row, updated in place
    # (see models.DiaryEntry's docstring) — this tracks its running
    # watched-episode count for display. Nullable, so this backfills as
    # NULL on any row written before the column existed; the app only
    # ever reads it off a series' row, which is rewritten on its very
    # next log anyway.
    "ALTER TABLE diary_entries ADD COLUMN IF NOT EXISTS episodes_watched INTEGER",
    "ALTER TABLE episode_progress ADD COLUMN IF NOT EXISTS rating INTEGER",
    "ALTER TABLE episode_progress ADD COLUMN IF NOT EXISTS note VARCHAR",
    # Wrapped's "first & last", decade breakdown, and directors-of-the-year
    # cards read these two snapshot columns — see models.DiaryEntry.
    "ALTER TABLE diary_entries ADD COLUMN IF NOT EXISTS year INTEGER",
    "ALTER TABLE diary_entries ADD COLUMN IF NOT EXISTS director VARCHAR",
    # Watch Together genre filter (setup step) and each side's own
    # "add matches to my list?" choice — see models.TogetherSession.
    "ALTER TABLE together_sessions ADD COLUMN IF NOT EXISTS genres_filter JSON",
    "ALTER TABLE together_sessions ADD COLUMN IF NOT EXISTS owner_sync_to_list BOOLEAN DEFAULT TRUE",
    "ALTER TABLE together_sessions ADD COLUMN IF NOT EXISTS guest_sync_to_list BOOLEAN DEFAULT TRUE",
    # Teamira shelves used to be TMDB movie/series only — this tags each
    # item with which catalog it came from so anime/games/books/manga can
    # go on a shelf too (see models.TeamiraCollectionItem). NULL on every
    # pre-existing row, read back as "tmdb" — see
    # routers/teamira.py::_resolve_manual_item.
    "ALTER TABLE teamira_collection_items ADD COLUMN IF NOT EXISTS source VARCHAR",
    # Lets hand-picked Teamira shelves (as opposed to the franchise ones
    # in curated_franchises.py, which already had an English name) switch
    # their title with the language toggle too — see
    # models.TeamiraCollection.title_en. NULL on every pre-existing shelf,
    # read back as "just show the Russian title", same fallback as
    # everywhere else this pattern is used.
    "ALTER TABLE teamira_collections ADD COLUMN IF NOT EXISTS title_en VARCHAR",
    # The friends system (see models.User, routers/friends.py) — a lazily-
    # generated standing invite code per account, and who (if anyone)
    # referred this account at registration. NULL on every pre-existing
    # row: an old account simply has no code yet (one is minted the first
    # time GET /friends/invite is called) and no referrer, same "backfills
    # as absent" story as every other nullable column in this list.
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS invite_code VARCHAR",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS referred_by_id VARCHAR",
    # Editable profile identity: name/avatar/status — see models.User.
    # NULL on every pre-existing row, same "backfills as absent" story as
    # everything else in this list; the client falls back to `username`
    # and no avatar/status shown until the person sets one.
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS display_name VARCHAR",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_preset VARCHAR",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url VARCHAR",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS status_text VARCHAR",
    # Per-shelf privacy (watched / watching now / plan to watch) — see
    # models.User. NULL on every pre-existing row would read as "no
    # setting", so this backfills the same default the column itself
    # ships with (open by default) rather than leaving it empty.
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS privacy_watched VARCHAR DEFAULT 'everyone'",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS privacy_watching VARCHAR DEFAULT 'everyone'",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS privacy_planned VARCHAR DEFAULT 'everyone'",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS privacy_favorites VARCHAR DEFAULT 'everyone'",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS top_favorite_media_id VARCHAR",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS top_favorite_source VARCHAR",
    # Badge showcase: up to 3 pinned achievement ids — see models.User.
    # NULL on every pre-existing row, same "backfills as absent" story as
    # everything else here; the profile header simply shows no showcase
    # row until the person pins something.
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS pinned_achievement_ids VARCHAR",
    # Stories-style multi-favorite spotlight on the Profile header banner
    # — see models.User.top_favorite_picks. NULL on every pre-existing
    # row; backfilled below from the old single top_favorite_media_id/
    # top_favorite_source columns so nobody's existing pick silently
    # disappears from their banner the first time this ships.
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS top_favorite_picks JSON",
    """
    UPDATE users SET top_favorite_picks = json_build_array(
        json_build_object('media_id', top_favorite_media_id, 'source', top_favorite_source)
    )
    WHERE top_favorite_picks IS NULL
      AND top_favorite_media_id IS NOT NULL
      AND top_favorite_source IS NOT NULL
    """,
    "UPDATE users SET top_favorite_picks = '[]' WHERE top_favorite_picks IS NULL",
    "UPDATE users SET privacy_watched = 'everyone' WHERE privacy_watched IS NULL",
    "UPDATE users SET privacy_watching = 'everyone' WHERE privacy_watching IS NULL",
    "UPDATE users SET privacy_planned = 'everyone' WHERE privacy_planned IS NULL",
    "UPDATE users SET privacy_favorites = 'everyone' WHERE privacy_favorites IS NULL",
    # Poster + a way to open the real title, on friends' activity events
    # (see models.ActivityEvent) — rows written before this shipped just
    # have these as NULL, which the feed treats as "text-only, not
    # tappable".
    "ALTER TABLE activity_events ADD COLUMN IF NOT EXISTS media_id VARCHAR",
    "ALTER TABLE activity_events ADD COLUMN IF NOT EXISTS source VARCHAR",
    "ALTER TABLE activity_events ADD COLUMN IF NOT EXISTS poster_url VARCHAR",
    "ALTER TABLE activity_events ADD COLUMN IF NOT EXISTS rating INTEGER",
    # "Plan an evening"'s co-viewing toggle, mirrored onto the shared
    # co-viewing list so a partner actually sees the scheduled evening
    # too — see models.CoViewEntry. NULL on every pre-existing row
    # (suggest-heart / Watch Together matches never had a schedule),
    # which the co-viewing screen reads as "planned, whenever."
    "ALTER TABLE co_view_entries ADD COLUMN IF NOT EXISTS scheduled_date TIMESTAMP",
    "ALTER TABLE co_view_entries ADD COLUMN IF NOT EXISTS scheduled_hour INTEGER",
    "ALTER TABLE co_view_entries ADD COLUMN IF NOT EXISTS scheduled_minute INTEGER",
    # Up to 3 cast standouts picked on the themed log flows' "who did
    # you love most tonight?" step — see models.DiaryEntry.favorite_cast.
    # NULL on every pre-existing row, read back as "step was skipped",
    # same convention as mood_tags.
    "ALTER TABLE diary_entries ADD COLUMN IF NOT EXISTS favorite_cast JSON",
    # Mirrors of the latest logged evening's mood tags / favorite cast
    # onto the title-level watchlist row — see
    # models.WatchlistEntry.mood_tags's own docstring. NULL on every
    # pre-existing row, read back as "no tags/cast yet", same convention
    # as diary_entries.mood_tags/favorite_cast above.
    "ALTER TABLE watchlist_entries ADD COLUMN IF NOT EXISTS mood_tags JSON",
    "ALTER TABLE watchlist_entries ADD COLUMN IF NOT EXISTS favorite_cast JSON",
    "UPDATE watchlist_entries SET mood_tags = '[]' WHERE mood_tags IS NULL",
    "UPDATE watchlist_entries SET favorite_cast = '[]' WHERE favorite_cast IS NULL",
    # Wide backdrop snapshot for the Profile header's stories banner —
    # see models.WatchlistEntry.backdrop_url's own docstring. NULL on
    # every pre-existing row; the client already falls back to
    # poster_url for those, same as a row from a source with no
    # backdrop at all.
    "ALTER TABLE watchlist_entries ADD COLUMN IF NOT EXISTS backdrop_url VARCHAR",
    # Same wide-backdrop snapshot, now on the diary rows themselves — see
    # models.DiaryEntry.backdrop_url's own docstring. NULL on every
    # pre-existing row; the client falls back to poster_url for those.
    "ALTER TABLE diary_entries ADD COLUMN IF NOT EXISTS backdrop_url VARCHAR",
]

# Same MVP-migration problem, but for the Postgres enum type behind
# WatchlistEntry.status (see models.WatchStatus): create_all() only
# creates the `watchstatus` TYPE if it doesn't exist yet — on any
# database that already had a watchlist_entries table from before
# `watching`/`dropped` were added to the Python enum, the Postgres type
# still only knows `watch_later`/`watched`, and every attempt to write
# WatchStatus.watching (routers/diary.py::log_watched, the very first
# episode of a series ever logged) fails outright. That's why, without
# this, a series could never actually show up under "watching now" —
# not a client bug, a stuck database. `ADD VALUE IF NOT EXISTS` (Postgres
# 12+) makes this safe to run on every startup, on a brand-new database
# and an already-migrated one alike.
_STARTUP_ENUM_MIGRATIONS = [
    "ALTER TYPE watchstatus ADD VALUE IF NOT EXISTS 'watching'",
    "ALTER TYPE watchstatus ADD VALUE IF NOT EXISTS 'dropped'",
    # "your sources" (routers/sources.py) — YouTube/Twitch items are their
    # own media_type. Same story as the two lines above: without this, any
    # database that already had its `mediatype` TYPE before this shipped
    # rejects every row a source import tries to write.
    "ALTER TYPE mediatype ADD VALUE IF NOT EXISTS 'video'",
]


def _run_startup_migrations():
    with engine.begin() as conn:
        for statement in _STARTUP_COLUMN_MIGRATIONS:
            conn.execute(text(statement))

    if engine.dialect.name != "postgresql":
        # SQLite/others store the enum as a plain string column — nothing
        # to migrate, every value the Python enum knows about just works.
        return

    # ALTER TYPE ... ADD VALUE can't run inside the same transaction as
    # other DDL on older Postgres, and can't be safely batched with
    # statements that might use the new value — give it its own
    # autocommit connection, separate from the column migrations above.
    with engine.connect().execution_options(isolation_level="AUTOCOMMIT") as conn:
        for statement in _STARTUP_ENUM_MIGRATIONS:
            conn.execute(text(statement))


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


@app.on_event("startup")
async def on_startup():
    # MVP: create tables directly. Move to Alembic migrations before real launch.
    Base.metadata.create_all(bind=engine)
    _run_startup_migrations()
    db = SessionLocal()
    try:
        _consolidate_series_diary_entries(db)
        # Non-affiliate starter links for the common providers, so
        # "where to watch" has somewhere real to send a tap from day one —
        # see app/seed.py and app/routers/watch.py.
        seed_affiliate_providers(db)
    finally:
        db.close()

    # Backgrounded, not awaited — see _seed_teamira_shelves_background's
    # own docstring for why.
    asyncio.create_task(_seed_teamira_shelves_background())


@app.get("/health")
def health():
    return {"status": "ok"}
