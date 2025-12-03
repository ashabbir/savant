# PRD — Savant UI Overhaul (Compact + Pro Diagnostics)

Owner: Amd
Priority: P0 (Improves usability and velocity)
Status: NEW
Depends On: Multiplexer, Engines, Think, Workflow Engine

---------------------------------------------------------------------

## 1. Purpose

Deliver a cohesive, compact, high‑signal UI that serves two primary use cases:

- User‑friendly Engine UI: discover tools, run workflows, view results with minimal friction.
- Engineer‑friendly Diagnostics UI: observe, trace, and debug engines with live telemetry.

The UI must feel fast, readable at high information density, and consistent across engines.

---------------------------------------------------------------------

## 2. Goals

- Compact visual density with small typography and tight spacing.
- Clear, consistent navigation for “Engines → Subtabs (Tools/Workflows/Runs/Docs)”.
- Powerful Tools explorer: schema, presets, form+JSON input, history, copy cURL/CLI.
- Workflow lifecycle: list, start with schema‑driven params, inspect runs, export/share.
- Diagnostics that engineers trust: live events, logs, requests, routes, multiplexer health.
- Accessibility (a11y): keyboardable, focus states, ARIA labels, high contrast option.

Non‑Goals (MVP): RBAC admin UI, theme editor, visualization of repo diffs (nice to have).

---------------------------------------------------------------------

## 3. Users & Personas

- Builder: Runs tools/workflows, inspects results, iterates quickly. Wants speed and clarity.
- Engineer: Investigates issues, correlates events, checks health, restarts processes.
- Operator (future): Manages access, environment, config, audit—out of scope for MVP.

---------------------------------------------------------------------

## 4. Information Architecture

Top level navigation
- Dashboard: overview cards (engines, multiplexer, quick actions)
- Engines: per‑engine views with consistent subtabs
- Diagnostics: Overview, Requests, Logs, Routes, Agent, Workflows

Per‑engine subtabs (consistent)
- Context: Resources, Search, Memory, Repos, Tools
- Think: Workflows, Prompts, Runs, Tools
- Workflow: Runs, Tools
- Personas: Browse, Tools
- Rules: Browse, Tools
- Jira: Tools
- Git: Tools

---------------------------------------------------------------------

## 5. Interaction Model

- Command palette (Cmd/Ctrl+K) to jump to engines/tools/workflows (v2)
- Filter-as-you-type for lists (tools, workflows, runs)
- Toggle JSON/form inputs with schema‑derived forms
- Quick actions on cards: Run, Start, Index, Logs
- Deep link every primary state (routes include selected item/workflow/run)

---------------------------------------------------------------------

## 6. Visual Design System (Compact)

- Base typography: 12px body; small chips/badges/tabs
- Tight padding: 6–8px vertical for controls, low whitespace
- Dense lists/tables (28–32px rows), small icons
- Compact elevation/shadows; borderRadius ≈ 6
- Consistent monospace for code/logs; JSON prettified lazily for large payloads
- High-contrast mode available via theme toggle

---------------------------------------------------------------------

## 7. Features (Engine UI)

Tools Explorer
- List with search/filter, descriptions
- Input: JSON editor or generated form from JSON schema
- Saved presets per tool, recent history, copy cURL/CLI
- Output viewer with JSON/markdown render

Workflows
- Catalog: filter/tags, preview diagram & YAML
- Start: schema‑driven params, defaults per workflow
- Runs: list with status/duration, cancel/rerun, export JSON/Markdown

Results
- MR Review rich render: summary + sections (findings/risks/tests/checklist)
- Copy/export; Attach to Memory Bank resource

---------------------------------------------------------------------

## 8. Features (Diagnostics UI)

Engines Overview
- Status, PID, uptime, tools, version, restart (if permitted)

Live Events
- SSE, filters (engine/type/level), pause/resume, search

Requests
- Recent tool calls with inputs/outputs, re‑execute tool call

Logs
- Per-engine tail with level filter and grep query

