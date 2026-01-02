#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Reset/clear the Reasoning Queue in MongoDB.

Usage:
  - Clear all items (default):
      python3 scripts/reasoning_queue_reset.py

  - Mark all processing -> canceled (non-destructive):
      python3 scripts/reasoning_queue_reset.py --cancel-processing

Env:
  - MONGO_URI or MONGO_HOST
  - SAVANT_ENV/RACK_ENV/RAILS_ENV to select DB name
"""

import os
import sys

try:
    import pymongo  # type: ignore
except Exception as e:  # pragma: no cover
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


def main(argv) -> int:
    cancel_only = '--cancel-processing' in argv
    try:
        cli = get_client()
    except Exception as e:
        print(f"Mongo not reachable: {e}", file=sys.stderr)
        return 2
    db = cli[mongo_db_name()]
    col = db['reasoning_queue']

    if cancel_only:
        # Set any stuck processing jobs to canceled
        res = col.update_many({'status': 'processing'}, {'$set': {'status': 'canceled'}})
        print(f"processing -> canceled: {res.modified_count}")
        return 0

    # Full reset: drop collection contents
    try:
        n = col.estimated_document_count()
    except Exception:
        n = 0
    res = col.delete_many({})
    print(f"deleted: {res.deleted_count} (was ~{n})")
    return 0


if __name__ == '__main__':  # pragma: no cover
    raise SystemExit(main(sys.argv[1:]))

