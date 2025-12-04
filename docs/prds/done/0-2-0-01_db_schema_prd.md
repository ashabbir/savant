# PRD — Savant Database Schema (v0.2.0 Foundation)

## 1. Purpose
Savant requires persistent storage for agents, workflows, personas, rules, and run history. This schema enables UI, runtime history, workflow orchestration, and reliable execution.

## 2. Scope
- Database schema
- Migrations
- CRUD layer (Savant::DB)
- JSONB transcripts
- Indexes and constraints

## 3. Requirements
Must store:
- Agents
- Personas
- Rulesets
- Agent Runs
- Workflows
- Workflow Steps
- Workflow Runs

## 4. Schema
### 4.1 agents
id, name, persona_id, driver_prompt, rule_set_ids, created_at, updated_at, favorite, run_count, last_run_at

### 4.2 personas
id, name, content, created_at

### 4.3 rulesets
id, name, content, created_at

### 4.4 agent_runs
id, agent_id, input, output_summary, status, duration, created_at, full_transcript (jsonb)

### 4.5 workflows
id, name, description, graph (jsonb), favorite, run_count, created_at, updated_at

### 4.6 workflow_steps
id, workflow_id, name, step_type, config (jsonb), position

### 4.7 workflow_runs
id, workflow_id, input, output, status, duration, created_at, transcript (jsonb)

## 5. Acceptance Criteria
- Persist agents & workflows
- Persist runs with transcripts
- UI can read list/detail/history
- Compatible with SQLite & Postgres
- Supports streaming and large transcripts

## 6. Non-functional Requirements
- Atomic writes
- Fast reads
- Scalable transcripts
- Versioned migrations

## 7. Risks
- Transcript size
- Index performance
- Schema evolution

## 8. Deliverables
- Migrations
- DB schema
- Savant::DB wrapper
- CRUD tests
- Runtime integration

## 9. Timeline
3–6 days total

## Agent Implementation Plan

- Create tables for agents, personas, rulesets, agent_runs, workflows, workflow_steps, workflow_runs with required columns, indexes, and foreign keys.
- Extend `lib/savant/framework/db.rb` with CRUD helpers for each entity and JSONB transcript storage (Postgres).
- Update `bin/db_migrate` to include the new schema (destructive dev reset) and keep `bin/db_fts` unchanged.
- Add RSpec tests covering create/read/update for agents, personas, rulesets, workflows, and inserting runs with transcripts.
- Validate on local Postgres via `make migrate && make fts` and run `bundle exec rspec`.

Files to change/add:
- `lib/savant/framework/db.rb` — schema additions + CRUD helpers
- `spec/savant/framework/db_app_schema_spec.rb` — CRUD specs for new tables
- `bin/db_migrate` — no interface change; uses updated `migrate_tables`

Notes and constraints:
- Initial implementation targets Postgres only (existing adapter); SQLite compatibility to be added in a follow‑up migration layer.
- Non‑destructive, versioned migrations are implemented. Destructive reset remains available for dev via `SAVANT_DESTRUCTIVE=1 ./bin/db_migrate` or `make migrate-reset`.

## Deviations vs PRD

- SQLite compatibility: deferred. The code remains Postgres‑only via `pg`. Adapter abstraction and SQLite DDL will follow.

## Delivery Summary (Done)

- Schema delivered for: `personas`, `rulesets`, `agents`, `agent_runs(jsonb)`, `workflows(jsonb)`, `workflow_steps(jsonb)`, `workflow_runs(jsonb)` plus existing indexer tables (`repos`, `files`, `blobs`, `file_blob_map`, `chunks` with GIN FTS).
- Versioned migrations: `db/migrations/001_initial.sql` applied via `Savant::Framework::DB#apply_migrations` with `schema_migrations` tracking.
- Dev reset path retained: `SAVANT_DESTRUCTIVE=1 make migrate-reset` drops/recreates tables.
- CRUD helpers added in `lib/savant/framework/db.rb` for personas/rulesets/agents(+runs)/workflows(+steps,+runs).
- Diagnostics: Hub `/diagnostics` and Context tool `fs_repo_diagnostics` return per‑table stats (rows, size, latest); UI renders compact table.
- Dev ergonomics: `bin/mcp_server` and `bin/savant` default to `SAVANT_DEV=1` and set `SAVANT_PATH` for smooth local runs.

## How To Verify

- Bring up stack + migrate: `make quickstart` (or `make dev && make migrate && make fts`).
- Shared DB URL: `postgres://context:contextpw@localhost:5433/contextdb` (Hub, MCP, Indexer).
- UI: Build `make ui-build`, open `http://localhost:9999/ui/diagnostics/overview`; Database shows name + rows + status per table.
- Tool JSON: `curl -s -H 'x-savant-user-id: dev' -H 'Content-Type: application/json' -d '{"params":{}}' http://localhost:9999/context/tools/fs_repo_diagnostics/call | jq '.db.tables'`.
- Tests: inside container `docker compose exec -T indexer-ruby bash -lc 'bundle install && bundle exec rspec spec/savant/framework/db_app_schema_spec.rb'`.

# END OF PRD
