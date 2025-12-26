# Changelog

All notable changes to this project are documented in this file.

The format is based on Keep a Changelog, and this project aims to follow
Semantic Versioning where practical. Dates are in YYYY-MM-DD.

## [1.1.0] - 2025-10-20

### Added
- files.repo_name column in Postgres with backfill and index for faster repo filtering.
- Multi-repo filtering in FTS; search results now include `repo`.
- Context FS repo indexer surface:
  - CLI: `bin/context_repo_indexer` (`index|delete|status`).
  - MCP tools: `fs_repo_index`, `fs_repo_delete`, `fs_repo_status`.
- Namespaced Context tools:
  - `fts_search` — general code/docs FTS.
  - `memory_search` — FTS over memory bank only.
  - `memory_resources_list`, `memory_resources_read` — memory bank resource helpers.
- Memory Bank class rename: `Savant::Context::MemoryBank::Search` (formerly `Indexer`).

### Changed
- Context Engine now owns a shared DB handle and injects it into Ops/FTS and FS RepoIndexer.
- `memory_resources_list` is DB-backed; `resources/read` resolves repo roots via DB before reading from disk.
- Makefile targets consolidated under `repo-*` (e.g., `repo-index-all`).
- Updated README, AGENTS.md, and PRDs to reflect new tool names and flows.

### Removed
- Deprecated MCP tool aliases: `search`, `search_memory`, `resources/*`, `repo_indexer/*`.
- Legacy CLIs: `bin/index`, `bin/status`.
- `size_bytes` from memory resource outputs (MCP surface no longer exposes file size).

### Migration Notes
- Database:
  - Run migrations and ensure FTS: `make migrate && make fts`.
  - Re-index recommended: `make repo-index-all`.
- MCP clients:
- Replace `search` with `fts_search` and `search_memory` with `memory_search`.
- Replace `resources/list` and `resources/read` with `memory_resources_*`.
- Update any indexer calls to use `fs_repo_*`.
- Make targets:
  - Use `repo-index-all`, `repo-index-repo`, `repo-delete-all`, `repo-delete-repo`, `repo-status`.
- Behavior:
  - Memory Bank search now queries DB FTS; listing uses DB rows; reading still pulls file contents from disk using repo roots from DB.

## [1.0.0] - 2025-10-01
- Initial public structure and MCP servers (Context, Jira).
- Indexer scanning/chunking with Postgres FTS.

[1.1.0]: https://github.com/ashabbir/savant/compare/1.0.0...1.1.0

## [1.1.1] - 2025-12-26

### Docs
- PRD (Council): Marked Implemented (v1), added implementation snapshot, API/mounts, DB model, UI behavior, and env flags.
- README: Added Council engine section with UI path, HTTP examples, data model, and link to the PRD.
- Getting Started: Added “Council Quickstart” with UI flow and cURL snippets.
