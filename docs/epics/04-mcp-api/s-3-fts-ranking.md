# Story S-3: FTS Query and Ranking

## Summary
Use Postgres FTS to query `chunks` and rank results.

## Tasks
- `plainto_tsquery`/`to_tsvector` query; order by rank; limit N.
- Join with `files` to include `rel_path`.

## Acceptance
- Results are relevant and ordered; limit respected.

