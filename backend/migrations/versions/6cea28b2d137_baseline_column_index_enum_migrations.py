"""baseline: column/index/enum migrations carried over from main.py

This is the pre-Alembic history of this schema, frozen into one
revision instead of rewritten as individual `op.add_column` calls per
change. Two reasons for that, not just laziness:

1. Faithfulness. These statements are copied verbatim (same
   `IF NOT EXISTS` / `ADD VALUE IF NOT EXISTS` guards) from what
   main.py's `_STARTUP_COLUMN_MIGRATIONS` / `_STARTUP_INDEX_MIGRATIONS`
   / `_STARTUP_ENUM_MIGRATIONS` used to run on *every* app startup.
   Keeping them idempotent means this revision is safe to run against
   a database that's already been through some or all of them the old
   way — `alembic upgrade head` on a database that already has every
   column just finds nothing left to do, rather than needing an
   operator to figure out and hand-run `alembic stamp head` first.
2. History that already happened. These aren't new schema changes
   being designed now; they're a log of what this app already did,
   one line per thing that already shipped. Re-deriving each as a
   "clean" typed `op.add_column(...)` wouldn't add real value here and
   risks a transcription mistake versus copying the working SQL
   directly. Anything genuinely new from this point on (see revision
   b6c97a145511 for the first example) uses normal typed Alembic
   operations, not raw `op.execute` — this revision is the one-time
   bridge from the old system into this one, not the new pattern.

Revision ID: 6cea28b2d137
Revises:
Create Date: 2026-09-11
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "6cea28b2d137"
down_revision = None
branch_labels = None
depends_on = None


# Same statements, same order, as main.py's old _STARTUP_COLUMN_MIGRATIONS
# — see that list's own history/comments in version control for why each
# one exists. Kept together as one block since most of them predate this
# migration system and were always run as one batch.
_COLUMN_MIGRATIONS = [
    "ALTER TABLE diary_entries ADD COLUMN IF NOT EXISTS season INTEGER",
    "ALTER TABLE diary_entries ADD COLUMN IF NOT EXISTS episode INTEGER",
    "ALTER TABLE diary_entries ADD COLUMN IF NOT EXISTS episodes_watched INTEGER",
    "ALTER TABLE episode_progress ADD COLUMN IF NOT EXISTS rating INTEGER",
    "ALTER TABLE episode_progress ADD COLUMN IF NOT EXISTS note VARCHAR",
    "ALTER TABLE diary_entries ADD COLUMN IF NOT EXISTS year INTEGER",
    "ALTER TABLE diary_entries ADD COLUMN IF NOT EXISTS director VARCHAR",
    "ALTER TABLE together_sessions ADD COLUMN IF NOT EXISTS genres_filter JSON",
    "ALTER TABLE together_sessions ADD COLUMN IF NOT EXISTS owner_sync_to_list BOOLEAN DEFAULT TRUE",
    "ALTER TABLE together_sessions ADD COLUMN IF NOT EXISTS guest_sync_to_list BOOLEAN DEFAULT TRUE",
    "ALTER TABLE teamira_collection_items ADD COLUMN IF NOT EXISTS source VARCHAR",
    "ALTER TABLE teamira_collections ADD COLUMN IF NOT EXISTS title_en VARCHAR",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS invite_code VARCHAR",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS referred_by_id VARCHAR",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS display_name VARCHAR",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_preset VARCHAR",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url VARCHAR",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS status_text VARCHAR",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS privacy_watched VARCHAR DEFAULT 'everyone'",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS privacy_watching VARCHAR DEFAULT 'everyone'",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS privacy_planned VARCHAR DEFAULT 'everyone'",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS privacy_favorites VARCHAR DEFAULT 'everyone'",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS top_favorite_media_id VARCHAR",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS top_favorite_source VARCHAR",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS pinned_achievement_ids VARCHAR",
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
    "ALTER TABLE activity_events ADD COLUMN IF NOT EXISTS media_id VARCHAR",
    "ALTER TABLE activity_events ADD COLUMN IF NOT EXISTS source VARCHAR",
    "ALTER TABLE activity_events ADD COLUMN IF NOT EXISTS poster_url VARCHAR",
    "ALTER TABLE activity_events ADD COLUMN IF NOT EXISTS rating INTEGER",
    "ALTER TABLE co_view_entries ADD COLUMN IF NOT EXISTS scheduled_date TIMESTAMP",
    "ALTER TABLE co_view_entries ADD COLUMN IF NOT EXISTS scheduled_hour INTEGER",
    "ALTER TABLE co_view_entries ADD COLUMN IF NOT EXISTS scheduled_minute INTEGER",
    "ALTER TABLE diary_entries ADD COLUMN IF NOT EXISTS favorite_cast JSON",
    "ALTER TABLE watchlist_entries ADD COLUMN IF NOT EXISTS mood_tags JSON",
    "ALTER TABLE watchlist_entries ADD COLUMN IF NOT EXISTS favorite_cast JSON",
    "UPDATE watchlist_entries SET mood_tags = '[]' WHERE mood_tags IS NULL",
    "UPDATE watchlist_entries SET favorite_cast = '[]' WHERE favorite_cast IS NULL",
    "ALTER TABLE watchlist_entries ADD COLUMN IF NOT EXISTS backdrop_url VARCHAR",
    "ALTER TABLE diary_entries ADD COLUMN IF NOT EXISTS backdrop_url VARCHAR",
]

# Same as main.py's old _STARTUP_INDEX_MIGRATIONS. See that list's own
# comment (kept in main.py's git history) on the CREATE INDEX
# CONCURRENTLY caveat for large existing tables — still applies here:
# this runs inside Alembic's own migration transaction, so it's still
# plain (blocking) CREATE INDEX, same as before. Fine for this app's
# current table sizes; build a large index by hand with CONCURRENTLY
# instead of through a migration if that ever stops being true.
_INDEX_MIGRATIONS = [
    "CREATE INDEX IF NOT EXISTS ix_watchlist_entries_user_id_updated_at ON watchlist_entries (user_id, updated_at)",
    "CREATE INDEX IF NOT EXISTS ix_diary_entries_user_id_watched_at ON diary_entries (user_id, watched_at)",
    "CREATE INDEX IF NOT EXISTS ix_activity_events_user_id_created_at ON activity_events (user_id, created_at)",
]

# Same as main.py's old _STARTUP_ENUM_MIGRATIONS. `ALTER TYPE ... ADD
# VALUE` can't run inside a transaction block on Postgres < 12 and,
# more importantly for *this* migration, can't run inside the same
# transaction as other DDL that might use the new value — Alembic runs
# `upgrade()` inside one transaction per revision (see migrations/env.py),
# so these get their own `autocommit_block()` the same way main.py used
# to give them their own separate AUTOCOMMIT connection.
_ENUM_MIGRATIONS = [
    "ALTER TYPE watchstatus ADD VALUE IF NOT EXISTS 'watching'",
    "ALTER TYPE watchstatus ADD VALUE IF NOT EXISTS 'dropped'",
    "ALTER TYPE mediatype ADD VALUE IF NOT EXISTS 'video'",
]


def upgrade() -> None:
    for statement in _COLUMN_MIGRATIONS:
        op.execute(statement)
    for statement in _INDEX_MIGRATIONS:
        op.execute(statement)

    if op.get_bind().dialect.name != "postgresql":
        # SQLite/others store the enum as a plain string column —
        # nothing to migrate, every value the Python enum knows about
        # just works.
        return
    with op.get_context().autocommit_block():
        for statement in _ENUM_MIGRATIONS:
            op.execute(statement)


def downgrade() -> None:
    # Deliberately unsupported rather than a guessed-at reverse. The
    # system this replaced had no downgrade path at all (raw ALTER
    # TABLE statements run forward-only on every startup); refusing
    # clearly here is a strict improvement on that — an operator finds
    # out immediately that they need to restore from a backup instead
    # of an `alembic downgrade` silently doing something approximate
    # (dropping columns is inherently lossy, and several of the
    # statements above are one-time data backfills with no meaningful
    # inverse at all).
    raise NotImplementedError(
        "This baseline revision has no downgrade — restore from a backup "
        "instead. See this revision's own docstring."
    )
