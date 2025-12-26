from fastapi import FastAPI, Request, Header
from pydantic import BaseModel
from typing import Optional, Dict, Any, List
import time
import os
from datetime import datetime, timedelta
import threading
import requests
try:
    import pymongo  # type: ignore
except Exception:
    pymongo = None


app = FastAPI(title="Savant Reasoning API", version="v1")


# --- Lightweight Mongo logger (compatible with Hub diagnostics) ---
_MONGO_CLIENT = None
_MONGO_DISABLED_UNTIL = None
_QUEUE_WORKER_STARTED = False
_QUEUE_WORKERS = int(os.environ.get('REASONING_QUEUE_WORKERS', '4') or '4')
_QUEUE_POLL_MS = int(os.environ.get('REASONING_QUEUE_POLL_MS', '50') or '50')

# Optional local logging controls
_REASONING_LOG_STDOUT = os.environ.get('REASONING_LOG_STDOUT', '1') not in ('0', '', 'false', 'False')
_REASONING_LOG_FILE = os.environ.get('REASONING_LOG_FILE')  # e.g., 'logs/reasoning.log'


def _mongo_db_name():
    env = os.environ.get('SAVANT_ENV') or os.environ.get('RACK_ENV') or os.environ.get('RAILS_ENV') or 'development'
    return 'savant_test' if env == 'test' else 'savant_development'


def _get_mongo_client():
    global _MONGO_CLIENT, _MONGO_DISABLED_UNTIL
    if pymongo is None:
        return None
    now = datetime.utcnow()
    if _MONGO_DISABLED_UNTIL and now < _MONGO_DISABLED_UNTIL:
        return None
    if _MONGO_CLIENT is not None:
        return _MONGO_CLIENT
    try:
        uri = os.environ.get('MONGO_URI') or f"mongodb://{os.environ.get('MONGO_HOST', 'localhost:27017')}"  # host only; db chosen later
        client = pymongo.MongoClient(uri, serverSelectionTimeoutMS=1500, connectTimeoutMS=1500, socketTimeoutMS=2000)
        # Ping / fetch server info (lightweight)
        client.server_info()
        _MONGO_CLIENT = client
        return _MONGO_CLIENT
    except Exception:
        _MONGO_CLIENT = None
        _MONGO_DISABLED_UNTIL = now + timedelta(seconds=10)
        return None


def _write_local_log(doc: Dict[str, Any]):
    try:
        import json
        line_doc = dict(doc)
        ts = line_doc.get('timestamp')
        if isinstance(ts, datetime):
            line_doc['timestamp'] = ts.isoformat() + 'Z'
        line = json.dumps(line_doc, default=str)
        # Always mirror to stdout for visibility
        print(line, flush=True)
        if _REASONING_LOG_FILE:
            try:
                os.makedirs(os.path.dirname(_REASONING_LOG_FILE), exist_ok=True)
            except Exception:
                pass
            with open(_REASONING_LOG_FILE, 'a', encoding='utf-8') as f:
                f.write(line + "\n")
    except Exception:
        # Never throw from logging
        pass


def log_event(event: str, **kwargs):
    doc = {
        'service': 'reasoning',
        'mcp': 'reasoning',
        'event': event,
        'timestamp': datetime.utcnow(),
    }
    doc.update(kwargs or {})
    # Best-effort Mongo write
    try:
        cli = _get_mongo_client()
        if cli is not None:
            db = cli[_mongo_db_name()]
            col = db['reasoning_logs']
            col.insert_one(doc)
    except Exception:
        pass
    # Optional local stdout/file logging
    # Always mirror to local stdout; file logging remains opt-in via REASONING_LOG_FILE
    _write_local_log(doc)


class AgentIntentRequest(BaseModel):
    session_id: str
    persona: Dict[str, Any]
    driver: Optional[Dict[str, Any]] = None
    rules: Optional[Dict[str, Any]] = None
    instructions: Optional[str] = None
    llm: Optional[Dict[str, Any]] = None
    repo_context: Optional[Dict[str, Any]] = None
    memory_state: Optional[Dict[str, Any]] = None
    history: Optional[List[Dict[str, Any]]] = None
    goal_text: str
    forced_tool: Optional[str] = None
    max_steps: Optional[int] = None
    agent_state: Optional[Dict[str, Any]] = None
    # Async hook support (optional): if provided, service will POST the intent result to this URL
    callback_url: Optional[str] = None
    correlation_id: Optional[str] = None


