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
- `bin/db_migrate` is destructive by design for dev; production will require versioned, non‑destructive migrations.

## Deviations vs PRD

- SQLite compatibility: deferred. The code remains Postgres‑only via `pg`. We will introduce adapter abstraction and SQLite DDL in a subsequent PRD.
- Versioned migrations: deferred. Current flow continues to use a destructive reset script for developer environments; a simple migrations table and stepwise DDL will follow.
