Overview

- Scope: Reviewed Ruby codebase for configuration, DB layer, indexer, MCP server, Jira/Context engines, CLIs, and docs. Focused on correctness, safety, performance, maintainability, testing, and ops.
- Method: Static review of repository structure and representative files. Did not execute runtime flows.

Strengths

- Clear architecture: Indexer/Context/Jira concerns are separated; MCP stdio boundary is explicit.
- Pragmatic DB schema: Proper keys and indices; GIN FTS over `chunks.chunk_text` with a helper to ensure index.
- Helpful CLIs and Make targets: Enable local workflows for migration, indexing, and MCP.
- Lightweight logger: Supports timing and file-backed logging per service; stdout sync for stdio mode.
- Config validation: Central `Savant::Config.load` with explicit errors; example and JSON schema present.
- Tests present: Specs cover registrar validation, indexer runner/scanner, and Jira engine basics.

Notable Risks and Issues

- MCP server robustness:
  - Progress: Server now calls `handle_jsonrpc(req, log)`; undefined locals removed and a generic convention-based service loader added. Great step toward a pleasant DX.
  - Still recommended: add light request validation (check `jsonrpc`, `id` type, and `params` shape) and centralize error codes per failure class.
  - Consider extracting a tiny `ServiceRegistry` for engines/registrars and documenting the convention to make adding services trivial.

- Configuration loading in MCP server:
  - Progress: Base path resolution is clearer and logs include selected paths.
  - Still recommended: replace raw JSON parse with `Savant::Config.load(settings_path)` to avoid silent misconfig and surface `ConfigError` in logs and init response.

- Database layer:
  - No connection retry/backoff and no statement timeout safeguards. Add `connect_timeout`, `statement_timeout`, and safe reconnect on failure.
  - `delete_missing_files` builds a large `NOT IN` list; for large repos this can exceed parameter limits. Consider temporary table + join, or `UNNEST($2::text[])` with array parameter and `= ANY(...)`.
  - `replace_chunks` performs row-by-row inserts without batching. Use `COPY` or multi-values insert in a transaction for throughput.
  - `delete_all_data` uses deletes without `TRUNCATE ... CASCADE`, which is slower for large tables; ensure constraints permit truncate where appropriate.

- Indexer and chunking:
  - Ensure binary/large-file detection is robust across encodings; tests for edge cases (UTF-16, mixed newlines, CRLF) recommended.
  - Chunking configuration (overlap, max sizes) should guard against pathological inputs (very long lines) to avoid memory spikes.
  - Language detection by extension only; consider a light content heuristic for common mislabels.

- Security and secrets:
  - Jira client code should confirm headers redact logs and avoid printing credentials. Ensure logger never dumps ENV.
  - Validate all user-provided repo paths against a safe allowlist to avoid accidental indexing of sensitive directories.

- Error handling and observability:
  - Add structured context (request_id, repo, file) to logs consistently, not only in MCP. Provide counters for indexer outcomes (scanned, skipped, deduped, errored).
  - Return MCP errors with stable codes per failure class (validation, tool-not-found, engine-error), and include minimal, actionable messages.

- Testing:
  - Positive coverage present but limited around DB helpers and MCP server. Add integration tests for JSON-RPC roundtrips and schema ops (migrate/fts).
  - Add property-style tests for chunkers (idempotence, coverage, overlap boundaries).

Style and Maintainability

- Prefer constants for protocol versions, default ports, and log file names; reference consistently.
- Extract repeated path logic into a `Savant::Paths` helper (repo root, config path, logs dir).
- Use `rubocop` rules to enforce consistent error class naming and message patterns.
- Ensure all binaries under `bin/` have `#!/usr/bin/env ruby` and `set -euo pipefail` for shell stubs where applicable.

Concrete Recommendations

- MCP server fixes:
  - Keep the convention-based loader; add envelope validation and a mapping of error classes→codes.
  - Use `Savant::Config.load` for settings where needed; log `ConfigError` and return a clear `initialize` instructions message.
  - Add `server_info` hook to engines (you started this) and document it so engines can brand themselves.

Developer Experience (Pleasant to Work With)

- Scaffolding: Add `bin/mcp_scaffold <service>` to generate `engine.rb` and `tools.rb` with tests. Provide a docs/examples/hello-service.
- Friendly errors: “tool not found: <name>. Try tools/list.” Short, actionable hints across CLI and MCP.
- Consistent paths: Introduce `Savant::Paths` helper for repo root, config, logs to avoid ad-hoc joins.
- Guard rails: Pre-flight checks command (`bin/doctor`) validating DB connectivity, settings, and Jira envs with clear output.

- DB improvements:
  - Add `statement_timeout` (e.g., 5–10s) per connection and wrap long ops in explicit timeouts.
  - Switch `replace_chunks` to batch insert: `INSERT ... VALUES (...), (...), ...` or `COPY`.
  - Change `delete_missing_files` to use `rel_path <> ALL($2)` with a single array parameter to avoid large parameter lists.

- Config and safety:
  - Enforce repo path existence and readability in `Savant::Config.validate!`; expand `ignore` validation to accept only strings and reject glob patterns that traverse (`..`).
  - Document environment matrix for runtime (Docker vs host) with examples for `DATABASE_URL` and Jira envs; align with README.

- Observability:
  - Introduce a simple metrics emitter (counts + timings) via logger or StatsD-compatible interface; include MCP request latencies and indexer throughput.

Quick Wins (Low Effort)

- Fix typos and logging in `mcp_server.rb` and remove unused parameters.
- Replace swallowed config read with validated load; fail-fast with clear log.
- Add `TRUNCATE` option to `delete_all_data` or clarify destructive intent.
- Add spec for MCP `initialize`, `tools/list`, `tools/call` happy-path and method-not-found.

Potential Follow-ups

- Add a light connection pool (e.g., `pg` with manual multiplex) if concurrency increases.
- Consider background job support for long-running tool operations with progress messages.
- Add optional TLS or socket activation if MCP extends beyond local stdio usage.

Summary

The design is solid and practical for local code search + Jira tooling. Addressing MCP server correctness (undefined vars, validation), tightening DB performance patterns, and enhancing observability and tests will materially improve reliability and maintainability without large architectural changes.
