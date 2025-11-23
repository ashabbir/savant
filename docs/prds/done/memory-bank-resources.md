# PRD: Memory Bank Resources and Summaries (Ruby Indexer)

## Problem
- Repositories often contain memory-related Markdown under `**/memory_bank/`.
- Current MCP "search" server lacks first-class resources for these docs and does not provide concise summaries in results.
- We want deterministic, local processing in the Ruby indexer, without external LLMs.

## Goals
- Discover Markdown files under any `memory_bank` directory and expose them as listable, readable resources.
- Generate concise summaries using the Ruby `summarize` gem during indexing.
- Index both the full document text and the summary; search ranks on full text only.
- Return summaries and hit snippets in search responses.
 - Additive change: maintain full backward compatibility with existing features and APIs.

## Non-Goals
- Using external LLMs or network calls.
- Writing/modifying repository files.
- Cross-repo aggregation or advanced semantic ranking.
 - Changing existing search behavior or resource contracts unrelated to memory bank support.

## Users & Use Cases
- Agent developers: fetch memory docs to prime prompts.
- Analysts: browse memory bank docs via client resource explorer.
- CI/tooling: validate presence/structure of memory docs.

## Scope
- Detect Markdown:
  - Any `*.md` within `**/memory_bank/` (recursive).
  - README handling: `README.md` / `readme.md` treated as regular Markdown.
- Expose as MCP resources with stable URIs and metadata.
- Summarize with `summarize` gem; attach to metadata and index row.
- Search over full text; return summary and top snippets.
 - Must not alter existing search endpoints’ response shapes outside of the optional `summary` field for memory bank items.

## Definitions
- Memory Bank Folder: any directory whose basename is `memory_bank`.
- Markdown File: case-insensitive `*.md`, including README variants.

## Resource Model
- URI: `repo://<root-id>/memory-bank/<repo-relative-path>`
- Mime type: `text/markdown; charset=utf-8`
- Metadata:
  - `path`: repo-relative path
  - `title`: filename without extension or first H1 (if extracted)
  (size omitted from MCP output)
  - `modified_at`: ISO 8601 mtime
  - `source`: `memory_bank`
  - `summary`: { `text`, `length`, `source`: "summarize", `generated_at` }

## Index Schema (Ruby)
- `id`: stable hash of repo-relative path
- `path`: repo-relative path
- `title`: derived from filename or first H1
- `content_full`: plain text extracted from Markdown
- `content_summary`: summary text (<= `summary_max_length`)
- `modified_at`: file mtime
  (file size tracked internally; omitted from MCP output)
- `source`: constant `memory_bank`

## Indexing Flow
1. Discover files via glob patterns (configurable): `**/memory_bank/**/*.md`.
2. Guardrails: skip indexing content if `size_bytes > max_bytes_index`; still register resource.
3. Read file; normalize to UTF-8.
4. Convert Markdown to plain text (strip frontmatter, code fences, images/links URLs, HTML).
5. `content_full` = cleaned text.
6. `content_summary` = `Summarize.summarize(content_full, max_length: summary_max_length)`.
7. Upsert into index store and update in-memory resource registry.

## Search Behavior
- Query executes against `content_full` only (summary is not scored).
- Extract snippets around query term occurrences using a fixed window.
- Response item includes: `path`, `title`, `score`, `summary`, `snippets`, `metadata`.

## MCP Surfaces
- `memory/resources/list`: returns all memory bank resources with metadata.
- `memory/resources/read`: returns raw Markdown content for the requested URI.
- `memory/search`: executes search over memory bank docs (DB-backed FTS).

## Backward Compatibility
- No breaking changes to current MCP endpoints (`resources/*`, existing `tools/*`).
- Existing search functionality for non-memory content remains unchanged in ranking, fields, and scoring.
- The `summary` field is additive and optional; absence should not break clients.
- Configuration defaults preserve current behavior when `memory_bank.enabled` is false or missing.
- URI scheme is additive (`repo://.../memory-bank/...`) and does not replace existing URIs.

## Configuration (Ruby)
```yaml
memory_bank:
  enabled: true
  patterns: ["**/memory_bank/**/*.md"]
  follow_symlinks: false
  max_bytes_index: 2_000_000
  summary_max_length: 300
  summarize_enabled: true
  parser: "kramdown" # enum: kramdown|plain
search:
  snippet_window: 160
  snippet_windows_per_doc: 2
  max_results: 20
```

