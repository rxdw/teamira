"""pair album: settings, sealed notes, time capsules

Adds the five tables behind the premium "Альбом пары" (see
app/pair_album.py for the rules): pair_album_settings, pair_notes,
pair_capsules, pair_capsule_letters, pair_capsule_reads. All of them hang
off partner_links with ON DELETE CASCADE.

app/main.py runs Base.metadata.create_all() before run_migrations(), so on
a fresh database (and on any database that has booted this code once) the
tables already exist by the time this revision runs. Each table is created
only if it is missing, from the model's own definition, so the schema can't
drift between the two paths.

Revision ID: c4d1e7a92b38
Revises: a3e9c1b7d502
Create Date: 2026-09-29
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "c4d1e7a92b38"
down_revision = "a3e9c1b7d502"
branch_labels = None
depends_on = None

# Creation order matters: letters/reads reference capsules.
_TABLES = (
    "pair_album_settings",
    "pair_notes",
    "pair_capsules",
    "pair_capsule_letters",
    "pair_capsule_reads",
)


def upgrade() -> None:
    from app import models  # imported here so the migration module stays cheap to load

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
