"""timestamps: naive -> timezone-aware (audit 3.4.1)

Every DateTime column in the app was declared naive (`Column(DateTime, ...)`)
and every timestamp the app writes to it comes from `datetime.utcnow()` —
also naive, and also *implicitly* UTC, with nothing in either the column
or the Python value saying so. That's fine right up until the moment
something compares one of these values against an aware datetime
(`datetime.now(timezone.utc)`, or anything read back from a column that
*is* aware), which raises `TypeError: can't compare offset-naive and
offset-aware datetimes`. This already happened three times in the
existing codebase by accident — see the comments this same change added
to app/routers/feed.py, app/routers/shared_diary.py and
app/challenges.py::period_bounds, all of which built a naive
`datetime.min`/date-range boundary specifically because that's what the
DB columns were at the time.

app/models.py now declares every one of these 68 columns as
`DateTime(timezone=True)`, and every `datetime.utcnow()` call in the
Python code became `datetime.now(timezone.utc)` (see that commit/diff).
This migration is the other half: it converts the *existing* columns in
a database that predates that change, so the Python-level type and the
column-level type agree on a database that already has rows in it.

The conversion itself
----------------------
`ALTER COLUMN col TYPE TIMESTAMP WITH TIME ZONE USING col AT TIME ZONE
'UTC'` — for every naive value already in the column, this labels it as
UTC without shifting the wall-clock number, which is correct precisely
because `datetime.utcnow()` is what put it there. Verified by hand
against a real Postgres 16 instance before writing this: inserting
'2024-06-15 10:30:00' into a naive column, running this exact ALTER, and
reading it back under `SET TIME ZONE 'Europe/Moscow'` correctly showed
'2024-06-15 13:30:00+03' — same instant, adjusted for display, nothing
lost. The reverse (downgrade, below) uses the same `AT TIME ZONE 'UTC'`
expression, which is its own inverse for this conversion.

The lock this takes — read before running this in production
----------------------------------------------------------------
Unlike the FK/ON DELETE migration before this one (a7d3f1e08b45), there
is no NOT VALID-style trick available here: changing a column's type is
not a validation, it's the type. I checked whether Postgres treats
timestamp->timestamptz as a cheap, rewrite-free metadata change (some
type changes are, when the on-disk representation doesn't change) by
comparing `pg_class.relfilenode` before and after the ALTER on a table
with rows in it — it changed. So this rewrites the table, and holds an
ACCESS EXCLUSIVE lock for the duration, same as the FK migration's
locking concern but for however long a full rewrite takes rather than
however long validation takes. On the empty-or-near-empty database this
project currently has (see the audit's 2.6/2.8 findings — nothing is
published yet, so there's no production traffic to protect), that's
sub-second for every table here and not worth engineering around. If
this is still unrun by the time real user data exists, don't run it
as-is during peak traffic: the standard fix at that point is the
expand/contract pattern (add a new tz-aware column, backfill it in
batches with a trigger keeping it in sync, swap, drop the old one) —
listing 68 columns across 37 tables through that machinery here, for a
database that doesn't need it yet, would be solving a problem this
project doesn't have.

Revision ID: 92081e10cd3f
Revises: a7d3f1e08b45
Create Date: 2026-09-18
"""

from alembic import op

revision = "92081e10cd3f"
down_revision = "a7d3f1e08b45"
branch_labels = None
depends_on = None


# (table, column). Generated from app/models.py's DateTime(timezone=True)
# columns — every one of them, in declaration order. See that file for
# what each column means; this migration only cares about its type.
_TZ_COLUMNS = [
    ("users", "created_at"),
    ("users", "deleted_at"),
    ("users", "purge_after"),
    ("users", "suspended_at"),
    ("users", "suspended_until"),
    ("users", "eula_accepted_at"),
    ("watchlist_entries", "watched_at"),
    ("watchlist_entries", "created_at"),
    ("watchlist_entries", "updated_at"),
    ("diary_entries", "watched_at"),
    ("diary_entries", "created_at"),
    ("user_lists", "created_at"),
    ("user_lists", "updated_at"),
    ("user_list_items", "added_at"),
    ("activity_events", "created_at"),
    ("friend_requests", "created_at"),
    ("friend_requests", "responded_at"),
    ("episode_progress", "watched_at"),
    ("cached_title_details", "cached_at"),
    ("cached_episodes", "cached_at"),
    ("cached_embeddings", "cached_at"),
    ("cached_feed_snapshots", "cached_at"),
    ("user_premium_state", "purchased_at"),
    ("user_premium_state", "premium_expires_at"),
    ("together_sessions", "created_at"),
    ("together_sessions", "updated_at"),
    ("together_swipes", "created_at"),
    ("partner_links", "created_at"),
    ("partner_link_members", "joined_at"),
    ("partner_link_invites", "created_at"),
    ("partner_link_invites", "responded_at"),
    ("partner_prefs", "created_at"),
    ("challenge_progress", "completed_at"),
    ("challenge_progress", "claimed_at"),
    ("challenge_progress", "seen_at"),
    ("challenge_progress", "created_at"),
    ("co_view_entries", "watched_at"),
    ("co_view_entries", "created_at"),
    ("co_view_entries", "scheduled_date"),
    ("co_view_vote_sessions", "created_at"),
    ("co_view_vote_casts", "created_at"),
    ("co_view_poll_sessions", "deadline"),
    ("co_view_poll_sessions", "created_at"),
    ("scrobble_events", "created_at"),
    ("affiliate_providers", "updated_at"),
    ("outbound_clicks", "created_at"),
    ("suggestions", "created_at"),
    ("teamira_collections", "created_at"),
    ("teamira_collections", "updated_at"),
    ("teamira_collection_items", "added_at"),
    ("referrals", "created_at"),
    ("referrals", "verified_at"),
    ("referral_rewards", "granted_at"),
    ("promo_codes", "used_at"),
    ("promo_codes", "created_at"),
    ("sincerity_transactions", "created_at"),
    ("refresh_sessions", "created_at"),
    ("refresh_sessions", "last_used_at"),
    ("refresh_sessions", "expires_at"),
    ("refresh_sessions", "rotated_at"),
    ("refresh_sessions", "revoked_at"),
    ("account_tokens", "expires_at"),
    ("account_tokens", "consumed_at"),
    ("account_tokens", "created_at"),
    ("user_blocks", "created_at"),
    ("reports", "created_at"),
    ("reports", "due_at"),
    ("reports", "resolved_at"),
]


def upgrade():
    for table, column in _TZ_COLUMNS:
        op.execute(
            f'ALTER TABLE {table} ALTER COLUMN {column} '
            f"TYPE TIMESTAMP WITH TIME ZONE USING {column} AT TIME ZONE 'UTC'"
        )


def downgrade():
    for table, column in _TZ_COLUMNS:
        op.execute(
            f'ALTER TABLE {table} ALTER COLUMN {column} '
            f"TYPE TIMESTAMP WITHOUT TIME ZONE USING {column} AT TIME ZONE 'UTC'"
        )
