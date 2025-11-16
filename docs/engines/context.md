# Context Engine (File‑by‑File)

Purpose: Fast, ranked repo search via Postgres FTS populated by the Indexer.

## Files
- Engine façade: [lib/savant/context/engine.rb](../../lib/savant/context/engine.rb)
- Tools registrar: [lib/savant/context/tools.rb](../../lib/savant/context/tools.rb)
- Operations: [lib/savant/context/ops.rb](../../lib/savant/context/ops.rb)
- FTS helper: [lib/savant/context/fts.rb](../../lib/savant/context/fts.rb)
- Repo indexer (fs entry): [lib/savant/context/fs/repo_indexer.rb](../../lib/savant/context/fs/repo_indexer.rb)
- Memory bank helpers:
  - [lib/savant/context/memory_bank/snippets.rb](../../lib/savant/context/memory_bank/snippets.rb)
  - [lib/savant/context/memory_bank/search.rb](../../lib/savant/context/memory_bank/search.rb)
  - [lib/savant/context/memory_bank/markdown.rb](../../lib/savant/context/memory_bank/markdown.rb)

Related indexer modules:
- [lib/savant/indexer.rb](../../lib/savant/indexer.rb)
- `lib/savant/indexer/*` (runner, scanner, chunkers, blob store, etc.)

## Tools
- `fts/search` — FTS query over indexed chunks
- `memory/search` — FTS search for memory bank markdown
- `memory/resources/list|read` — list/read memory bank resources
- `fs/repo/index|delete|status` — manage index
- `repos/list` — list repos with README excerpts

## Setup
- Requires Postgres and FTS: run `make migrate && make fts`, then index repos.
- Start: `MCP_SERVICE=context SAVANT_PATH=$(pwd) DATABASE_URL=postgres://... ruby ./bin/mcp_server`

