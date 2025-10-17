# Story S-3: FTS Index

## Summary
Create `GIN` index on `to_tsvector('english', chunk_text)`.

## Tasks
- Add FTS index and verify usage with EXPLAIN.
- Provide sample query for smoke test.

## Acceptance
- Search uses index; ranking available.