class AgentIntentResponse(BaseModel):
    status: str
    duration_ms: int
    intent_id: str
    tool_name: Optional[str] = None
    tool_args: Optional[Dict[str, Any]] = None
    reasoning: Optional[str] = None
    finish: bool
    final_text: Optional[str] = None
    trace: Optional[List[Dict[str, Any]]] = None


class WorkflowIntentRequest(BaseModel):
    run_id: str
    workflow_name: str
    current_node: str
    outputs: Optional[Dict[str, Any]] = None
    params: Optional[Dict[str, Any]] = None
    memory_state: Optional[Dict[str, Any]] = None


class WorkflowIntentResponse(BaseModel):
    status: str
    duration_ms: int
    intent_id: str
    next_node: Optional[str] = None
    action_type: Optional[str] = None
    tool_name: Optional[str] = None
    tool_args: Optional[Dict[str, Any]] = None
    reasoning: Optional[str] = None
    finish: bool
    trace: Optional[List[Dict[str, Any]]] = None


@app.get("/healthz")
def healthz():
    return {"status": "ok"}

# Back-compat health alias used by Hub diagnostics
@app.get("/health")
def health():
    return {"status": "ok"}

# Simple root for reachability checks
@app.get("/")
def root():
    return {"service": "savant-reasoning", "status": "ok"}


def _call_google_api(model: str, goal: str, instructions: Optional[str], api_key: str, history: Optional[List[Dict[str, Any]]] = None) -> str:
    """Call Google Generative AI API directly."""
    system_prompt = instructions or "You are a helpful agent. Provide concise responses."

    # Debug: log that this function was called
    try:
        log_event('google_api_called', goal=goal, history_is_none=(history is None), history_len=len(history) if history else 0)
    except:
        pass

    # Build history context if available
    history_context = ""
    if history and isinstance(history, list) and len(history) > 0:
        # Log that we have history with first item details
        try:
            first_item = history[0] if len(history) > 0 else {}
            first_item_type = type(first_item).__name__
            first_item_str = str(first_item)[:300] if first_item else "empty"
            log_event('history_received', history_count=len(history), goal_text=goal, first_item_type=first_item_type, first_item_preview=first_item_str)
        except Exception as e:
            log_event('history_received_error', history_count=len(history), goal_text=goal, error=str(e))
        history_context = "\n## Previous Actions and Results:\n"
        for i, item in enumerate(history[-5:], 1):  # Show last 5 actions to keep prompt short
            if isinstance(item, dict):
                # Handle nested structure from runtime (item has 'action' dict with 'tool_name', 'output' with results)
                action_obj = item.get('action')
                if isinstance(action_obj, dict):
                    action_type = action_obj.get('action') or 'tool'
                    tool = action_obj.get('tool_name') or ''
                else:
                    action_type = item.get('action') or item.get('type') or 'unknown'
                    tool = item.get('tool_name') or item.get('tool') or ''

                # Get results from various possible locations
                result_preview = ''
                output_obj = item.get('output')
                if isinstance(output_obj, dict):
                    # Check for content array (MCP standard response)
                    content = output_obj.get('content')
                    if isinstance(content, list) and len(content) > 0:
                        first_item = content[0]
                        if isinstance(first_item, dict):
                            result_preview = first_item.get('text') or str(first_item)[:200]
                        else:
                            result_preview = str(first_item)[:200]
                    else:
                        result_preview = str(output_obj)[:200]
                else:
                    result_preview = item.get('result') or item.get('content') or ''
                    if isinstance(result_preview, list) and len(result_preview) > 0:
                        result_preview = str(result_preview[0])[:200]
                    elif isinstance(result_preview, dict):
                        result_preview = str(result_preview)[:200]
                    elif result_preview:
                        result_preview = str(result_preview)[:200]

                if result_preview:
                    history_context += f"{i}. {action_type} {tool}: {result_preview}...\n"
                    try:
                        log_event('history_item_with_result', action_type=action_type, tool=tool, result_preview=result_preview[:100])
                    except:
                        pass
                else:
                    history_context += f"{i}. {action_type} {tool}\n"

    prompt = f"""{system_prompt}

You are analyzing a task and deciding whether to search or finish.

CRITICAL RULE: If you see previous search results in "Previous Actions and Results",
you MUST choose "finish" - do NOT search again!

{history_context}

Goal: {goal}

Decision Rules:
1. Do you have search results above? YES → ACTION: finish
2. Have you already searched for this? YES → ACTION: finish
3. Do you need to search? NO → ACTION: finish
4. Otherwise search.

Respond with ONLY these exact lines:
ACTION: finish
RESULT: your answer
REASONING: why you chose this

OR

ACTION: context.fts_search
RESULT: search query
REASONING: why you need to search"""

    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
    payload = {
        "contents": [
            {
                "parts": [
                    {
                        "text": prompt
                    }
                ]
            }
        ],
        "generationConfig": {
            "temperature": 0.3,
            "maxOutputTokens": 500
        }
    }

    try:
        response = requests.post(url, json=payload, timeout=30)
        response.raise_for_status()
        result = response.json()

        # Extract text from response
        if 'candidates' in result and len(result['candidates']) > 0:
            candidate = result['candidates'][0]
            if 'content' in candidate and 'parts' in candidate['content']:
                text_parts = candidate['content']['parts']
                if len(text_parts) > 0 and 'text' in text_parts[0]:
                    return text_parts[0]['text']

        raise Exception(f"Unexpected Google API response: {result}")
    except requests.exceptions.RequestException as e:
        raise Exception(f"Google API request failed: {str(e)}")


