"""referrals: extend milestone ladder, drop standing influencer discount

Product decision: a referrer's reward for being prolific should never
be a cut of their OWN future purchases (see routers/referrals.py's
removed INFLUENCER_* tunables) — it should look exactly like the
existing 1/5/10 milestone ladder does, just repeating: every
RECURRING_MILESTONE_STEP confirmed invites past 10 grants another flat
RECURRING_MILESTONE_DAYS (capped at the same 90 days the 10th-invite
tier already grants — nothing here ever hands out more than that in
one go). This migration only adds the one new enum value that ladder
needs (models.ReferralRewardReason.milestone_recurring); the removal
of the old discount fields is pure application code, nothing there
touches the schema.

Revision ID: d8e51f3a7c92
Revises: a7c3f0e91b44
Create Date: 2026-09-21
"""
from alembic import op

# revision identifiers, used by Alembic.
revision = "d8e51f3a7c92"
down_revision = "a7c3f0e91b44"
branch_labels = None
depends_on = None


def upgrade() -> None:
    if op.get_bind().dialect.name != "postgresql":
        # SQLite/others store the enum as a plain string column — every
        # value the Python enum knows about just works, nothing to do.
        return
    # Same autocommit_block() reasoning as b3f7a2d94c61's own upgrade().
    with op.get_context().autocommit_block():
        op.execute("ALTER TYPE referralrewardreason ADD VALUE IF NOT EXISTS 'milestone_recurring'")


def downgrade() -> None:
    # Same stance as b3f7a2d94c61 and 6cea28b2d137 before it — dropping
    # an enum value that live rows might already reference isn't a safe
    # automatic operation.
    raise NotImplementedError(
        "d8e51f3a7c92 has no downgrade path — see this module's docstring"
    )
