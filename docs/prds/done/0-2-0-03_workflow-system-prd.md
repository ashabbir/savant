# PRD — Savant Workflow System (v0.2.0)

## 1. Purpose
The Workflow System enables users to create, run, and inspect multi-step processes composed of agents and tools. Workflows are explicit graphs where each step passes data to the next. All executions run through THINK → PLAN → NEXT.

This is the backbone of Savant’s automation pipeline.

---

## 2. Scope
### In-Scope
- Workflow creation wizard
- Workflow graph editor UI
- Step configuration (agent/tool)
- Workflow list + detail pages
- Workflow run execution + transcript logging
- Chat-style workflow run viewer
- DB persistence
- CLI integration

### Out-of-Scope
- Conditional branches (v0.3.0)
- Parallel steps
- Advanced data mapping UI
- Workflow templates marketplace

---

## 3. Workflow Definition Model
A workflow consists of:

1. **Name**
2. **Description**
3. **Graph** (ordered nodes/edges)
4. **Steps** (agent or tool)
5. **Data Flow** (output → next input)
6. **Execution Mode:** THINK → PLAN → NEXT

Each step can be:
- `agent:<agent_name>`
- `tool:<tool_name>`

Outputs of each step are automatically passed as context to the next.

---

## 4. Requirements

### 4.1 Workflow Creation Wizard
Flow:
1. Name + Description
2. Add Steps (in order or graph mode)
3. Configure each step:
   - Type: agent or tool
   - Config: input mapping / parameters
4. Save workflow

ACCEPTANCE:
- Users can create a workflow in <2 minutes
- Steps are easy to reorder
- Graph auto-draws

---

### 4.2 Graph Editor UI
- Nodes = steps
- Edges = data flow
- Drag to reorder
- Click node to edit config
- Auto-layout

Graph saved as JSON.

---

### 4.3 Workflow List Page
Columns:
- Name
- Description preview
- Favorite toggle
- Created date
- Last run
- Run count
- Actions (Run/Edit/History)

---

### 4.4 Workflow Detail Page
Sections:
- Overview (name, description, favorites)
- Graph visualization
- Step list (readable order)
- Run history table

---

### 4.5 Workflow Run Execution
Execution must follow:

### THINK
Agent interprets the workflow + inputs.

### PLAN
Agent produces the execution plan:
- which steps
- in what order
- predicted outputs

### NEXT
Savant executes each step sequentially:
- agent step → full agent run
- tool step → tool call

Every step emits an event stored in transcript:
- model message
- tool call
- step completed
- AMR match (if agent)
- final output

---

### 4.6 Workflow Run Viewer
Chat-style transcript identical to Agent viewer:
- Bubbles for reasoning
- Cards for tool calls
- Step markers between nodes
- Final output card
- Errors shown clearly

NO JSON displayed by default.

---

### 4.7 CLI Commands
```
savant workflow create
savant workflow list
savant workflow run <name>
savant workflow show <name>
savant workflow delete <name>
```

---

## 5. Non-Functional Requirements
- SQLite & Postgres compatible
- Graph size up to 50 steps
- Transcript scalable to 10k events
- Runs must be atomic and recoverable

---

## 6. Risks
- Complex workflows may produce large transcripts
- Graph editor UX complexity
- Data handoff errors

---

## 7. Deliverables
- Workflow creation wizard UI
- Graph editor
- Workflow detail page
- Workflow run viewer
- Runtime execution logic (THINK/PLAN/NEXT)
- DB integration
- CLI bindings

---

## 8. Timeline
**Week 1:**  
- Workflow DB integration  
- Workflow creation UI  
- Graph editor MVP  

**Week 2:**  
- Runtime (THINK/PLAN/NEXT) integration  
- Run viewer  
- CLI commands  
- Final polish  

