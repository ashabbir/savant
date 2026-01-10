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

# No external API module dependency; compute intent locally in this worker.

from typing import Any, Dict, List, Optional


def _intent_id() -> str:
    return f"agent-{int(time.time())}-{random.randint(10000, 99999)}"


class AgentIntentRequest:
    def __init__(
        self,
        session_id: str,
        persona: Optional[Dict[str, Any]] = None,
        driver: Optional[Dict[str, Any]] = None,
        rules: Optional[Dict[str, Any]] = None,
        instructions: Optional[str] = None,
        llm: Optional[Dict[str, Any]] = None,
        repo_context: Optional[Dict[str, Any]] = None,
        memory_state: Optional[Dict[str, Any]] = None,
        history: Optional[List[Dict[str, Any]]] = None,
        tools_available: Optional[List[str]] = None,
        tools_catalog: Optional[List[str]] = None,
        goal_text: str = "",
        forced_tool: Optional[str] = None,
        max_steps: Optional[int] = None,
        agent_state: Optional[Dict[str, Any]] = None,
        correlation_id: Optional[str] = None,
        is_reaction: bool = False,
    ) -> None:
        self.session_id = session_id
        self.persona = persona or {}
        self.driver = driver or {}
        self.rules = rules or {}
        self.instructions = instructions
        self.llm = llm or {}
        self.repo_context = repo_context or {}
        self.memory_state = memory_state or {}
        self.history = history or []
        self.tools_available = tools_available or []
        self.tools_catalog = tools_catalog or []
        self.goal_text = goal_text or ""
        self.forced_tool = forced_tool
        self.max_steps = max_steps or 1
        self.agent_state = agent_state or {}
        self.correlation_id = correlation_id
        self.is_reaction = bool(is_reaction)


def _compute_intent_sync(req: AgentIntentRequest) -> Dict[str, Any]:
    goal = (req.goal_text or "").strip()

    # 1) Forced tool takes precedence
    if req.forced_tool:
        return {
            "intent_id": _intent_id(),
            "tool_name": str(req.forced_tool),
            "tool_args": {"query": goal} if goal else {},
            "finish": False,
            "final_text": None,
            "reasoning": "Forced tool from runtime",
            "trace": [],
        }

    tools = [str(t) for t in (req.tools_available or [])]

    # 2) Prefer contextual search when available
    if "context.fts_search" in tools:
        return {
            "intent_id": _intent_id(),
            "tool_name": "context.fts_search",
            "tool_args": {"query": goal or ""},
            "finish": False,
            "final_text": None,
            "reasoning": "Targeted search required to find specific information.",
            "trace": [],
        }

    # 3) Fallback: finish with a direct response placeholder
    final = goal if goal else "Acknowledged."
    return {
        "intent_id": _intent_id(),
        "tool_name": None,
        "tool_args": {},
        "finish": True,
        "final_text": final,
        "reasoning": "No suitable tools available; providing a direct response.",
        "trace": [],
    }

# Redis Configuration
REDIS_URL = os.environ.get('REDIS_URL', 'redis://localhost:6379/0')
QUEUE_KEY = 'savant:queue:reasoning'
PROCESSING_KEY = 'savant:jobs:running'  # Set of running job IDs
COMPLETED_KEY = 'savant:jobs:completed' # List or ZSET of recent completions
FAILED_KEY = 'savant:jobs:failed'
CANCEL_REQUESTED_SET = 'savant:jobs:cancel:requested'  # Set of job_ids flagged for cancel
CANCELED_KEY = 'savant:jobs:canceled'  # List of canceled job summaries

def get_redis_client():
    return redis.Redis.from_url(REDIS_URL, decode_responses=True)

def log(msg, **kwargs):
    ts = datetime.utcnow().isoformat() + 'Z'
    out = f"[{ts}] {msg}"
    if kwargs:
        out += f" {json.dumps(kwargs)}"
    print(out, flush=True)

