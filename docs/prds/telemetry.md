PRD — AGENT RUN OBSERVABILITY UI
Product: Savant Engine
Feature: Agent Run UI (Observability & Inspection)
Owner: Amd
Status: APPROVED
Target Release: Engine v0.1.x
Scope: Read-only UI (no execution, no mutation)

---

1. PURPOSE

The Agent Run Observability UI provides a single place where developers can inspect how any Savant agent executed.

The UI must allow a developer to:

* Look at any agent
* Look at any run for that agent
* See every event emitted during execution
* Drill into individual events
* See results produced by the agent
* See exceptions, errors, and failures clearly

This UI establishes trust, debuggability, and explainability for Savant agents.

---

2. CORE USER CAPABILITIES (REQUIRED)

From the UI, a user must be able to:

1. Select any agent
2. View all runs for that agent
3. Open any specific run
4. See all events for the run (live and replay)
5. Drill into any event
6. View results / artifacts if produced
7. View exceptions and errors if they occurred

If any of these are missing, the UI is incomplete.

---

3. NON-GOALS (EXPLICIT)

The UI will NOT:

* Trigger agent runs
* Re-run agents
* Modify agents
* Modify workflows
* Compare runs
* Aggregate metrics
* Enforce RBAC

This UI is observability only.

---

4. ARCHITECTURE CONTEXT

Backend stack (locked):

* Redis: agent execution queue
* Postgres: application data and run summaries
* Mongo: agent logs and events
* SSE: live streaming to UI

UI data rules:

* UI consumes data only via SSE
* UI never queries Postgres directly
* UI never queries Mongo directly

---

5. UI ROUTES

5.1 Agent List
Route: /agents

Displays:

* agent_id
* agent_name
* total run count
* last run status

---

5.2 Agent Runs
Route: /agents/{agent_id}/runs

Displays:

* run_id
* status (running / success / failed)
* started_at
* duration
* error indicator if failed

---

5.3 Agent Run Detail (Primary Screen)
Route: /runs/{run_id}

This is the core UI screen.

---

6. AGENT RUN DETAIL — REQUIRED SECTIONS

6.1 Run Header

Displays:

* agent name
* run_id
* status
* current phase
* step count
* confidence (if available)

---

6.2 Event Timeline

Requirements:

* Shows every event emitted during the run
* Events are ordered strictly by sequence number
* Events stream live during execution
* Completed runs replay deterministically
* Failure point is clearly visible

Event categories:

* state
* step
* tool
* rule
* log
* artifact

---

6.3 Event Detail Panel

When any event is selected, the UI must show:

* event type
* sequence number
* timestamp
* formatted (human-readable) view
* raw JSON payload

Raw payload visibility is mandatory.

---

6.4 Results / Artifacts Panel

Appears if artifact events exist.

Displays:

* artifact type
* artifact count
* reference id
* preview if text-based
* full artifact content on click

Artifacts represent agent output.

---

6.5 Exceptions and Failures

If a run fails, the UI must:

* Highlight the failing event
* Show error message
* Show stack trace if available
* Show tool error payload if applicable
* Clearly mark run status as FAILED

Failures must be impossible to miss.

---

7. EVENT MODEL (UI CONTRACT)

Each event delivered to the UI follows this structure:

run_id: string
agent_id: string
seq: integer (strictly increasing per run)
type: state | step | tool | rule | log | artifact
payload: JSON object
ts: ISO timestamp

Rules:

* seq is the only ordering mechanism
* events are append-only
* no updates or deletes
* UI deduplicates by seq

---

8. LIVE VS REPLAY BEHAVIOR

Live run:

* UI subscribes to SSE
* events append in real time
* auto-scroll enabled

Replay:

* UI replays stored events
* same rendering logic
* same ordering
* no feature differences

Live and replay must feel identical.

---

9. ERROR AND EDGE CASE HANDLING

* SSE disconnect: show reconnecting state
* No events yet: show waiting indicator
* Partial event stream: mark run as degraded
* Duplicate events: ignore duplicates
* Backend unavailable: UI degrades gracefully

UI must never crash.

---

10. SECURITY AND SAFETY

* Events must not contain secrets
* Sensitive data must be redacted before emission
* Raw payload view is still required
* Environment behavior:

  * DEV: verbose
  * PROD: strict redaction

---

11. ACCEPTANCE CRITERIA

* Can open any agent
* Can open any run
* All events are visible
* Events are strictly ordered
* Any event can be drilled into
* Raw payload is visible
* Results are clearly visible
* Failures are clearly visible
* Live and replay behavior match
* UI does not query databases directly

---

12. CANONICAL DEFINITION

The Agent Run Observability UI is a read-only, event-driven interface that shows exactly how an agent executed, step by step, tool by tool, rule by rule, with full transparency into results and failures.

---

13. RECOMMENDED FILE LOCATION

/PRD/agent_run_ui.txt

---

