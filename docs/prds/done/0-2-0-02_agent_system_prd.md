# PRD — Savant Agent System (v0.2.0) — Done

Status: Done

Implemented on branch `feature/0-2-0-02-agent-system`.

## 1. Purpose
The Savant Agent System enables users to create, edit, run, and inspect AI agents using structured components stored in the database. This PRD defines the UI, backend, runtime behavior, storage, and CLI required for v0.2.0.

---

## 2. Scope
### In-Scope
- Agent creation wizard (Persona → Driver → Rules)
- Agent list UI
- Agent detail page (editable)
- Agent run execution + transcript logging
- Chat-style run viewer
- DB integration
- CLI integration

### Out-of-Scope
- Workflow system
- Advanced AMR editor
- Persona/Rules editor engines

---

## 3. Agent Definition Model
Agents consist of five components:

1. **Persona** – who the agent is  
2. **Driver** – what the agent does (mission + endpoint)  
3. **Rules** – constraints + boundaries  
4. **AMR** – Action Matching Rules (defaulted)  
5. **Tools** – capabilities (defaulted)

User defines Persona, Driver, Rules.  
Savant auto-generates default AMR + Tools.

---

## 4. Requirements

### 4.1 Agent Creation Wizard
Flow:
1. Persona (select/create)
2. Driver (text)
3. Rules (select from rules engine)
4. Save → auto attaches default AMR + tools

ACCEPTANCE:
- Create agent in <30 sec
- Only 3 required fields

---

### 4.2 Agent List Page
Columns:
- Name
- Favorite toggle
- Created date
- Last run
- Run count
- Actions (Run/Edit/History)

---

### 4.3 Agent Detail Page
Sections:
- Persona (editable)
- Driver (editable)
- Rules (editable)
- AMR (read-only default)
- Tools (read-only default)
- Run History

---

### 4.4 Agent Run Execution
Execution uses:
- Persona
- Driver
- Rules
- Default AMR
- Default Tools

All reasoning, AMR matches, tool calls recorded into `agent_runs.full_transcript`.

---

### 4.5 Agent Run Viewer
Chat-style display eliminating JSON:
- Model messages → chat bubbles
- Tool calls → formatted cards
- AMR matches → side tags
- Errors → red banners
- Final output → summary card

---

### 4.6 CLI Commands
```
savant agent create
savant agent list
savant agent run <name>
savant agent show <name>
savant agent delete <name>
```

---

## 5. Non-Functional Requirements
- SQLite first, Postgres later
- Fast list loading (<80ms)
- JSONB transcript storage
- Atomic writes

---

## 6. Risks
- Large transcript sizes
- Performance indexing
- Personas/Rules drift

---

## 7. Deliverables
- UI (list/create/detail/run)
- Backend storage
- Agent execution logic
- CLI bindings
- Tests

---

## 8. Timeline
**Week 1:**  
- UI pages  
- DB CRUD connections  

**Week 2:**  
- Agent execution  
- Chat-style run viewer  
- CLI support  

---

## Delivery Summary (Done)

- Backend: Added Agents engine with CRUD + run tools (`lib/savant/engines/agents/*`), plus DB helper `delete_agent_by_name`.
- CLI: Added `savant agent` subcommands (create/list/show/run/delete).
- Frontend: Agents pages (list/run, wizard, detail with transcript), API bindings, and routes.
- Tests: Backend spec for Ops (CRUD + dry-run run) and frontend spec for Agents page rendering and run UI wiring.
- Notes: Hub auto-discovers engine; multiplexer defaults exclude Agents, but runtime retains access to core tools.

## Agent Implementation Plan (by Codex)

- Backend
  - Add `lib/savant/engines/agents/{engine.rb,ops.rb,tools.rb}` exposing CRUD and run tools.
  - Extend DB with `delete_agent_by_name` helper; reuse existing agents/agent_runs schema.
  - Implement run orchestration: boot runtime with persona, override driver from agent row, execute `Savant::Agent::Runtime`, persist transcript to `agent_runs.full_transcript`.
- CLI
  - Add `savant agent` subcommands to `bin/savant` (create/list/show/run/delete).
- Frontend
  - Add Agents pages: list/run (`frontend/src/pages/agents/Agents.tsx`), create wizard (`AgentWizard.tsx`), detail + transcript viewer (`AgentDetail.tsx`).
  - Wire routes and engine ordering in `frontend/src/App.tsx`.
  - Add API bindings in `frontend/src/api.ts`.
- Tests
  - Backend: `spec/savant/engines/agents_engine_spec.rb` covers CRUD + dry-run execution using a stub DB.
  - Frontend: `frontend/src/pages/agents/Agents.test.tsx` renders list and validates run UX wiring with mocked API.
- Docs
  - Move this PRD to `docs/prds/done/` after implementation with delivery summary.

Notes: The Hub auto-discovers new engine via `tools.rb`. Multiplexer default engines exclude Agents; agent runtime still has access to core tools (context/git/jira/workflow) for execution.
