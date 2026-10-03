"""account lifecycle, sessions, recovery, moderation, and ON DELETE rules

Everything the audit's 2.3, 2.4, 2.5, 3.2 and 3.3 findings need, in one
revision, because they are genuinely one change: account deletion is
impossible without the foreign-key rules, the foreign-key rules are only
worth adding because deletion needs them, and the moderation tables and
the session tables both hang off columns added to `users` here.

Four parts:

1. **New columns on `users`** — username_lower, email/email_verified,
   token_version, deleted_at/purge_after, suspension, EULA acceptance,
   discoverable.
2. **New tables** — refresh_sessions, account_tokens, user_blocks,
   reports.
3. **ON DELETE on all 46 foreign keys.** See `_FK_POLICY` below.
4. **A backfill** of username_lower, which has to happen before its
   unique index can be created.

--- On part 3, which is the risky one ------------------------------------

None of these constraints has a name in the application's own source:
they were created implicitly by `Base.metadata.create_all()` (see
main.py's on_startup), so Postgres generated names for them using its own
convention — usually `<table>_<column>_fkey`, but *not always*. Postgres
appends a disambiguating suffix when that name is already taken, and a
database that has been through a `create_all()` on a partially-existing
schema can end up with `..._fkey1`. Hard-coding the conventional name
would therefore work on most databases and fail on some, in a migration
that can't be re-run halfway.

So this doesn't guess. `_recreate_fk` looks the constraint up in
`pg_constraint` by (table, column, referenced table), drops whatever it
actually finds, and recreates it with an explicit, stable name plus the
ON DELETE rule. From here on the constraints are named in the schema and
a future migration can address them directly.

The rewrite takes an ACCESS EXCLUSIVE lock on each table for the duration
of the ADD CONSTRAINT, which validates existing rows. On a small
database that's milliseconds. On a large `diary_entries` it is not, which
is why each constraint is added as NOT VALID first and validated in a
second statement — VALIDATE CONSTRAINT takes only a SHARE UPDATE
EXCLUSIVE lock, so ordinary reads and writes keep working while it runs.

Revision ID: a7d3f1e08b45
Revises: f3a91d4c7e20
Create Date: 2026-09-16
"""

from alembic import op
import sqlalchemy as sa

revision = "a7d3f1e08b45"
down_revision = "f3a91d4c7e20"
branch_labels = None
depends_on = None


