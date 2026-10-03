"""co-view rooms: rooms, members, events

Adds the three tables behind "Гостиная" (see app/co_view_room.py for the
rules): co_view_rooms, co_view_room_members, co_view_room_events. All hang
off partner_links / users with ON DELETE CASCADE (or SET NULL where a
deleted person should not delete the log).

app/main.py runs Base.metadata.create_all() before run_migrations(), so on
a fresh database the tables already exist by the time this runs. Each
table is created only if it is missing, from the model's own definition,
so the two paths cannot drift.

Revision ID: e5b2a8c1d730
Revises: c4d1e7a92b38
Create Date: 2026-09-30
"""
from alembic import op
import sqlalchemy as sa

revision = "e5b2a8c1d730"
down_revision = "c4d1e7a92b38"
branch_labels = None
depends_on = None

_TABLES = ("co_view_rooms", "co_view_room_members", "co_view_room_events")


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
    op.execute("DROP TYPE IF EXISTS coviewroomstatus")
