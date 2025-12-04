# PRD — Savant Agent System (v0.2.0)

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

