"""push notifications: tokens, per-category prefs, send log

Backs app/push.py end to end:

  - `push_tokens` — one row per registered device (see routers/push.py::
    register_token). `timezone` (IANA name, reported by the client) is
    what lets scripts/send_scheduled_push.py's streak reminder fire in
    the evening *where the person actually is*, not at a fixed UTC hour.
  - `users.notification_prefs` — per-category opt-outs, JSON, missing key
    (or a NULL column on an existing row) means "on". See models.User's
    own docstring on why opt-out rather than opt-in.
  - `push_log` — one row per notification actually handed to Firebase,
    for debugging *and* so the cron-driven scheduled script can ask "did
    I already send this today" without any in-process memory of its own
    between runs (this app has no scheduler; see that script's docstring).

Revision ID: 8d82a0fd511d
Revises: d4a7e1c05b92
Create Date: 2026-09-19

(Re-parented onto the analytics stat-views migration d4a7e1c05b92 when the push
branch was merged with analytics + Grafana — it was written against 92081e10cd3f,
which would otherwise have left two Alembic heads. The tables it touches are
independent of the analytics ones.)
"""

from alembic import op
import sqlalchemy as sa

revision = "8d82a0fd511d"
down_revision = "d4a7e1c05b92"
branch_labels = None
depends_on = None


def _has_table(name: str) -> bool:
    """See f3a91d4c7e20's own comment on this helper — every migration
    since the 6cea28b2d137 baseline needs it for the same reason:
    app/main.py's create_all() has usually already made this table by
    the time this runs."""
    bind = op.get_bind()
    return sa.inspect(bind).has_table(name)


def _has_column(table: str, column: str) -> bool:
    bind = op.get_bind()
    if not sa.inspect(bind).has_table(table):
        return False
    return any(c["name"] == column for c in sa.inspect(bind).get_columns(table))


def upgrade() -> None:
    if not _has_column("users", "notification_prefs"):
        op.add_column("users", sa.Column("notification_prefs", sa.JSON(), nullable=True))

    if not _has_table("push_tokens"):
        # In practice this create_table below almost never actually runs
        # — app/main.py calls Base.metadata.create_all() before
        # run_migrations() on every startup (see f3a91d4c7e20's _has_table
        # docstring), so a brand new table like this one is normally
        # already created from models.py's own Column definitions by the
        # time this migration gets here, uniqueness-on-token included
        # (see PushToken.token's `unique=True, index=True`). This block
        # exists for the one path where that's not true — run_migrations()
        # invoked on its own, e.g. from scripts/, against a database that
        # skipped create_all() — and is written to produce the same
        # schema create_all() would: a single unique index on `token`
        # named the same way SQLAlchemy's own Column(unique=True,
        # index=True) convention would (ix_push_tokens_token), not a
        # separately-named UNIQUE CONSTRAINT, so there's exactly one
        # thing enforcing this regardless of which path created it.
        op.create_table(
            "push_tokens",
            sa.Column("id", sa.String(), primary_key=True),
            sa.Column(
                "user_id", sa.String(),
                sa.ForeignKey("users.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("token", sa.String(), nullable=False),
            sa.Column("platform", sa.String(), nullable=False),
            sa.Column("timezone", sa.String(), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
            sa.Column("last_seen_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        )
        op.create_index("ix_push_tokens_user_id", "push_tokens", ["user_id"])
        op.create_index("ix_push_tokens_token", "push_tokens", ["token"], unique=True)

    if not _has_table("push_log"):
        op.create_table(
            "push_log",
            sa.Column("id", sa.String(), primary_key=True),
            sa.Column(
                "user_id", sa.String(),
                sa.ForeignKey("users.id", ondelete="CASCADE"),
                nullable=False,
            ),
            sa.Column("category", sa.String(), nullable=False),
            sa.Column("title", sa.String(), nullable=False),
            sa.Column("body", sa.String(), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        )
        op.create_index("ix_push_log_user_id", "push_log", ["user_id"])
        op.create_index(
            "ix_push_log_user_category_created",
            "push_log",
            ["user_id", "category", "created_at"],
        )


def downgrade() -> None:
    if _has_table("push_log"):
        op.drop_table("push_log")
    if _has_table("push_tokens"):
        op.drop_table("push_tokens")
    if _has_column("users", "notification_prefs"):
        op.drop_column("users", "notification_prefs")
