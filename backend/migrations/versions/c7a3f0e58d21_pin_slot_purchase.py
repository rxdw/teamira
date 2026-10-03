"""sincerity: badge-showcase pin slots (pin_slot_purchased)

One more real spend — see app/sincerity.py's module docstring for why
this one has no earn-side counterpart. Adds:

- `users.bonus_pin_slots`: how many extra badge-showcase slots this
  account has bought, on top of the free 3 (see
  routers/profile.py::pin_achievements/buy_pin_slot).
- `pin_slot_purchased`: the new SincerityReason value the purchase is
  logged under.

Revision ID: c7a3f0e58d21
Revises: b1e6d94a2f70
Create Date: 2026-09-27
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "c7a3f0e58d21"
down_revision = "b1e6d94a2f70"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()

    if bind.dialect.name == "postgresql":
        with op.get_context().autocommit_block():
            op.execute("ALTER TYPE sincerityreason ADD VALUE IF NOT EXISTS 'pin_slot_purchased'")

    existing_columns = {c["name"] for c in sa.inspect(bind).get_columns("users")}
    if "bonus_pin_slots" not in existing_columns:
        op.add_column(
            "users",
            sa.Column("bonus_pin_slots", sa.Integer(), nullable=False, server_default="0"),
        )


def downgrade() -> None:
    op.drop_column("users", "bonus_pin_slots")
    # No downgrade for the new enum value — same stance as every prior
    # migration that's added one (see b1e6d94a2f70's own note).
