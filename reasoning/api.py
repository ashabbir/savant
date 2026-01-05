from pydantic import BaseModel
from typing import Optional, Dict, Any, List
import time
import os
from datetime import datetime
import requests
import json
import threading

# --- Logging ---
_REASONING_LOG_STDOUT = os.environ.get('REASONING_LOG_STDOUT', '1') not in ('0', '', 'false', 'False')
_REASONING_LOG_FILE = os.environ.get('REASONING_LOG_FILE')  # e.g., 'logs/reasoning.log'

def _write_local_log(doc: Dict[str, Any]):
    try:
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
        pass

def log_event(event: str, **kwargs):
    doc = {
        'service': 'reasoning',
        'mcp': 'reasoning',
        'event': event,
        'timestamp': datetime.utcnow(),
    }
    doc.update(kwargs or {})
    # Only local logging (Redis/File based architecture)
    _write_local_log(doc)

# ---------------------
# Search orchestration helpers (dedupe/diversify/limits)
# ---------------------

def _normalize_query(q: Optional[str]) -> str:
    try:
        return " ".join((q or "").strip().lower().split())
    except Exception:
        return (q or "").strip().lower()


def _extract_search_history(history: Optional[List[Dict[str, Any]]]):
    """Parse history and extract prior search actions."""
    searches: List[Dict[str, Any]] = []
    pairs = set()
    tried_queries = set()
    tried_tools = set()
    if not (history and isinstance(history, list)):
        return searches, pairs, tried_queries, tried_tools

    for item in history:
        try:
            if not isinstance(item, dict):
                continue
            action_obj = item.get('action')
            if isinstance(action_obj, dict):
                action_type = action_obj.get('action') or 'tool'
                tool = (action_obj.get('tool_name') or '').strip()
                args = action_obj.get('args') or {}
            else:
                action_type = item.get('action') or item.get('type') or 'unknown'
                tool = (item.get('tool_name') or item.get('tool') or '').strip()
                args = item.get('args') or item.get('input') or {}

            if str(action_type).lower() != 'tool':
                continue

            t_low = tool.lower()
            # Consider these as searches
            is_search = any(s in t_low for s in ['search', 'fts_search'])
            if not is_search:
                continue

            # args may use 'q' or 'query'
            if isinstance(args, dict):
                q = args.get('query') or args.get('q') or ''
            else:
                q = ''
            nq = _normalize_query(str(q))
            had_output = bool(item.get('output'))
            entry = {
                'tool': tool,
                'query': nq,
                'args': args if isinstance(args, dict) else {},
                'had_output': had_output,
            }
            searches.append(entry)
            tried_tools.add(tool)
            if nq:
                tried_queries.add(nq)
                pairs.add((tool, nq))
        except Exception:
            continue

    return searches, pairs, tried_queries, tried_tools


def _keywords_variant(text: str) -> str:
    """Generate a simple keyword-only variant of a query by removing common stopwords."""
    stop = {
        'the', 'a', 'an', 'to', 'for', 'and', 'or', 'in', 'of', 'on', 'with', 'by', 'from', 'about', 'into', 'over',
        'how', 'what', 'where', 'when', 'why', 'which', 'who', 'whom', 'whose',
        'find', 'search', 'look', 'lookup', 'locate', 'show', 'give', 'me', 'all', 'any', 'some', 'is', 'are', 'was', 'were',
        'repo', 'project', 'code', 'file', 'files', 'docs', 'documentation'
    }
    toks = [t for t in _normalize_query(text).split() if t not in stop]
    # Keep top 8 tokens for brevity
    return ' '.join(toks[:8]) if toks else _normalize_query(text)

def _filter_search_tools(tools: Optional[List[str]]) -> Optional[List[str]]:
    if tools is None:
        return None
    allowed = [t for t in tools if isinstance(t, str) and t.strip()]
    search_tools = [t for t in allowed if any(k in t.lower() for k in ['search', 'fts_search', 'jira'])]
    return search_tools


