"""premium: seats table + the "family" plan kind (3-4 people)

Two changes that only make sense together:

1. Adds "family" to the premiumplankind enum — a plan that covers a
   circle of up to four people (the payer plus three).

2. Replaces user_premium_state.seat_user_id / seat_assigned_at (one seat,
   introduced by e2c8b5a1d746 for the couple plan) with a premium_seats
   table: one row per (payer, covered person, assigned_at). One pair of
   columns can remember one holder; a family plan has up to three. Rows
   that already exist in the old columns are copied over first, so a
   couple plan's seat, and the cooldown running on it, survive the move.

Coverage itself is still derived on every read and never stored — the
table only remembers who took which seat and since when (see
routers/premium.py::_seat_covers).

Revision ID: a3d6c8f1e572
Revises: f7b1c3d8a924
Create Date: 2026-09-28
"""
import uuid

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "a3d6c8f1e572"
down_revision = "f7b1c3d8a924"
branch_labels = None
depends_on = None

_STATE = "user_premium_state"
_SEATS = "premium_seats"
_OLD_INDEX = "ix_user_premium_state_seat_user_id"


def _has_table(table: str) -> bool:
    return sa.inspect(op.get_bind()).has_table(table)


def _has_column(table: str, column: str) -> bool:
    """Same guard as e2c8b5a1d746's: app/main.py runs
    Base.metadata.create_all() before run_migrations(), so on a fresh
    database this revision may find the new table already in place and
    the old columns already absent."""
    if not _has_table(table):
        return False
    return any(c["name"] == column for c in sa.inspect(op.get_bind()).get_columns(table))


def _has_index(table: str, name: str) -> bool:
    if not _has_table(table):
        return False
    return any(i["name"] == name for i in sa.inspect(op.get_bind()).get_indexes(table))


def upgrade() -> None:
    if op.get_bind().dialect.name == "postgresql":
        # `ALTER TYPE ... ADD VALUE` can't run inside the transaction
        # Alembic already has open for this revision — same reasoning as
        # b3f7a2d94c61, so it gets its own autocommit block.
        with op.get_context().autocommit_block():
            op.execute("ALTER TYPE premiumplankind ADD VALUE IF NOT EXISTS 'family'")
    # SQLite/others keep the enum as a plain string column — the new
    # value just works, nothing to do.

    if not _has_table(_SEATS):
        op.create_table(
            _SEATS,
            sa.Column("id", sa.String(), primary_key=True),
            sa.Column(
                "payer_id", sa.String(),
                sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False,
            ),
            sa.Column(
                "holder_id", sa.String(),
                sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False,
            ),
            sa.Column(
                "assigned_at", sa.DateTime(timezone=True),
                nullable=False, server_default=sa.func.now(),
            ),
            sa.UniqueConstraint("payer_id", "holder_id", name="uq_premium_seat_payer_holder"),
        )
    if not _has_index(_SEATS, "ix_premium_seats_payer_id"):
        op.create_index("ix_premium_seats_payer_id", _SEATS, ["payer_id"])
    if not _has_index(_SEATS, "ix_premium_seats_holder_id"):
        op.create_index("ix_premium_seats_holder_id", _SEATS, ["holder_id"])

    if _has_column(_STATE, "seat_user_id"):
        bind = op.get_bind()
        has_assigned = _has_column(_STATE, "seat_assigned_at")
        assigned_expr = "seat_assigned_at" if has_assigned else "NULL"
        rows = bind.execute(sa.text(
            f"SELECT user_id, seat_user_id, {assigned_expr} AS assigned_at "
            f"FROM {_STATE} WHERE seat_user_id IS NOT NULL"
        )).fetchall()
        for payer_id, holder_id, assigned_at in rows:
            bind.execute(
                sa.text(
                    f"INSERT INTO {_SEATS} (id, payer_id, holder_id, assigned_at) "
                    "VALUES (:id, :payer, :holder, COALESCE(:at, CURRENT_TIMESTAMP))"
                ),
                {"id": str(uuid.uuid4()), "payer": payer_id, "holder": holder_id, "at": assigned_at},
            )

        if _has_index(_STATE, _OLD_INDEX):
            op.drop_index(_OLD_INDEX, table_name=_STATE)
        op.drop_column(_STATE, "seat_user_id")
    if _has_column(_STATE, "seat_assigned_at"):
        op.drop_column(_STATE, "seat_assigned_at")


def downgrade() -> None:
    # Puts the single-seat columns back and refills them from each
    # payer's oldest seat (all a couple plan ever had). Anything beyond
    # the first seat of a family plan is dropped with the table, and the
    # 'family' enum label stays: removing a value live rows may already
    # reference isn't a safe automatic operation (same stance as
    # b3f7a2d94c61). Move family accounts off that plan before
    # downgrading.
    if not _has_column(_STATE, "seat_user_id"):
        op.add_column(
            _STATE,
            sa.Column(
                "seat_user_id", sa.String(),
                sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True,
            ),
        )
    if not _has_column(_STATE, "seat_assigned_at"):
        op.add_column(
            _STATE, sa.Column("seat_assigned_at", sa.DateTime(timezone=True), nullable=True),
        )
    if not _has_index(_STATE, _OLD_INDEX):
        op.create_index(_OLD_INDEX, _STATE, ["seat_user_id"])

    if _has_table(_SEATS):
        bind = op.get_bind()
        rows = bind.execute(sa.text(
            f"SELECT payer_id, holder_id, assigned_at FROM {_SEATS} ORDER BY assigned_at ASC"
        )).fetchall()
        seen = set()
        for payer_id, holder_id, assigned_at in rows:
            if payer_id in seen:
                continue
            seen.add(payer_id)
            bind.execute(
                sa.text(
                    f"UPDATE {_STATE} SET seat_user_id = :holder, seat_assigned_at = :at "
                    "WHERE user_id = :payer"
                ),
                {"holder": holder_id, "at": assigned_at, "payer": payer_id},
            )
        op.drop_index("ix_premium_seats_holder_id", table_name=_SEATS)
        op.drop_index("ix_premium_seats_payer_id", table_name=_SEATS)
        op.drop_table(_SEATS)
