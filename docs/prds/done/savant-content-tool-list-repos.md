# Context Repo README Listing PRD

## Executive Summary
- **Objective:** Provide an MCP/CLI tool that reports every indexed repo’s name plus its README content directly from Postgres so users can discover repo summaries without touching local checkouts or configs.
- **Outcome:** A trusted catalog view reflecting what the indexer actually stored, enabling editors and automation to surface repo descriptions inside MCP clients.

## Background
- **Current State:** Repo metadata is only discoverable via `config/settings.json` or manual filesystem inspection. Once indexed, only `repos`, `files`, `blobs`, and `chunks` tables contain the authoritative state, but there is no tool to surface README details.
- **Pain:** Users spinning up context search in new editors can’t easily see which repos are available or what they contain. Config entries may be stale or missing descriptions, and reviewing logs is cumbersome.
- **Why Now:** As MCP adoption grows, onboarding flows need a quick “list repos + README” command so assistants can suggest relevant repos and provide descriptions inline.

## Goals
- **DB Source of Truth:** Derive repo list exclusively from Postgres `repos` table so only successfully indexed repos appear.
- **README Extraction:** Pull README markdown out of the indexed data (preferably from `chunks` for the README file) and include it in the response.
- **Tooling Surface:** Expose via new MCP tool (e.g., `repos/readme_list`) and optional CLI command for scripting.
- **Filtering & Limits:** Support optional filters (e.g., repo name substring) and cap README payload (first chunk or <=4KB) to keep responses lightweight.

## Non-Goals
- No schema changes or new tables.
- No live filesystem reads; everything comes from DB state.
- No per-repo stats beyond name + README snippet.
- No editor UI work—clients render the returned data.

## Requirements & Acceptance Criteria
- **Tool Spec:** Add MCP tool spec with optional `repo` filter and `max_length` parameter.
- **DB Query:** Use `repos` table to fetch `id` + `name`. For each repo, locate README file via `files` (case-insensitive match on `README*`).
- **Content Source:** Fetch README text from indexed data (`chunks.chunk_text` joined via `file_blob_map`). Return the first chunk (or aggregate up to limit) ensuring UTF-8.
- **Fallback:** If no README exists, include `readme: nil` but still list repo.
- **Performance:** Use batched SQL to avoid N+1 queries; acceptable approach is single SQL with lateral join grabbing first README chunk per repo.
- **Error Handling:** On DB failure, surface meaningful error message but keep MCP server running.
- **Tests:** Add specs ensuring README lookup works with multiple repos, missing readmes, and limit enforcement.
- **Docs:** Document tool usage and config in README or MCP docs.

## Architecture / Implementation Plan
1. **DB Helper:** Extend `Savant::DB` with query method `list_repos_with_readme(limit:, filter:)` returning array of structs `{ name:, readme_text: }`.
2. **Context Engine:** Add op in `Context::Ops` that calls DB helper and handles truncation.
3. **Tool Registrar:** Register new MCP tool (e.g., `repos/list`) referencing the op and schema.
4. **CLI Wrapper:** Optionally add `bin/context_repo_indexer repos` or `make repo-list` command to output data for shell usage.
5. **Docs & Tests:** Update specs for DB helper and ops, ensure registrar spec registers new tool, and document command in README/CHANGELOG.

## Testing Strategy
- **Unit Specs:**
  - Fake DB returning repo rows to validate ops formatting.
  - DB helper spec using test database or mocked connection verifying SQL.
- **Integration Spec:** Use in-memory or fixture DB to verify README retrieval from `chunks` and `files` tables.
- **Manual:** Run MCP `tools/call repos/list` with sample DB to confirm output.

## Risks & Mitigations
- **Large Readmes:** Could return huge text. Mitigate with `max_length` default (e.g., 4KB) and truncation indicator.
- **Missing Readmes:** Many repos may not have README; ensure we still list them with `readme: nil` to avoid confusion.
- **Query Complexity:** Joining across tables might be heavy; use indexes (`files(repo_id, rel_path)`) and limit to first chunk.
- **Staleness:** README content reflects last index run, not live repo. Communicate in docs and encourage re-indexing if outdated.

## Milestones
1. **SQL + DB helper (Day 1)**
2. **Ops + tool wiring (Day 2)**
3. **Specs + docs (Day 2-3)**
4. **Manual verification + release (Day 3)**

## Open Questions
- Should we support returning multiple README formats (e.g., README.md vs README.rst) beyond naming heuristics?
- Do we need pagination if repo count grows large, or is a full list acceptable for now?
- Should we include additional metadata (e.g., last indexed time) alongside README text?
