"""circle reviews: joint review of an evening watched together

Adds circle_reviews and circle_review_entries (see app/circle_review.py).
Same create-if-missing-from-the-model approach as the pair album and
co-view room migrations; create_all() normally got there first.

Revision ID: f7c3d9b2e415
Revises: e5b2a8c1d730
Create Date: 2026-09-30
"""
from alembic import op
import sqlalchemy as sa

revision = "f7c3d9b2e415"
down_revision = "e5b2a8c1d730"
branch_labels = None
depends_on = None

_TABLES = ("circle_reviews", "circle_review_entries")


def upgrade() -> None:
    from app import models

    bind = op.get_bind()
    inspector = sa.inspect(bind)
    for name in _TABLES:
        if not inspector.has_table(name):
            models.Base.metadata.tables[name].create(bind)


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    for name in reversed(_TABLES):
        if inspector.has_table(name):
            op.drop_table(name)