def _use_llm_for_reasoning(goal_text: str, instructions: Optional[str], llm_provider: Optional[str], llm_model: Optional[str], api_key: Optional[str] = None, history: Optional[List[Dict[str, Any]]] = None) -> tuple:
    """Use LLM to reason about what tool to call or action to take."""
    try:
        from langchain.prompts import PromptTemplate

        model_name = llm_model or 'phi3.5:latest'
        provider_name = (llm_provider or '').lower().strip()

        # Build history context if available
        history_context = ""
        if history and isinstance(history, list) and len(history) > 0:
            # Log that we have history with first item details
            try:
                first_item = history[0] if len(history) > 0 else {}
                first_item_type = type(first_item).__name__
                first_item_str = str(first_item)[:300] if first_item else "empty"
                log_event('history_received', history_count=len(history), goal_text=goal_text, first_item_type=first_item_type, first_item_preview=first_item_str)
            except Exception as e:
                log_event('history_received_error', history_count=len(history), goal_text=goal_text, error=str(e))
            history_context = "\n## Previous Actions and Results:\n"
            for i, item in enumerate(history[-5:], 1):  # Show last 5 actions
                if isinstance(item, dict):
                    # Handle nested structure from runtime (item has 'action' dict with 'tool_name', 'output' with results)
                    action_obj = item.get('action')
                    if isinstance(action_obj, dict):
                        action_type = action_obj.get('action') or 'tool'
                        tool = action_obj.get('tool_name') or ''
                    else:
                        action_type = item.get('action') or item.get('type') or 'unknown'
                        tool = item.get('tool_name') or item.get('tool') or ''

                    # Get results from various possible locations
                    result_preview = ''
                    output_obj = item.get('output')
                    if isinstance(output_obj, dict):
                        # Check for content array (MCP standard response)
                        content = output_obj.get('content')
                        if isinstance(content, list) and len(content) > 0:
                            first_item = content[0]
                            if isinstance(first_item, dict):
                                result_preview = first_item.get('text') or str(first_item)[:200]
                            else:
                                result_preview = str(first_item)[:200]
                        else:
                            result_preview = str(output_obj)[:200]
                    else:
                        result_preview = item.get('result') or item.get('content') or ''
                        if isinstance(result_preview, list) and len(result_preview) > 0:
                            result_preview = str(result_preview[0])[:200]
                        elif isinstance(result_preview, dict):
                            result_preview = str(result_preview)[:200]
                        elif result_preview:
                            result_preview = str(result_preview)[:200]

                    if result_preview:
                        history_context += f"{i}. {action_type} {tool}: {result_preview}...\n"
                    else:
                        history_context += f"{i}. {action_type} {tool}\n"

        # Select LLM based on provider
        if provider_name == 'google api':
            # Use Google Generative AI / Gemini via direct API
            if not api_key:
                raise Exception('API key not provided for Google API provider')
            response = _call_google_api(model_name, goal_text, instructions, api_key, history)
        else:
            # Default to Ollama
            from langchain_community.llms import Ollama
            llm_base_url = os.environ.get('OLLAMA_BASE_URL', 'http://localhost:11434')
            llm = Ollama(base_url=llm_base_url, model=model_name, temperature=0.3)

            # Build system prompt from instructions
            system_prompt = instructions or "You are a helpful agent. Provide concise responses."

            # Create a prompt that asks the LLM to reason about the goal
            prompt_template = PromptTemplate(
                input_variables=["goal"],
                template=f"""{system_prompt}

You are analyzing a task and deciding whether to search or finish.

CRITICAL RULE: If you see previous search results in "Previous Actions and Results",
you MUST choose "finish" - do NOT search again!

{history_context}

Goal: {{goal}}

Decision Rules:
1. Do you have search results above? YES → ACTION: finish
2. Have you already searched for this? YES → ACTION: finish
3. Do you need to search? NO → ACTION: finish
4. Otherwise search.

Respond with ONLY these exact lines:
ACTION: finish
RESULT: your answer
REASONING: why you chose this

OR

ACTION: context.fts_search
RESULT: search query
REASONING: why you need to search"""
            )

            # Use LangChain Expression Language (LCEL): prompt | llm, then invoke
            chain = prompt_template | llm
            response = chain.invoke({"goal": goal_text})

        # Parse the LLM response
        lines = response.strip().split('\n')
        action = None
        result = None
        reasoning = response[:200]  # Use full response as reasoning if parse fails

        for line in lines:
            if line.startswith('ACTION:'):
                action = line.replace('ACTION:', '').strip()
            elif line.startswith('RESULT:'):
                result = line.replace('RESULT:', '').strip()
            elif line.startswith('REASONING:'):
                reasoning = line.replace('REASONING:', '').strip()

        # Determine finish vs tool call
        if action and action.lower() == 'finish':
            return (None, None, result or goal_text, reasoning, True)
        elif action and action.lower().startswith('context.fts_search'):
            return ("context.fts_search", {"query": result or goal_text}, None, reasoning, False)
        else:
            # Default to finish if we can't parse, but return the LLM's response
            return (None, None, result or response[:80], reasoning, True)

    except Exception as e:
        # Log error to Mongo for visibility
        try:
            log_event('llm_reasoning_error', error=str(e), goal_text=goal_text)
        except:
            pass
        # Fall back to heuristic if LLM fails - return failure signal  so fallback is used
        return (None, None, None, f"LLM error: {str(e)}", False)


