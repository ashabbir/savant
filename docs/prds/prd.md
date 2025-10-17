
# AI Context System — Local Repo Indexer + MCP Search Layer (Ruby + Docker, FTS-Only)

Project code name: savant

## 🚀 MVP Definition (Phase 1 — Must Ship)

The MVP delivers a working local AI context system with **only these capabilities**:

1. **Startup & Config**
   - Run `docker compose up -d` to start:
     - Postgres database container
     - Ruby Indexer container (manual run via `index all`)
     - Ruby MCP Server container (WebSocket on `localhost:8765`)
   - All configuration is pulled from a single `settings.json`.

2. **Indexing (On-Demand, One-Time per Command)**
   - Command: `index all` (or `index <repoName>`)
   - Behavior:
     - Scan configured repos recursively from settings.json.
     - Apply ignore rules (node_modules/**, .git/**, dist/**, etc).
     - For each file:
       - Use `(file size + mtime_ns)` to detect change.
       - If changed → compute fast hash (xxh3 or SHA256).
         - If hash not seen before → chunk and store blob.
         - If hash exists → reuse chunks but update mapping.
     - No automatic watching. Re-run `index all` whenever needed.

3. **Database**
   - Postgres 16, using Ruby `pg` gem.
   - Tables:
     - `repos`
     - `files`
     - `blobs`
     - `file_blob_map`
     - `chunks`
   - FTS enabled on `chunks.chunk_text` via `tsvector` + `GIN`.

4. **MCP API (Single Tool: `search`)**
   - Ruby WebSocket server using `async-websocket` + `pg` gem.
   - MCP contract:
     - Tool Name: `search`
     - Input: `{ q: string, repo?: string, limit?: number }`
     - Output: Chunk list with fields `{ rel_path, chunk, lang, score }`
   - No `byPath`, no `recentChanges`, no UI in MVP.

5. **Usage Flow**
   - Edit `settings.json` with repo paths.
   - Run `docker compose up -d`
   - Run `index all`
   - Configure **Cline MCP endpoint** to `ws://localhost:8765`
   - Query via:
     ```
     search("Panko serializer")
     ```
     → returns chunks from local code.

🎯 MVP is considered successful when:
> "I can ask Cline via MCP to search a class/method, and it returns code chunks from my actual repositories, indexed locally and served via Ruby MCP, with zero cloud dependency."

---

## 🎛 Configuration — `settings.json`

Example structure:

````

{
"api": {
"token": "OPTIONAL_FOR_LATER",
"provider": "none",
"useForEmbeddings": false
},
"indexer": {
"maxFileSizeKB": 512,
"languages": ["rb", "ts", "tsx", "js", "md", "mdx", "yml", "yaml", "json"],
"chunk": {
"mdMaxChars": 1200,
"codeMaxLines": 200,
"overlapLines": 3
}
},
"repos": [
{
"name": "icn",
"path": "/host/icn-backend",
"ignore": ["node_modules/**", "tmp/**", "vendor/**", "log/**", ".git/**", ".next/**", "dist/**"]
},
{
"name": "appserve",
"path": "/host/appserve",
"ignore": ["node_modules/**", ".next/**", "dist/**", ".git/**"]
}
],
"mcp": {
"listenHost": "0.0.0.0",
"listenPort": 8765,
"allowOrigins": ["*"]
},
"database": {
"host": "postgres",
"port": 5432,
"db": "contextdb",
"user": "context",
"password": "contextpw",
"useVectors": false
}
}

```

---

## 📌 Tech Stack (Locked)

- **Language:** Ruby 3.2+
- **Indexer:** Ruby CLI using:
  - `pg`, `json`, `digest` or `xxhash`, `find` or `Dir.glob`
- **MCP Server:** Ruby WebSocket using:
  - `async`, `async-websocket`, `protocol-websocket`, `pg`, `json`
- **Container base image:** `ruby:3.3-alpine`
- **Database:** Postgres 16 with FTS only (`tsvector`, `GIN`, `pg_trgm`)
- **No embeddings**, no vector search, no background fs watchers in MVP.

---

## 🔁 Indexer Algorithm

- For each repo:
  - Recursively walk files (respect ignore globs).
  - Skip files > `maxFileSizeKB`.
  - If `(mtime_ns + size)` unchanged → skip.
  - Else compute hash:
    - If hash new → read, chunk, insert blob + chunks.
    - Else → reuse existing blob ID.
  - Update `file_blob_map` to map current `rel_path → blob_id`.
- Remove mappings for files no longer on disk.
- Chunks linked to blobs → dedup across rebuilds.

---

## 🗂 Database Schema Summary

Tables:

| Table           | Purpose |
|----------------|--------|
| `repos`          | Stores registered repo names & root paths. |
| `files`          | One row per current file path. |
| `blobs`          | One row per unique file content (hash-based). |
| `file_blob_map`  | Current path → blob mapping. |
| `chunks`         | Chunked text tied to blob_id, with `chunk_text` field indexed for FTS. |

FTS:
- Create `GIN` index on `to_tsvector('english', chunks.chunk_text)`.

---

## 🔌 MCP Method — MVP Scope

### `search`
- **Input**:
```

{ "q": "string", "repo": "optional string", "limit": optional number }

```
- **Output**: JSON array:
```

[{
"rel_path": "app/models/user.rb",
"lang": "rb",
"chunk": "...",
"score": 0.85
}]

```

---

## 🐳 Docker Compose Stack

Services:
- `postgres` (persistent with volume)
- `indexer-ruby` (CLI container)
- `mcp-ruby` (WebSocket server, port 8765)

Usage:
```

docker compose up -d
docker compose logs -f indexer-ruby mcp-ruby
docker compose run --rm indexer-ruby index all

```

---

## 🎯 Performance Targets

| Metric | Target |
|--------|--------|
| Cold index 200k LOC | ≤ 3 minutes |
| Re-run `index all` after small change | ≤ 5 seconds (due to hash dedupe) |
| MCP `search()` latency | < 150 ms per request |

---

## 🚧 Future (Not in MVP)

- Watching filesystem / auto-index on save
- `byPath`, `recentChanges` MCP methods
- Embeddings + vector hybrid search
- Web UI viewer for chunks
- Symbol index (`bySymbol(className)`)

---

## ✅ Acceptable Delivery Criteria

- Repo contains:
  - `docker-compose.yml`
  - `/indexer` Ruby CLI
  - `/mcp` Ruby WebSocket MCP service
  - `settings.json.example`
  - `PRD.md` (this document)
- Running `docker compose up -d` + `index all` makes **MCP search functional in Cline**.
- MCP returns actual code chunks from local repos with full-text relevance.

---