# (table, column, referenced_table, ondelete). Mirrors models.py exactly;
# see each model's own docstring for why a given relationship cascades or
# nulls. The short version:
#
#   CASCADE   — rows that are only meaningful as part of one account (or
#               one parent row) and have no life without it.
#   SET NULL  — references *to* a person or a link from a row that
#               belongs to someone else, or that must outlive them:
#               referred_by_id, a co-viewing seat, who started a vote,
#               and every reference on `reports`.
_FK_POLICY = [
    ("users", "referred_by_id", "users", "SET NULL"),
    ("watchlist_entries", "user_id", "users", "CASCADE"),
    ("diary_entries", "user_id", "users", "CASCADE"),
    ("diary_entries", "shared_link_id", "partner_links", "SET NULL"),
    ("user_lists", "user_id", "users", "CASCADE"),
    ("user_list_items", "list_id", "user_lists", "CASCADE"),
    ("activity_events", "user_id", "users", "CASCADE"),
    ("friend_requests", "from_user_id", "users", "CASCADE"),
    ("friend_requests", "to_user_id", "users", "CASCADE"),
    ("episode_progress", "user_id", "users", "CASCADE"),
    ("user_premium_state", "user_id", "users", "CASCADE"),
    ("together_sessions", "owner_id", "users", "CASCADE"),
    ("together_sessions", "guest_id", "users", "SET NULL"),
    ("together_swipes", "session_id", "together_sessions", "CASCADE"),
    ("together_swipes", "user_id", "users", "CASCADE"),
    ("partner_links", "owner_id", "users", "CASCADE"),
    ("partner_links", "partner_id", "users", "SET NULL"),
    ("partner_link_members", "link_id", "partner_links", "CASCADE"),
    ("partner_link_members", "user_id", "users", "CASCADE"),
    ("partner_link_invites", "link_id", "partner_links", "CASCADE"),
    ("partner_link_invites", "from_user_id", "users", "CASCADE"),
    ("partner_link_invites", "to_user_id", "users", "CASCADE"),
    ("partner_prefs", "user_id", "users", "CASCADE"),
    ("partner_prefs", "link_id", "partner_links", "CASCADE"),
    ("challenge_progress", "user_id", "users", "CASCADE"),
    ("co_view_entries", "link_id", "partner_links", "CASCADE"),
    ("co_view_entries", "added_by_id", "users", "SET NULL"),
    ("co_view_vote_sessions", "link_id", "partner_links", "CASCADE"),
    ("co_view_vote_sessions", "started_by_id", "users", "SET NULL"),
    ("co_view_vote_casts", "session_id", "co_view_vote_sessions", "CASCADE"),
    ("co_view_vote_casts", "user_id", "users", "CASCADE"),
    ("co_view_poll_sessions", "link_id", "partner_links", "CASCADE"),
    ("co_view_poll_sessions", "started_by_id", "users", "SET NULL"),
    ("co_view_poll_votes", "session_id", "co_view_poll_sessions", "CASCADE"),
    ("co_view_poll_votes", "user_id", "users", "CASCADE"),
    ("scrobble_events", "user_id", "users", "CASCADE"),
    ("suggestions", "sender_id", "users", "CASCADE"),
    ("suggestions", "receiver_id", "users", "CASCADE"),
    ("teamira_collection_items", "collection_id", "teamira_collections", "CASCADE"),
    ("referrals", "referrer_id", "users", "CASCADE"),
    ("referrals", "referred_id", "users", "CASCADE"),
    ("referral_rewards", "user_id", "users", "CASCADE"),
    ("referral_rewards", "source_referral_id", "referrals", "SET NULL"),
    ("promo_codes", "referrer_id", "users", "CASCADE"),
    ("promo_codes", "referred_id", "users", "SET NULL"),
    ("sincerity_transactions", "user_id", "users", "CASCADE"),
]


def _is_postgres() -> bool:
    return op.get_bind().dialect.name == "postgresql"


def _table_exists(name: str) -> bool:
    return sa.inspect(op.get_bind()).has_table(name)


def _column_exists(table: str, column: str) -> bool:
    if not _table_exists(table):
        return False
    return column in {c["name"] for c in sa.inspect(op.get_bind()).get_columns(table)}


def _find_fk_name(table: str, column: str, ref_table: str) -> str | None:
    """The real constraint name, as Postgres actually assigned it.

    Looked up rather than assumed — see this revision's docstring. Only
    single-column foreign keys are considered (`array_length(conkey) = 1`),
    which is every one in this schema.
    """
    row = op.get_bind().execute(
        sa.text(
            """
            SELECT con.conname
            FROM pg_constraint con
            JOIN pg_class child  ON child.oid  = con.conrelid
            JOIN pg_class parent ON parent.oid = con.confrelid
            JOIN pg_attribute att
              ON att.attrelid = con.conrelid AND att.attnum = con.conkey[1]
            WHERE con.contype = 'f'
              AND child.relname  = :table
              AND parent.relname = :ref_table
              AND att.attname    = :column
              AND array_length(con.conkey, 1) = 1
            LIMIT 1
            """
        ),
        {"table": table, "column": column, "ref_table": ref_table},
    ).first()
    return row[0] if row else None


def _stable_name(table: str, column: str) -> str:
    return f"fk_{table}_{column}"


