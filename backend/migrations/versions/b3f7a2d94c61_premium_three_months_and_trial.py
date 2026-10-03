"""premium: threeMonths duration + free-trial tracking

Two independent additions, bundled here because they landed in the same
paywall pass:

1. Adds "threeMonths" to the premiumduration enum, additively — see
   models.py::PremiumDuration's own comment on why this doesn't touch
   or remove "sixMonths": any existing purchase/gift row still
   referencing sixMonths stays perfectly valid, it's just no longer an
   option the mobile app offers going forward.

2. Adds user_premium_state.trial_started_at, so the one-time free
   trial (POST /premium/start-trial) has somewhere to record "this
   account has already had one" — see models.py::UserPremiumState's
   own comment on why that's a separate flag from premium_expires_at
   rather than folded into it.

Revision ID: b3f7a2d94c61
Revises: 8d82a0fd511d
Create Date: 2026-09-21
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "b3f7a2d94c61"
down_revision = "8d82a0fd511d"
branch_labels = None
depends_on = None


def _has_column(table: str, column: str) -> bool:
    """See f3a91d4c7e20's own _has_column (same helper, duplicated here
    rather than imported — Alembic revision modules aren't meant to
    import from each other). app/main.py calls
    Base.metadata.create_all() *before* run_migrations(), so on a fresh
    database SQLAlchemy has already created this column (it's already
    in models.py::UserPremiumState) by the time this runs; an unguarded
    add_column here collides with that, which is exactly what this
    revision was missing until this guard was added."""
    bind = op.get_bind()
    if not sa.inspect(bind).has_table(table):
        return False
    return any(c["name"] == column for c in sa.inspect(bind).get_columns(table))


def upgrade() -> None:
    if not _has_column("user_premium_state", "trial_started_at"):
        op.add_column(
            "user_premium_state",
            sa.Column("trial_started_at", sa.DateTime(timezone=True), nullable=True),
        )

    if op.get_bind().dialect.name != "postgresql":
        # SQLite/others store the enum as a plain string column — every
        # value the Python enum knows about just works, nothing to do.
        return
    # Same reasoning as 6cea28b2d137's own _ENUM_MIGRATIONS: `ALTER
    # TYPE ... ADD VALUE` can't run inside the same transaction Alembic
    # already has open for this revision, so it gets its own
    # autocommit_block().
    with op.get_context().autocommit_block():
        op.execute("ALTER TYPE premiumduration ADD VALUE IF NOT EXISTS 'threeMonths'")


def downgrade() -> None:
    # Deliberately unsupported — same stance as 6cea28b2d137's own
    # downgrade(): dropping an enum value that live rows might already
    # reference isn't a safe automatic operation. Restore from a backup
    # instead if this revision needs to be undone.
    raise NotImplementedError(
        "b3f7a2d94c61 has no downgrade path — see this module's docstring"
    )
