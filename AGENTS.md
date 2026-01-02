Savant Codebase Overview

Purpose
- Local repository indexer and MCP servers for fast, private code search and Jira access. Ruby services store chunked repo content in Postgres with FTS and expose tools over MCP stdio for editors.

Important Documents:
docs/getting-started.md
docs/savant-foundation.md
docs/savant-instructions.md
docs/savant-vision.md

Architecture
- Indexer: scans configured repos, hashes/dedupes files, chunks content, and writes to Postgres tables (`repos`, `files`, `blobs`, `file_blob_map`, `chunks`). FTS index on `chunks.chunk_text` powers ranked search. Implemented under `lib/savant/engines/indexer/*`.
- MCP: `lib/savant/framework/mcp/server.rb` provides a transport-agnostic MCP server (stdio or websocket). Default mode is stdio.
- Multiplexer: `lib/savant/multiplexer.rb` can spawn multiple engines (context, git, think, personas, rules, jira) and route `service.tool` calls to the correct engine.
- Config: `config/settings.json` drives indexer limits, repo list, multiplexer engines, transport options, and DB defaults (see `config/schema.json`, `config/settings.example.json`).
- HTTP Hub: HTTP transport under `lib/savant/framework/transports/http/rack_app.rb`, mounted via the Hub (`lib/savant/hub/*`) to serve `/healthz`, `/rpc`, and the static UI.

Key Components (Ruby)
- `lib/savant/framework/config.rb`:
  - `Savant::Framework::Config.load(path)`: loads/validates `settings.json`. Ensures presence of top-level sections; validates indexer and repo entries; raises `Savant::ConfigError` on invalid/missing config.
- `lib/savant/framework/db.rb`:
  - Postgres connection wrapper (pg). Non-destructive, versioned migrations; `ensure_fts` and CRUD used by the indexer: `find_or_create_repo`, `find_or_create_blob`, `replace_chunks`, `upsert_file`, `map_file_to_blob`, `delete_missing_files`, `delete_repo_by_name`, `delete_all_data`.
- `lib/savant/logging/logger.rb` and `lib/savant/logging/mongo_logger.rb`:
  - Structured logging with levels, `with_timing(label:)`, and optional file outputs under `logs/`.
- `lib/savant/engines/indexer.rb` and `lib/savant/engines/indexer/*`:
  - Facade `Savant::Indexer::Facade` wires config/cache/db to `Runner`. Submodules: Runner, RepositoryScanner, BlobStore, Chunkers, Cache, Config, Instrumentation, Admin, CLI.
  - Runner merges `.gitignore` and `.git/info/exclude`; skips hidden, binary, oversized, or unchanged files (tracked in `.cache/indexer.json`).
  - Dedupes by SHA256; chunks code by lines with overlap; markdown/plaintext by chars; language from extension with allowlist.
  - Upserts file metadata, maps file→blob, replaces blob chunks, and cleans missing files per repo.
- `lib/savant/engines/context/*`:
  - `engine.rb`: orchestrates context tools; `ops.rb`: search, memory_bank, resources; `fts.rb`: FTS helper (ranked `[repo, rel_path, chunk, lang, score]`); `tools.rb`: MCP registrar.
- `lib/savant/framework/mcp/server.rb`:
  - MCP server launcher (stdio or websocket). Selects service via `MCP_SERVICE` or uses the multiplexer.
- `lib/savant/multiplexer.rb`:
  - Spawns/supervises engines and routes tool calls across them. Aggregates `tools/list` across engines.
- `lib/savant/hub/*` and `lib/savant/framework/transports/http/rack_app.rb`:
  - HTTP transport and Hub router for `/healthz`, `/rpc`, and static UI (`public/ui`).
- `lib/savant/engines/jira/*`:
  - `engine.rb`, `ops.rb`, `client.rb`, `tools.rb` implement Jira REST v3 tools with write-guard (`JIRA_ALLOW_WRITES`).
- Additional engines: `engines/git`, `engines/think`, `engines/personas`, `engines/rules`, `engines/drivers`, `engines/workflow`, `engines/llm`.

- CLI Entrypoints (`bin/`)
- `bin/context_repo_indexer`: index/delete/status for repos.
  - `index all` | `index <repo>` | `delete all` | `delete <repo>` | `status`
- `bin/savant`: primary CLI:
  - `serve --transport=stdio|http [--service=NAME]`, `hub`, `engines`, `tools`, `list tools`, `call <tool> --input='{}'`
  - agents: `agent create|list|show|run|delete`; workflows: `workflow <name> --params='{}'`
  - generator: `generate engine <name> [--with-db]`
- `bin/db_migrate`, `bin/db_fts`, `bin/db_smoke`: setup/verify DB and FTS.
- `bin/mcp_server`: direct MCP launcher (stdio/websocket).
- `bin/config_validate`: validate `settings.json`.

Configuration
- Primary: `config/settings.json` (see `config/settings.example.json`, `config/schema.json`). Key sections:
  - `indexer`: `maxFileSizeKB`, `languages`, `chunk` ({`codeMaxLines`,`overlapLines`,`mdMaxChars`}), `repos` (name, path, optional ignore), optional `scanMode` (`ls` or `git-ls`).
  - `mcp.multiplexer.engines`: engine list and options; optional `transport` section for websocket overrides.
  - `database`: `host`, `port`, `db`, `user`, `password` (or use `DATABASE_URL`).
  - Optional: `logging`, `llm`, `jira`, `agent`.
