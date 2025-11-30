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

