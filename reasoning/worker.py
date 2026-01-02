#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Standalone Reasoning queue worker (Redis-backed).

Consumes jobs from `savant:queue:reasoning`.
Executes using `reasoning.api._compute_intent_sync`.
Handles callbacks and result storage.
"""

import os
import sys
import time
import json
import redis
import requests
import traceback
from datetime import datetime

# Disable Mongo worker auto-start in api.py
os.environ['REASONING_QUEUE_WORKER'] = '0'

try:
    from reasoning import api as api_mod
except Exception as e:
    print(f"[reasoning-worker] Failed to import API module: {e}", file=sys.stderr)
    sys.exit(1)

# Redis Configuration
REDIS_URL = os.environ.get('REDIS_URL', 'redis://localhost:6379/0')
QUEUE_KEY = 'savant:queue:reasoning'
PROCESSING_KEY = 'savant:jobs:running'  # Set of running job IDs
COMPLETED_KEY = 'savant:jobs:completed' # List or ZSET of recent completions
FAILED_KEY = 'savant:jobs:failed'

def get_redis_client():
    return redis.Redis.from_url(REDIS_URL, decode_responses=True)

def log(msg, **kwargs):
    ts = datetime.utcnow().isoformat() + 'Z'
    out = f"[{ts}] {msg}"
    if kwargs:
        out += f" {json.dumps(kwargs)}"
    print(out, flush=True)

def process_job(r, job_json):
    try:
        job = json.loads(job_json)
    except json.JSONDecodeError:
        log("error: invalid json", payload=job_json)
        return

    job_id = job.get('job_id')
    callback_url = job.get('callback_url')
    # Default to sync result storage key if no callback (for CLI/legacy)
    result_key = f"savant:result:{job_id}" if job_id else None

    log("job_started", job_id=job_id)
    if job_id:
        r.sadd(PROCESSING_KEY, job_id)

    try:
        # Construct Request object for api
        # The payload structure in Redis matches what the Ruby client sends.
        # We need to adapt it to AgentIntentRequest
        payload = job.get('payload') or {}
        
        # Ensure required fields exist or handle gracefully
        # api.AgentIntentRequest requires: session_id, persona, goal_text
        # We wrap in try/except to catch validation errors
        
        req = api_mod.AgentIntentRequest(**{
            'session_id': payload.get('session_id') or 'dev',
            'persona': payload.get('persona') or {'name': 'savant-engineer'},
            'driver': payload.get('driver'),
            'rules': payload.get('rules'),
            'instructions': payload.get('instructions'),
            'llm': payload.get('llm'),
            'repo_context': payload.get('repo_context'),
            'memory_state': payload.get('memory_state'),
            'history': payload.get('history'),
            'tools_available': payload.get('tools_available'),
            'tools_catalog': payload.get('tools_catalog'),
            'goal_text': payload.get('goal_text') or '',
            'forced_tool': payload.get('forced_tool'),
            'max_steps': payload.get('max_steps'),
            'agent_state': payload.get('agent_state'),
            'correlation_id': payload.get('correlation_id')
        })

        # Execute Logic
        result = api_mod._compute_intent_sync(req)
        
        # Success
        result['status'] = 'ok'
        result['job_id'] = job_id or ''
        
        # 1. Send Callback if requested
        if callback_url:
            try:
                requests.post(callback_url, json=result, timeout=5)
                log("callback_sent", url=callback_url, status="ok")
            except Exception as e:
                log("callback_failed", url=callback_url, error=str(e))
        
        # 2. Store result in Redis for sync polling (TTL 60s)
        if result_key:
            r.setex(result_key, 60, json.dumps(result))

        # 3. Add to completed log (optional, capped)
        r.lpush(COMPLETED_KEY, json.dumps({'job_id': job_id, 'ts': time.time(), 'status': 'ok'}))
        r.ltrim(COMPLETED_KEY, 0, 99)

        log("job_completed", job_id=job_id)

    except Exception as e:
        error_msg = str(e)
        trace = traceback.format_exc()
        log("job_failed", job_id=job_id, error=error_msg)
        
        error_result = {
            "status": "error",
            "error": error_msg,
            "job_id": job_id
        }
        
        if callback_url:
            try:
                requests.post(callback_url, json=error_result, timeout=5)
            except:
                pass
        
        if result_key:
            r.setex(result_key, 60, json.dumps(error_result))

        r.lpush(FAILED_KEY, json.dumps({'job_id': job_id, 'ts': time.time(), 'error': error_msg}))
        r.ltrim(FAILED_KEY, 0, 99)
    finally:
        if job_id:
            r.srem(PROCESSING_KEY, job_id)

def main() -> int:
    log("worker_starting", pid=os.getpid())
    r = None
    try:
        r = get_redis_client()
        r.ping()
        log("redis_connected")
    except Exception as e:
        log("redis_connection_failed", error=str(e))
        return 1

    log("waiting_for_jobs", queue=QUEUE_KEY)
    
    # Register worker ID
    worker_id = f"{os.uname().nodename}:{os.getpid()}"

    while True:
        try:
            # Heartbeat
            r.setex(f"savant:workers:heartbeat:{worker_id}", 30, str(time.time()))

            # BLPOP returns (key, value) tuple
            # Timeout 5 seconds to allow for heartbeat/logging if needed
            item = r.blpop(QUEUE_KEY, timeout=5)
            if item:
                _, job_json = item
                process_job(r, job_json)
            else:
                # Idle heartbeat could go here
                pass
        except KeyboardInterrupt:
            log("worker_stopping")
            break
        except Exception as e:
            log("worker_loop_error", error=str(e))
            time.sleep(1)

    return 0

if __name__ == "__main__":
    sys.exit(main())

