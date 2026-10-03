"""sincerity: second_chance (earn) and nudge_sent (spend)

Two more real reasons — see app/sincerity.py's module docstring for
why: "still only four things to spend on, still only five ways to
earn" was the next round of product feedback after b1e6d94a2f70 and
c7a3f0e58d21. No new tables or columns this time — second_chance reads
WatchlistEntry.updated_at (already there) and nudge_sent reads
CoViewEntry.created_at (already there); only the enum needs extending.

Revision ID: d94b2c6f81a3
Revises: c7a3f0e58d21
Create Date: 2026-09-28
"""
from alembic import op

# revision identifiers, used by Alembic.
revision = "d94b2c6f81a3"
down_revision = "c7a3f0e58d21"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name == "postgresql":
        with op.get_context().autocommit_block():
            op.execute("ALTER TYPE sincerityreason ADD VALUE IF NOT EXISTS 'second_chance'")
            op.execute("ALTER TYPE sincerityreason ADD VALUE IF NOT EXISTS 'nudge_sent'")
    # SQLite (tests) stores the column as a plain string, so both values
    # already work there with nothing to migrate — same note as every
    # prior enum-extending migration in this folder.


def downgrade() -> None:
    # No downgrade for either new enum value — same stance as every
    # prior migration that's added one.
    pass