@app.post("/agent_intent", response_model=AgentIntentResponse)
async def agent_intent(req: AgentIntentRequest, accept_version: Optional[str] = Header(default="v1", alias="Accept-Version")):
    start = time.time()
    # Log receipt with full details
    try:
        persona_name = (req.persona or {}).get('name') if isinstance(req.persona, dict) else None
        rulesets = 0
        if req.rules and isinstance(req.rules, dict):
            rs = req.rules.get('agent_rulesets') or []
            if isinstance(rs, list):
                rulesets = len(rs)
        llm_provider = (req.llm or {}).get('provider') if isinstance(req.llm, dict) else None
        llm_model = (req.llm or {}).get('model') if isinstance(req.llm, dict) else None
        agent_state = req.agent_state or {}
        log_event('agent_intent_received',
                  session_id=req.session_id,
                  persona=persona_name,
                  rulesets=rulesets,
                  has_instructions=bool(req.instructions),
                  llm_provider=llm_provider,
                  llm_model=llm_model,
                  agent_state_current=agent_state.get('current_state'),
                  agent_state_stuck=agent_state.get('stuck'),
                  goal_text=req.goal_text,
                  forced_tool=req.forced_tool,
                  max_steps=req.max_steps)
    except Exception:
        pass

    tool_name = None
    tool_args = None
    final_text = None
    reasoning = None
    finish = False

    if req.forced_tool:
        tool_name = req.forced_tool
        tool_args = {"echo": True}
        reasoning = f"Forced tool: {req.forced_tool}"
        finish = False
    else:
        # Try to use LLM for reasoning
        llm_provider = (req.llm or {}).get('provider') if isinstance(req.llm, dict) else None
        llm_model = (req.llm or {}).get('model') if isinstance(req.llm, dict) else None

        llm_api_key = (req.llm or {}).get('api_key') if isinstance(req.llm, dict) else None
        tool_name, tool_args, final_text, reasoning, finish = _use_llm_for_reasoning(
            req.goal_text,
            req.instructions,
            llm_provider,
            llm_model,
            llm_api_key,
            req.history
        )

        # If LLM reasoning failed, fall back to heuristic
        if tool_name is None and not finish:
            # Check if we have previous search results (only consider 'tool' actions with 'output')
            has_search_results = False
            if req.history and isinstance(req.history, list):
                for item in req.history:
                    if isinstance(item, dict):
                        action_obj = item.get('action')
                        if isinstance(action_obj, dict) and action_obj.get('action') == 'tool':
                            tool_name_in_hist = action_obj.get('tool_name') or ''
                            if 'search' in tool_name_in_hist.lower() and item.get('output'):
                                has_search_results = True
                                break

            # If we already have search results, finish instead of searching again
            if has_search_results:
                final_text = f"Based on previous search results for '{req.goal_text}'."
                reasoning = "Already have search results from previous action."
                finish = True
            else:
                # Otherwise, try searching if goal suggests it
                lower_goal = req.goal_text.lower()
                if any(word in lower_goal for word in ["search", "find", "lookup", "fts", "what", "how", "where", "when", "why", "information"]):
                    tool_name = "context.fts_search"
                    tool_args = {"query": req.goal_text}
                    reasoning = "Full-text search will help answer this question"
                    finish = False
                elif any(word in lower_goal for word in ["repo", "analyze", "code", "understand", "structure", "architecture"]):
                    tool_name = "context.fts_search"
                    tool_args = {"query": req.goal_text}
                    reasoning = "Analyzing codebase requires searching documentation and code"
                    finish = False
                else:
                    final_text = f"Completed: {req.goal_text[:80]}"
                    reasoning = "Task completed. No additional tool calls required."
                    finish = True

    dur = int((time.time() - start) * 1000)
    try:
        log_event('agent_intent_decision',
                  session_id=req.session_id,
                  status='ok',
                  tool_name=tool_name,
                  tool_args=tool_args,
                  reasoning=reasoning,
                  finish=finish,
                  final_text=final_text,
                  duration_ms=dur,
                  goal_text=req.goal_text)
    except Exception:
        pass
    intent_id = f"agent-{int(time.time()*1000)}"
    return AgentIntentResponse(
        status="ok",
        duration_ms=dur,
        intent_id=intent_id,
        tool_name=tool_name,
        tool_args=tool_args,
        reasoning=reasoning,
        finish=finish,
        final_text=final_text,
        trace=[]
    )