def _history_weights(count: int) -> List[float]:
    if count <= 0:
        return []
    if count == 1:
        return [1.0]
    last_weight = 0.7
    remainder = 0.3
    denom = (count - 1) * count / 2.0
    weights = []
    for i in range(1, count):
        weights.append(remainder * (i / denom))
    weights.append(last_weight)
    return weights


def _history_item_line(item: Dict[str, Any], index: int, weight: float) -> str:
    action_obj = item.get('action')
    if isinstance(action_obj, dict):
        action_type = action_obj.get('action') or 'tool'
        tool = action_obj.get('tool_name') or ''
    else:
        action_type = item.get('action') or item.get('type') or 'unknown'
        tool = item.get('tool_name') or item.get('tool') or ''

    result_preview = ''
    output_obj = item.get('output')
    if isinstance(output_obj, dict):
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

    base = f"{index}. (weight {weight:.2f}) {action_type} {tool}".rstrip()
    if result_preview:
        return f"{base}: {result_preview}..."
    return base


def _history_context_with_weights(history: Optional[List[Dict[str, Any]]]) -> str:
    if not (history and isinstance(history, list)):
        return ""
    weights = _history_weights(len(history))
    try:
        log_event('history_weights', count=len(history), first=weights[0] if weights else None, last=weights[-1] if weights else None)
    except Exception:
        pass
    lines = ["Note: Newer items have higher weight; older items have lower weight."]
    for i, item in enumerate(history, 1):
        if isinstance(item, dict):
            weight = weights[i - 1] if i - 1 < len(weights) else 0.0
            lines.append(_history_item_line(item, i, weight))
    return "\n## Previous Actions and Results:\n" + "\n".join(lines)


def _candidate_search_tools(goal_text: str, preferred: Optional[str] = None, available_tools: Optional[List[str]] = None) -> List[str]:
    goal = _normalize_query(goal_text)
    tools = []
    if preferred:
        tools.append(preferred)
    if available_tools is not None:
        # If explicitly provided, only consider allowed tools.
        allowed = [t for t in available_tools if isinstance(t, str) and t.strip()]
        for t in allowed:
            if t not in tools:
                tools.append(t)
        return tools
    # Default search tools when no allowlist is supplied
    if 'context.fts_search' not in tools:
        tools.append('context.fts_search')
    if 'context.memory_search' not in tools:
        tools.append('context.memory_search')
    if any(k in goal for k in ['jira', 'issue ', 'ticket ']):
        tools.append('jira.jira_search')
    return tools


def _candidate_queries(goal_text: str, llm_query: Optional[str] = None) -> List[str]:
    cands: List[str] = []
    # LLM suggested query first
    if llm_query and _normalize_query(llm_query):
        cands.append(llm_query)
    # Then the raw goal
    if _normalize_query(goal_text) not in map(_normalize_query, cands):
        cands.append(goal_text)
    # Then a keywords-only variant
    kw = _keywords_variant(goal_text)
    if _normalize_query(kw) not in map(_normalize_query, cands):
        cands.append(kw)
    return cands


def _math_fallback(text: str) -> Optional[str]:
    if text is None:
        return None
    try:
        import re
        m = re.search(r'(-?\d+(?:\.\d+)?(?:\s*[\+\-\*\/]\s*-?\d+(?:\.\d+)?)+)', str(text))
        if not m:
            return None
        expr = m.group(1).strip()
        if not re.fullmatch(r'[\d\.\s\+\-\*\/\(\)]+', expr):
            return None
        val = eval(expr, {"__builtins__": {}}, {})
        if isinstance(val, (int, float)):
            if isinstance(val, float) and val.is_integer():
                return str(int(val))
            return str(val)
    except Exception:
        return None
    return None


