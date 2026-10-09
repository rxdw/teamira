"""reading_progress: where a user is in a book or manga

One new table. `reading_progress` keeps a single bookmark per (user, source,
media_id) — the current volume, chapter and/or page — for the title screen's
reading tracker (see models.ReadingProgress and routers/progress.py). It holds
no totals and touches neither watchlist_entries nor diary_entries.

Revision ID: a5c2e7d19b36
Revises: d1a7f3c9e254
Create Date: 2026-10-06
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "a5c2e7d19b36"
down_revision = "d1a7f3c9e254"
branch_labels = None
depends_on = None


def _has_table(name: str) -> bool:
    """Same guard as every migration since the 6cea28b2d137 baseline —
    app/main.py runs `Base.metadata.create_all()` before this, so on a fresh
    database the table may already exist by the time we get here."""
    bind = op.get_bind()
    return sa.inspect(bind).has_table(name)


def upgrade() -> None:
    if _has_table("reading_progress"):
        return
    op.create_table(
        "reading_progress",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column(
            "user_id",
            sa.String(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("media_id", sa.String(), nullable=False),
        sa.Column("source", sa.String(), nullable=False),
        sa.Column("volume", sa.Integer(), nullable=True),
        sa.Column("chapter", sa.Integer(), nullable=True),
        sa.Column("page", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("user_id", "source", "media_id", name="uq_reading_progress"),
    )
    op.create_index("ix_reading_progress_user_id", "reading_progress", ["user_id"])


def downgrade() -> None:
    op.drop_index("ix_reading_progress_user_id", table_name="reading_progress")
    op.drop_table("reading_progress")
