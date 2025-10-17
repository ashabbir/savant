# Story S-1: Postgres-Only Simplification

## Summary
Remove non-Postgres options and simplify configuration to rely solely on Postgres FTS.

## Tasks
- Drop unused `api` config and any vector/embedding flags from settings and schema.
- Update loader validation to the new schema.
- Ensure Compose and code paths assume Postgres for all persistence and search.
- Refresh example config and docs to reflect Postgres-only.

## Acceptance
- Config validates without `api` and without `useVectors`.
- Example runs with `docker compose up -d` and `bin/db_smoke`.
- README epics marks this story completed.

