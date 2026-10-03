"""partner_links owner_id/partner_id indexes

routers/partner.py's `_active_link` — "who's my standing co-viewing
partner", called on essentially every co-viewing-related request —
filters `owner_id == user_id OR partner_id == user_id` with no index on
either column. Grows with total ever-linked users, not with diary/
activity volume, so slower-growing than the tables this pass originally
went looking at — but a real, previously undetected gap in exactly the
"which hot columns are missing an index" audit this migration is part
of. See models.py's PartnerLink.owner_id/partner_id for the full
reasoning on two single-column indexes here instead of one composite.

Revision ID: 166a1551e982
Revises: c2ce9a945958
Create Date: 2026-09-11
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "166a1551e982"
down_revision = "c2ce9a945958"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    existing = {ix["name"] for ix in sa.inspect(bind).get_indexes("partner_links")}
    # See b6c97a145511's own comment: create_all() (runs before Alembic
    # in app/main.py::on_startup) already creates these two indexes
    # straight from PartnerLink.owner_id/partner_id's own index=True,
    # so this migration is a no-op wherever that already happened.
    if "ix_partner_links_owner_id" not in existing:
        op.create_index("ix_partner_links_owner_id", "partner_links", ["owner_id"])
    if "ix_partner_links_partner_id" not in existing:
        op.create_index("ix_partner_links_partner_id", "partner_links", ["partner_id"])


def downgrade() -> None:
    op.drop_index("ix_partner_links_partner_id", table_name="partner_links")
    op.drop_index("ix_partner_links_owner_id", table_name="partner_links")