def process_job(r, job_json, worker_id: str = None):
    try:
        job = json.loads(job_json)
    except json.JSONDecodeError:
        log("error: invalid json", payload=job_json)
        return

    job_id = job.get('job_id')
    callback_url = job.get('callback_url')
    # Default to sync result storage key if no callback (for CLI/legacy)
    result_key = f"savant:result:{job_id}" if job_id else None

    log("job_started", job_id=job_id, worker_id=worker_id)
    if job_id:
        r.sadd(PROCESSING_KEY, job_id)
        try:
            # Track job->worker mapping while running
            r.setex(f"savant:job:worker:{job_id}", 3600, worker_id or '')
        except Exception:
            pass

    try:
        # Check for cancel before starting compute
        if job_id and r.sismember(CANCEL_REQUESTED_SET, job_id):
            canceled = {"status": "canceled", "job_id": job_id}
            if result_key:
                ttl_seconds = int(os.environ.get('REASONING_RESULT_TTL', '300'))
                r.setex(result_key, ttl_seconds, json.dumps(canceled))
            r.lpush(CANCELED_KEY, json.dumps({'job_id': job_id, 'ts': time.time(), 'status': 'canceled', 'worker_id': worker_id}))
            r.ltrim(CANCELED_KEY, 0, 99)
            log("job_canceled_pre", job_id=job_id, worker_id=worker_id)
            return

        # Construct Request object for api
        # The payload structure in Redis matches what the Ruby client sends.
        # We need to adapt it to AgentIntentRequest
        payload = job.get('payload') or {}
        
        # Ensure required fields exist or handle gracefully
        # api.AgentIntentRequest requires: session_id, persona, goal_text
        # We wrap in try/except to catch validation errors
        
        req = AgentIntentRequest(**{
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
            'correlation_id': payload.get('correlation_id'),
            'is_reaction': payload.get('is_reaction', False)
        })

        # Execute Logic (local)
        result = _compute_intent_sync(req)
        
        # Success or post-cancel override
        if job_id and r.sismember(CANCEL_REQUESTED_SET, job_id):
          # Override to canceled if cancel was requested during compute
          result = {"status": "canceled", "job_id": job_id}
          if worker_id:
            result["worker_id"] = worker_id
        else:
          result['status'] = 'ok'
          result['job_id'] = job_id or ''
          if worker_id:
            result['worker_id'] = worker_id

        # Best-effort: Mirror final results to Blackboard if session provided
        try:
            bb_sid = (payload.get('blackboard_session_id') if isinstance(payload, dict) else None)
            if bb_sid and result.get('status') == 'ok' and bool(result.get('finish')) and (result.get('final_text') or result.get('reasoning')):
                import requests
                base = os.environ.get('SAVANT_HUB_URL') or f"http://{os.environ.get('SAVANT_HUB_HOST','127.0.0.1')}:{os.environ.get('SAVANT_HUB_PORT','9999')}"
                actor = None
                try:
                    agent_name = payload.get('agent_name') if isinstance(payload, dict) else None
                    if agent_name:
                        actor = str(agent_name)
                    else:
                        persona = payload.get('persona') if isinstance(payload, dict) else None
                        actor = (persona.get('name') if isinstance(persona, dict) else None) or 'agent'
                except Exception:
                    actor = 'agent'
                ev = {
                    'event': {
                        'session_id': bb_sid,
                        'type': 'result_emitted',
                        'actor_id': actor,
                        'actor_type': 'agent',
                        'visibility': 'public',
                        'payload': {
                            'text': (result.get('final_text') or result.get('reasoning') or ''),
                            'job_id': job_id,
                            'correlation_id': payload.get('correlation_id') if isinstance(payload, dict) else None
                        }
                    }
                }
                try:
                    requests.post(f"{base.rstrip('/')}/blackboard/events", json=ev, timeout=3)
                except Exception:
                    pass
        except Exception:
            pass
        
        # 1. Send Callback if requested
        if callback_url:
            try:
                requests.post(callback_url, json=result, timeout=5)
                log("callback_sent", url=callback_url, status="ok")
            except Exception as e:
                log("callback_failed", url=callback_url, error=str(e))
        
        # 2. Store result in Redis for sync polling (TTL 60s)
        if result_key:
            # Extend TTL to reduce 404s when users click after completion
            ttl_seconds = int(os.environ.get('REASONING_RESULT_TTL', '300'))
            r.setex(result_key, ttl_seconds, json.dumps(result))

        # 3. Add to history logs (completed or canceled)
        if result.get('status') == 'canceled':
            r.lpush(CANCELED_KEY, json.dumps({'job_id': job_id, 'ts': time.time(), 'status': 'canceled', 'worker_id': worker_id}))
            r.ltrim(CANCELED_KEY, 0, 99)
            log("job_canceled_post", job_id=job_id, worker_id=worker_id)
        else:
            r.lpush(COMPLETED_KEY, json.dumps({'job_id': job_id, 'ts': time.time(), 'status': 'ok', 'worker_id': worker_id}))
            r.ltrim(COMPLETED_KEY, 0, 99)
            log("job_completed", job_id=job_id, worker_id=worker_id)

    except Exception as e:
        error_msg = str(e)
        trace = traceback.format_exc()
        log("job_failed", job_id=job_id, error=error_msg)
        
        error_result = {
            "status": "error",
            "error": error_msg,
            "job_id": job_id
        }
        if worker_id:
            error_result["worker_id"] = worker_id
        
        if callback_url:
            try:
                requests.post(callback_url, json=error_result, timeout=5)
            except:
                pass
        
        if result_key:
            ttl_seconds = int(os.environ.get('REASONING_RESULT_TTL', '300'))
            r.setex(result_key, ttl_seconds, json.dumps(error_result))

        r.lpush(FAILED_KEY, json.dumps({'job_id': job_id, 'ts': time.time(), 'error': error_msg, 'worker_id': worker_id}))
        r.ltrim(FAILED_KEY, 0, 99)
    finally:
        if job_id:
            r.srem(PROCESSING_KEY, job_id)
            try:
                r.delete(f"savant:job:worker:{job_id}")
            except Exception:
                pass

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
    # Persist in a registry set for dead-worker visibility
    try:
        r.sadd('savant:workers:registry', worker_id)
    except Exception:
        pass

    while True:
        try:
            # Heartbeat (ephemeral) and last_seen (persistent)
            now_ts = str(time.time())
            r.setex(f"savant:workers:heartbeat:{worker_id}", 30, now_ts)
            try:
                r.set(f"savant:workers:last_seen:{worker_id}", now_ts)
            except Exception:
                pass

            # BLPOP returns (key, value) tuple
            # Timeout 5 seconds to allow for heartbeat/logging if needed
            item = r.blpop(QUEUE_KEY, timeout=5)
            if item:
                _, job_json = item
                process_job(r, job_json, worker_id)
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
