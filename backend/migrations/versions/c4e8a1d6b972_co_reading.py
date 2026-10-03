"""reading together: books and manga in a co-view room

Adds the reading columns to co_view_rooms, co_view_room_members and
co_view_room_events (see models.CoViewRoom and app/co_reading.py). Every
column is added only if it is missing, the same defensive shape the other
co-view migrations use, so running this on a database that was created from
the models in the meantime is a no-op rather than an error.

Revision ID: c4e8a1d6b972
Revises: a9e6c2f4b158
Create Date: 2026-10-02
"""
from alembic import op
import sqlalchemy as sa

revision = "c4e8a1d6b972"
down_revision = "a9e6c2f4b158"
branch_labels = None
depends_on = None


def _has_column(table: str, column: str) -> bool:
    inspector = sa.inspect(op.get_bind())
    if not inspector.has_table(table):
        return False
    return any(c["name"] == column for c in inspector.get_columns(table))


def _add(table: str, column: sa.Column) -> None:
    if not _has_column(table, column.name):
        op.add_column(table, column)


def upgrade() -> None:
    _add("co_view_rooms", sa.Column("activity", sa.String(8), nullable=False, server_default="watch"))
    _add("co_view_rooms", sa.Column("read_kind", sa.String(12), nullable=True))
    _add("co_view_rooms", sa.Column("content_hash", sa.String(64), nullable=True))
    _add("co_view_rooms", sa.Column("read_units", sa.Integer(), nullable=True))
    _add("co_view_rooms", sa.Column("read_mode", sa.String(8), nullable=False, server_default="own"))
    _add("co_view_rooms", sa.Column("lead_locator", sa.String(24), nullable=True))
    _add(
        "co_view_rooms",
        sa.Column("lead_user_id", sa.String(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
    )

    _add("co_view_room_members", sa.Column("locator", sa.String(24), nullable=True))
    _add("co_view_room_members", sa.Column("progress", sa.Integer(), nullable=False, server_default="0"))
    _add("co_view_room_members", sa.Column("locator_at", sa.DateTime(timezone=True), nullable=True))
    _add("co_view_room_members", sa.Column("content_hash", sa.String(64), nullable=True))

    _add("co_view_room_events", sa.Column("locator", sa.String(24), nullable=True))
    _add("co_view_room_events", sa.Column("quote", sa.String(240), nullable=True))


def downgrade() -> None:
    for table, columns in (
        ("co_view_room_events", ("quote", "locator")),
        ("co_view_room_members", ("content_hash", "locator_at", "progress", "locator")),
        (
            "co_view_rooms",
            ("lead_user_id", "lead_locator", "read_mode", "read_units", "content_hash", "read_kind", "activity"),
        ),
    ):
        for column in columns:
            if _has_column(table, column):
                op.drop_column(table, column)