class IntentAccepted(BaseModel):
    status: str
    job_id: str


def _compute_intent_sync(req: AgentIntentRequest) -> Dict[str, Any]:
    # Reuse the logic from agent_intent (without FastAPI decorators) for async path
    tool_name = None
    tool_args: Optional[Dict[str, Any]] = None
    final_text = None
    reasoning = None
    finish = False

    if req.forced_tool:
        tool_name = req.forced_tool
        tool_args = {"echo": True}
        reasoning = f"Forced tool: {req.forced_tool}"
        finish = False
    else:
        # Try to use LLM for reasoning
        llm_provider = (req.llm or {}).get('provider') if isinstance(req.llm, dict) else None
        llm_model = (req.llm or {}).get('model') if isinstance(req.llm, dict) else None

        llm_api_key = (req.llm or {}).get('api_key') if isinstance(req.llm, dict) else None
        tool_name, tool_args, final_text, reasoning, finish = _use_llm_for_reasoning(
            req.goal_text,
            req.instructions,
            llm_provider,
            llm_model,
            llm_api_key,
            req.history
        )

        # If LLM reasoning failed, fall back to heuristic
        if tool_name is None and not finish:
            # Check if we have previous search results (only consider 'tool' actions with 'output')
            has_search_results = False
            if req.history and isinstance(req.history, list):
                for item in req.history:
                    if isinstance(item, dict):
                        action_obj = item.get('action')
                        if isinstance(action_obj, dict) and action_obj.get('action') == 'tool':
                            tool_name_in_hist = action_obj.get('tool_name') or ''
                            if 'search' in tool_name_in_hist.lower() and item.get('output'):
                                has_search_results = True
                                break

            # If we already have search results, finish instead of searching again
            if has_search_results:
                final_text = f"Based on previous search results for '{req.goal_text}'."
                reasoning = "Already have search results from previous action."
                finish = True
            else:
                # Otherwise, try searching if goal suggests it
                lower_goal = req.goal_text.lower()
                if any(word in lower_goal for word in ["search", "find", "lookup", "fts", "what", "how", "where", "when", "why", "information"]):
                    tool_name = "context.fts_search"
                    tool_args = {"query": req.goal_text}
                    reasoning = "Full-text search will help answer this question"
                    finish = False
                elif any(word in lower_goal for word in ["repo", "analyze", "code", "understand", "structure", "architecture"]):
                    tool_name = "context.fts_search"
                    tool_args = {"query": req.goal_text}
                    reasoning = "Analyzing codebase requires searching documentation and code"
                    finish = False
                else:
                    final_text = f"Completed: {req.goal_text[:80]}"
                    reasoning = "Task completed. No additional tool calls required."
                    finish = True

    return {
        "status": "ok",
        "duration_ms": 0,
        "intent_id": f"agent-{int(time.time()*1000)}",
        "tool_name": tool_name,
        "tool_args": tool_args,
        "reasoning": reasoning,
        "finish": finish,
        "final_text": final_text,
        "trace": []
    }


