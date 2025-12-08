# Savant Architecture Implementation Strategy (Current ➜ Target)

## Executive Summary
- Goal: Evolve the current Savant stack into the PRD architecture described in `00-architecture-full.md`, keeping momentum and minimizing churn.
- Approach: Incremental, testable phases that leverage what already exists (Multiplexer, Context/Index/Git/Jira/Rules/Personas/Workflow engines, Hub UI, Postgres) and add missing pieces (Sandbox Manager, Exec/FS MCP, optional Python reasoning bridge, optional Mongo logging sink).
- North Star: Safe, observable, deterministic tooling with a clean separation between “reasoning” and “doing,” unified via MCP and surfaced in the Hub.

## Current State Snapshot (What We Have)
- Multiplexer
  - `lib/savant/multiplexer.rb`, `multiplexer/engine_process.rb`, `multiplexer/router.rb` with stdio JSON‑RPC to engines.
  - Autostarts engines via `bin/mcp_server` with `MCP_SERVICE` and supports websocket or stdio transport.
- MCP Engines
  - Context: FTS search + repo index lifecycle (`lib/savant/engines/context/*`), Tools in `context/tools.rb`.
  - Git: file read/diff/hunks/status (`lib/savant/engines/git/*`), tools in `git/tools.rb`.
  - Jira: REST v3 wrapper (`lib/savant/engines/jira/*`).
  - Think: deterministic orchestration for workflows + prompts (`lib/savant/engines/think/*`).
  - Workflow: YAML executor and run persistence (`lib/savant/engines/workflow/*`).
  - Personas/Rules/Drivers: content catalogs + tools.
- Transports
  - MCP stdio/websocket (`lib/savant/framework/mcp/server.rb`), HTTP Hub server (`lib/savant/hub/server/http_runner.rb`).
- UI (Hub)
  - React app (`frontend/`) with pages for engines, tools, multiplexer status, logs/SSE, workflows.
  - HTTP routes in `lib/savant/hub/router.rb` provide tooling discovery, logs, diagnostics.
- Indexer + Context
  - Postgres FTS over `chunks.chunk_text`, repo/file/blob/chunk schema.
  - Scanner, chunkers, and maintenance under `lib/savant/engines/context/fs/repo_indexer.rb` and Context engine.
- Persistence
  - Postgres wrapper + migrations (`lib/savant/framework/db.rb`, `db/migrations/001_initial.sql`).
  - Agents/personas/rules/workflows in Postgres; workflow runs saved to `.savant/workflow_runs/*.json` and runs tables.
- Logging & Telemetry
  - JSON logger (`lib/savant/logging/logger.rb`) and unified EventRecorder with SSE (`lib/savant/logging/event_recorder.rb`).
  - Governance policy gate for sandbox/audit (`lib/savant/logging/audit/policy.rb`).

## Target Architecture (From PRD)
- Savant Engine (Ruby fibers) orchestrating:
  - MCP Multiplexer; Sandbox Manager; Repo Indexer fiber; API/Hub; Postgres (definitions); Mongo (logs); Python backends (LangChain/LangGraph) for intent.
- MCP Servers (inside sandbox): FS, Git, Exec; Context search.
- Python Backends: pure reasoning that output “intent” (tool calls, transitions) without direct system access.
- Observability: rich, structured logs and traces in Mongo, streamed in Hub.

## Gap Analysis (Delta: Current ➜ Target)
- Sandbox Manager
  - Current: policy gate toggles “sandbox?” but no actual workspace jail.
  - Target: process‑level isolation for engines/tools; per‑run workspace dirs; enforced cwd; optional Docker/namespace layer.
- Exec MCP
  - Current: missing.
  - Target: safe command runner with allowlist, timeouts, resource caps, output shaping.
- FS MCP
  - Current: partial (Git read_file). No generic FS read/write/search under sandbox root.
  - Target: read_file/write_file/search with path guards to sandbox workspace.
- Python Reasoning Backends
  - Current: Think/Workflow engines in Ruby; no LangChain/LangGraph bridge.
  - Target: optional subprocess service that produces intent JSON; integrated through MCP or internal adapter.
- Logging to Mongo
  - Current: file + in‑memory EventRecorder, Postgres JSONB for runs.
  - Target: optional Mongo sink for operational traces; keep existing sinks for local/dev.
