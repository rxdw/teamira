"""watchlist drop reason

Backs the new "mark as dropped, honestly" flow (routers/watchlist.py) —
see that router's module docstring and models.WatchlistEntry.drop_reason
for why this exists: it's what lets sincerity.py's earn_honest_drop
actually fire for a real mid-watch drop, as opposed to a watch_later
item closed via "not for me" (earn_closed_gestalt, no reason needed).

Revision ID: e58a2c71b4f3
Revises: d47f6b1a9c02
Create Date: 2026-09-14
"""
from alembic import op
import sqlalchemy as sa

revision = "e58a2c71b4f3"
down_revision = "d47f6b1a9c02"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    existing_columns = {c["name"] for c in sa.inspect(bind).get_columns("watchlist_entries")}
    if "drop_reason" not in existing_columns:
        op.add_column("watchlist_entries", sa.Column("drop_reason", sa.String(), nullable=True))


def downgrade() -> None:
    op.drop_column("watchlist_entries", "drop_reason")
