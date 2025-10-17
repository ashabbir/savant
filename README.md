# Savant

Version 1 — Local repo indexer + MCP search layer (Ruby + Docker, Postgres FTS). This README provides a high-level overview, an architecture diagram, the end-to-end flow, and pointers for development.

## Overview
- **Purpose:** Index local repositories, chunk content, store in FTS-backed DB, and expose fast search via an MCP WebSocket tool.
- **Core Pieces:** Indexer CLI, Postgres 16 + FTS (tsvector + GIN), MCP server exposing `search`, containerized via Docker Compose.
- **Docs:** See `docs/README.md` for epics, stories, and PRD.

## Problem
- Codebases are large and change frequently; AI tools need fast, accurate, and privacy‑preserving access to local code.
- Remote embeddings or cloud search increase latency, cost, and risk exposure of proprietary code.
- Developers need a simple, repeatable way to index repos and query them through standard MCP clients.

## Solution
- A local, containerized pipeline that scans repos, chunks content with language‑aware heuristics, and stores data in a single FTS index.
- A minimal MCP server that exposes a `search` tool over WebSocket, returning ranked hits and optional snippets.
- A single `settings.json` drives configuration across services for predictable, reproducible results.

## How It Works
- Scan: indexer reads repo paths from config, applies ignore rules, and detects changes via size/mtime.
- Normalize: compute hashes, deduplicate blobs, and create chunks with overlap to preserve context boundaries.
- Store: upsert blobs/chunks/mappings and populate FTS tables for fast ranking.
- Serve: MCP server connects to the DB, executes FTS queries, and returns results to the client.

## Architecture
```mermaid
flowchart LR
  subgraph Host
    W[Editor / Client]
  end

  subgraph Compose Stack
    I[Index-er CLI\nscan → hash → chunk]
    DB[(DB + FTS Index)]
    MCP[MCP Server\nWebSocket + tool: search]
  end

  Repo[Local Repo Files]

  Repo -->|scan| I
  I -->|blobs/chunks + metadata| DB
  W <-->|MCP protocol| MCP
  MCP -->|query FTS| DB
  MCP -->|ranked results| W

  classDef svc fill:#f0f7ff,stroke:#1e88e5,color:#0d47a1,stroke-width:1px
  classDef data fill:#f9fbe7,stroke:#7cb342,color:#33691e,stroke-width:1px
  class I,MCP svc
  class DB data
```

## Flow Diagram
```mermaid
sequenceDiagram
  participant Dev as Developer
  participant IDX as Indexer CLI
  participant DB as DB + FTS
  participant MCP as MCP Server
  participant IDE as Editor/Client

  Dev->>IDX: run index (scan/hash/chunk)
  IDX->>DB: upsert blobs/chunks + maps
  Dev->>MCP: start server (ws)
  IDE->>MCP: tool.search(query)
  MCP->>DB: FTS query + rank
  DB-->>MCP: hits + snippets
  MCP-->>IDE: results
```

## Configuration Examples
- Primary configuration lives in `config/settings.json` (see example below). The stack reads it via `SETTINGS_PATH`.

Minimal `config/settings.json` example:

```json
{
  "indexer": {
    "maxFileSizeKB": 512,
    "languages": ["rb", "ts", "tsx", "js", "md", "yml", "yaml", "json"],
    "chunk": { "mdMaxChars": 1200, "codeMaxLines": 200, "overlapLines": 3 }
  },
  "repos": [
    { "name": "example", "path": "/host/example-repo", "ignore": ["node_modules/**", "tmp/**", ".git/**"] }
  ],
  "mcp": { "listenHost": "0.0.0.0", "listenPort": 8765, "allowOrigins": ["*"] },
  "database": { "host": "postgres", "port": 5432, "db": "contextdb", "user": "context", "password": "contextpw" }
}
```

Notes:
- Full schema: `config/schema.json`; reference example: `config/settings.example.json`.
- Mount your host repo into the compose stack so the indexer can read it (see `docker-compose.yml`).

## Project Layout
- **Docs:** `docs/` — epics, PRD, and ops notes.
- **Config:** `config/` — settings and loaders (see `settings.example.json`).
- **Scripts:** `bin/` — Ruby CLIs for index and DB ops.
- **Compose:** `docker-compose.yml` — services, networks, and volumes.

## Development
- **Dev:** `make dev` (compose up)
- **Logs:** `make logs`
- **Down:** `make down`
- **PS:** `make ps`

Common ops:
- Tail logs: `docker compose logs -f indexer-ruby mcp-ruby`
- Readiness grep: `docker compose logs mcp-ruby | rg '^READY'`

## Configuration
- Provide `config/settings.json` (see `config/settings.example.json`).
- The compose stack mounts `settings.json` and services read via `SETTINGS_PATH`.

## Usage Summary
- Start services: `docker compose up -d`
- Run indexer: `bin/index` (or via compose service command)
- Query via MCP: connect your MCP‑aware client to `ws://localhost:8765` and call `search`.

Database
- Version 1 uses Postgres 16 with built-in FTS (tsvector + GIN). No embeddings or vector search are used.

## Make Commands
- `make dev`: start the stack
- `make migrate`: create/upgrade tables
- `make fts`: ensure FTS index exists
- `make smoke`: quick DB check (migrate + FTS ok)
- `make index-all`: run indexer for all repos and append output to `logs/indexer.log`
- ``make index-repo repo=<name>``: index a single repo
- `make status`: show per‑repo files/blobs/chunks counters
- `make mcp`: start the MCP container
- ``make mcp-test q='<term>' repo=<name> limit=5``: run a search against MCP
- `make logs`: follow indexer + MCP logs
- `make ps`: list service status
- `make down`: stop stack and remove containers (keeps volume)

## MCP Testing
- Quick test: ``make mcp-test q='User'``
- With repo filter: ``make mcp-test q='Orchestrator' repo=crawler``
- From inside the container: `./bin/mcp_server` (reads JSON on stdin, prints JSON)

## Troubleshooting
- No files indexed:
  - Ensure `config/settings.json` uses container paths (e.g., `/host/crawler`).
  - Mount your host repo in `docker-compose.yml`, e.g., `- /ABSOLUTE/HOST/PATH:/host/crawler:ro`.
  - Clear cache on host: `rm -f .cache/indexer.json`, then re‑run indexing.
- Nothing in `logs/indexer.log` while running:
  - Use: `docker compose exec -T indexer-ruby ./bin/index all 2>&1 | tee -a logs/indexer.log`
  - Tail: `tail -F logs/indexer.log`
- Permission denied on scripts:
  - `chmod +x bin/index bin/status bin/mcp_server`
- Docker warnings like `LISTEN_HOST/PORT not set`:
  - Harmless; compose uses defaults. Confirm with `docker compose ps`.
- Reset DB to a clean state:
  - `docker compose down -v` (drops the Postgres volume), then `make dev && make migrate && make fts`.
- Large/binary/unwanted files:
  - Indexer skips `.git`, dotfiles, `.gitignore`d paths, binaries (NUL bytes), and files above `indexer.maxFileSizeKB`.
  - Adjust limits in `config/settings.json`.
- MCP returns empty results:
  - Ensure indexing completed (`make status` shows non‑zero counts) and try broader `q`.

## Roadmap & References
- **Epics & Stories:** `docs/README.md`
- **PRD:** `docs/prds/prd.md`
- **Health & Logs:** `docs/epics/01-setup/s-3-logs-health.md`
