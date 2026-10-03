"""premium: trial reminder series progress

Adds user_premium_state.trial_reminder_stage / trial_reminder_sent_at.
They record how far the "your free period is ending" push series
(app/trial.py, run hourly from scripts/send_scheduled_push.py) has got
for an account, so each reminder is sent at most once.

Revision ID: f7b1c3d8a924
Revises: e2c8b5a1d746
Create Date: 2026-09-28
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "f7b1c3d8a924"
down_revision = "e2c8b5a1d746"
branch_labels = None
depends_on = None

_TABLE = "user_premium_state"


def _has_column(table: str, column: str) -> bool:
    """Same guard as e2c8b5a1d746's: Base.metadata.create_all() runs
    before run_migrations() on a fresh database, so the columns may
    already exist by the time this revision runs."""
    bind = op.get_bind()
    if not sa.inspect(bind).has_table(table):
        return False
    return any(c["name"] == column for c in sa.inspect(bind).get_columns(table))


def upgrade() -> None:
    if not _has_column(_TABLE, "trial_reminder_stage"):
        op.add_column(
            _TABLE,
            sa.Column("trial_reminder_stage", sa.Integer(), nullable=False, server_default="0"),
        )
    if not _has_column(_TABLE, "trial_reminder_sent_at"):
        op.add_column(
            _TABLE,
            sa.Column("trial_reminder_sent_at", sa.DateTime(timezone=True), nullable=True),
        )


def downgrade() -> None:
    if _has_column(_TABLE, "trial_reminder_sent_at"):
        op.drop_column(_TABLE, "trial_reminder_sent_at")
    if _has_column(_TABLE, "trial_reminder_stage"):
        op.drop_column(_TABLE, "trial_reminder_stage")
