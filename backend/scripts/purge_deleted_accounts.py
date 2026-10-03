#!/usr/bin/env python3
"""Permanently erases accounts whose deletion grace period has run out.

The same work `main.py`'s startup does when `PURGE_ON_STARTUP=true`,
available as a standalone command for deployments that would rather this
be a scheduled job with its own logs, exit code and alerting than
something that happens whenever a container restarts — which is the right
choice for anything serious, because a container that stops restarting
is a container that quietly stops honouring deletion requests.

Run it daily:

    0 4 * * *  cd /app && python scripts/purge_deleted_accounts.py

Set `PURGE_ON_STARTUP=false` alongside it, or the two just race for the
same rows behind the same advisory lock and one of them finds nothing to
do.

    --dry-run   list what would be purged and exit
    --limit N   cap how many accounts one run destroys (default 500)
"""

import argparse
import logging
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.account_deletion import purge_due_accounts, sweep_expired_artifacts  # noqa: E402
from app.database import SessionLocal  # noqa: E402
from app.migrate import startup_lock  # noqa: E402
from app import models  # noqa: E402

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("purge")

# Distinct from the two keys main.py already uses (migrations,
# seed/consolidate) so a cron run and a container start can't block each
# other for no reason — they only need to exclude *each other*.
_PURGE_ADVISORY_LOCK_KEY = 8_234_015_579_112_235


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--limit", type=int, default=500)
    args = parser.parse_args()

    db = SessionLocal()
    try:
        if args.dry_run:
            from datetime import datetime, timezone

            due = (
                db.query(models.User)
                .filter(
                    models.User.deleted_at.isnot(None),
                    models.User.purge_after.isnot(None),
                    models.User.purge_after <= datetime.now(timezone.utc),
                )
                .limit(args.limit)
                .all()
            )
            for user in due:
                logger.info(
                    "would purge %s (%s) — deleted %s, due %s",
                    user.id, user.username, user.deleted_at, user.purge_after,
                )
            logger.info("%d account(s) due", len(due))
            return 0

        with startup_lock(_PURGE_ADVISORY_LOCK_KEY):
            purged = purge_due_accounts(db, limit=args.limit)
            sweep_expired_artifacts(db)
        logger.info("purged %d account(s)", purged)
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