def _pick_search_action(goal_text: str,
                        history: Optional[List[Dict[str, Any]]],
                        suggested_tool: Optional[str],
                        suggested_query: Optional[str],
                        repo_context: Optional[Dict[str, Any]] = None,
                        max_searches: int = 4,
                        available_tools: Optional[List[str]] = None):
    """Choose the next search action honoring dedupe/diversity and limits."""
    searches, tried_pairs, tried_queries, tried_tools = _extract_search_history(history)
    total_searches = len(searches)

    # If we've reached max allowed searches, finish and request summary
    if total_searches >= max_searches:
        summary = _build_simple_summary_from_history(history, prefix=f"Reached search limit ({max_searches}). ")
        return (None, None, True, summary)

    # Build candidate tools and queries
    tools = _candidate_search_tools(goal_text, preferred=suggested_tool, available_tools=available_tools)
    if available_tools is not None and not tools:
        return (None, None, True, "No tools available.")
    queries = _candidate_queries(goal_text, llm_query=suggested_query)

    # Try to find a new (tool, query) combination not yet tried
    for tool in tools:
        for q in queries:
            nq = _normalize_query(q)
            if (tool, nq) in tried_pairs:
                continue
            # Build args; include repo if provided
            if tool == 'jira.jira_search':
                args = { 'jql': q }
            else:
                args = { 'query': q }
            if isinstance(repo_context, dict):
                repo = repo_context.get('repo') or repo_context.get('repos')
                if repo:
                    args['repo'] = repo
            return (tool, args, False, None)

    # If all combinations exhausted but we still under limit, finish to avoid loops
    exhausted_msg = _build_simple_summary_from_history(history, prefix="No new search combinations left. ")
    return (None, None, True, exhausted_msg)


def _build_simple_summary_from_history(history: Optional[List[Dict[str, Any]]], prefix: str = "") -> str:
    """Build a lightweight text summary from prior search outputs in history."""
    parts: List[str] = []
    if history and isinstance(history, list):
        idx = 0
        for item in history:
            try:
                if not isinstance(item, dict):
                    continue
                action_obj = item.get('action')
                tool = ''
                if isinstance(action_obj, dict):
                    if (action_obj.get('action') or '').lower() != 'tool':
                        continue
                    tool = (action_obj.get('tool_name') or '').strip()
                else:
                    if (item.get('action') or item.get('type') or '').lower() != 'tool':
                        continue
                    tool = (item.get('tool_name') or item.get('tool') or '').strip()
                if 'search' not in tool.lower():
                    continue
                out = item.get('output') or {}
                text = ''
                if isinstance(out, dict):
                    content = out.get('content')
                    if isinstance(content, list) and content:
                        first = content[0]
                        if isinstance(first, dict):
                            text = first.get('text') or ''
                        else:
                            text = str(first)
                # Truncate
                text = (text or '')
                text = text.replace('\n', ' ')
                if text:
                    text = text[:200]
                if text:
                    idx += 1
                    parts.append(f"{idx}. {tool}: {text} ...")
            except Exception:
                continue
    base = prefix + "Summaries from previous searches:\n" if prefix else "Summaries from previous searches:\n"
    if parts:
        return base + "\n".join(parts)
    return prefix + "No prior search outputs to summarize."


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
    tools_available: Optional[List[str]] = None
    tools_catalog: Optional[List[str]] = None
    goal_text: str
    forced_tool: Optional[str] = None
    max_steps: Optional[int] = None
    agent_state: Optional[Dict[str, Any]] = None
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


