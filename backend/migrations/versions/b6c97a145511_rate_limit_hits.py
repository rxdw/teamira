"""rate_limit_hits table

Backs the Postgres-based rate limiter in app/rate_limit.py — see that
module's docstring for why this replaced an in-process dict. This is
the first migration in this app written as normal typed Alembic
operations rather than raw SQL — see revision 6cea28b2d137's own
docstring for why *that* one is the exception, not the pattern.

Revision ID: b6c97a145511
Revises: 6cea28b2d137
Create Date: 2026-09-11
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "b6c97a145511"
down_revision = "6cea28b2d137"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Guarded rather than a bare create_table(): on any database that
    # already went through this app's pre-Alembic life (see migrate.py's
    # own docstring on the old `_run_startup_migrations()`), this table
    # can already exist even though alembic_version says otherwise —
    # the baseline revision (6cea28b2d137) captured the schema as it
    # stood at the moment it was frozen, and rate_limit_hits was added
    # by that old raw-SQL path independently afterward on some already-
    # running databases, but not others. Without this check, upgrade()
    # unconditionally CREATE TABLEs and fails with "relation already
    # exists" on exactly those databases, even though nothing is
    # actually wrong with their schema.
    inspector = sa.inspect(op.get_bind())
    if "rate_limit_hits" in inspector.get_table_names():
        return
    op.create_table(
        "rate_limit_hits",
        sa.Column("limiter", sa.String(), primary_key=True),
        sa.Column("key", sa.String(), primary_key=True),
        sa.Column("window_start", sa.Integer(), primary_key=True),
        sa.Column("count", sa.Integer(), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("rate_limit_hits")
