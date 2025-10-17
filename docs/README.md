# Epics & Stories Index

This repository implements the "AI Context System — Local Repo Indexer + MCP Search Layer (Ruby + Docker, FTS-Only)" MVP.

- PRD: [docs/prds/prd.md](prds/prd.md)

## Epics
- Containerized MVP Setup — Compose services and base config
  - [S-1: Compose Stack Starts Services](epics/01-setup/s-1-compose.md)
  - [S-2: Config Loaded From settings.json](epics/01-setup/s-2-config.md)
  - [S-3: Logs and Health Signals](epics/01-setup/s-3-logs-health.md)
- Indexer CLI — Scan, hash, chunk, and map files
  - [S-1: Command Scaffolding](epics/02-indexer/s-1-command.md)
  - [S-2: Repo Scanning with Ignore Rules](epics/02-indexer/s-2-scan-ignore.md)
  - [S-3: Change Detection via mtime+size](epics/02-indexer/s-3-change-detection.md)
  - [S-4: Hash + Blob Deduplication](epics/02-indexer/s-4-dedupe-hash.md)
  - [S-5: Chunking](epics/02-indexer/s-5-chunking.md)
  - [S-6: Mapping and Garbage Collection](epics/02-indexer/s-6-mapping-gc.md)
- Database & FTS — Schema and full-text search index
  - [S-1: Connection and Migrations](epics/03-database/s-1-migrations.md)
  - [S-2: Tables](epics/03-database/s-2-tables.md)
  - [S-3: FTS Index](epics/03-database/s-3-fts-index.md)
  - [S-4: Minimal Seed/Smoke Check](epics/03-database/s-4-smoke-seed.md)
- MCP Server (`search`) — WebSocket tool exposing FTS results
  - [S-1: WebSocket Server Scaffolding](epics/04-mcp-api/s-1-server-scaffold.md)
  - [S-2: Tool Contract `search`](epics/04-mcp-api/s-2-tool-contract.md)
  - [S-3: FTS Query and Ranking](epics/04-mcp-api/s-3-fts-ranking.md)
  - [S-4: Container Integration](epics/04-mcp-api/s-4-container-integr.md)
- Configuration (`settings.json`) — Single source of truth for runtime
  - [S-1: Schema Definition](epics/05-configuration/s-1-schema.md)
  - [S-2: Loader and Validation](epics/05-configuration/s-2-loader-validate.md)
  - [S-3: Example and Docs](epics/05-configuration/s-3-example-docs.md)
- Usage & Integration — End-to-end steps and troubleshooting
  - [S-1: Usage Flow](epics/06-usage/s-1-usage-flow.md)
  - [S-2: Quick Troubleshooting](epics/06-usage/s-2-troubleshoot.md)

## Conventions
- Keep epics small and shippable; stories include tasks + acceptance.
- Link code and docs changes in PRs to the relevant epic.