- Data Model
  - Current: repos/files/blobs/chunks; personas/rulesets/agents/workflows/*; no explicit drivers table (drivers YAML exists).
  - Target: drivers in Postgres; keep context schema; add optional log indices in Mongo.
- Config
  - Current: `config/settings.json` covers indexer/mcp/database/transport.
  - Target: add sandbox, engines (fs/exec) defaults, python backend endpoint, mongo connection.

## Principles and Decisions
- Backwards‑compatible by default: new capabilities are opt‑in via config.
- Local‑first and zero‑friction: default to file logs + Postgres; Mongo and Python are pluggable.
- Security before power: sandbox constraints and allowlists gate Exec/FS early.
- One transport contract: keep JSON‑RPC 2.0 via stdio/websocket everywhere.
- Determinism: limit payload sizes and normalize outputs; preserve the existing deterministic Think/Workflow path.

## Phased Plan

### Phase 0 — Baseline Hardening (1–2 weeks)
- Config + Docs
  - Add schema keys for `sandbox`, `mongo`, `python`, `mcp.multiplexer.engines` with defaults.
  - Extend `bin/config_validate` to cover new keys.
- Multiplexer/Server
  - Ensure websocket transport parity for multiplexer; surface `server_info` for each engine consistently.
- Tests
  - Add happy‑path integration tests for multiplexer tools list/call over stdio.

Deliverables:
- Updated config/schema, validation, and docs.
- Passing tests for multiplexer discovery/call.

### Phase 1 — Sandbox Manager MVP (1–2 weeks)
- Implement `lib/savant/framework/sandbox`:
  - Workspace root creation per run/session: `.savant/sandboxes/<id>`.
  - Path guard utilities and cwd enforcement wrappers.
  - Pluggable runners: local dir jail (default), Docker (optional later).
- Integrate
  - Multiplexer sets `PWD` and `SAVANT_SANDBOX_DIR` for engines; engine processes spawn with sandbox cwd.
  - Audit policy enforce() remains; add explicit “requires_system” flag on tools; reject out‑of‑root paths.
- UI
  - Hub diagnostics page: show active sandboxes, size, age, and allow purge.

Deliverables:
- Sandbox library + integration with multiplexer/engines.
- Basic UI to view/purge sandboxes.

### Phase 2 — FS MCP (1 week)
- New engine `lib/savant/engines/fs` with tools:
  - `fs.read_file(path)` — path must be under sandbox root; size limit; binary guard.
  - `fs.write_file(path, content)` — safe write with backup and line‑ending normalization.
  - `fs.search(q, path?)` — grep‑like search in sandbox root with caps.
- Validation
  - JSON schema with constraints; require sandbox.
- UI
  - Add FS tool runner panel in Hub for quick smoke testing.

Deliverables:
- FS engine + specs + Hub exposure.

### Phase 3 — Exec MCP (1–2 weeks)
- New engine `lib/savant/engines/exec` with tools:
  - `exec.run(cmd, args?, cwd?)` — allowlist commands, timeouts, CPU/mem caps, redact env.
  - `exec.test(framework)` — adapters for `rspec`, `npm test`, `pytest` (when available), parse to structured JSON.
  - `exec.lint(kind)` — adapters for `rubocop`, `eslint`, etc.
- Enforcement
  - Always runs inside sandbox cwd; capture stdout/stderr with size/time caps.
- UI
  - Live streaming logs via SSE; summarized result renderer.

Deliverables:
- Exec engine + adapters + SSE streaming; policy‑enforced execution.

### Phase 4 — Logging: Mongo Sink (1 week, optional)
- Add `Savant::Logging::Exporter` sink to Mongo (new `mongodb` adapter).
  - Mirror events from EventRecorder to Mongo collections described in PRD (tool_calls, exec_ops, workflow_runs, etc.).
  - Feature‑flagged by config; continues writing to file/SSE regardless.
- Simple health check and retention policy doc.

Deliverables:
- Optional Mongo logging with config; unchanged local developer defaults.

### Phase 5 — Python Reasoning Bridge (2–3 weeks, optional)
- Thin subprocess service `think_py` (or `ai_py`) exposing:
  - `agent_intent(prompt, context)` → intent JSON.
  - `workflow_intent(state)` → next transition JSON.
- Transport
  - Prefer stdio JSON‑RPC mirroring our engines. Spawned by Multiplexer as another engine.
- Integration
  - Add adapter in Think/Workflow engines to optionally fetch intent from Python service.
  - Strict payload caps + timeouts; no FS/network/system access in Python process.
- Packaging
  - `scripts/python/setup.sh` to create a venv and install pinned deps.

Deliverables:
- Optional Python engine wired via multiplexer; Think/Workflow adapters.

### Phase 6 — Data Model Enhancements (0.5–1 week)
- Add `drivers` table to Postgres (name, content, created_at, updated_at).
- CRUD helpers in `lib/savant/framework/db.rb`; Tools in `engines/drivers/*` already align with catalog approach.
- Migration in `db/migrations/00x_drivers.sql` and schema loader support.

Deliverables:
- Drivers stored in Postgres when desired; catalog path maintained.

### Phase 7 — UX Refinements (ongoing)
- Multiplexer page: engine status, tool counts, logs tail, restart controls.
- Sandbox panel: per‑engine cwd, disk usage, purge button.
- Exec/FS consoles: run output streaming, copy/download artifacts.
- Workflow diagram: Think graph rendering and validation feedback loop.

Deliverables:
- Improved Hub ergonomics for daily workflows and diagnostics.

## Cross‑Cutting Concerns
- Security
  - Enforce sandbox path guards in FS/Git/Exec; block symlink escapes; size/time caps everywhere.
  - Allowlist commands for Exec; optional policy overrides for trusted users.
- Performance
  - Keep repo indexer fiber decoupled; throttle FS/Exec I/O; tune FTS queries and limits.
- Observability
  - Standardize event envelope fields (ts, type, mcp, tool, duration_ms, slow, status, run_id, sandbox_id, size_bytes).
  - Emit timing via `with_timing` and surface slow operation badges in Hub.

## Config and Defaults
- `config/settings.json` additions (backed by `config/schema.json`):
  - `sandbox`: `{ enabled: false, root: ".savant/sandboxes", driver: "local" }`
  - `mongo`: `{ url: null, database: "savant", enabled: false }`
  - `python`: `{ enabled: false, command: ["python3", "-m", "savant_bridge"], env: {} }`
  - `mcp.multiplexer.engines`: include `fs`, `exec`, `think_py` when enabled.

## Data and Migrations
- Postgres
  - Add `drivers` table and optional indices as migration `00x_drivers.sql`.
  - Continue FTS index on `chunks` as is.
- Mongo (optional)
  - Collections per PRD; TTL/indexes for large logs.

## Testing Strategy
- Unit
  - FS/Git path guards, Exec allowlist, DB CRUD for drivers, config validator.
- Integration
  - Multiplexer stdio/websocket tools list/call; sandbox cwd and path enforcement.
  - Exec runners for `rspec`/`rubocop` with timeouts and output capping.
- E2E
  - Hub flows: index repo → search → propose patch → run tests → commit.
  - SSE streams: logs and tool call events across engines.
- Security/Abuse
  - Symlink traversal attempts; long path names; huge outputs; fork bombs blocked by caps.

## Risks and Mitigations
- Sandbox OS differences: prefer portable local jail first; gate Docker behind a flag.
- Python env drift: pin versions; provide bootstrap script; make optional.
- Log volume: size caps and TTL indexes; file rotation remains default.
- Complexity: keep each phase shippable with clear toggles and docs.

## Success Metrics
- P95 tool call latency captured + surfaced in Hub.
- Zero sandbox escapes in tests; no writes outside sandbox root.
- Exec tool reliability: >99% success in controlled scenarios.
- Optional components (Mongo/Python) can be toggled without core regressions.

## Immediate Next Steps (this repo)
- Add schema keys and docs; wire `Savant::Framework::Sandbox` skeleton + integration points.
- Scaffold `engines/fs` and `engines/exec` with minimal tools and tests.
- Hub pages: Sandbox diagnostics + FS/Exec consoles.
- Draft Python engine contract (JSON‑RPC methods + payload caps) as a separate PRD and keep behind a flag.

---

Appendix: Key References
- Multiplexer: `lib/savant/multiplexer*.rb`, `bin/mcp_server`
- Indexer & Context: `lib/savant/engines/context/*`, `db/migrations/001_initial.sql`
- Git: `lib/savant/engines/git/*`
- Workflow/Think: `lib/savant/engines/workflow/*`, `lib/savant/engines/think/*`
- Hub: `lib/savant/hub/*`, `frontend/`
- Logging: `lib/savant/logging/*`