def _call_google_api(model: str, goal: str, instructions: Optional[str], api_key: str, history: Optional[List[Dict[str, Any]]] = None, persona: Optional[Dict[str, Any]] = None, driver: Optional[Dict[str, Any]] = None) -> str:
    """Call Google Generative AI API directly."""
    # Combine instructions, persona, and driver for a comprehensive system prompt
    system_parts = []
    if persona and (persona.get('prompt_md') or persona.get('summary')):
        system_parts.append(f"## Persona\n{persona.get('prompt_md') or persona.get('summary')}")
    if driver and driver.get('prompt_md'):
        system_parts.append(f"## Driver\n{driver.get('prompt_md')}")
    if instructions:
        system_parts.append(f"## Additional Instructions\n{instructions}")
    
    system_prompt = "\n\n".join(system_parts) or "You are a helpful agent. Provide concise responses."

    try:
        log_event('google_api_called', goal=goal, history_is_none=(history is None), history_len=len(history) if history else 0)
    except:
        pass

    history_context = ""
    if history and isinstance(history, list) and len(history) > 0:
        try:
            first_item = history[0] if len(history) > 0 else {}
            first_item_type = type(first_item).__name__
            first_item_str = str(first_item)[:300] if first_item else "empty"
            log_event('history_received', history_count=len(history), goal_text=goal, first_item_type=first_item_type, first_item_preview=first_item_str)
        except Exception as e:
            log_event('history_received_error', history_count=len(history), goal_text=goal, error=str(e))
        history_context = _history_context_with_weights(history)

    prompt = f"""{system_prompt}

You are analyzing a task and deciding how to proceed.

Decision Rules:
1. If you can answer the goal directly from the Goal text or history, choose ACTION: finish.
2. If you need more information, choose a tool from the "Available Tools" list.
3. NEVER repeat the same tool+query combination.
4. Use at most 4 steps total.

Available Tools: context.fts_search, context.memory_search, jira.jira_search

{history_context}

Goal: {goal}

Respond with ONLY these exact lines:
ACTION: finish
RESULT: your final answer
REASONING: short explanation of your decision

OR

ACTION: tool_name
RESULT: tool arguments (query or JQL)
REASONING: why you need this tool"""

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

        if 'candidates' in result and len(result['candidates']) > 0:
            candidate = result['candidates'][0]
            if 'content' in candidate and 'parts' in candidate['content']:
                text_parts = candidate['content']['parts']
                if len(text_parts) > 0 and 'text' in text_parts[0]:
                    return text_parts[0]['text']

        raise Exception(f"Unexpected Google API response: {result}")
    except requests.exceptions.RequestException as e:
        raise Exception(f"Google API request failed: {str(e)}")


