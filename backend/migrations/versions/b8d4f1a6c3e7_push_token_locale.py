"""push_tokens.locale: which language a device's pushes should be worded in

One nullable column. The app sends its interface language ("ru" / "en") with
every token registration (POST /push/tokens); app/push.py then words each push
for the device it is going to. NULL — every token registered before this
migration — means Russian, i.e. exactly what those devices have always received.

Revision ID: b8d4f1a6c3e7
Revises: a5c2e7d19b36
Create Date: 2026-10-08
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "b8d4f1a6c3e7"
down_revision = "a5c2e7d19b36"
branch_labels = None
depends_on = None


def _has_column(table: str, column: str) -> bool:
    """Same guard as every migration here: app/main.py runs
    `Base.metadata.create_all()` first, and on a fresh database that already
    builds the table with the column."""
    insp = sa.inspect(op.get_bind())
    return insp.has_table(table) and any(c["name"] == column for c in insp.get_columns(table))


def upgrade() -> None:
    if not _has_column("push_tokens", "locale"):
        op.add_column("push_tokens", sa.Column("locale", sa.String(length=8), nullable=True))


def downgrade() -> None:
    if _has_column("push_tokens", "locale"):
        op.drop_column("push_tokens", "locale")
