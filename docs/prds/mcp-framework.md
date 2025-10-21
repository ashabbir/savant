# PRD: Savant MCP Framework

## Executive Summary
- Objective: Evolve Savant into a small, reusable framework for building and deploying MCP servers with clear boundaries, simple deployment, and strong defaults.
- Outcome: A core MCP library (transport, registrar, tool DSL, middleware, config, DI, observability) with plug-in services (Context, Jira), standardized tool naming, and easy Docker/Make flows.

## Problem / Opportunity
- Current code provides working MCP servers (Context, Jira) but mixes app logic with server responsibilities.
- Adding new MCP services requires copy/paste of patterns and lacks a tool DSL, middleware pipeline, standardized error taxonomy, or configurable transports.
- We want a “drop-in” pattern to spin up an MCP with:
  - Namespaced tools + JSON schema validation
  - Standardized request lifecycle (logging, timing, error handling)
  - Shared dependency injection (DB, logger, config)
  - Simple packaging and deployment to editors

## Goals
- Core framework abstractions:
  - Transport adapters (stdio first; optional WebSocket later)
  - Registrar to advertise tools and dispatch calls
  - Tool DSL for concise tool definitions with schema validation
  - Middleware chain (logging, validation, rate-limit, auth hooks)
  - DI context (db, logger, config, request_id)
  - Config loader/validator with env overrides
  - Observability: structured logs and timing; optional metrics hooks
- First-class services built on the core:
  - Context service with FTS and repo indexer (already present)
  - Jira service (already present)
- Namespaced tools: `fts/search`, `memory/*`, `fs/repo/*`, `jira_*`
- One-command local deploy via Make and Docker (Postgres + services)

## Non-Goals
- Multi-tenant, network-exposed control plane
- Complex role-based auth (simple hooks/ACLs only)
- Distributed processing of index jobs (single-node scope)

## Users / Use Cases
- Agent developers: add a custom MCP with a few tools quickly
- Team members: run Context/Jira MCP locally with minimal setup
- Automations: scriptable indexing and FTS search over local repos

## Architecture Overview

### Core (new)
- `Server`:
  - JSON-RPC 2.0 framing
  - Transport adapters: `Transports::Stdio` (now), pluggable interface for future `WebSocket`
  - Service loading via manifest or convention (e.g., `Savant::<Service>::Tools.specs`)
- `Registrar`:
  - Aggregates tool specs and dispatches invocations
  - Enforces namespaced tool names
- `Tool DSL`:
  - `tool 'ns/name' do; schema {…}; handler { |ctx, args| … }; end`
  - Built-in JSON schema validation errors with consistent formatting
- `Middleware`:
  - `around` hooks for request id, logging, timing, validation
  - Optional rate limiter, ACL checks
- `Config`:
  - Layered: defaults → file → env
  - Strict schema and coercion; descriptive errors
- `Context` (DI):
  - Shared objects: `db`, `logger`, `config`, `request_id`, `started_at`
- `Observability`:
  - Structured logs for every `tools/call` (service, tool, dur_ms, size)
  - Hooks for metrics/tracing (no-op by default)

### Services (existing, adapted)
- Context:
  - Engine owns shared `db` and injects into Ops/FTS/FS::RepoIndexer
  - FTS search (`fts/search`) over `chunks` filtered by `files.repo_name`
  - Memory bank:
    - `memory/search` (DB-backed FTS over `rel_path LIKE '%/memory_bank/%'`)
    - `memory/resources/list` (DB-backed rows from `files`), `memory/resources/read` (resolve repo root via DB, read disk)
  - Repo indexer: `fs/repo/*` using existing scanning/chunking (Context::FS::RepoIndexer)
- Jira:
  - Existing tools remain; migrate to Tool DSL and middleware

### Database & Migrations
- DB managed by service Engine, injected to tools
- Migration strategy: destructive reset (drop/create) for dev and local deployments
  - `bin/db_migrate`: drop/create tables and indexes, then ensure FTS
  - `make migrate` warns that it is destructive

## Protocol and Tooling
- JSON-RPC 2.0 Methods:
  - `initialize`, `tools/list`, `tools/call`
- Tool Naming / Schema:
  - Namespaced (e.g., `fts/search`, `memory/resources/read`)
  - JSON schema for inputs (type coercion, defaults)
  - Standard result envelope: array/object payload per tool
- Error Taxonomy:
  - Validation error: -32602
  - Unknown tool: -32601
  - Internal: -32000
  - Service-specific codes: -32050..-32099
- Optional Streaming (later): chunked results for large payloads

## Configuration
- `config/settings.json` with `indexer`, `database`, `mcp` sections
- Env overrides: `DATABASE_URL`, `MCP_SERVICE`, `LOG_LEVEL`, etc.
- Validation via schema; clear error messages through core Config module

## Operations
- Make targets:
  - `make migrate` (destructive reset), `make fts`, `make smoke`
  - `make repo-index-all`, `repo-index-repo`, `repo-delete-all`, `repo-delete-repo`, `repo-status`
  - `make mcp-test q=... repo=...`
- Docker:
  - Postgres + optional Ruby services; host MCP via stdio
- Logging:
  - logs/<service>.log with request_id, tool, durations

## Security
- Secrets from env (e.g., Jira), optional config files (mounted via Docker)
- Log scrubbing for secrets
- Filesystem access limited to configured repo roots
- Optional repo ACLs per tool

## Acceptance Criteria (MVP)
- Core server provides a stable API to register namespaced tools with schema validation and middleware
- Context and Jira run unchanged on top of the core (after adapting registration)
- Shared DB owned by Context Engine, injected across Context components
- Destructive `make migrate` works end-to-end; `repo-*` targets function
- Structured logging for each `tools/call` (service, name, dur_ms)

## Milestones
1) Core Foundations
   - Extract minimal core (registrar, middleware hooks, Tool DSL)
   - Adapt Context/Jira registrars to DSL; maintain current behavior
2) Observability & Config
   - Structured logs, request ids; config loader with schema
3) Transport Abstraction (optional)
   - Encapsulate stdio; define interface for other transports

## Risks & Mitigations
- Backwards compatibility: Keep tool names stable (already namespaced); publish migration notes (done in CHANGELOG)
- Over-engineering: Keep core minimal; defer WebSocket/streaming until demanded
- Security drift: Add tests for path constraints and secret masking

## Open Questions
- Do we want a code generator for new services (`bin/mcp_new_service <name>`)?
- Should we publish gems or keep as a mono-repo?
- Add a watch mode (fs events) for indexer as an optional feature?

