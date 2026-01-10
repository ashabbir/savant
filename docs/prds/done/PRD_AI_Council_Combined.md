# PRD — AI Council with Chat-to-Council Interaction

**Protocol Version:** 1.0  
**Owner:** Amd  
**Status:** Implemented (v1)  
**Scope:** Backend + Hub UI (basic)

---

## 1. Overview

**Product Name:** AI Council  

**Purpose**  
AI Council is a backend orchestration service that supports two tightly integrated execution modes:

- **Chat Mode** — lightweight, conversational, exploratory thinking  
- **Council Mode** — structured, multi-agent deliberation for decisions  

A user can begin with simple chat and, at any point, explicitly escalate the same session into a formal council decision. The system returns a single synthesized, high-quality answer while preserving full context.

Chat and Council are **not separate systems**.  
They are two execution modes over a **single session and shared context**.

---

## 1.1 Implementation Snapshot (v1)

- Engine: `lib/savant/engines/council/*` (Ruby) with MCP tools exposed over HTTP via the Hub.
- Storage (Postgres): `council_sessions`, `council_messages`, `council_runs` (+ indices). Optional Mongo mirrors for logs.
- Frontend (Hub UI): `frontend/src/pages/council/Council.tsx` mounts at `/council` with a two‑panel layout and live polling during council runs.
- Reasoning: Integrates `Savant::Reasoning::Client` with a safe demo fallback (`COUNCIL_DEMO_MODE=1`).
- Protocol: Enforces explicit escalation, safety veto, and mandatory return to chat.

Notes:
- Requires at least two agents to escalate; raises `insufficient_agents` otherwise.
- Session `mode` is persisted and flipped back to `chat` when the run completes or on explicit return.
- UI reflects status with live updates and a council transcript appended to the session.

---

## 2. Core Principles

- **Chat = Thinking**
- **Council = Deciding**
- One session, continuous context
- Council is explicit, never silent
- System always returns to chat after council

---

## 3. Users and Use Cases

**Users**
- Engineers
- Architects
- Product Managers
- Savant workflows

**Use Cases**
- Brainstorm → decide
- Clarify → finalize
- Trade-off analysis
- Strategy stress-testing
- Iterative decision refinement

---

## 4. Session Model

All interactions occur within a single session object.

```json
{
  "session_id": "uuid",
  "messages": [],
  "context": {},
  "mode": "chat | council",
  "artifacts": {}
}
```

**Field Definitions**
- `messages`: chronological chat history
- `context`: extracted goals, constraints, assumptions
- `mode`: current execution behavior
- `artifacts`: council outputs, traces, summaries

Implementation details
- `messages` are persisted in `council_messages` with `role`, optional `agent_name`, `status`, `run_id`, and timestamps.
- `mode` is stored on `council_sessions.mode` and set to `council` on escalation, then back to `chat` on completion/return.
- `context`/`artifacts` stored as JSONB columns on `council_sessions` (added via migrations/ALTER in engine bootstrap).

---

## 5. Chat Mode (Default)

### Behavior
- Single lightweight agent
- No multi-agent debate
- No voting or veto logic
- Minimal logging
- Optimized for latency

### Intended Usage
- Requirement discovery
- Brainstorming
- Clarification
- Iterative thinking

---

## 6. Council Mode (Escalated)

### Behavior
- Full multi-agent council protocol
- Parallel role execution
- Debate and refinement rounds
- Voting signals and veto enforcement
- Structured final output
- Full observability

### Entry Rule
Council mode is **never automatic without user consent**.

---

## 7. Council Roles

Roles are pluggable via configuration. All roles share the same runtime and differ only by system prompt and authority rules.

### 7.1 Analyst
- Decomposes the problem
- Proposes options with pros/cons and assumptions

### 7.2 Skeptic
- Identifies risks and hidden assumptions
- Challenges over-confidence

### 7.3 Pragmatist
- Optimizes for feasibility
- Proposes a realistic default path

### 7.4 Safety / Ethics
- Evaluates safety and compliance
- Holds **hard veto authority** in configured domains

### 7.5 Moderator
- Orchestrates the protocol
- Synthesizes the final answer
- Must respect vetoes and policies

---

## 8. Promotion from Chat to Council

### 8.1 Explicit Trigger (Primary)

User issues a command such as:
- “run council”
- “escalate to council”
- “get a council decision”

System immediately escalates.

---

### 8.2 Implicit Trigger (Optional, Confirmed)

System may detect decision-oriented language or ambiguity and must ask for confirmation before escalation.

No silent council runs are allowed.

---

## 9. Council Invocation Flow

1. **Freeze Chat Context**  
   - Summarize conversation
   - Extract goal, constraints, options, unresolved questions

2. **Generate Council Input**
```json
{
  "query": "synthesized problem statement",
  "context": {
    "conversation_summary": "...",
    "constraints": [],
    "options": []
  }
}
```

3. **Execute Council Protocol**
   - Intent classification
   - Initial positions
   - Debate / refinement
   - Synthesis

4. **Persist Artifacts**
   - Final recommendation
   - Council trace
   - Confidence signals

Implementation specifics
- Escalation creates a `council_runs` record with `run_id`, `status='pending'`, `phase='init'`, and captured `query/context`.
- Safety veto short‑circuits the run and appends a veto message; session returns to chat with a system notice.

---

## 10. Discussion Protocol (Council Mode)

### Phase -1 — Intent Classification
Determines intent and domain to select council preset.

### Phase 0 — Input Normalization
Normalizes goal, constraints, context, and options.

### Phase 1 — Initial Positions
Roles run in parallel and emit structured outputs.

