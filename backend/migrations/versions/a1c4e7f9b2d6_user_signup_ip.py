"""users.signup_ip

Backs the promo-code anti-self-dealing check in
app/routers/premium.py::purchase — see that check's own comment for
why. Same best-effort fingerprint models.Referral.ip_at_signup already
carries for the invite-link flow, just also captured for EVERY account
(not only ones that were themselves referred), since a promo code can
be redeemed by an account that never went through the invite-link flow
at all.

Nullable and NOT backfilled for existing accounts on purpose — same
"best-effort, not retroactive" stance as ip_at_signup: old accounts
simply have signup_ip = NULL, and the check that reads it already
treats a NULL on either side as "can't compare, don't block" rather
than as a match.

Revision ID: a1c4e7f9b2d6
Revises: 8f1a2c9e4d3b
Create Date: 2026-09-13
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "a1c4e7f9b2d6"
down_revision = "8f1a2c9e4d3b"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    existing_columns = {c["name"] for c in sa.inspect(bind).get_columns("users")}
    if "signup_ip" in existing_columns:
        return
    op.add_column("users", sa.Column("signup_ip", sa.String(), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "signup_ip")
