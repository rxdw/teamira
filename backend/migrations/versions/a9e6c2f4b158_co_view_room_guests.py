"""co-view room guests: friends invited into one room

Adds co_view_room_guests (see models.CoViewRoomGuest). Same create-if-missing-
from-the-model approach as the other co-view migrations.

Revision ID: a9e6c2f4b158
Revises: f7c3d9b2e415
Create Date: 2026-10-01
"""
from alembic import op
import sqlalchemy as sa

revision = "a9e6c2f4b158"
down_revision = "f7c3d9b2e415"
branch_labels = None
depends_on = None


def upgrade() -> None:
    from app import models

    bind = op.get_bind()
    if not sa.inspect(bind).has_table("co_view_room_guests"):
        models.Base.metadata.tables["co_view_room_guests"].create(bind)


def downgrade() -> None:
    if sa.inspect(op.get_bind()).has_table("co_view_room_guests"):
        op.drop_table("co_view_room_guests")
