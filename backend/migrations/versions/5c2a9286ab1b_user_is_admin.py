"""users.is_admin — role-based admin access

Replaces the single shared-secret header (TEAMIRA_ADMIN_KEY, see
app/deps.py::require_teamira_admin in git history) that used to guard
every Teamira-picks admin endpoint. That secret was the whole access
model: one value, handed out over .env/Slack to whoever needed it,
un-attributable and un-revocable per person. This column plus
app/deps.py::require_admin_user turns "admin" into an actual property
of an actual account, checked via the same JWT login as everything
else. Nobody starts admin — see scripts/grant_admin.py to set the
first one after this migration runs.

Revision ID: 5c2a9286ab1b
Revises: 166a1551e982
Create Date: 2026-09-12
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "5c2a9286ab1b"
down_revision = "166a1551e982"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    existing_columns = {c["name"] for c in sa.inspect(bind).get_columns("users")}
    if "is_admin" in existing_columns:
        return
    op.add_column(
        "users",
        sa.Column("is_admin", sa.Boolean(), nullable=False, server_default=sa.false()),
    )


def downgrade() -> None:
    op.drop_column("users", "is_admin")
