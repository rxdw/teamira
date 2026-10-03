"""analytics_events table + reporting views

Backs the first-party product analytics (app/routers/analytics.py,
docs/analytics.md): one row per event the mobile app reports.

Same guarded-create shape as b6c97a145511_rate_limit_hits — main.py's
on_startup runs Base.metadata.create_all() *before* Alembic, so on any
normal boot the table already exists by the time this runs and only the
views below are new. The full create_table stays here anyway, so
`alembic upgrade head` against an empty database (no create_all first)
still ends up in the same place.

The three views exist for Metabase / plain psql (see docs/analytics.md):
they hide the window-function SQL that turns raw events into "seconds
spent on a screen", so someone building a dashboard by clicking can pick
`v_analytics_screen_views` and group by `screen`. Postgres-only, and
CREATE OR REPLACE, so re-running is safe and changing a view later is a
new revision, not an edit to this one.

Revision ID: c9e4b7a21f58
Revises: 92081e10cd3f
Create Date: 2026-09-19
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = "c9e4b7a21f58"
down_revision = "92081e10cd3f"
branch_labels = None
depends_on = None


_VIEWS = {
    # Every screen/sheet opening, with how long the person stayed until
    # their next screen change (or until the app went to the background).
    # Capped at 10 minutes: a phone left face-up on a desk would otherwise
    # make one screen look like the most-used one in the app.
    "v_analytics_screen_views": """
        SELECT
            id,
            ts,
            (ts AT TIME ZONE 'UTC')::date                AS day,
            anon_id,
            user_id,
            session_id,
            screen,
            COALESCE(props->>'kind', 'screen')           AS kind,
            COALESCE(props->>'nav',  'push')             AS nav,
            platform,
            app_version,
            build,
            locale,
            LEAST(EXTRACT(EPOCH FROM (next_ts - ts)), 600)::int AS seconds_on_screen
        FROM (
            SELECT
                e.*,
                LEAD(e.ts) OVER (PARTITION BY e.session_id ORDER BY e.ts, e.id) AS next_ts
            FROM analytics_events e
            WHERE e.name IN ('screen_view', 'app_background')
        ) t
        WHERE name = 'screen_view'
    """,
    # One row per day and build: how many devices/people/sessions were active.
    "v_analytics_daily_active": """
        SELECT
            (ts AT TIME ZONE 'UTC')::date          AS day,
            build,
            COUNT(DISTINCT anon_id)                AS active_devices,
            COUNT(DISTINCT user_id)                AS signed_in_users,
            COUNT(DISTINCT session_id)             AS sessions,
            COUNT(*)                               AS events
        FROM analytics_events
        GROUP BY 1, 2
    """,
    # One row per day, build and event name — for "how often is X used".
    "v_analytics_events_daily": """
        SELECT
            (ts AT TIME ZONE 'UTC')::date          AS day,
            build,
            name,
            COUNT(*)                               AS events,
            COUNT(DISTINCT anon_id)                AS devices
        FROM analytics_events
        WHERE name <> 'screen_view'
        GROUP BY 1, 2, 3
    """,
}


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "analytics_events" not in inspector.get_table_names():
        props_type = postgresql.JSONB() if bind.dialect.name == "postgresql" else sa.JSON()
        op.create_table(
            "analytics_events",
            sa.Column("id", sa.BigInteger().with_variant(sa.Integer(), "sqlite"), primary_key=True, autoincrement=True),
            sa.Column("event_id", sa.String(40), nullable=False, unique=True),
            sa.Column("ts", sa.DateTime(timezone=True), nullable=False),
            sa.Column("received_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("anon_id", sa.String(40), nullable=False),
            sa.Column("user_id", sa.String(), nullable=True),
            sa.Column("session_id", sa.String(40), nullable=False),
            sa.Column("name", sa.String(64), nullable=False),
            sa.Column("screen", sa.String(80), nullable=True),
            sa.Column("props", props_type, nullable=True),
            sa.Column("platform", sa.String(16), nullable=True),
            sa.Column("app_version", sa.String(32), nullable=True),
            sa.Column("build", sa.String(8), nullable=True),
            sa.Column("locale", sa.String(8), nullable=True),
        )
        op.create_index("ix_analytics_events_ts", "analytics_events", ["ts"])
        op.create_index("ix_analytics_events_name_ts", "analytics_events", ["name", "ts"])
        op.create_index("ix_analytics_events_anon_ts", "analytics_events", ["anon_id", "ts"])
        op.create_index("ix_analytics_events_user_id", "analytics_events", ["user_id"])

    if bind.dialect.name == "postgresql":
        for name, select_sql in _VIEWS.items():
            op.execute(f"CREATE OR REPLACE VIEW {name} AS {select_sql}")


def downgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name == "postgresql":
        for name in reversed(list(_VIEWS)):
            op.execute(f"DROP VIEW IF EXISTS {name}")
    op.drop_table("analytics_events")
