"""Reasoning API

This module provides the minimal interface expected by the queue worker:
- `AgentIntentRequest`: a light container for request fields
- `_compute_intent_sync(req)`: computes the next agent action synchronously

The implementation here is intentionally lightweight so the worker can boot
without requiring provider-specific dependencies. It makes a simple heuristic
decision: if a contextual search tool looks available, suggest using it; 
otherwise, finish with a brief response. Real provider integrations can be
added behind this interface without changing the worker.
"""

from __future__ import annotations

import os
import time
import uuid
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional


@dataclass
class AgentIntentRequest:
    session_id: str
    persona: Optional[Dict[str, Any]] = None
    driver: Optional[Dict[str, Any]] = None
    rules: Optional[Dict[str, Any]] = None
    instructions: Optional[str] = None
    llm: Optional[Dict[str, Any]] = None
    repo_context: Optional[Dict[str, Any]] = None
    memory_state: Optional[Dict[str, Any]] = None
    history: Optional[List[Dict[str, Any]]] = None
    tools_available: Optional[List[str]] = None
    tools_catalog: Optional[Dict[str, Any]] = None
    goal_text: str = ""
    forced_tool: Optional[str] = None
    max_steps: Optional[int] = None
    agent_state: Optional[Dict[str, Any]] = None
    correlation_id: Optional[str] = None
    is_reaction: bool = False


def _compute_intent_sync(req: AgentIntentRequest) -> Dict[str, Any]:
    """Return a single action decision for the runtime.

    This is a safe fallback implementation used by the worker. It does not
    call external LLMs. It attempts to choose a sensible default action: if a
    context search tool is available, suggest it with the goal text; otherwise
    return a `finish` response with a short message.
    """

    # Prepare a trace stub for diagnostics UIs
    trace: List[Dict[str, Any]] = []

    intent_id = f"int-{uuid.uuid4().hex[:8]}"
    goal = (req.goal_text or "").strip()
    tools_available = req.tools_available or []

    # Allow a forced tool via request
    if req.forced_tool:
        decision = {
            "status": "ok",
            "intent_id": intent_id,
            "tool_name": req.forced_tool,
            "tool_args": {"query": goal} if goal else {},
            "reasoning": "Forced tool was specified in the request.",
            "finish": False,
            "final_text": None,
            "trace": trace,
        }
        return decision

    # Heuristic: prefer a context search when available
    def has_tool(prefix: str) -> bool:
        return any(t.startswith(prefix) for t in tools_available)

    # Try common search tool names
    context_tool = None
    for candidate in [
        "context.fts_search",
        "context.search",
        "context.repo_search",
    ]:
        if candidate in tools_available:
            context_tool = candidate
            break
    if context_tool is None and has_tool("context."):
        # Fallback to any context.* tool
        context_tool = next((t for t in tools_available if t.startswith("context.")), None)

    if context_tool and goal:
        return {
            "status": "ok",
            "intent_id": intent_id,
            "tool_name": context_tool,
            "tool_args": {"query": goal},
            "reasoning": "Search the codebase to gather relevant context.",
            "finish": False,
            "final_text": None,
            "trace": trace,
        }

    # Otherwise finish with a minimal response
    final = (
        goal if goal else "No goal provided. Nothing to do right now."
    )
    return {
        "status": "ok",
        "intent_id": intent_id,
        "tool_name": "finish",
        "tool_args": {"answer": final},
        "reasoning": "Finish due to no suitable tools available.",
        "finish": True,
        "final_text": final,
        "trace": trace,
    }

