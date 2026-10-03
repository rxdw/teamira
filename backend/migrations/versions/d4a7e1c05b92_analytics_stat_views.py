"""reporting views for dashboards: business counts + cohort retention

Follow-up to c9e4b7a21f58. That revision made the raw event table and three
views over it; this adds the four that a dashboard (Grafana — see
docs/analytics.md, "Способ Б") needs beyond it:

  v_analytics_registrations_daily   sign-ups per day            (from users)
  v_analytics_diary_daily           diary entries logged per day, by media type
  v_analytics_premium_daily         premium purchases per day, by plan
  v_analytics_retention             per first-seen day: cohort size and how
                                    many devices came back on day 1 / day 7

Why these are VIEWS rather than a grant on the tables: the dashboard
connects with a read-only role that must never be able to read `users`
(e-mail addresses, password hashes). A view runs with its *owner's*
privileges, so the role can be granted SELECT on the view alone and sees
only the counts it exposes. Nothing here selects a name, an e-mail or an
id — only dates, categories and counts.

Two things to know before changing the tables underneath:

  * Postgres refuses `ALTER COLUMN ... TYPE` (and DROP COLUMN) on a column
    a view reads. `users.created_at`, `diary_entries.created_at`/`media_type`
    and `user_premium_state.purchased_at`/`plan_kind`/`plan_duration` are now
    read by views, so a future migration touching them must
    `DROP VIEW IF EXISTS v_analytics_...` first and let this revision's
    definitions (or a newer one) recreate them.
  * `v_analytics_retention` scans analytics_events with a correlated
    EXISTS; fine for the first million-ish rows, and the retention setting
    (ANALYTICS_RETENTION_DAYS) bounds it. If it ever gets slow, materialise
    it — the column contract below is what the dashboard depends on.

Postgres-only and CREATE OR REPLACE, same as the previous revision. Each
view is created only if every table it reads exists, so `alembic upgrade
head` on an unusual empty database degrades to "fewer views" instead of
failing.

Revision ID: d4a7e1c05b92
Revises: c9e4b7a21f58
Create Date: 2026-09-20
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "d4a7e1c05b92"
down_revision = "c9e4b7a21f58"
branch_labels = None
depends_on = None


# name -> (tables it reads, SELECT)
_VIEWS = {
    "v_analytics_registrations_daily": (
        ["users"],
        """
        SELECT
            (created_at AT TIME ZONE 'UTC')::date AS day,
            COUNT(*)                              AS registrations
        FROM users
        WHERE created_at IS NOT NULL
        GROUP BY 1
        """,
    ),
    "v_analytics_diary_daily": (
        ["diary_entries"],
        """
        SELECT
            (created_at AT TIME ZONE 'UTC')::date AS day,
            media_type::text                      AS media_type,
            COUNT(*)                              AS entries,
            COUNT(DISTINCT user_id)               AS people
        FROM diary_entries
        WHERE created_at IS NOT NULL
        GROUP BY 1, 2
        """,
    ),
    "v_analytics_premium_daily": (
        ["user_premium_state"],
        """
        SELECT
            (purchased_at AT TIME ZONE 'UTC')::date AS day,
            COALESCE(plan_kind::text, '?')          AS plan_kind,
            COALESCE(plan_duration::text, '?')      AS plan_duration,
            COUNT(*)                                AS purchases
        FROM user_premium_state
        WHERE purchased_at IS NOT NULL
        GROUP BY 1, 2, 3
        """,
    ),
    # One row per (first-seen day, build). `eligible_*` is the cohort size when
    # that many days have already passed (otherwise 0): dividing returned by
    # eligible over any date range gives an honest rate, without counting
    # yesterday's installs as "failed to come back on day 7".
    "v_analytics_retention": (
        ["analytics_events"],
        """
        SELECT
            f.cohort_day                                                   AS day,
            f.build,
            COUNT(*)                                                       AS cohort_size,
            COUNT(*) FILTER (WHERE f.cohort_day + 1 <= CURRENT_DATE)       AS eligible_d1,
            COUNT(*) FILTER (WHERE f.cohort_day + 1 <= CURRENT_DATE
                AND EXISTS (SELECT 1 FROM active a
                            WHERE a.anon_id = f.anon_id
                              AND a.build IS NOT DISTINCT FROM f.build
                              AND a.day = f.cohort_day + 1))               AS returned_d1,
            COUNT(*) FILTER (WHERE f.cohort_day + 7 <= CURRENT_DATE)       AS eligible_d7,
            COUNT(*) FILTER (WHERE f.cohort_day + 7 <= CURRENT_DATE
                AND EXISTS (SELECT 1 FROM active a
                            WHERE a.anon_id = f.anon_id
                              AND a.build IS NOT DISTINCT FROM f.build
                              AND a.day = f.cohort_day + 7))               AS returned_d7
        FROM (
            SELECT anon_id, build, MIN((ts AT TIME ZONE 'UTC')::date) AS cohort_day
            FROM analytics_events
            GROUP BY anon_id, build
        ) f
        GROUP BY f.cohort_day, f.build
        """,
    ),
}

# `active` is a CTE shared by the retention view; SQL views can't declare a
# CTE separately from the SELECT, so it's prepended here.
_RETENTION_CTE = """
        WITH active AS (
            SELECT DISTINCT anon_id, build, (ts AT TIME ZONE 'UTC')::date AS day
            FROM analytics_events
        )
"""


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return
    existing = set(sa.inspect(bind).get_table_names())
    for name, (tables, select_sql) in _VIEWS.items():
        if not all(t in existing for t in tables):
            continue
        body = (_RETENTION_CTE + select_sql) if name == "v_analytics_retention" else select_sql
        op.execute(f"CREATE OR REPLACE VIEW {name} AS {body}")


def downgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name == "postgresql":
        for name in reversed(list(_VIEWS)):
            op.execute(f"DROP VIEW IF EXISTS {name}")
