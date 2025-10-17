# Story S-2: Config Loaded From settings.json

## Summary
All services read a single `settings.json` for config.

## Tasks
- Mount `settings.json` into indexer and MCP containers.
- Pass path via env var; validate on start.
- Fail fast with actionable error if missing/invalid.

## Acceptance
- Missing file exits with clear message.
- Valid file loads; values reflected in logs.