def _use_llm_for_reasoning(goal_text: str, instructions: Optional[str], llm_provider: Optional[str], llm_model: Optional[str], api_key: Optional[str] = None, history: Optional[List[Dict[str, Any]]] = None, available_tools: Optional[List[str]] = None, persona: Optional[Dict[str, Any]] = None, driver: Optional[Dict[str, Any]] = None) -> tuple:
    """Use LLM to reason about what tool to call or action to take."""
    try:
        from langchain.prompts import PromptTemplate

        model_name = llm_model or 'phi3.5:latest'
        provider_name = (llm_provider or '').lower().strip()

        history_context = ""
        if history and isinstance(history, list) and len(history) > 0:
            try:
                first_item = history[0] if len(history) > 0 else {}
                first_item_type = type(first_item).__name__
                first_item_str = str(first_item)[:300] if first_item else "empty"
                log_event('history_received', history_count=len(history), goal_text=goal_text, first_item_type=first_item_type, first_item_preview=first_item_str)
            except Exception as e:
                log_event('history_received_error', history_count=len(history), goal_text=goal_text, error=str(e))
            history_context = _history_context_with_weights(history)

        if provider_name in ['google api', 'google']:
            if not api_key:
                raise Exception('API key not provided for Google API provider')
            response = _call_google_api(model_name, goal_text, instructions, api_key, history, persona, driver)
        else:
            from langchain_community.llms import Ollama
            llm_base_url = os.environ.get('OLLAMA_BASE_URL', 'http://localhost:11434')
            llm = Ollama(base_url=llm_base_url, model=model_name, temperature=0.3)

            # Combine instructions, persona, and driver for a comprehensive system prompt
            system_parts = []
            if persona and (persona.get('prompt_md') or persona.get('summary')):
                system_parts.append(f"## Persona\n{persona.get('prompt_md') or persona.get('summary')}")
            if driver and driver.get('prompt_md'):
                system_parts.append(f"## Driver\n{driver.get('prompt_md')}")
            if instructions:
                system_parts.append(f"## Additional Instructions\n{instructions}")
            
            system_prompt = "\n\n".join(system_parts) or "You are a helpful agent. Provide concise responses."

            tools_line = None
            if available_tools is not None:
                tools_line = ", ".join(available_tools) if available_tools else "none"

            prompt_template = PromptTemplate(
                input_variables=["goal"],
                template=f"""{system_prompt}

You are analyzing a task and deciding how to proceed.

Decision Rules:
1. If you can answer the goal directly from the Goal text or history, choose ACTION: finish.
2. If you need more information, choose a tool from the "Available Tools" list.
3. NEVER repeat the same tool+query combination.
4. Use at most 4 steps total.

Available Tools: {tools_line or "context.fts_search, context.memory_search, jira.jira_search"}

{history_context}

Goal: {{goal}}

Respond with ONLY these exact lines:
ACTION: finish
RESULT: your final answer
REASONING: short explanation of your decision

OR

ACTION: tool_name
RESULT: tool arguments (query or JQL)
REASONING: why you need this tool"""
            )

            chain = prompt_template | llm
            response = chain.invoke({"goal": goal_text})

        lines = response.strip().split('\n')
        action = None
        result = None
        reasoning = response[:200]

        for line in lines:
            if line.startswith('ACTION:'):
                action = line.replace('ACTION:', '').strip()
            elif line.startswith('RESULT:'):
                result = line.replace('RESULT:', '').strip()
            elif line.startswith('REASONING:'):
                reasoning = line.replace('REASONING:', '').strip()

        if action and action.lower() == 'finish':
            return (None, None, result or goal_text, reasoning, True)
        elif action:
            a = action.lower()
            if a.startswith('context.fts_search'):
                return ("context.fts_search", {"query": result or goal_text}, None, reasoning, False)
            if a.startswith('context.memory_search'):
                return ("context.memory_search", {"query": result or goal_text}, None, reasoning, False)
            if a.startswith('jira.jira_search'):
                return ("jira.jira_search", {"jql": result or goal_text}, None, reasoning, False)
            
            # Generic tool fallback
            return (action, {"query": result or goal_text}, None, reasoning, False)
        else:
            # Fallback: Check if response is JSON despite line-based instructions
            try:
                import json
                # Find JSON block
                s = response.strip()
                if '```json' in s:
                    s = s.split('```json')[1].split('```')[0].strip()
                elif '{' in s:
                    s = s[s.find('{'):s.rfind('}')+1]
                
                data = json.loads(s)
                action_val = data.get('action') or data.get('tool_name') or data.get('tool')
                result_val = data.get('result') or data.get('final') or data.get('args', {}).get('query') or data.get('args', {}).get('q')
                reason_val = data.get('reasoning') or data.get('reason') or "Parsed from JSON fallback"
                
                if action_val:
                    if str(action_val).lower() == 'finish':
                        return (None, None, result_val or goal_text, reason_val, True)
                    return (str(action_val), {"query": result_val or goal_text}, None, reason_val, False)
            except:
                pass

            return (None, None, result or response[:500], reasoning, True)

    except Exception as e:
        try:
            log_event('llm_reasoning_error', error=str(e), goal_text=goal_text)
        except:
            pass
        return (None, None, None, f"LLM error: {str(e)}", False)


