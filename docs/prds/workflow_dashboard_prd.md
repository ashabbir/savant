# Savant Dashboard – Workflow Builder Module PRD

## 1. Overview
The Savant Dashboard Workflow Builder adds full UI‑based workflow management on top of the existing Workflow MCP engine.  
This module enables users to **create, update, delete, and visualize workflows directly from the dashboard** using a flow‑chart style builder.

No LLM.  
No agent behavior.  
Pure UI + backend YAML manipulation.

---

## 2. Goals
- Provide a visual workflow editor for Savant workflows.
- Allow CRUD operations on workflow YAML files.
- Maintain full compatibility with existing Workflow MCP execution.
- Provide a React‑based visual builder (React Flow).
- Enforce schema validation before saving YAML.
- Enable secure file‑based persistence.

---

## 3. Non‑Goals
- No agent editing, AMR editing, or driver prompt editing.
- No LLM inference or auto‑generation of workflows.
- No runtime workflow execution preview.

---

## 4. Workflow Format (Existing YAML)
Workflows follow a simple YAML structure:

```yaml
id: "fetch_user"
title: "Fetch User and Orders"
description: "Fetches user details and orders"

steps:
  - id: "get_user"
    type: "tool"
    engine: "users"
    method: "find"
    args:
      id: "{{ input.userId }}"

  - id: "get_orders"
    type: "tool"
    engine: "orders"
    method: "listForUser"
    args:
      userId: "{{ get_user.data.id }}"

  - id: "merge"
    type: "llm"
    prompt: "Combine user and orders."
```

The PRD maintains this exact format.

---

## 5. System Architecture

### 5.1 High‑Level Diagram
```
Dashboard UI (React)
      |
      v
Workflow API (Rails or Ruby service)
      |
      v
/workflows/*.yaml
```

### 5.2 Components
- **UI Layer**
  - Workflow List Page
  - Visual Editor Page
- **Backend API**
  - CRUD endpoints
  - YAML ↔ Graph conversion layer
- **Storage Layer**
  - YAML files in `/workflows/*.yaml`
- **Loader**
  - Existing Workflow MCP loader reloads workflows on server restart or hot‑reload trigger.

---

## 6. UI Specification

### 6.1 Workflow List Page
- Table of workflows
  - ID
  - Title
  - Last Modified
- Buttons:
  - **Create New Workflow**
  - **Edit**
  - **Delete**

### 6.2 Workflow Editor (React Flow)
- Node palette (left)
  - Tool Step
  - LLM Step
  - Return Step
  - (Future) Conditional Step
- Canvas (center)
  - Drag, drop, connect nodes
  - Auto‑align
- Node Properties Panel (right)
  - Fields change based on node type
- Top Bar
  - Save
  - Preview YAML
  - Validate

---

## 7. Backend API

### 7.1 GET /workflows
Returns all workflow metadata.

### 7.2 GET /workflows/:id
Returns parsed YAML + graph JSON for UI.

### 7.3 POST /workflows
Creates a new workflow file.

Payload:
```json
{
  "id": "new_workflow",
  "graph": {...}
}
```

### 7.4 PUT /workflows/:id
Updates workflow YAML.

### 7.5 DELETE /workflows/:id
Deletes workflow YAML file.

---

## 8. YAML ↔ Graph Specification

### 8.1 Graph JSON Structure
```json
{
  "nodes": [
    { "id": "get_user", "type": "tool", "data": {...} },
    { "id": "get_orders", "type": "tool", "data": {...} }
  ],
  "edges": [
    { "source": "get_user", "target": "get_orders" }
  ]
}
```

### 8.2 YAML Generation Rules
- Ordered edges define step sequence.
- Each node maps to a YAML step.
- Data fields are written exactly as provided.
- Missing required fields cause validation failure.

---

## 9. Validation Rules
- `id` must be unique across steps.
- No disconnected nodes.
- All fields required by node type must be present:
  - **tool**: engine, method
  - **llm**: prompt
  - **return**: value
- Circular flows not allowed (until future version).

---

## 10. File Storage
Workflows stored under:

```
/workflows/<id>.yaml
```

Example:
```
/workflows/fetch_user.yaml
```

---

## 11. Versioning
Each save writes:

```
<id>.yaml
<id>.yaml.bak(timestamp)
```

---

## 12. Permissions
- Only authenticated dashboard users can edit workflows.
- Editing requires admin or workflow‑owner permissions.

---

## 13. Hot Reloading
Two modes:

### A. Manual
Button in dashboard:
```
Reload Workflows
```

### B. Automatic
Every PUT/POST triggers a reload signal to the Workflow MCP engine.

---

## 14. Future Extensions (Not in Phase 1)
- Conditional flows
- Loops
- Sub‑workflows
- Workflow execution preview
- Workflow simulation
- Git‑backed version control

---

## 15. Milestones

### Phase 1 — CRUD + Visual Builder
- List workflows
- View workflow
- Edit workflow visually
- Create new workflow
- Delete workflow
- YAML ↔ Graph conversion layer

### Phase 2 — Advanced Features
- Validation engine
- Hot reload
- Backup/versioning

### Phase 3 — Future
- Conditional logic
- Subworkflows
- Testing workflows

---

## 16. Acceptance Criteria
- Workflows can be created/edited/deleted fully from UI.
- YAML generated matches existing MCP workflow format.
- MCP workflow engine loads and executes UI‑created workflows without modification.
- Graph matches YAML and YAML matches graph.

---

## 17. Conclusion
This PRD enables a production‑grade workflow editor inside Savant Dashboard, giving full power to manage all workflows visually while keeping the underlying workflow engine untouched.

This is a clean, robust, maintainable extension that fits perfectly into Savant's architecture.

---

## Agent Implementation Plan

1. Backend engine (Ruby)
   - Add `lib/savant/workflows/engine.rb` for CRUD and YAML↔Graph conversion per PRD.
   - Add `lib/savant/workflows/tools.rb` registrar exposing:
     - `workflows.list`, `workflows.read` (YAML + derived graph), `workflows.create`, `workflows.update`, `workflows.delete`, `workflows.validate`.
   - Persist to `$SAVANT_PATH/workflows/<id>.yaml` with timestamped backups on save.
   - Enforce validation rules (unique ids, required fields, connectivity, no cycles).
   - Wire mount in `config/mounts.yml` at `/workflows`.

2. Frontend (React)
   - Install `reactflow` and build Workflow List and Editor pages:
     - List: table with ID, Title, Updated, actions (Create, Edit, Delete).
     - Editor: React Flow canvas, node palette (Tool, LLM, Return), properties panel, and top bar (Save, Preview YAML, Validate).
   - Add API bindings in `frontend/src/api.ts` to call `/workflows/tools/*/call` methods.
   - Route entries in `App.tsx` and nav link under Think/Engines.

3. YAML↔Graph
   - Graph schema: `{ nodes: [{ id, type, data }], edges: [{ source, target }] }`.
   - YAML generation preserves PRD format and step ordering by edges; fails on invalid graphs.
   - YAML parse builds nodes and edges in display order.

4. Tests
   - RSpec: engine validation and graph round‑trip (graph→yaml→graph) and CRUD to temp dir.

5. Quality & Run
   - Run RuboCop auto‑correct; fix remaining offenses.
   - Run RSpec.
   - Build frontend to `public/ui` and verify basic workflows page loads.