### Phase 2 — Debate / Refinement
Configurable rounds; roles refine positions using summaries.

### Phase 3 — Synthesis
Moderator produces a single final answer.

---

## 11. Voting and Weighting

- Role scores are **signals only**
- Safety veto overrides all scoring
- Conflicting signals must be explained in justification

---

## 12. Return to Chat (Mandatory)

After council completion:
- Session mode switches back to `chat`
- Council result is injected into conversation
- User may iterate, adjust constraints, or re-run council

Council never ends the session.

Implementation specifics
- Engine appends a system message on return: "Returned to chat mode. …"
- UI exposes an explicit "Return to Chat" action when in council mode.

---

## 13. API Contract (MCP + HTTP via Hub)

All operations are implemented as MCP tools on the `council` engine and surfaced over HTTP by the Hub at `/{engine}/tools/{tool}/call`.

Session management
- `POST /council/tools/council_session_create/call` → `{ title?, description?, agents?[] }`
- `POST /council/tools/council_sessions_list/call` → `{ limit? }`
- `POST /council/tools/council_session_get/call` → `{ id }`
- `POST /council/tools/council_session_update/call` → `{ id, title?, description?, agents?[] }`
- `POST /council/tools/council_session_delete/call` → `{ id }`

Chat mode
- `POST /council/tools/council_append_user/call` → `{ session_id, text }`
- `POST /council/tools/council_append_agent/call` → `{ session_id, agent_name, run_id?, text?, status? }`
- `POST /council/tools/council_agent_step/call` → `{ session_id, goal_text, agent_name? }` (single reasoning step)

Council protocol
- `POST /council/tools/council_roles/call` → `{}"
- `POST /council/tools/council_status/call` → `{ session_id }`
- `POST /council/tools/council_escalate/call` → `{ session_id, query? }`
- `POST /council/tools/council_run/call` → `{ session_id, run_id?, max_debate_rounds? }`
- `POST /council/tools/council_return_to_chat/call` → `{ session_id, message? }`
- `POST /council/tools/council_run_get/call` → `{ run_id }`
- `POST /council/tools/council_runs_list/call` → `{ session_id, limit? }`

Mode semantics (v1)
- Chat and council are explicit. An `auto` suggestion mode is reserved for future; not implemented in v1.

---

## 14. Functional Requirements

1. Single session lifecycle
2. Seamless chat ↔ council switching
3. Explicit user consent for council runs
4. Configurable roles and rounds
5. Strict structured outputs
6. Replayable and auditable executions

Implemented deltas
- Enforced ≥2 agents to escalate; else `insufficient_agents`.
- Safety veto with short‑circuit and explicit explanation.
- Demo mode for offline/dev testing without the Reasoning Worker.

---

## 15. Non-Functional Requirements

- **Latency:**  
  Chat < 2s; Council per Council configuration
- **Scalability:**  
  Parallel role execution
- **Reliability:**  
  Retries and per-role timeouts
- **Cost Control:**  
  Council runs are explicit
- **Safety:**  
  Mandatory safety enforcement by domain

Implementation notes
- UI polls session/run status every ~1.5s during a council run.
- Reasoning client timeouts fall back per‑role to demo data; if all time out, use demo positions.

---

## 16. Risks and Mitigations

**Risks**
- Overuse of council
- Poor summaries degrading decisions
- Collective agreement on wrong assumptions

**Mitigations**
- Explicit escalation
- Clear cost signaling
- Structured summarization
- Skeptic + Safety roles

---

## 17. Versioning

All outputs must include:
```json
"councilProtocolVersion": "1.0"
```

---

## 18. Success Criteria

- Users naturally start in chat
- Council is used intentionally
- Decisions feel higher quality than chat alone
- No confusion between modes

---

## 19. Data Model (Implemented)

Postgres tables and columns
- `council_sessions(id, title, user_id, agents TEXT[], description, mode TEXT DEFAULT 'chat', context JSONB, artifacts JSONB, created_at, updated_at)`
  - Indices: `idx_council_sessions_user(user_id)`
- `council_messages(id, session_id → council_sessions.id, role TEXT, agent_name TEXT, run_id INTEGER, status TEXT, text TEXT, created_at)`
  - Indices: `idx_council_messages_session(session_id, created_at)`
- `council_runs(id, session_id → council_sessions.id, run_id TEXT UNIQUE, status TEXT, phase TEXT, query TEXT, context JSONB, positions JSONB, debate_rounds JSONB, synthesis JSONB, votes JSONB, veto BOOLEAN, veto_reason TEXT, started_at, completed_at, error TEXT)`
  - Indices: `idx_council_runs_session(session_id)`, `idx_council_runs_status(status)`

Mongo (optional; best‑effort)
- Mirrors `council_sessions` and `council_messages` for lightweight logs/diagnostics when configured.

---

## 20. UI Behavior (Hub)

- Location: `/council` tab in the Hub.
- Left panel: sessions list with search, create, rename, edit members, delete.
- Right panel: grouped chat transcript with agent replies, run timings, and council artifacts appended.
- Actions: escalate to council (with optional query), live status during run, and explicit return to chat.

---

## 21. Testing

- Engine unit tests: `spec/savant/engines/council/ops_spec.rb` (sessions, messages, mode, escalation, runs list, veto/return, helpers).
- Manual: exercise UI flows in Hub; verify DB tables populated and mode transitions.

---

## 22. Env and Flags

- `COUNCIL_DEMO_MODE=1` → demo positions/synthesis without the Reasoning Worker.
- `COUNCIL_AUTO_AGENT_STEP=1` → optional auto single‑step agent reasoning on user append (chat mode).

---

**End of PRD**