Workflows Telemetry
- Step timeline, durations, error markers, correlation with tool calls

Multiplexer
- Engine online/offline, restarts, route map, heartbeats

---------------------------------------------------------------------

## 9. Performance & Reliability

- Progressive rendering for large JSON
- Log/event tailing throttled with backpressure
- Timeouts and retries surfaced in telemetry; cancel controls for long runs

---------------------------------------------------------------------

## 10. Accessibility

- Keyboard navigation across lists/forms
- Focus outlines; ARIA labelling on interactive lists
- High-contrast theme option (palette tweak)

---------------------------------------------------------------------

## 11. Deliverables

- Compact theme module (small typography, tight paddings)
- Tools pages for all engines (done)
- Workflow Runs improvements (start dialog, presets)
- Diagnostics: requests inspector, logs/live events polish
- Docs: auto‑generated specs view per engine (v2)

---------------------------------------------------------------------

## 12. Acceptance Criteria

- All engines have a Tools subtab with working schemas
- Compact typography adopted globally; list rows ≤ 32px
- Workflow start dialog supports form+JSON and defaults
- Live events show recent workflow/tool events; logs tailing works
- No major layout regressions on md+ screens (≥ 1200px width)

---------------------------------------------------------------------

## 13. Rollout

- Phase 1: Compact theme + Tools consistency (done here)
- Phase 2: Workflow form schemas + presets; live run status
- Phase 3: Requests inspector + re‑execute; logs polish
- Phase 4: Command palette; docs generator; RBAC guardrails

---------------------------------------------------------------------

## 14. Agent Implementation Plan

Overview
- Deliver the compact, consistent Engine UI and Diagnostics per acceptance criteria with minimal disruption. Reuse existing patterns, add a reusable Tool Runner, and tighten layout/typography globally.

Milestones (aligns to Rollout)
- M1 (Done/Verify): Compact theme applied; baseline Tools tabs present for all engines.
- M2: Schema‑driven Tool Runner + presets/history; Workflow start dialog with form+JSON; live run status.
- M3: Diagnostics polish: Requests re‑execute + copy cURL/CLI; logs tail and events UX refinements.
- M4: Command palette MVP; engine specs auto‑doc (v2); optional RBAC guards.

Work Breakdown
1) Theme + Layout (compact + a11y)
   - Finalize compact theme tokens (12px base, 28–32px rows, tight paddings).
   - Add high‑contrast variant via theme toggle; ensure focus outlines and keyboard order across lists/forms.
   - Normalize md+ layouts to a consistent left/right split for tool and diagnostic screens.

2) Tools Explorer (all engines)
   - Introduce reusable `ToolRunner` component providing:
     - Schema preview, generated form for simple schemas, JSON editor fallback.
     - Run tool, show output (JSON/markdown), copy result.
     - Presets (save/load per tool), recent history, and “copy cURL/CLI”.
   - Replace per‑engine Tools pages to consume `ToolRunner` via generic engine/tool APIs.

3) Workflows UX
   - Catalog: filter/tags, preview diagram + YAML (optimize mermaid pre‑render path).
   - Start Dialog: derive form fields from workflow param schema; toggle form/JSON; apply defaults; persist last used params as preset.
   - Runs: list status/duration; cancel/rerun; export JSON/Markdown; show live step status in detail view.

4) Diagnostics
   - Requests: add detail inspector actions — re‑execute tool call (prefill ToolRunner) and copy cURL.
   - Logs: keep SSE streaming with pause/resume; polish filters; copy/clear buttons; event aggregation view.
   - Workflows Telemetry: timeline with durations, error markers; correlation to tool calls.
   - Multiplexer: status/uptime/tools/routes overview; link to engine logs.

5) Accessibility + Performance
   - Keyboardable lists/forms; ARIA labelling for list items and action buttons.
   - Progressive rendering for large JSON; throttle tail streams with backpressure; avoid main‑thread stalls.

