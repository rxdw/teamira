#!/usr/bin/env python3
"""
Grants (or revokes) admin access — sets User.is_admin — for an existing
account, by username.

Talks to the DB directly rather than over HTTP, same reasoning as
app/seed_teamira_picks.py: there deliberately is no HTTP endpoint for
this. An endpoint that grants admin access has to itself be guarded by
require_admin_user, which needs an admin account to already exist —
that's the chicken-and-egg this script exists to break. Whoever can run
this already has direct database access, which is a strictly bigger
permission than is_admin grants inside the app anyway.

Usage:
    cd backend
    python -m scripts.grant_admin alice
    python -m scripts.grant_admin alice --revoke
    python -m scripts.grant_admin --list
"""
from __future__ import annotations

import argparse
import sys

from app import models
from app.database import SessionLocal


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("username", nargs="?", help="Account to grant/revoke admin on")
    parser.add_argument("--revoke", action="store_true", help="Remove admin instead of granting it")
    parser.add_argument("--list", action="store_true", help="List current admins and exit")
    args = parser.parse_args()

    db = SessionLocal()
    try:
        if args.list:
            admins = db.query(models.User).filter_by(is_admin=True).all()
            if not admins:
                print("No admin accounts yet.")
            else:
                print(f"{len(admins)} admin account(s):")
                for u in admins:
                    print(f"  - {u.username}  ({u.id})")
            return

        if not args.username:
            parser.error("username is required unless --list is given")

        user = db.query(models.User).filter_by(username=args.username).first()
        if user is None:
            print(f"No account found with username '{args.username}'.", file=sys.stderr)
            sys.exit(1)

        if args.revoke:
            if not user.is_admin:
                print(f"'{args.username}' is already not an admin — nothing to do.")
                return
            user.is_admin = False
            db.commit()
            print(f"Revoked admin access from '{args.username}'.")
        else:
            if user.is_admin:
                print(f"'{args.username}' is already an admin — nothing to do.")
                return
            user.is_admin = True
            db.commit()
            print(f"Granted admin access to '{args.username}'.")
    finally:
        db.close()


if __name__ == "__main__":
    main()