def _compute_intent_sync(req: AgentIntentRequest) -> Dict[str, Any]:
    tool_name = None
    tool_args: Optional[Dict[str, Any]] = None
    final_text = None
    reasoning = None
    finish = False
    tools_available = _filter_search_tools(req.tools_available)
    tools_disabled = req.tools_available is not None and not tools_available

    if req.forced_tool:
        tool_name = req.forced_tool
        tool_args = {"echo": True}
        reasoning = f"Forced tool: {req.forced_tool}"
        finish = False
    else:
        llm_provider = (req.llm or {}).get('provider') if isinstance(req.llm, dict) else None
        llm_model = (req.llm or {}).get('model') if isinstance(req.llm, dict) else None

        llm_api_key = (req.llm or {}).get('api_key') if isinstance(req.llm, dict) else None
        tool_name, tool_args, final_text, reasoning, finish = _use_llm_for_reasoning(
            req.goal_text,
            req.instructions,
            llm_provider,
            llm_model,
            llm_api_key,
            req.history,
            tools_available,
            req.persona,
            req.driver
        )

        if tool_name is None and not finish and not tools_disabled:
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

            if not has_search_results:
                # Only force search if it's CLEARLY a search intent and tools are available
                lower_goal = req.goal_text.lower()
                is_search_query = any(word in lower_goal for word in ["search", "find", "fts", "lookup"])
                
                if is_search_query and (tools_available is None or "context.fts_search" in tools_available):
                    tool_name = "context.fts_search"
                    tool_args = {"query": req.goal_text}
                    reasoning = "Targeted search required to find specific information."
                    finish = False
                else:
                    # Generic completion: don't force search for "what/how" if LLM didn't suggest it
                    final_text = _math_fallback(req.goal_text) or req.goal_text
                    reasoning = "Task processed. Providing direct answer based on request."
                    finish = True

        if tools_disabled:
            tool_name = None
            tool_args = None
            finish = True
            if not final_text:
                final_text = _math_fallback(req.goal_text) or req.goal_text
        if not finish and not tools_disabled:
            try:
                suggested_tool = tool_name or ''
                suggested_query = None
                if isinstance(tool_args, dict):
                    suggested_query = tool_args.get('query') or tool_args.get('q')
                is_search_tool = suggested_tool and any(s in suggested_tool.lower() for s in ['search', 'fts_search'])
                if is_search_tool or not tool_name:
                    sel_tool, sel_args, must_finish, finish_text = _pick_search_action(
                        req.goal_text, req.history, suggested_tool if is_search_tool else None, suggested_query, req.repo_context, max_searches=int(req.max_steps or 4), available_tools=tools_available
                    )
                    if must_finish:
                        tool_name = None
                        tool_args = None
                        finish = True
                        final_text = finish_text
                        if not reasoning:
                            reasoning = 'Search budget reached or no new combinations left.'
                        try:
                            log_event('search_finish_enforced', goal=req.goal_text)
                        except Exception:
                            pass
                    else:
                        tool_name = sel_tool
                        tool_args = sel_args
                        finish = False
                        if not reasoning:
                            reasoning = 'Chose diversified search tool/query based on history.'
                        try:
                            log_event('search_selection', tool=sel_tool, query=(sel_args.get('query') if isinstance(sel_args, dict) else None) or (sel_args.get('jql') if isinstance(sel_args, dict) else None))
                        except Exception:
                            pass
            except Exception:
                pass

    # Post-process: If we are finishing and the final_text looks like it might be a hallucinated math result
    if finish and final_text:
        # If the result is a short string (like "4") but the goal has a complex math expression
        # that doesn't equal that number, try to correct it.
        goal_math = _math_fallback(req.goal_text)
        if goal_math:
            # If the LLM result is just a number and it's different from our calculation
            clean_final = final_text.strip().lower()
            if clean_final.replace('.','',1).isdigit():
                if clean_final != goal_math.lower():
                    final_text = goal_math
                    reasoning = f"(Corrected math) {reasoning}"
            elif clean_final == req.goal_text.strip().lower():
                final_text = goal_math

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