- Env vars: `DATABASE_URL`, `SAVANT_PATH`, `LOG_LEVEL`, `MCP_SERVICE`, `SAVANT_DEV`, multiplexer toggles, Jira creds (`JIRA_*`).

Runtime Modes
- Multiplexer (stdio): `savant serve --transport=stdio`
- Hub (HTTP + static UI): `savant hub --host=0.0.0.0 --port=9999` then open `/ui` if built
- Dev mode (hot reload): see `docs/getting-started.md` → `make dev` (Vite + Rails + Hub)
- MCP editors (Cline/Claude Code): run via stdio; configure commands and env per README examples.

Makefile Highlights
- Dev: `make dev` (Vite + Rails + Hub), or individually: `make dev-ui`, `make dev-server`, `make kill-dev-server`, `make ui-build-local`
- DB: `make db-create`, `make db-migrate`, `make db-fts`, `make db-smoke`, `make db-reset` (see DB_ENV)
- Indexing: `make repo-index-all`, `make repo-index repo=<name>`, `make repo-delete-all`, `make repo-delete repo=<name>`, `make repo-status`
- Utilities: `make pg`, `make mongosh`, `make ls`, `make ps`
- Reasoning API: `make reasoning-setup`, `make reasoning-api`

Data Model (Postgres)
- `repos(id,name,root_path)`
- `files(id,repo_id,repo_name,rel_path,size_bytes,mtime_ns)` with unique `(repo_id, rel_path)`
- `blobs(id,hash,byte_len)` unique `hash`
- `file_blob_map(file_id,blob_id)` primary key `file_id`
- `chunks(id,blob_id,idx,lang,chunk_text)` with GIN FTS index on `to_tsvector('english', chunk_text)`
- App tables used by engines: `personas`, `rulesets`, `drivers`, `agents`, `agent_runs`, `think_workflows` (see `server/db/migrate` and helpers in `lib/savant/framework/db.rb`).

Logs
- Structured logs via `Savant::Logging::Logger`/`MongoLogger` to stdout and `logs/<service>.log`. Timing info and slow-op flags included. Multiplexer and HTTP transports log to `logs/multiplexer.log` and `logs/http.log`.

Security & Secrets
- Use env or `secrets.yml` (see `secrets.example.yml`). Avoid committing real credentials in `config/settings.json` or `.env`. Prefer `DATABASE_URL`, `JIRA_*`, and SecretStore (`lib/savant/framework/secret_store.rb`). License stored at `~/.savant/license.json` (dev bypass via `SAVANT_DEV=1`).

- Configure `config/settings.json` (copy from example), prepare DB (`make db-create && make db-migrate && make db-fts`), then index repos (`make repo-index-all`).
- Run MCP stdio: `savant serve --transport=stdio` or run the Hub: `savant hub` (serve `/rpc` and optionally `/ui`).
- Scaffold a new engine via: `bundle exec ruby ./bin/savant generate engine <name> [--with-db]`.

Not In Scope
- This overview excludes the Memory Bank Resource PRD; see docs for broader product context.

Developer Flow (PRD → Branch → Plan → TDD Implement -> commit -> push)

Overview
- The Codex agent can autonomously turn a PRD into a branch with implemented code and tests in one run. It creates a branch from the PRD name, writes an implementation plan back into the PRD, makes the changes, runs RuboCop and tests, then commits and pushes.

Defaults and Options
- Branch: `feature/<prd-slug>` (override with `--branch-prefix`)
- Remote: `origin` (override with `--remote`)
- Push: enabled (disable with `--no-push`)
- Preview: `--dry-run` to show planned actions/diffs without writing
- Allow dirty tree: `--allow-dirty` to proceed with local changes
- Lint/test tolerances: `--allow-lint-fail`, `--allow-test-fail`

Flow Details
- Branching: Creates a new branch from current HEAD using a slug from the PRD title or filename.
- Planning: Appends/updates an “Agent Implementation Plan” section in the PRD listing concrete steps, files to change, and tests.
- Implementation: Applies code and spec changes in a single logical commit, adhering to existing style and structure.
- Linting: Runs `bundle exec rubocop -A`; aborts on remaining offenses unless allowed.
- Tests: Runs `bundle exec rspec` if present; aborts on failures unless allowed.
- Commit & Push: Single commit with a message referencing the PRD; pushes to the target remote unless `--no-push` is set.

Requirements
- Ruby + Bundler installed (`bundle install`).
- Git repo with a configured remote (default `origin`).
- RuboCop and RSpec present in the bundle for linting/tests.

UI Layout Rules (Codex)

- Left/Right Panels: Always use a two-panel layout where the left panel is the Action panel and the right panel is the Result panel.
  - Action panel (left): navigation, filters, create/edit/delete controls, property forms, and editors for input.
  - Result panel (right): read-only views, previews, diagrams, logs, YAML/Markdown rendering.
- Sizing Defaults: Use a 4/8 split on md+ screens (left md:4, right md:8) unless a page has strong reasons to deviate. Keep xs at 12 for both.
- Preview Behavior: Use popups (modal Dialog) for large YAML/Markdown previews. Keep the right panel focused on the primary result (graph/list/view) and only open larger previews in a dialog.
- Close Controls: All dialogs must include a close icon button in the title bar and may also include a Close action button.
- Consistency: Apply this pattern to all “Rules” windows and editors, and prefer it across the app (Workflows, Personas, Diagnostics) unless a different UX is clearly better for usability.
- Footer Debug: Clicking the footer label "amdSh@2025" opens a modal with the current component name and debug info (path, mode, hub base URL, user ID, engine, hub status).
