"""shared couple diary, partner prefs, challenges

Three features in one revision, because they land together and one of
them (challenges) reads a column another one adds (diary_entries.country,
diary_entries.watched_together) — splitting them would create an ordering
dependency between revisions for no benefit.

  - `diary_entries.shared_link_id` / `.watched_together` / `.country` —
    the shared-diary view over personal entries. See
    models.DiaryEntry's own docstrings for why the shared diary is a tag
    on the personal row rather than a second table.
  - `partner_prefs` — per-person, per-circle sharing settings.
  - `challenge_progress` — completion/claim/seen state for weekly and
    yearly challenges. Progress itself is never stored here; see
    app/challenges.py.

MERGE NOTE — this revision also has two `down_revision`s on purpose.
Before it, the migration tree had genuinely forked at c2ce9a945958 into
two independent heads (a1c4e7f9b2d6, from the referral/admin line, and
e58a2c71b4f3, from the sincerity line). `app/migrate.py` runs
`command.upgrade(cfg, "head")` — singular — which raises
"Multiple head revisions are present" the moment there's more than one,
so that fork would have failed at startup on any database that hadn't
already been migrated past it by hand. This revision is the merge point
that resolves it back to a single head; nothing about the merge is
specific to these three features, it just had to happen here.

Revision ID: f3a91d4c7e20
Revises: a1c4e7f9b2d6, e58a2c71b4f3
Create Date: 2026-09-15
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "f3a91d4c7e20"
down_revision = ("a1c4e7f9b2d6", "e58a2c71b4f3")
branch_labels = None
depends_on = None


def _has_table(name: str) -> bool:
    """Every migration after the 6cea28b2d137 baseline guards itself this
    way — see b6c97a145511's own comment for the full reasoning. Short
    version: app/main.py calls `Base.metadata.create_all()` *before*
    `run_migrations()`, so on a fresh database SQLAlchemy has already
    created every table in models.py by the time this runs, and an
    unguarded CREATE TABLE here would collide with it."""
    bind = op.get_bind()
    return sa.inspect(bind).has_table(name)


def _has_column(table: str, column: str) -> bool:
    bind = op.get_bind()
    if not sa.inspect(bind).has_table(table):
        return False
    return any(c["name"] == column for c in sa.inspect(bind).get_columns(table))


def upgrade() -> None:
    # --- diary_entries: shared diary + country snapshot -------------------
    if not _has_column("diary_entries", "shared_link_id"):
        op.add_column(
            "diary_entries",
            sa.Column("shared_link_id", sa.String(), nullable=True),
        )
        op.create_foreign_key(
            "fk_diary_entries_shared_link_id",
            "diary_entries",
            "partner_links",
            ["shared_link_id"],
            ["id"],
        )
        # The shared diary's only query shape is "this link's rows, newest
        # first" — a composite index rather than a plain one on
        # shared_link_id alone, so the ORDER BY is served by the index too
        # instead of sorting a whole circle's history on every page.
        op.create_index(
            "ix_diary_entries_shared_link_watched_at",
            "diary_entries",
            ["shared_link_id", "watched_at"],
        )

    if not _has_column("diary_entries", "watched_together"):
        op.add_column(
            "diary_entries",
            sa.Column(
                "watched_together",
                sa.Integer(),
                nullable=True,
                server_default="0",
            ),
        )

    if not _has_column("diary_entries", "country"):
        op.add_column("diary_entries", sa.Column("country", sa.String(), nullable=True))

    # --- partner_prefs ----------------------------------------------------
    if not _has_table("partner_prefs"):
        op.create_table(
            "partner_prefs",
            sa.Column("id", sa.String(), primary_key=True),
            sa.Column("user_id", sa.String(), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("link_id", sa.String(), sa.ForeignKey("partner_links.id"), nullable=False),
            sa.Column("auto_share_logs", sa.Boolean(), nullable=False, server_default="true"),
            sa.Column("share_ratings", sa.Boolean(), nullable=False, server_default="true"),
            sa.Column("share_notes", sa.Boolean(), nullable=False, server_default="false"),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
            sa.UniqueConstraint("user_id", "link_id", name="uq_partner_prefs"),
        )
        op.create_index("ix_partner_prefs_user_id", "partner_prefs", ["user_id"])
        op.create_index("ix_partner_prefs_link_id", "partner_prefs", ["link_id"])

    # --- challenge_progress ----------------------------------------------
    if not _has_table("challenge_progress"):
        op.create_table(
            "challenge_progress",
            sa.Column("id", sa.String(), primary_key=True),
            sa.Column("user_id", sa.String(), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("challenge_id", sa.String(), nullable=False),
            sa.Column("period_key", sa.String(), nullable=False),
            sa.Column("completed_at", sa.DateTime(), nullable=True),
            sa.Column("claimed_at", sa.DateTime(), nullable=True),
            sa.Column("seen_at", sa.DateTime(), nullable=True),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
            sa.UniqueConstraint(
                "user_id", "challenge_id", "period_key", name="uq_challenge_progress"
            ),
        )
        op.create_index("ix_challenge_progress_user_id", "challenge_progress", ["user_id"])
        op.create_index(
            "ix_challenge_progress_user_period",
            "challenge_progress",
            ["user_id", "period_key"],
        )


def downgrade() -> None:
    # Dropping challenge_progress loses claimed rewards, which is real
    # data loss — but a downgrade of this revision is explicitly asking
    # for the feature to not exist, and leaving an orphan table behind
    # would be worse than honest removal.
    if _has_table("challenge_progress"):
        op.drop_table("challenge_progress")
    if _has_table("partner_prefs"):
        op.drop_table("partner_prefs")
    if _has_column("diary_entries", "country"):
        op.drop_column("diary_entries", "country")
    if _has_column("diary_entries", "watched_together"):
        op.drop_column("diary_entries", "watched_together")
    if _has_column("diary_entries", "shared_link_id"):
        op.drop_index("ix_diary_entries_shared_link_watched_at", table_name="diary_entries")
        op.drop_constraint(
            "fk_diary_entries_shared_link_id", "diary_entries", type_="foreignkey"
        )
        op.drop_column("diary_entries", "shared_link_id")
