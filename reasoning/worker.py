#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Standalone Reasoning queue worker (no HTTP server).

Runs the Mongo-backed intent processor loop from reasoning.api in background
thread(s) and continuously prints queue status to stdout so you can see
activity at a glance.

Env:
  - MONGO_URI / MONGO_HOST
  - SAVANT_ENV / RACK_ENV / RAILS_ENV (db name selection)
  - REASONING_QUEUE_WORKERS (default 4)
  - REASONING_QUEUE_POLL_MS (default 50)
  - REASONING_QUEUE_STATUS_MS (default 60000)  # print at least this often
  - REASONING_QUEUE_STATUS_POLL_MS (default 1000)  # check for changes
  - REASONING_LOG_FILE / REASONING_LOG_STDOUT (optional logging)
"""

import os
import signal
import sys
import time

from typing import Any

try:
    # Reuse internal worker from API module
    from reasoning import api as api_mod  # type: ignore
except Exception as e:  # pragma: no cover
    print(f"[reasoning-worker] Failed to import API module: {e}", file=sys.stderr)
    sys.exit(1)


def main() -> int:
    try:
        # Ensure Mongo reachable; worker will no-op if unavailable
        cli = api_mod._get_mongo_client()  # type: ignore[attr-defined]
        if cli is None:
            print("[reasoning-worker] Mongo is not available; exiting.", file=sys.stderr)
            return 2
        # Start N worker threads
        api_mod._start_queue_worker()  # type: ignore[attr-defined]
        # Log
        try:
            api_mod.log_event('queue_worker_started', workers=os.environ.get('REASONING_QUEUE_WORKERS', '1'))  # type: ignore[attr-defined]
        except Exception:
            pass

        # Block until terminated
        print("[reasoning-worker] running. Press Ctrl+C to exit.")

        # Simple signal-aware loop
        stop = False

        def _sig(_sig: int, _frm: Any) -> None:
            nonlocal stop
            stop = True

        for s in (signal.SIGINT, signal.SIGTERM):
            try:
                signal.signal(s, _sig)
            except Exception:
                pass

        # Periodic status loop (prints queue totals and last activity)
        status_ms = int(os.environ.get('REASONING_QUEUE_STATUS_MS', '60000') or '60000')
        poll_ms = int(os.environ.get('REASONING_QUEUE_STATUS_POLL_MS', '1000') or '1000')

        def _status_loop():
            import time as _time
            last_print = 0.0
            last_snapshot = None
            while not stop:
                try:
                    col = api_mod._queue_collection()  # type: ignore[attr-defined]
                    if col is None:
                        print("[reasoning-worker] queue not available (no Mongo collection)")
                    else:
                        total = None
                        try:
                            total = col.estimated_document_count()
                        except Exception:
                            pass
                        by = {}
                        for s in ('queued', 'processing', 'done', 'canceled'):
                            try:
                                by[s] = col.count_documents({'status': s})
                            except Exception:
                                by[s] = 'n/a'
                        newest = None
                        try:
                            d = col.find({}, {'updated_at': 1, 'created_at': 1}).sort([('updated_at', -1), ('created_at', -1)]).limit(1).next()
                            ts = d.get('updated_at') or d.get('created_at')
                            newest = ts.isoformat() + 'Z' if hasattr(ts, 'isoformat') else str(ts)
                        except Exception:
                            newest = None
                        snapshot = (total, by.get('queued'), by.get('processing'), by.get('done'), by.get('canceled'), newest)
                        now = _time.time()
                        should_print = False
                        if last_snapshot is None:
                            should_print = True
                        elif snapshot != last_snapshot:
                            should_print = True
                        elif (now - last_print) * 1000.0 >= status_ms:
                            should_print = True
                        if should_print:
                            line = f"[queue] total={total if total is not None else 'n/a'} queued={by.get('queued')} processing={by.get('processing')} done={by.get('done')} canceled={by.get('canceled')}"
                            if newest:
                                line += f" last={newest}"
                            print(line)
                            last_snapshot = snapshot
                            last_print = now
                except Exception:
                    # keep status loop alive
                    pass
                finally:
                    time.sleep(max(min(poll_ms, status_ms), 200) / 1000.0)

        # Start status thread
        try:
            t = api_mod.threading.Thread(target=_status_loop, daemon=True)  # type: ignore[attr-defined]
            t.start()
        except Exception:
            # Fallback if api_mod.threading not usable
            import threading as _th
            _th.Thread(target=_status_loop, daemon=True).start()

        while not stop:
            time.sleep(0.5)
        print("[reasoning-worker] stopping...")
        return 0
    except KeyboardInterrupt:
        print("[reasoning-worker] interrupted.")
        return 130


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