def _post_callback(url: str, payload: Dict[str, Any]):
    try:
        requests.post(url, json=payload, timeout=3)
        try:
            log_event('agent_intent_callback_delivered', url=url, correlation_id=payload.get('correlation_id'))
        except Exception:
            pass
    except Exception as e:
        try:
            log_event('agent_intent_callback_error', url=url, error=str(e))
        except Exception:
            pass


@app.post("/agent_intent_async", response_model=IntentAccepted)
async def agent_intent_async(req: AgentIntentRequest, accept_version: Optional[str] = Header(default="v1", alias="Accept-Version")):
    # Accept and compute in background, then POST to callback_url
    if not req.callback_url:
        return IntentAccepted(status="error", job_id="")  # client error; require callback_url

    job_id = f"agent-{int(time.time()*1000)}"
    payload = {
        "job_id": job_id,
        "correlation_id": req.correlation_id,
    }

    def worker():
        start = time.time()
        try:
            log_event('agent_intent_received_async', correlation_id=req.correlation_id)
        except Exception:
            pass
        try:
            result = _compute_intent_sync(req)
            result.update(payload)
            result["duration_ms"] = int((time.time() - start) * 1000)
        except Exception as e:
            result = {"status": "error", "error": str(e)}
            result.update(payload)
        _post_callback(req.callback_url or '', result)

    threading.Thread(target=worker, daemon=True).start()
    return IntentAccepted(status="accepted", job_id=job_id)


@app.post("/workflow_intent", response_model=WorkflowIntentResponse)
async def workflow_intent(req: WorkflowIntentRequest, accept_version: Optional[str] = Header(default="v1", alias="Accept-Version")):
    start = time.time()
    try:
        log_event('workflow_intent_received', run_id=req.run_id, workflow=req.workflow_name, node=req.current_node)
    except Exception:
        pass
    # Minimal stub: move to next node if present in params, else finish
    next_node = None
    action_type = None
    tool_name = None
    tool_args = None
    finish = False
    reasoning = None

    # Accept a trivial transition rule from params
    if req.params and "next" in req.params:
        next_node = str(req.params["next"]) or None
        reasoning = f"Transition to {next_node} based on params"
    else:
        finish = True
        reasoning = "No further steps"

    dur = int((time.time() - start) * 1000)
    try:
        log_event('workflow_intent_decision', run_id=req.run_id, workflow=req.workflow_name, next_node=next_node, duration_ms=dur)
    except Exception:
        pass
    return WorkflowIntentResponse(
        status="ok",
        duration_ms=dur,
        intent_id=f"wf-{int(time.time()*1000)}",
        next_node=next_node,
        action_type=action_type,
        tool_name=tool_name,
        tool_args=tool_args,
        reasoning=reasoning,
        finish=finish,
        trace=[]
    )
