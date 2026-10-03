"""sincerity: real spends (recommendations, debt exemption, own-opinion)

Gives the three previously-dead SincerityReason spends somewhere real to
go — see app/sincerity.py's module docstring for the full product story.

Three schema changes, all additive:

- `recommendations`: backs the new staked-recommendation feature (see
  app/routers/recommendations.py and models.Recommendation).
- `watchlist_entries.debt_exempt`: a one-time flag set by
  spend_debt_settlement, checked by
  apply_stale_planned_decay_for_user to permanently exempt one item
  from further stale_debt charges.
- Two new SincerityReason values (`stake_expired`, `formed_own_opinion`)
  — Postgres enums need an explicit ADD VALUE; SQLite (tests) stores the
  column as a plain string, so every value the Python enum knows about
  already works there with nothing to migrate.

Revision ID: b1e6d94a2f70
Revises: e4b2a7c91d38
Create Date: 2026-09-24
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "b1e6d94a2f70"
down_revision = "e4b2a7c91d38"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()

    if bind.dialect.name == "postgresql":
        # Same autocommit_block() reasoning as d8e51f3a7c92's own
        # upgrade() — Postgres won't let ADD VALUE run inside the same
        # transaction as other DDL.
        with op.get_context().autocommit_block():
            op.execute("ALTER TYPE sincerityreason ADD VALUE IF NOT EXISTS 'formed_own_opinion'")
            op.execute("ALTER TYPE sincerityreason ADD VALUE IF NOT EXISTS 'stake_expired'")

    existing_columns = {c["name"] for c in sa.inspect(bind).get_columns("watchlist_entries")}
    if "debt_exempt" not in existing_columns:
        op.add_column(
            "watchlist_entries",
            sa.Column("debt_exempt", sa.Boolean(), nullable=False, server_default="false"),
        )

    # Same create_all()-may-have-already-made-it race as other tables in
    # this migrations folder (see c2ce9a945958's own comment).
    if "recommendations" in sa.inspect(bind).get_table_names():
        return

    _recommendation_status = sa.Enum(
        "pending", "hit", "missed", "expired", name="recommendationstatus",
    )
    _recommendation_status.create(bind, checkfirst=True)

    op.create_table(
        "recommendations",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("staker_id", sa.String(), sa.ForeignKey("users.id"), nullable=False, index=True),
        sa.Column("recipient_id", sa.String(), sa.ForeignKey("users.id"), nullable=False, index=True),
        sa.Column("source", sa.String(), nullable=False),
        sa.Column("media_id", sa.String(), nullable=False),
        sa.Column("title", sa.String(), nullable=False),
        sa.Column("predicted_rating", sa.Integer(), nullable=False),
        sa.Column("staked_amount", sa.Integer(), nullable=False),
        sa.Column("status", _recommendation_status, nullable=False, server_default="pending"),
        sa.Column("actual_rating", sa.Integer(), nullable=True),
        sa.Column("resolved_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
    )
    op.create_index(
        "ix_recommendations_recipient_status", "recommendations", ["recipient_id", "status"],
    )
    op.create_index(
        "ix_recommendations_staker_status", "recommendations", ["staker_id", "status"],
    )


def downgrade() -> None:
    op.drop_index("ix_recommendations_staker_status", table_name="recommendations")
    op.drop_index("ix_recommendations_recipient_status", table_name="recommendations")
    op.drop_table("recommendations")
    bind = op.get_bind()
    sa.Enum(name="recommendationstatus").drop(bind, checkfirst=True)
    op.drop_column("watchlist_entries", "debt_exempt")
    # No downgrade for the two new enum values — same stance as
    # d8e51f3a7c92 and b3f7a2d94c61 before it: dropping an enum value
    # that live rows might already reference isn't a safe automatic
    # operation.
