"""sincerity points

Backs the "sincerity points" feature (see app/sincerity.py's module
docstring for the full product reasoning): a symbolic, purely-reflective
running total on User, plus a full transaction ledger explaining how it
got there.

Revision ID: d47f6b1a9c02
Revises: c2ce9a945958
Create Date: 2026-09-13
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "d47f6b1a9c02"
down_revision = "c2ce9a945958"
branch_labels = None
depends_on = None

_sincerity_reason = sa.Enum(
    "closed_gestalt",
    "revised_rating",
    "accurate_recommendation",
    "honest_drop",
    "recommendation_stake",
    "stake_forfeited",
    "spoiler_unlock",
    "debt_settled",
    "stale_debt",
    name="sincerityreason",
)


def upgrade() -> None:
    bind = op.get_bind()
    existing_columns = {c["name"] for c in sa.inspect(bind).get_columns("users")}
    if "sincerity_balance" not in existing_columns:
        op.add_column(
            "users",
            sa.Column("sincerity_balance", sa.Integer(), nullable=False, server_default="0"),
        )
    if "sincerity_visible_to_friends" not in existing_columns:
        op.add_column(
            "users",
            sa.Column("sincerity_visible_to_friends", sa.Boolean(), nullable=False, server_default="false"),
        )

    _sincerity_reason.create(bind, checkfirst=True)

    # Same create_all()-may-have-already-made-it race as other tables in
    # this migrations folder (see c2ce9a945958's own comment) — app/
    # main.py::on_startup runs create_all() straight from models.py
    # before Alembic ever gets a turn.
    if "sincerity_transactions" in sa.inspect(bind).get_table_names():
        return
    op.create_table(
        "sincerity_transactions",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id"), nullable=False, index=True),
        sa.Column("delta", sa.Integer(), nullable=False),
        sa.Column("reason", _sincerity_reason, nullable=False),
        sa.Column("note", sa.String(), nullable=True),
        sa.Column("related_entry_id", sa.String(), nullable=True),
        sa.Column("related_user_id", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
    )


def downgrade() -> None:
    op.drop_table("sincerity_transactions")
    bind = op.get_bind()
    _sincerity_reason.drop(bind, checkfirst=True)
    op.drop_column("users", "sincerity_visible_to_friends")
    op.drop_column("users", "sincerity_balance")
