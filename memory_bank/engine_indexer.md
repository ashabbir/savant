# Indexer Engine

## Overview
Scans configured repositories, dedupes file blobs by hash, chunks content, and persists searchable chunks into Postgres with FTS. Skips hidden/binary/oversized/unchanged files and respects .gitignore patterns.

## Key Files
- `lib/savant/engines/indexer/runner.rb`: Orchestrates scans and DB upserts
- `lib/savant/engines/indexer/repository_scanner.rb`: Repo/file traversal + ignore handling
- `lib/savant/engines/indexer/blob_store.rb`: SHA256 dedupe + blob writes
- `lib/savant/engines/indexer/chunker/{code,markdown}.rb`: Chunking strategies
- `lib/savant/engines/indexer/config.rb`: Indexer config loader (languages, limits, chunk sizes)
- `lib/savant/engines/indexer/cache.rb`: Change cache (.cache/indexer.json)
- `lib/savant/engines/indexer/instrumentation.rb`: Timing + counters
- Context entrypoint: `lib/savant/engines/context/fs/repo_indexer.rb`

## Data Flow
1. Load repos from `config/settings.json`
2. Merge ignore patterns: `.gitignore` + `.git/info/exclude`
3. Skip: hidden, binary, > maxFileSizeKB, or unchanged by mtime/size/hash
4. Blob dedupe by SHA256; upsert `blobs`
5. Chunk content (code by lines with overlap; markdown by chars)
6. Upsert `files`, map `file_blob_map`, replace `chunks`
7. Cleanup: delete missing files for the repo

## DB Model
- `repos(id,name,root_path)`
- `files(id,repo_id,repo_name,rel_path,size_bytes,mtime_ns)` unique `(repo_id, rel_path)`
- `blobs(id,hash,byte_len)` unique `hash`
- `file_blob_map(file_id,blob_id)` PK `file_id`
- `chunks(id,blob_id,idx,lang,chunk_text)` + GIN FTS on `to_tsvector('english', chunk_text)`

## CLI & Make Targets
- `./bin/context_repo_indexer index all|<repo>`
- `./bin/context_repo_indexer delete all|<repo>`
- `./bin/context_repo_indexer status`
- `make repo-index-all`, `make repo-index-repo repo=<name>`, `make repo-status`

## Config
`config/settings.json` → `indexer`: `maxFileSizeKB`, `languages`, `chunk` (`codeMaxLines`,`overlapLines`,`mdMaxChars`), and `repos[]`.

## Notes
- Language from file extension with optional allowlist.
- Change cache accelerates re-runs; delete `.cache/indexer.json` to force.
- Timing and slow-op flags via `Savant::Logging::Logger`.

