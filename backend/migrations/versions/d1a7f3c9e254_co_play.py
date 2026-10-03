"""playing together: the ready check of a game room

Adds `ready` to co_view_room_members (see models.CoViewRoomMember and
app/co_play.py). Added only if missing, the same defensive shape as the other
co-view migrations, so running it on a database that was created from the
models in the meantime is a no-op rather than an error.

Revision ID: d1a7f3c9e254
Revises: c4e8a1d6b972
Create Date: 2026-10-03
"""
from alembic import op
import sqlalchemy as sa

revision = "d1a7f3c9e254"
down_revision = "c4e8a1d6b972"
branch_labels = None
depends_on = None


def _has_column(table: str, column: str) -> bool:
    inspector = sa.inspect(op.get_bind())
    if not inspector.has_table(table):
        return False
    return any(c["name"] == column for c in inspector.get_columns(table))


def upgrade() -> None:
    if not _has_column("co_view_room_members", "ready"):
        op.add_column(
            "co_view_room_members",
            sa.Column("ready", sa.Boolean(), nullable=False, server_default=sa.false()),
        )


def downgrade() -> None:
    if _has_column("co_view_room_members", "ready"):
        op.drop_column("co_view_room_members", "ready")
