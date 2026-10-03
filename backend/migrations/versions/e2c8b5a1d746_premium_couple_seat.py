"""premium: couple-plan seat (who holds the second seat, since when)

Adds user_premium_state.seat_user_id / seat_assigned_at. A purchased
couple plan covers the other member of a two-person circle (see
routers/premium.py::_seat_covers); these two columns only remember who
holds the seat and since when, so the seat can't be rotated between
people faster than SEAT_REASSIGN_COOLDOWN. Coverage itself is derived
on read and never stored.

Revision ID: e2c8b5a1d746
Revises: a7c92e4f0b6d
Create Date: 2026-09-28
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "e2c8b5a1d746"
down_revision = "a7c92e4f0b6d"
branch_labels = None
depends_on = None

_TABLE = "user_premium_state"
_INDEX = "ix_user_premium_state_seat_user_id"


def _has_column(table: str, column: str) -> bool:
    """Same guard as b3f7a2d94c61's own _has_column: app/main.py runs
    Base.metadata.create_all() before run_migrations(), so on a fresh
    database these columns already exist by the time this revision runs
    and an unguarded add_column would collide with them."""
    bind = op.get_bind()
    if not sa.inspect(bind).has_table(table):
        return False
    return any(c["name"] == column for c in sa.inspect(bind).get_columns(table))


def _has_index(table: str, name: str) -> bool:
    bind = op.get_bind()
    if not sa.inspect(bind).has_table(table):
        return False
    return any(i["name"] == name for i in sa.inspect(bind).get_indexes(table))


def upgrade() -> None:
    if not _has_column(_TABLE, "seat_user_id"):
        op.add_column(
            _TABLE,
            sa.Column(
                "seat_user_id",
                sa.String(),
                sa.ForeignKey("users.id", ondelete="SET NULL"),
                nullable=True,
            ),
        )
    if not _has_column(_TABLE, "seat_assigned_at"):
        op.add_column(
            _TABLE,
            sa.Column("seat_assigned_at", sa.DateTime(timezone=True), nullable=True),
        )
    # Indexed because deleting a user makes Postgres look up every row
    # whose seat_user_id points at them (the SET NULL above).
    if not _has_index(_TABLE, _INDEX):
        op.create_index(_INDEX, _TABLE, ["seat_user_id"])


def downgrade() -> None:
    if _has_index(_TABLE, _INDEX):
        op.drop_index(_INDEX, table_name=_TABLE)
    if _has_column(_TABLE, "seat_assigned_at"):
        op.drop_column(_TABLE, "seat_assigned_at")
    if _has_column(_TABLE, "seat_user_id"):
        op.drop_column(_TABLE, "seat_user_id")