def _recreate_fk(table: str, column: str, ref_table: str, ondelete: str | None) -> None:
    if not _column_exists(table, column):
        # A table added by a later feature that this database hasn't got
        # yet, or an install that never ran create_all for it. Nothing to
        # rewrite; models.py carries the rule for whenever it is created.
        return

    existing = _find_fk_name(table, column, ref_table)
    if existing:
        op.drop_constraint(existing, table, type_="foreignkey")

    name = _stable_name(table, column)
    if ondelete:
        # NOT VALID, then VALIDATE, so the (potentially long) check of
        # existing rows doesn't hold an ACCESS EXCLUSIVE lock on the
        # table — see this revision's docstring.
        op.execute(
            sa.text(
                f'ALTER TABLE "{table}" ADD CONSTRAINT "{name}" '
                f'FOREIGN KEY ("{column}") REFERENCES "{ref_table}" (id) '
                f"ON DELETE {ondelete} NOT VALID"
            )
        )
        op.execute(sa.text(f'ALTER TABLE "{table}" VALIDATE CONSTRAINT "{name}"'))
    else:
        op.create_foreign_key(name, table, ref_table, [column], ["id"])


def upgrade() -> None:
    # --- 1. users -----------------------------------------------------
    #
    # Guarded per column: main.py still calls Base.metadata.create_all()
    # before running migrations (see its comment on why the baseline
    # revision needs that), so on a fresh database these columns already
    # exist by the time this runs. Same self-guarding pattern every
    # post-baseline revision in this directory uses.
    new_user_columns = [
        ("username_lower", sa.Column("username_lower", sa.String(), nullable=True)),
        ("email", sa.Column("email", sa.String(), nullable=True)),
        ("email_verified", sa.Column("email_verified", sa.Boolean(), nullable=False, server_default="false")),
        ("token_version", sa.Column("token_version", sa.Integer(), nullable=False, server_default="0")),
        ("deleted_at", sa.Column("deleted_at", sa.DateTime(), nullable=True)),
        ("purge_after", sa.Column("purge_after", sa.DateTime(), nullable=True)),
        ("suspended_at", sa.Column("suspended_at", sa.DateTime(), nullable=True)),
        ("suspended_until", sa.Column("suspended_until", sa.DateTime(), nullable=True)),
        ("suspension_reason", sa.Column("suspension_reason", sa.String(), nullable=True)),
        ("eula_version", sa.Column("eula_version", sa.String(), nullable=True)),
        ("eula_accepted_at", sa.Column("eula_accepted_at", sa.DateTime(), nullable=True)),
        ("discoverable", sa.Column("discoverable", sa.Boolean(), nullable=False, server_default="true")),
    ]
    for name, column in new_user_columns:
        if not _column_exists("users", name):
            op.add_column("users", column)

    # --- 2. backfill username_lower -----------------------------------
    #
    # Has to run before the unique index below, and `lower()` is the
    # closest SQL equivalent of app/usernames.py's NFKC+casefold. The two
    # differ only on inputs the old registration path couldn't produce in
    # any volume (fullwidth forms, "ß"), and a mismatch here is not a
    # correctness problem: routers/friends.py and routers/auth.py both
    # keep a `func.lower(username)` fallback for rows this leaves
    # imperfect. What matters is that every row gets *a* value, so the
    # unique index can exist.
    #
    # The DISTINCT ON guard exists because this schema previously allowed
    # "Anna" and "anna" to coexist — the exact bug this column fixes. A
    # plain UPDATE would collide on the new unique index. Duplicates keep
    # the oldest account's claim on the name and leave the rest NULL,
    # which is the conservative choice: nobody is renamed or locked out
    # by a migration, and the affected accounts are visible with one
    # query (`WHERE username_lower IS NULL`) so they can be sorted out by
    # hand.
    op.execute(
        sa.text(
            """
            UPDATE users u
            SET username_lower = lower(u.username)
            WHERE u.username_lower IS NULL
              AND u.id IN (
                SELECT DISTINCT ON (lower(username)) id
                FROM users
                ORDER BY lower(username), created_at ASC NULLS LAST, id ASC
              )
            """
        )
    )

    existing_indexes = {ix["name"] for ix in sa.inspect(op.get_bind()).get_indexes("users")}
    if "ix_users_username_lower" not in existing_indexes:
        op.create_index("ix_users_username_lower", "users", ["username_lower"], unique=True)
    if "ix_users_email" not in existing_indexes:
        op.create_index("ix_users_email", "users", ["email"], unique=True)
    if "ix_users_deleted_at" not in existing_indexes:
        op.create_index("ix_users_deleted_at", "users", ["deleted_at"])
    if "ix_users_purge_after" not in existing_indexes:
        op.create_index("ix_users_purge_after", "users", ["purge_after"])

    # --- 3. new tables ------------------------------------------------
    if not _table_exists("refresh_sessions"):
        op.create_table(
            "refresh_sessions",
            sa.Column("id", sa.String(), primary_key=True),
            sa.Column("user_id", sa.String(), nullable=False),
            sa.Column("token_hash", sa.String(), nullable=False),
            sa.Column("family_id", sa.String(), nullable=False),
            sa.Column("replaced_by_id", sa.String(), nullable=True),
            sa.Column("device_label", sa.String(), nullable=True),
            sa.Column("created_ip", sa.String(), nullable=True),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
            sa.Column("last_used_at", sa.DateTime(), nullable=True),
            sa.Column("expires_at", sa.DateTime(), nullable=False),
            sa.Column("rotated_at", sa.DateTime(), nullable=True),
            sa.Column("revoked_at", sa.DateTime(), nullable=True),
            sa.Column("revoked_reason", sa.String(), nullable=True),
            sa.ForeignKeyConstraint(
                ["user_id"], ["users.id"],
                name="fk_refresh_sessions_user_id", ondelete="CASCADE",
            ),
        )
        op.create_index("ix_refresh_sessions_token_hash", "refresh_sessions", ["token_hash"], unique=True)
        op.create_index("ix_refresh_sessions_user_id", "refresh_sessions", ["user_id"])
        op.create_index("ix_refresh_sessions_family_id", "refresh_sessions", ["family_id"])
        op.create_index("ix_refresh_sessions_user_active", "refresh_sessions", ["user_id", "revoked_at"])

    if not _table_exists("account_tokens"):
        account_token_purpose = sa.Enum(
            "password_reset", "email_verify", name="accounttokenpurpose"
        )
        account_token_purpose.create(op.get_bind(), checkfirst=True)
        op.create_table(
            "account_tokens",
            sa.Column("id", sa.String(), primary_key=True),
            sa.Column("user_id", sa.String(), nullable=False),
            sa.Column("purpose", account_token_purpose, nullable=False),
            sa.Column("token_hash", sa.String(), nullable=False),
            sa.Column("email", sa.String(), nullable=False),
            sa.Column("expires_at", sa.DateTime(), nullable=False),
            sa.Column("consumed_at", sa.DateTime(), nullable=True),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
            sa.Column("created_ip", sa.String(), nullable=True),
            sa.ForeignKeyConstraint(
                ["user_id"], ["users.id"],
                name="fk_account_tokens_user_id", ondelete="CASCADE",
            ),
        )
        op.create_index("ix_account_tokens_token_hash", "account_tokens", ["token_hash"], unique=True)
        op.create_index("ix_account_tokens_user_id", "account_tokens", ["user_id"])

    if not _table_exists("user_blocks"):
        op.create_table(
            "user_blocks",
            sa.Column("id", sa.String(), primary_key=True),
            sa.Column("blocker_id", sa.String(), nullable=False),
            sa.Column("blocked_id", sa.String(), nullable=False),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
            sa.ForeignKeyConstraint(
                ["blocker_id"], ["users.id"],
                name="fk_user_blocks_blocker_id", ondelete="CASCADE",
            ),
            sa.ForeignKeyConstraint(
                ["blocked_id"], ["users.id"],
                name="fk_user_blocks_blocked_id", ondelete="CASCADE",
            ),
            sa.UniqueConstraint("blocker_id", "blocked_id", name="uq_user_block_pair"),
        )
        op.create_index("ix_user_blocks_blocker_id", "user_blocks", ["blocker_id"])
        op.create_index("ix_user_blocks_blocked_id", "user_blocks", ["blocked_id"])

    if not _table_exists("reports"):
        target_type = sa.Enum(
            "user", "diary_entry", "activity_event", "list", "review",
            name="reporttargettype",
        )
        reason = sa.Enum(
            "harassment", "hate", "sexual_content", "violence", "spam",
            "impersonation", "self_harm", "child_safety", "other",
            name="reportreason",
        )
        report_status = sa.Enum("pending", "actioned", "dismissed", name="reportstatus")
        for enum_type in (target_type, reason, report_status):
            enum_type.create(op.get_bind(), checkfirst=True)

        op.create_table(
            "reports",
            sa.Column("id", sa.String(), primary_key=True),
            sa.Column("reporter_id", sa.String(), nullable=True),
            sa.Column("reported_user_id", sa.String(), nullable=True),
            sa.Column("target_type", target_type, nullable=False),
            sa.Column("target_id", sa.String(), nullable=True),
            sa.Column("reason", reason, nullable=False),
            sa.Column("details", sa.String(), nullable=True),
            sa.Column("target_snapshot", sa.Text(), nullable=True),
            sa.Column("reported_username_snapshot", sa.String(), nullable=True),
            sa.Column("status", report_status, nullable=False, server_default="pending"),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now()),
            sa.Column("due_at", sa.DateTime(), nullable=True),
            sa.Column("resolved_at", sa.DateTime(), nullable=True),
            sa.Column("resolved_by_id", sa.String(), nullable=True),
            sa.Column("resolution_note", sa.String(), nullable=True),
            sa.Column("action_taken", sa.String(), nullable=True),
            # SET NULL, alone among this schema's references to `users` —
            # a complaint has to outlive both the account it was about
            # and the account that filed it. See models.Report.
            sa.ForeignKeyConstraint(
                ["reporter_id"], ["users.id"],
                name="fk_reports_reporter_id", ondelete="SET NULL",
            ),
            sa.ForeignKeyConstraint(
                ["reported_user_id"], ["users.id"],
                name="fk_reports_reported_user_id", ondelete="SET NULL",
            ),
            sa.ForeignKeyConstraint(
                ["resolved_by_id"], ["users.id"],
                name="fk_reports_resolved_by_id", ondelete="SET NULL",
            ),
            # No plain UniqueConstraint here — see models.Report's own
            # __table_args__ comment for why one would silently fail to
            # dedupe `user`-type reports (target_id IS NULL on every one
            # of them, and SQL unique constraints never consider two
            # NULLs equal). The real constraint is the expression index
            # created below — unconditionally, not inside this
            # `if not _table_exists("reports")` guard; see that index's
            # own comment for why it has to live out there.
        )
        op.create_index("ix_reports_reporter_id", "reports", ["reporter_id"])
        op.create_index("ix_reports_reported_user_id", "reports", ["reported_user_id"])
        op.create_index("ix_reports_due_at", "reports", ["due_at"])
        op.create_index("ix_reports_status_due", "reports", ["status", "due_at"])

    if _is_postgres():
        # COALESCE(target_id, '') is what makes this NULL-safe: a
        # `user`-type report's target_id is always NULL (see the
        # column's own comment), and a plain unique index would treat
        # every one of those NULLs as distinct from every other, which
        # is exactly the bug this replaces — verified directly against
        # the plain-UniqueConstraint version of this table: two
        # identical (reporter, user-type target, reported user) reports
        # inserted without conflict. Folding NULL to '' first makes them
        # compare equal, the way the feature was always meant to behave.
        #
        # reported_user_id is left un-coalesced: it's always populated
        # at insert time (routers/moderation.py::create_report 404s
        # before that point if the target account doesn't exist), so it
        # only goes NULL later, when that account is purged — by which
        # point the report it's attached to already exists and this
        # index no longer needs to dedupe against it.
        #
        # DELIBERATELY OUTSIDE the `if not _table_exists("reports")`
        # guard above, and DELIBERATELY `IF NOT EXISTS` rather than a
        # bare `CREATE UNIQUE INDEX`. An earlier version of this
        # migration had this exact statement *inside* that guard, on the
        # reasoning that it only needs to run when this migration is the
        # one creating the table. That reasoning is wrong for how this
        # app actually boots: main.py's on_startup runs
        # `Base.metadata.create_all()` BEFORE `run_migrations()` (see
        # that file's own comment on why — the baseline revision
        # 6cea28b2d137 is pure `ADD COLUMN IF NOT EXISTS` and assumes the
        # tables already exist). So on every real deployment,
        # `create_all()` has already created `reports` — with every
        # column-level index and plain `__table_args__` constraint
        # models.py declares, but NOT this expression index, which isn't
        # expressible as SQLAlchemy metadata at all and exists only
        # here. `_table_exists("reports")` was therefore already True by
        # the time this migration ran, the whole `if not
        # _table_exists(...)` block was skipped, and this index was
        # never created — silently, with no error, because nothing
        # failed; a statement just never ran. Caught by actually running
        # this migration against a real Postgres instance in the order
        # main.py uses, rather than only against a database this
        # migration itself was the one creating from empty — which is
        # exactly the gap between the two that let it hide.
        op.execute(
            sa.text(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS uq_report_once_per_reporter
                ON reports (reporter_id, target_type, COALESCE(target_id, ''), reported_user_id)
                """
            )
        )

    # --- 4. ON DELETE rules -------------------------------------------
    #
    # Postgres only. SQLite (used by some local setups) can't ALTER a
    # constraint at all — it requires a full table rebuild — and it
    # ignores foreign keys entirely unless PRAGMA foreign_keys is on, so
    # there is nothing to gain from attempting it there.
    if not _is_postgres():
        return
    for table, column, ref_table, ondelete in _FK_POLICY:
        _recreate_fk(table, column, ref_table, ondelete)


def downgrade() -> None:
    # Drops the ON DELETE rules (recreating each constraint under its own
    # stable name, with no action), then the new tables and columns.
    #
    # Note what this deliberately does NOT do: it does not put the
    # constraints back under their original Postgres-generated names.
    # Those names were never recorded anywhere, so reproducing them is
    # guesswork; the stable names are strictly better and the only thing
    # that referred to the old ones was the lookup in `upgrade`.
    if _is_postgres():
        for table, column, ref_table, _ in _FK_POLICY:
            _recreate_fk(table, column, ref_table, None)

    for table in ("reports", "user_blocks", "account_tokens", "refresh_sessions"):
        if _table_exists(table):
            op.drop_table(table)

    for enum_name in ("reportstatus", "reportreason", "reporttargettype", "accounttokenpurpose"):
        op.execute(sa.text(f"DROP TYPE IF EXISTS {enum_name}"))

    for index in (
        "ix_users_purge_after", "ix_users_deleted_at",
        "ix_users_email", "ix_users_username_lower",
    ):
        op.execute(sa.text(f"DROP INDEX IF EXISTS {index}"))

    for column in (
        "discoverable", "eula_accepted_at", "eula_version", "suspension_reason",
        "suspended_until", "suspended_at", "purge_after", "deleted_at",
        "token_version", "email_verified", "email", "username_lower",
    ):
        if _column_exists("users", column):
            op.drop_column("users", column)
