# Story S-1: Compose Stack Starts Services

## Summary
Compose stack for `postgres`, `indexer-ruby`, and `mcp-ruby` with volumes and port 8765.

## Tasks
- Define services, shared network, persistent Postgres volume.
- Expose MCP on `8765`; set required env vars.
- Provide `docker compose logs -f indexer-ruby mcp-ruby` usage.

## Acceptance
- `docker compose up -d` runs cleanly.
- Logs show indexer and MCP ready without errors.

