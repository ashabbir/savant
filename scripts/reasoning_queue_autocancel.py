#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Reasoning queue watchdog: automatically cancel items stuck in 'processing'.

Env:
  - MONGO_URI or MONGO_HOST
  - SAVANT_ENV/RACK_ENV/RAILS_ENV -> DB name
  - AUTOCANCEL_THRESHOLD_MIN (default 10)
  - AUTOCANCEL_POLL_SEC (default 30)
"""

import os
import sys
import time
from datetime import datetime, timedelta

try:
    import pymongo  # type: ignore
except Exception:
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


def cancel_stuck(col, threshold_min: int) -> int:
    cutoff = datetime.utcnow() - timedelta(minutes=threshold_min)
    q = {
        'status': 'processing',
        '$or': [
            {'updated_at': {'$lt': cutoff}},
            {'updated_at': {'$exists': False}, 'created_at': {'$lt': cutoff}},
        ],
    }
    upd = {'$set': {'status': 'canceled', 'canceled_at': datetime.utcnow(), 'cancel_reason': f'auto-cancel: stuck >{threshold_min}m'}}
    res = col.update_many(q, upd)
    return int(res.modified_count or 0)


def main() -> int:
    threshold_min = int(os.environ.get('AUTOCANCEL_THRESHOLD_MIN', '10'))
    poll_sec = int(os.environ.get('AUTOCANCEL_POLL_SEC', '30'))
    try:
        cli = get_client()
    except Exception as e:
        print(f"Mongo not reachable: {e}", file=sys.stderr)
        return 2
    db = cli[mongo_db_name()]
    col = db['reasoning_queue']
    print(f"[reasoning-autocancel] watching, threshold={threshold_min}m, poll={poll_sec}s, db={db.name}")
    while True:
        try:
            n = cancel_stuck(col, threshold_min)
            if n:
                print(f"[reasoning-autocancel] canceled: {n}")
        except Exception as e:
            print(f"[reasoning-autocancel] error: {e}", file=sys.stderr)
        time.sleep(poll_sec)


if __name__ == '__main__':  # pragma: no cover
    raise SystemExit(main())

