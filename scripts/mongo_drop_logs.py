#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Drop MongoDB *_logs collections (e.g., reasoning_logs, agents_logs) in the
current environment database.

Env:
  - MONGO_URI / MONGO_HOST
  - SAVANT_ENV / RACK_ENV / RAILS_ENV (db name selection)
  - REASONING_ONLY=1 (drop only 'reasoning_logs')
  - LOG_PREFIX (optional, drop only collections starting with this prefix)
"""

import os
import sys

try:
    import pymongo  # type: ignore
except Exception as e:
    print("pymongo not installed. Run: make reasoning-setup", file=sys.stderr)
    sys.exit(2)


def mongo_db_name() -> str:
    env = os.environ.get('SAVANT_ENV') or os.environ.get('RACK_ENV') or os.environ.get('RAILS_ENV') or 'development'
    return 'savant_test' if env == 'test' else 'savant_development'


def get_client():
    uri = os.environ.get('MONGO_URI') or f"mongodb://{os.environ.get('MONGO_HOST', 'localhost:27017')}"
    cli = pymongo.MongoClient(uri, serverSelectionTimeoutMS=1500, connectTimeoutMS=1500, socketTimeoutMS=2000)
    cli.server_info()
    return cli


def main() -> int:
    try:
        cli = get_client()
    except Exception as e:
        print(f"Mongo not reachable: {e}", file=sys.stderr)
        return 2

    dbname = mongo_db_name()
    db = cli[dbname]

    only_reasoning = (os.environ.get('REASONING_ONLY', '') not in ('', '0', 'false', 'False'))
    prefix = os.environ.get('LOG_PREFIX', '').strip()

    names = db.list_collection_names()
    targets = []
    for n in names:
        if only_reasoning:
            if n == 'reasoning_logs':
                targets.append(n)
        else:
            if n.endswith('_logs'):
                if prefix and not n.startswith(prefix):
                    continue
                targets.append(n)

    if not targets:
        print(f"No log collections to drop in DB={dbname}")
        return 0

    for n in targets:
        try:
            db.drop_collection(n)
            print(f"Dropped collection: {n}")
        except Exception as e:
            print(f"Failed to drop {n}: {e}", file=sys.stderr)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

