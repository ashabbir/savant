# Database Model

## Overview
Postgres schema supporting repository indexing and FTS-backed search. Designed for fast, deduplicated chunk retrieval across repos and files.

## Tables
- `repos(id, name, root_path)`
- `files(id, repo_id, repo_name, rel_path, size_bytes, mtime_ns)` unique `(repo_id, rel_path)`
- `blobs(id, hash, byte_len)` unique `hash`
- `file_blob_map(file_id, blob_id)` primary key `file_id`
- `chunks(id, blob_id, idx, lang, chunk_text)` GIN index on `to_tsvector('english', chunk_text)`

## FTS
- Language: English dictionary for MVP
- Query expansion and ranking handled in engine ops (`context/fts.rb`)

## Migrations & FTS Setup
```
./bin/db_migrate  # create/reset schema (destructive)
./bin/db_fts      # ensure FTS index
./bin/db_smoke    # basic connectivity + sanity checks
```

## Context Engine Queries
- See `lib/savant/engines/context/fts.rb` for search query, ranking, and result mapping `[rel_path, chunk, lang, score]`.

## Notes
- Keep blob size small by deduping identical content across files
- Replace all chunks for a blob on change to simplify invalidation

