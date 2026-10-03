"""merge the old XP/level system into sincerity points

The app used to run two parallel "how much have you done" numbers side
by side: a live-recomputed XP/level total (routers/profile.py::
compute_level_for_user — never stored, just tallied fresh from watched
counts, reviews, rewatches, streaks, invites, card shares, and claimed
challenges every time it was read) and the sincerity ledger (a real,
spendable balance for a short list of honest acts). app/sincerity.py's
module docstring covers why keeping them apart stopped making sense
once sincerity itself broadened past "purely honest acts" — this
migration is the schema side of folding the first into the second.

Two new columns on users:

  - lifetime_sincerity_earned — a running total of every positive-delta
    SincerityTransaction ever recorded, kept alongside the existing
    spendable sincerity_balance. This is what the level ring is now
    computed from (app/sincerity.py::compute_level), specifically so
    that spending points can never knock someone back down a level.
  - streak_sincerity_award_days — high-water mark of the longest streak
    length already paid out for, so a broken-then-restarted streak
    doesn't re-earn days it already got credit for.

Nine new SincerityReason values for the everyday-activity wells that
used to feed live-recomputed XP (watched_logged, review_written,
rewatch_logged, watched_together_bonus, genre_explored,
streak_milestone, friend_invited, card_shared, challenge_claimed) — see
models.SincerityReason for what each one means.

No backfill: this app has no real users yet, so both new columns start
every account at 0 rather than trying to reconstruct a lifetime total
from historical activity.

Revision ID: a7c92e4f0b6d
Revises: d94b2c6f81a3
Create Date: 2026-09-27
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "a7c92e4f0b6d"
down_revision = "d94b2c6f81a3"
branch_labels = None
depends_on = None

_NEW_REASONS = [
    "watched_logged",
    "review_written",
    "rewatch_logged",
    "watched_together_bonus",
    "genre_explored",
    "streak_milestone",
    "friend_invited",
    "card_shared",
    "challenge_claimed",
]


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name == "postgresql":
        with op.get_context().autocommit_block():
            for value in _NEW_REASONS:
                op.execute(f"ALTER TYPE sincerityreason ADD VALUE IF NOT EXISTS '{value}'")
    # SQLite (tests) stores the column as a plain string — same note as
    # every prior enum-extending migration in this folder.

    existing_columns = {c["name"] for c in sa.inspect(bind).get_columns("users")}
    if "lifetime_sincerity_earned" not in existing_columns:
        op.add_column(
            "users",
            sa.Column("lifetime_sincerity_earned", sa.Integer(), nullable=False, server_default="0"),
        )
    if "streak_sincerity_award_days" not in existing_columns:
        op.add_column(
            "users",
            sa.Column("streak_sincerity_award_days", sa.Integer(), nullable=False, server_default="0"),
        )


def downgrade() -> None:
    op.drop_column("users", "streak_sincerity_award_days")
    op.drop_column("users", "lifetime_sincerity_earned")
    # No downgrade for the new enum values — same stance as every prior
    # migration that's added one.
