"""referral program — referrals, referral_rewards, promo_codes,
user_premium_state.premium_expires_at

Backs app/routers/referrals.py — see that module's own docstring for
the shape of the program. Three new tables plus one new column on the
existing premium table:

  - referrals: one row per (referrer, referred) pair, created at
    signup, carrying the anti-fraud verification state.
  - referral_rewards: append-only payout log (milestone bonuses +
    purchase-triggered bonus).
  - promo_codes: one shareable purchase-discount code per referrer.
  - user_premium_state.premium_expires_at: where referral-granted bonus
    days actually land — see models.UserPremiumState's own comment on
    how this combines with the pre-existing `is_premium` flag.

Revision ID: 8f1a2c9e4d3b
Revises: 5c2a9286ab1b
Create Date: 2026-09-13
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "8f1a2c9e4d3b"
down_revision = "5c2a9286ab1b"
branch_labels = None
depends_on = None

_referral_status = sa.Enum(
    "pending", "verified", "rewarded", "rejected", name="referralstatus"
)
_referral_reward_reason = sa.Enum(
    "milestone_1", "milestone_5", "milestone_10", "purchase_bonus", "referred_welcome",
    name="referralrewardreason"
)


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    _referral_status.create(bind, checkfirst=True)
    _referral_reward_reason.create(bind, checkfirst=True)

    # Same reasoning as b6c97a145511/c2ce9a945958: create_all()
    # (app/main.py::on_startup, runs before Alembic) already creates
    # anything models.py currently declares — including this column and
    # all three tables below, with the same indexes, since Referral/
    # ReferralReward/PromoCode already have index=True set on the
    # matching columns. Guard each piece individually so this migration
    # is a no-op wherever create_all() got there first, and still does
    # the real work on a database that predates these models.
    existing_columns = {c["name"] for c in inspector.get_columns("user_premium_state")}
    if "premium_expires_at" not in existing_columns:
        op.add_column(
            "user_premium_state",
            sa.Column("premium_expires_at", sa.DateTime(), nullable=True),
        )

    existing_tables = set(inspector.get_table_names())

    if "referrals" not in existing_tables:
        op.create_table(
            "referrals",
            sa.Column("id", sa.String(), primary_key=True),
            sa.Column("referrer_id", sa.String(), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("referred_id", sa.String(), sa.ForeignKey("users.id"), nullable=False, unique=True),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
            sa.Column("status", _referral_status, nullable=False, server_default="pending"),
            sa.Column("verified_at", sa.DateTime(), nullable=True),
            sa.Column("streak_days_current", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("entries_count_snapshot", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("ip_at_signup", sa.String(), nullable=True),
            sa.Column("device_fingerprint", sa.String(), nullable=True),
        )
        op.create_index("ix_referrals_referrer_id", "referrals", ["referrer_id"])
        op.create_index("ix_referrals_referred_id", "referrals", ["referred_id"])
        op.create_index("ix_referrals_referrer_status", "referrals", ["referrer_id", "status"])

    if "referral_rewards" not in existing_tables:
        op.create_table(
            "referral_rewards",
            sa.Column("id", sa.String(), primary_key=True),
            sa.Column("user_id", sa.String(), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("reason", _referral_reward_reason, nullable=False),
            sa.Column("granted_days", sa.Integer(), nullable=True),
            sa.Column("granted_at", sa.DateTime(), server_default=sa.func.now()),
            sa.Column("source_referral_id", sa.String(), sa.ForeignKey("referrals.id"), nullable=True),
        )
        op.create_index("ix_referral_rewards_user_id", "referral_rewards", ["user_id"])

    if "promo_codes" not in existing_tables:
        op.create_table(
            "promo_codes",
            sa.Column("id", sa.String(), primary_key=True),
            sa.Column("code", sa.String(), nullable=False, unique=True),
            sa.Column("referrer_id", sa.String(), sa.ForeignKey("users.id"), nullable=False, unique=True),
            sa.Column("referred_id", sa.String(), sa.ForeignKey("users.id"), nullable=True),
            sa.Column("discount_percent", sa.Integer(), nullable=False, server_default="15"),
            sa.Column("used_at", sa.DateTime(), nullable=True),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
        )
        op.create_index("ix_promo_codes_code", "promo_codes", ["code"])
        op.create_index("ix_promo_codes_referrer_id", "promo_codes", ["referrer_id"])
        op.create_index("ix_promo_codes_referred_id", "promo_codes", ["referred_id"])


def downgrade() -> None:
    op.drop_table("promo_codes")
    op.drop_table("referral_rewards")
    op.drop_index("ix_referrals_referrer_status", table_name="referrals")
    op.drop_index("ix_referrals_referred_id", table_name="referrals")
    op.drop_index("ix_referrals_referrer_id", table_name="referrals")
    op.drop_table("referrals")
    op.drop_column("user_premium_state", "premium_expires_at")

    bind = op.get_bind()
    _referral_reward_reason.drop(bind, checkfirst=True)
    _referral_status.drop(bind, checkfirst=True)
