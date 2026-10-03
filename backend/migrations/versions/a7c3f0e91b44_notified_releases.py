"""notified_releases: per-episode/per-release push dedup

Backs scripts/send_new_episode_push.py — see models.NotifiedRelease's own
docstring for why PushLog's existing "already sent this category today"
dedup isn't fine-grained enough for a new-episode push (one show can air
a new episode every week; each one needs exactly one push, not zero or
unlimited).

Revision ID: a7c3f0e91b44
Revises: b3f7a2d94c61
Create Date: 2026-09-22
"""
from alembic import op
import sqlalchemy as sa

revision = "a7c3f0e91b44"
down_revision = "b3f7a2d94c61"
branch_labels = None
depends_on = None


def _has_table(name: str) -> bool:
    """See f3a91d4c7e20's own comment on this helper — app/main.py's
    create_all() has usually already made this table by the time this
    runs; this migration only actually does the work on the one path
    where that's not true (run_migrations() invoked on its own against a
    database that skipped create_all())."""
    bind = op.get_bind()
    return sa.inspect(bind).has_table(name)


def upgrade() -> None:
    if not _has_table("notified_releases"):
        op.create_table(
            "notified_releases",
            sa.Column("id", sa.String(), primary_key=True),
            sa.Column(
                "user_id", sa.String(),
                sa.ForeignKey("users.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("source", sa.String(), nullable=False),
            sa.Column("media_id", sa.String(), nullable=False),
            sa.Column("release_key", sa.String(), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        )
        op.create_index("ix_notified_releases_user_id", "notified_releases", ["user_id"])
        op.create_index(
            "uq_notified_release",
            "notified_releases",
            ["user_id", "source", "media_id", "release_key"],
            unique=True,
        )


def downgrade() -> None:
    if _has_table("notified_releases"):
        op.drop_table("notified_releases")
