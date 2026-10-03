"""user_premium_state table

Backs the server-owned premium state in app/routers/premium.py — see
that module's docstring for why premium status moved off the mobile
app's local-only SharedPreferences.

Revision ID: c2ce9a945958
Revises: b6c97a145511
Create Date: 2026-09-11
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "c2ce9a945958"
down_revision = "b6c97a145511"
branch_labels = None
depends_on = None

_premium_plan_kind = sa.Enum("individual", "couple", name="premiumplankind")
_premium_duration = sa.Enum("month", "sixMonths", "year", name="premiumduration")


def upgrade() -> None:
    bind = op.get_bind()
    _premium_plan_kind.create(bind, checkfirst=True)
    _premium_duration.create(bind, checkfirst=True)
    # See b6c97a145511's own comment on why this table can already
    # exist even on what looks like a fresh migration run — create_all()
    # (app/main.py::on_startup, which runs before Alembic) creates it
    # straight from the UserPremiumState model the moment that model
    # exists in models.py, regardless of whether this migration has
    # "officially" run yet.
    if "user_premium_state" in sa.inspect(bind).get_table_names():
        return
    op.create_table(
        "user_premium_state",
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id"), primary_key=True),
        sa.Column("is_premium", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("plan_kind", _premium_plan_kind, nullable=True),
        sa.Column("plan_duration", _premium_duration, nullable=True),
        sa.Column("purchased_at", sa.DateTime(), nullable=True),
        sa.Column("ai_asks_used", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("ai_asks_month", sa.String(), nullable=True),
    )


def downgrade() -> None:
    op.drop_table("user_premium_state")
    bind = op.get_bind()
    _premium_plan_kind.drop(bind, checkfirst=True)
    _premium_duration.drop(bind, checkfirst=True)
