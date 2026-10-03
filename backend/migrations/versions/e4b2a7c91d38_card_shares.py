"""card_shares: XP for share cards sent out of the app

One new table. `card_shares` records that a specific card (identified by
the client's own stable id for it — see models.CardShare) left the app,
which is the one XP source that can't be recomputed from diary rows.
The (user_id, card_key) unique constraint is what makes the reward
once-per-card; the (user_id, day_key) index backs the per-day cap in
routers/card_shares.py. XP itself is still never stored — compute_level_
for_user counts these rows on every read.

Nothing else changes in the schema: "watched together" XP reads the
existing diary_entries.watched_together / watched_with_username columns,
and challenge XP reads the existing challenge_progress table.

Revision ID: e4b2a7c91d38
Revises: d8e51f3a7c92
Create Date: 2026-09-23
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "e4b2a7c91d38"
down_revision = "d8e51f3a7c92"
branch_labels = None
depends_on = None


def _has_table(name: str) -> bool:
    """Same guard as every migration since the 6cea28b2d137 baseline —
    app/main.py runs `Base.metadata.create_all()` before this, so on a
    fresh database the table may already exist by the time we get here.
    See b6c97a145511 for the full reasoning."""
    bind = op.get_bind()
    return sa.inspect(bind).has_table(name)


def upgrade() -> None:
    if _has_table("card_shares"):
        return
    op.create_table(
        "card_shares",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column(
            "user_id",
            sa.String(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("card_key", sa.String(), nullable=False),
        sa.Column("day_key", sa.String(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now()
        ),
        sa.UniqueConstraint("user_id", "card_key", name="uq_card_share_user_card"),
    )
    op.create_index("ix_card_shares_user_id", "card_shares", ["user_id"])
    op.create_index(
        "ix_card_shares_user_day", "card_shares", ["user_id", "day_key"]
    )


def downgrade() -> None:
    # Dropping the table forgets which cards already paid out, so a
    # later re-upgrade would let them pay again — real, but the same
    # trade-off as dropping challenge_progress in f3a91d4c7e20, and a
    # downgrade is explicitly asking for the feature not to exist.
    if _has_table("card_shares"):
        op.drop_table("card_shares")
