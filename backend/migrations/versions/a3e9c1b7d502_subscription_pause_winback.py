"""premium: cancel, pause and win-back

Adds the columns behind cancelling a subscription at the end of the paid
period, pausing it for a month instead, and the one-time win-back offer
after a cancelled plan runs out (see app/subscription.py):

  cancelled_at, cancel_effective_at   when it was cancelled / when it stops
  paused_at, paused_until             the current pause
  pause_used_at                       start of the last pause (cooldown)
  winback_used_at                     personal discount already redeemed
  winback_push_sent_at,
  pause_ending_push_sent_at           each push goes out at most once

Revision ID: a3e9c1b7d502
Revises: a3d6c8f1e572
Create Date: 2026-09-28
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "a3e9c1b7d502"
down_revision = "a3d6c8f1e572"
branch_labels = None
depends_on = None

_TABLE = "user_premium_state"
_COLUMNS = (
    "cancelled_at",
    "cancel_effective_at",
    "paused_at",
    "paused_until",
    "pause_used_at",
    "winback_used_at",
    "winback_push_sent_at",
    "pause_ending_push_sent_at",
)


def _has_column(table: str, column: str) -> bool:
    """Same guard as f7b1c3d8a924's: Base.metadata.create_all() runs
    before run_migrations() on a fresh database, so the columns may
    already exist by the time this revision runs."""
    bind = op.get_bind()
    if not sa.inspect(bind).has_table(table):
        return False
    return any(c["name"] == column for c in sa.inspect(bind).get_columns(table))


def upgrade() -> None:
    for name in _COLUMNS:
        if not _has_column(_TABLE, name):
            op.add_column(_TABLE, sa.Column(name, sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    for name in reversed(_COLUMNS):
        if _has_column(_TABLE, name):
            op.drop_column(_TABLE, name)
