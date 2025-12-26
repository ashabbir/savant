#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
from datetime import datetime

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


def fmt_ts(ts):
    if isinstance(ts, datetime):
        return ts.isoformat() + 'Z'
    return str(ts)


def main() -> int:
    try:
        cli = get_client()
    except Exception as e:
        print(f"Mongo not reachable: {e}", file=sys.stderr)
        return 2

    dbname = mongo_db_name()
    db = cli[dbname]
    col = db['reasoning_queue']

    try:
        total = col.estimated_document_count()
    except Exception:
        total = None

    statuses = ['queued', 'processing', 'done', 'canceled']
    by_status = {}
    for s in statuses:
        try:
            by_status[s] = col.count_documents({'status': s})
        except Exception:
            by_status[s] = None

    # Oldest queued item
    try:
        first = col.find({'status': 'queued'}, {'created_at': 1, 'correlation_id': 1}).sort('created_at', 1).limit(1).next()
        oldest = {'correlation_id': first.get('correlation_id'), 'created_at': fmt_ts(first.get('created_at'))}
    except Exception:
        oldest = None

    # Newest activity
    newest = None
    try:
        d = col.find({}, {'updated_at': 1, 'created_at': 1}).sort([('updated_at', -1), ('created_at', -1)]).limit(1).next()
        newest = fmt_ts(d.get('updated_at') or d.get('created_at'))
    except Exception:
        pass

    print(f"Reasoning Queue Status (DB={dbname})")
    print("- total:", total if total is not None else 'n/a')
    for s in statuses:
        v = by_status.get(s)
        print(f"- {s}:", v if v is not None else 'n/a')
    if oldest:
        print(f"- oldest queued: {oldest['created_at']} (cid={oldest.get('correlation_id')})")
    if newest:
        print(f"- last activity: {newest}")

    # Show 3 queued cids
    try:
        cur = col.find({'status': 'queued'}, {'correlation_id': 1}).limit(3)
        cids = [doc.get('correlation_id') for doc in cur]
        if cids:
            print(f"- sample queued: {', '.join([str(c) for c in cids if c])}")
    except Exception:
        pass

    return 0


if __name__ == '__main__':  # pragma: no cover
    raise SystemExit(main())

