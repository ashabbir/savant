Savant Codebase Overview

Purpose
- Local repository indexer and MCP servers for fast, private code search and Jira access. Ruby services store chunked repo content in Postgres with FTS and expose tools over MCP stdio for editors.

Architecture
- Indexer: scans configured repos, hashes/dedupes files, chunks content, and writes to Postgres tables (`repos`, `files`, `blobs`, `file_blob_map`, `chunks`). FTS index on `chunks.chunk_text` powers ranked search.
- MCP servers: stdio JSON-RPC interface; a single service is active per process via `MCP_SERVICE` (e.g., `context` or `jira`). Tools are advertised by the active service’s registrar and calls are delegated to its Engine.
- Config: `config/settings.json` drives indexer limits, repo list, MCP listen options, and DB connection defaults (see `config/schema.json`, `config/settings.example.json`).
- Docker: `docker-compose.yml` runs Postgres and optional Ruby services; Makefile wraps common flows.

Key Components (Ruby)
- `lib/savant/config.rb`:
  - `Savant::Config.load(path)`: loads/validates `settings.json`. Ensures presence of `indexer`, `database`, and `mcp` keys; validates repo entries and indexer fields.
  - Raises `Savant::ConfigError` on missing/invalid config.
- `lib/savant/db.rb`:
  - Connection wrapper over `pg`. Schema helpers: `migrate_tables`, `ensure_fts`.
  - CRUD helpers: `find_or_create_repo`, `find_or_create_blob`, `replace_chunks`, `upsert_file`, `map_file_to_blob`, `delete_missing_files`, `delete_repo_by_name`, `delete_all_data`.
- `lib/savant/logger.rb`:
  - Lightweight logger with levels, timing helper `with_timing(label:)`, and slow-op flag via `SLOW_THRESHOLD_MS`.
- `lib/savant/indexer.rb` and `lib/savant/indexer/*`:
  - Facade `Savant::Indexer` delegates to namespaced modules under `lib/savant/indexer/` (Runner, RepositoryScanner, BlobStore, Chunkers, Cache, Config, Instrumentation, Admin, CLI).
  - Runner scans repos from config; merges `.gitignore` and `.git/info/exclude` patterns; skips hidden, binary, oversized, or unchanged files (tracked in `.cache/indexer.json`).
  - Dedupes by SHA256 at blob level; chunks code by lines with overlap; markdown by chars; language derived from file extension with optional allowlist.
  - Upserts file metadata, maps file→blob, replaces blob chunks, and cleans up missing files per repo. Use `bin/context_repo_indexer` or Make `repo-*` targets.
- `lib/savant/context` Engine:
  - `lib/savant/context/engine.rb`: orchestrates context tools
  - `lib/savant/context/ops.rb`: implements search, memory_bank, resources
  - `lib/savant/context/fts.rb`: Postgres FTS helper; returns `[rel_path, chunk, lang, score]`
  - `lib/savant/context/tools.rb`: MCP registrar for context tools
- `lib/savant/mcp_server.rb`:
  - Stdio JSON-RPC 2.0 server. Selects service via `MCP_SERVICE` (`context` or `jira`).
  - `tools/list` returns only the active service’s registrar specs; `tools/call` delegates to the service’s Engine via its registrar. Logs to `logs/<service>.log`.
- `lib/savant/jira` Engine:
  - `lib/savant/jira/engine.rb`, `lib/savant/jira/ops.rb`, `lib/savant/jira/client.rb`, and `lib/savant/jira/tools.rb` implement Jira REST v3 tools and registrar.

- CLI Entrypoints (`bin/`)
- `bin/context_repo_indexer`: index or delete data, or show status. Commands:
  - `index all` | `index <repo>`
  - `delete all` | `delete <repo>`
  - `status`: prints per-repo counts and last mtime.
- `bin/savant`: generator CLI to scaffold new MCP engines and tools.
- `bin/db_migrate`, `bin/db_fts`, `bin/db_smoke`: setup/verify DB and FTS.
- `bin/mcp_server`: launches MCP server (stdio).
- `bin/config_validate`: validates `settings.json` against required structure.

Configuration
- Primary: `config/settings.json` (see `config/settings.example.json` and `config/schema.json`). Required top-level keys:
  - `indexer`: `maxFileSizeKB`, `languages`, `chunk` ({`codeMaxLines`,`overlapLines`,`mdMaxChars`}), `repos` (name, path, optional ignore).
  - `database`: `host`, `port`, `db`, `user`, `password` (or supply `DATABASE_URL`).
  - `mcp`: per-service options like `listenHost`/`listenPort`.
- Env vars: `DATABASE_URL`, `SAVANT_PATH`, `LOG_LEVEL`, Jira creds (`JIRA_*`).

Runtime Modes
- Direct (host): run Ruby scripts with `DATABASE_URL` set (Context) and Jira envs (Jira).
- Docker: use `docker compose` services; Postgres exposed on 5433; volumes mount host repos for indexing.
- MCP editors (Cline/Claude Code): run via stdio; configure commands and env per README examples.

Makefile Highlights
- Dev lifecycle: `make dev`, `make logs`, `make down`, `make ps`.
- DB: `make migrate` (destructive reset), `make fts`, `make smoke`.
- Indexing: `make repo-index-all`, `make repo-index-repo repo=<name>`, `make repo-delete-all`, `make repo-delete-repo repo=<name>`, `make repo-status`.
- MCP: `make mcp`, `make mcp-context(-run)`, `make mcp-jira(-run)`, tests (`make mcp-test`, `make jira-test`, `make jira-self`).
- Quality checks: `bundle exec rspec`, `bundle exec rubocop`, and `bundle exec guard` for watch mode.

Data Model (Postgres)
- `repos(id,name,root_path)`
- `files(id,repo_id,repo_name,rel_path,size_bytes,mtime_ns)` with unique `(repo_id, rel_path)`
- `blobs(id,hash,byte_len)` unique `hash`
- `file_blob_map(file_id,blob_id)` primary key `file_id`
- `chunks(id,blob_id,idx,lang,chunk_text)` with GIN FTS index on `to_tsvector('english', chunk_text)`

Logs
- Text logs written via `Savant::Logger` to stdout for CLIs and to `logs/<service>.log` for MCP. Timing info and slow-operation flags included.

Security & Secrets
- No secrets stored in repo. Jira credentials via env or optional config file. Avoid committing `.env`; `.env.example` is provided.

Getting Started
- Configure `config/settings.json` (copy from example), start Postgres (`make dev`), migrate and FTS (`make migrate && make fts`), index repos (`make repo-index-all`), then query via MCP (`make mcp-test q='term'`).
- Scaffold a new MCP service via generator: `bundle exec ruby ./bin/savant generate engine <name> [--with-db]`, then run with `MCP_SERVICE=<name> ruby ./bin/mcp_server`.

Not In Scope
- This overview excludes the Memory Bank Resource PRD; see docs for broader product context.
