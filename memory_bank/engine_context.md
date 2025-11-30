# Context Engine Notes

## Overview
- Entry point: `MCP_SERVICE=context ruby ./bin/mcp_server`
- Files: `lib/savant/engines/context/{engine.rb,ops.rb,tools.rb,fts.rb}` plus `fs/` + `memory_bank/`
- Purpose: fast private code/markdown search over Postgres FTS and helpers for memory resources and repo admin.

## Call Flow
```mermaid
sequenceDiagram
  participant UI as UI / Client
  participant Hub as HTTP Hub
  participant Ctx as Context Registrar
  participant Ops as Context Ops
  participant DB as Postgres

  UI->>Hub: POST /context/tools/fts_search/call {q, repo?, limit}
  Hub->>Ctx: call "fts_search" (ctx={user_id})
  Ctx->>Ops: search(q, repo, limit)
  Ops->>DB: SELECT ts_rank_cd(...) FROM chunks WHERE ...
  DB-->>Ops: rows [rel_path, chunk, lang, score]
  Ops-->>Ctx: results
  Ctx-->>Hub: results
  Hub-->>UI: results
```

## Data Model (DB)
```mermaid
erDiagram
  repos ||--o{ files : has
  files ||--o{ file_blob_map : maps
  blobs ||--o{ file_blob_map : maps
  blobs ||--o{ chunks : has

  repos { INT id PK TEXT name TEXT root_path }
  files { INT id PK INT repo_id TEXT rel_path BIGINT size_bytes BIGINT mtime_ns }
  blobs { INT id PK TEXT hash INT byte_len }
  file_blob_map { INT file_id PK INT blob_id }
  chunks { INT id PK INT blob_id INT idx TEXT lang TEXT chunk_text }
```

## Tools (Selected)
- `fts_search` – ranked snippet search (code + markdown)
- `memory/resources/*` – list/read memory_bank markdown stored in DB
- `fs/repo/*` – index/delete/status helpers

## Notes
- Ensure DB is migrated and FTS created (`make migrate && make fts`).
- Index before searching (`make repo-index-all`).
- Logs: `/tmp/savant/context.log` (Hub) or `logs/context.log` (stdio).