## Edge Cases
- Empty/very short docs: summary falls back to first paragraph truncated.
- Large docs (> `max_bytes_index`): listed as resources; content not indexed; summary omitted.
- Duplicate filenames: uniqueness by repo-relative path; `id` derived from path hash.
- Non-UTF8: attempt transcode to UTF-8; on failure, skip with warning and list as resource without index.

## Decisions
- Multiple roots: support multiple `memory_bank` folders via configurable glob list; no cross-folder grouping.
- Frontmatter: strip during text extraction; do not parse for metadata in v1.
- Parser: default `kramdown`; fallback to `plain` regex sanitizer on error or when configured.
- Titles: prefer first H1 for all files (including README); fallback to filename stem; normalize whitespace; max 120 chars.
- Summaries: if `summarize_enabled`, use `summarize` gem with `max_length = summary_max_length`; hard-truncate with ellipsis. If disabled/too short, use first paragraph with same truncation. Omit for oversized files.
- Snippets: case-insensitive matching; de-duplicate overlapping windows; include highlight offsets. If no matches, return empty snippets (no context-only windows in v1).
- Encoding errors: attempt UTF-8 transcode; on failure, list as resource without index/summary; log warning.
- URIs: path-derived; renames produce new URIs; stability guaranteed by path.
- Symlinks: respect `follow_symlinks` (default false) and avoid cycles when enabled.
- Extensions: case-insensitive `.md` detection.

## Telemetry & Logging
- Log counts: discovered, indexed, skipped (size/encoding), and timing for summarize.
- Expose `last_indexed_at` in server info if available.

## Acceptance Criteria
- Files under `**/memory_bank/` appear in `resources/list` with stable URIs and metadata including summary (when not skipped).
- `resources/read` returns exact Markdown content.
- Index contains `content_full` and `content_summary`; search runs on `content_full` only.
- Search results include summary and 1–2 snippets with matched context.
- Modifying a file and invoking refresh reindexes and updates summary and `modified_at`.
 - No regressions in existing search results for non-memory content (fields, scores, ordering) under equivalent configuration.
 - With `memory_bank.enabled: false`, system behaves exactly as before this feature.

## Implementation Notes (Ruby)
- Dependencies:
  - `summarize` gem for summaries.
  - Markdown-to-text: prefer a robust approach (e.g., `kramdown` to parse then extract text nodes) or a conservative sanitizer.
  - Bundler-only posture: gems declared in `Gemfile`; invoke via `bundle exec`.
- Helpers:
  - `markdown_to_text(markdown) -> String`
  - `make_snippets(text, query, window:, max_windows:) -> Array[String]`
  - `path_to_id(repo_relative_path) -> String`
- Index Store: reuse existing search store; add fields for `content_summary`.
- Resource Registry: in-memory map keyed by repo-relative path with metadata and URI.

## Title Derivation
- Use first Markdown H1 (`^#\s+...`) when present, stripping Markdown formatting.
- Otherwise, use filename without extension.
- Normalize internal whitespace; trim; limit to 120 characters.

## Developer Workflow (Bundler + Make)
- Makefile targets (invoked via Bundler; no system installs):
  - `make setup`: `bundle install`
  - `make lint`: `bundle exec rubocop` (when linter configured)
  - `make quickstart`: boot Docker stack + migrations/FTS (no indexing)
  - `make dev`: start local dev task when available
- All CLI invocations in docs/examples should be prefixed with `bundle exec`.
- Do not require system-level packages beyond Ruby; gems are managed via Bundler.

## Module Skeleton (Planned)
- `lib/savant/memory_bank/`
  - `discovery.rb`: glob discovery honoring `patterns` and `follow_symlinks`.
  - `markdown.rb`: `markdown_to_text`, title extraction, frontmatter strip.
  - `summaries.rb`: wrapper for `Summarize.summarize` with fallbacks and truncation.
  - `indexer.rb`: orchestration for indexing flow and guardrails.
  - `snippets.rb`: snippet windowing and highlight offsets.

## API Shapes (Illustrative)
- memory/resources/list → `[ { uri, mimeType, metadata: { path, title, modified_at, source } } ]`
- memory/resources/read → `{ contents: [ { uri, mimeType: "text/markdown", text } ] }`
- memory/search (params: { q, repo?, limit? }) →
  - `[ { repo, rel_path, lang, chunk, score } ]`
