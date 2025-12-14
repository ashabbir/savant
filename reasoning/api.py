from fastapi import FastAPI, Request, Header
from pydantic import BaseModel
from typing import Optional, Dict, Any, List
import time


app = FastAPI(title="Savant Reasoning API", version="v1")


class AgentIntentRequest(BaseModel):
    session_id: str
    persona: Dict[str, Any]
    driver: Optional[Dict[str, Any]] = None
    repo_context: Optional[Dict[str, Any]] = None
    memory_state: Optional[Dict[str, Any]] = None
    history: Optional[List[Dict[str, Any]]] = None
    goal_text: str
    forced_tool: Optional[str] = None
    max_steps: Optional[int] = None


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


@app.post("/agent_intent", response_model=AgentIntentResponse)
async def agent_intent(req: AgentIntentRequest, accept_version: Optional[str] = Header(default="v1", alias="Accept-Version")):
    start = time.time()
    # Minimal stub logic: if forced_tool given, echo it; otherwise finish with a summary
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
        # Simple heuristic: if goal mentions search, propose context.fts_search else finish
        if any(word in req.goal_text.lower() for word in ["search", "find", "lookup", "fts"]):
            tool_name = "context.fts_search"
            tool_args = {"query": req.goal_text}
            reasoning = "Search seems appropriate"
            finish = False
        else:
            final_text = f"Completed: {req.goal_text[:80]}"
            reasoning = "No tool required"
            finish = True

    dur = int((time.time() - start) * 1000)
    return AgentIntentResponse(
        status="ok",
        duration_ms=dur,
        intent_id=f"agent-{int(time.time()*1000)}",
        tool_name=tool_name,
        tool_args=tool_args,
        reasoning=reasoning,
        finish=finish,
        final_text=final_text,
        trace=[]
    )


@app.post("/workflow_intent", response_model=WorkflowIntentResponse)
async def workflow_intent(req: WorkflowIntentRequest, accept_version: Optional[str] = Header(default="v1", alias="Accept-Version")):
    start = time.time()
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