Concrete Changes (frontend)
- Theme
  - frontend/src/theme/compact.ts: verify row heights (≤32px), chip/tabs sizing, focus states; add high‑contrast palette toggle hook.
- Core shell
  - frontend/src/App.tsx: ensure deep links for selected engine/subtab; consistent left/right panel layout; remember user theme preference.
- Tools Explorer
  - frontend/src/components/EngineToolsList.tsx: refactor to delegate to `ToolRunner` for selected tool; keep left list with search/filter.
  - frontend/src/components/ToolRunner.tsx (new):
    - Inputs: engine, tool spec, schema.
    - UI: form/JSON toggle; presets; history; run/cancel; copy cURL/CLI; output viewer.
  - frontend/src/pages/*/Tools.tsx: migrate Jira/Git/Rules/Workflow/Think/Personas to use `EngineToolsList` + `ToolRunner` (Context already supports run; normalize to reuse).
- Workflows
  - frontend/src/pages/think/Workflows.tsx: add Start dialog with schema‑derived form; save presets per workflow; live run status in detail modal.
  - frontend/src/pages/workflow/Runs.tsx: ensure cancel/rerun; export; link to detail view with timeline.
- Diagnostics
  - frontend/src/pages/diagnostics/Requests.tsx: add “Re‑execute” action (opens ToolRunner prefilled); add “Copy cURL/CLI”.
  - frontend/src/pages/diagnostics/Logs.tsx: retain SSE; add pause/resume + follow; improve filters; copy all.
  - frontend/src/pages/diagnostics/Workflows.tsx: step timeline and correlation to tool calls.
- Shared
  - frontend/src/components/Viewer.tsx: ensure progressive JSON rendering; preserve code/markdown readability.
  - frontend/src/api.ts: helper to construct cURL/CLI for any engine tool; generic `callEngineTool` already exists.

Concrete Changes (backend/hub; only if gaps appear)
- Add/confirm endpoints consumed by UI:
  - GET `/hub/stats` recent requests; GET `/routes?expand=1` for route map.
  - Streams: `/<engine>/logs?stream=1` and `/logs/stream` for events (SSE).
  - Tool calls: `/<engine>/tools/:name/call` (already supported via MCP hub).
  - Optional: endpoint to fetch tool schema by name for deep link prefill (if not present in list payload).

Acceptance Validation
- Tools
  - All engines show a Tools subtab with working schemas; runners accept form+JSON; presets and history persist; copy cURL/CLI works.
  - Output viewer renders JSON prettified and markdown properly.
- Typography/Spacing
  - Global compact theme active; table/list rows ≤ 32px; controls padding 6–8px; borderRadius ≈ 6.
- Workflows
  - Start dialog (form+JSON) honors defaults; runs display live step status; export works.
- Diagnostics
  - Live events (SSE) with filters, pause/resume; logs tail per engine; requests inspector loads inputs/outputs and re‑executes.
- Layout
  - No major layout regressions on md+ screens (≥ 1200px); left/right panels remain readable and keyboardable.

Test Plan (manual + lightweight checks)
- Smoke: load Dashboard, Engines→Tools for all engines, Diagnostics→Requests/Logs/Workflows.
- ToolRunner: run at least one tool per engine via form and via JSON; verify presets/history; verify cURL matches request shown in Requests.
- Workflows: start think workflow with defaults; observe live status; export final.
- Logs/Events: stream engine logs and aggregated events; change filters; pause/resume; copy logs.
- A11y: tab through list → runner → actions; verify visible focus rings and ARIA labels on list items and buttons.

Risks/Dependencies
- Multiplexer/hub SSE stability under load — ensure backpressure and sensible client retry.
- Tool schemas variability — simple form generation handles primitives/arrays; complex nested schemas default to JSON input.
- Mermaid rendering for large workflows — pre‑render path and fallback to text if dynamic load fails.

Out of Scope (for this pass)
- Full RBAC admin UI; visual diffing; theme editor; docs auto‑gen (planned for v2).