def _queue_collection():
    cli = _get_mongo_client()
    if cli is None:
        return None
    db = cli[_mongo_db_name()]
    return db['reasoning_queue']

def _ensure_queue_indexes():
    try:
        col = _queue_collection()
        if col is None:
            return
        # Compound index to accelerate claiming and listing
        col.create_index([
            ('type', 1), ('status', 1), ('created_at', 1)
        ], name='type_status_created_at')
        col.create_index('correlation_id', name='correlation_id')
    except Exception:
        # best-effort only
        pass


def _process_one_queue_item():
    col = _queue_collection()
    if col is None:
        return False
    try:
        doc = col.find_one_and_update(
            { 'type': 'agent_intent', 'status': 'queued' },
            { '$set': { 'status': 'processing', 'updated_at': datetime.utcnow() } },
            sort=[('created_at', 1)],
            return_document=True
        )
        if not doc:
            return False
        # If canceled between queue and processing state, honor cancel
        if doc.get('status') == 'canceled':
            return False
        payload = doc.get('payload') or {}
        req = AgentIntentRequest(**{
            'session_id': payload.get('session_id') or 'dev',
            'persona': payload.get('persona') or { 'name': 'savant-engineer' },
            'driver': payload.get('driver'),
            'rules': payload.get('rules'),
            'instructions': payload.get('instructions'),
            'llm': payload.get('llm'),
            'repo_context': payload.get('repo_context'),
            'memory_state': payload.get('memory_state'),
            'history': payload.get('history'),
            'goal_text': payload.get('goal_text') or '',
            'forced_tool': payload.get('forced_tool'),
            'max_steps': payload.get('max_steps'),
        })
        # If canceled before compute, bail
        dcheck = col.find_one({ '_id': doc['_id'] }) or {}
        if dcheck.get('status') == 'canceled':
            return True
        result = _compute_intent_sync(req)
        col.update_one({ '_id': doc['_id'] }, { '$set': { 'status': 'done', 'updated_at': datetime.utcnow(), 'result': result } })
        try:
            log_event('agent_intent_processed_queue', correlation_id=doc.get('correlation_id'))
        except Exception:
            pass
        return True
    except Exception:
        return False


def _queue_loop():
    # Polls Mongo for queued items and processes them
    while True:
        processed = _process_one_queue_item()
        if not processed:
            time.sleep(max(_QUEUE_POLL_MS, 1) / 1000.0)


def _start_queue_worker():
    global _QUEUE_WORKER_STARTED
    if _QUEUE_WORKER_STARTED:
        return
    try:
        if _get_mongo_client() is None:
            return
        _ensure_queue_indexes()
        # Spawn N worker threads
        n = max(_QUEUE_WORKERS, 1)
        for _ in range(n):
            t = threading.Thread(target=_queue_loop, daemon=True)
            t.start()
        _QUEUE_WORKER_STARTED = True
    except Exception:
        _QUEUE_WORKER_STARTED = False


# Start queue worker by default (can disable with REASONING_QUEUE_WORKER=0)
if os.environ.get('REASONING_QUEUE_WORKER', '1') != '0':
    _start_queue_worker()


@app.post("/agent_intent_cancel")
def agent_intent_cancel(payload: Dict[str, Any]):
    try:
        cid = str((payload or {}).get('correlation_id') or '')
        if not cid:
            return { 'ok': False, 'error': 'missing_correlation_id' }
        col = _queue_collection()
        if col is None:
            return { 'ok': True }  # nothing to cancel in http mode
        col.update_many({ 'type': 'agent_intent', 'correlation_id': cid, 'status': { '$in': ['queued', 'processing'] } }, { '$set': { 'status': 'canceled', 'updated_at': datetime.utcnow() } })
        return { 'ok': True }
    except Exception as e:
        return { 'ok': False, 'error': str(e) }
