# Savant

Savant is a lightweight Ruby framework for building and running local MCP services. The core boots a single MCP server, loads an engine, and handles transport, logging, config, and dependency wiring. Each engine you mount becomes its own MCP service, so `MCP_SERVICE=context` launches the Context MCP, `MCP_SERVICE=jira` launches the Jira MCP, and custom engines plug in the same way.

## Table of Contents
- Chapter 1 – Introduction
- Chapter 2 – Getting Started
- Chapter 3 – Framework
  - 3.1 Transport Layer
  - 3.2 Tool Registrar and Middleware
  - 3.3 Runtime and Services
- Chapter 4 – Engines
- Chapter 5 – Current Engines
  - 5.1 Context
  - 5.2 Jira
- Chapter 6 – Scaffolding an Engine
- Chapter 7 – IDE Integration
- Chapter 8 – Additional Information
- Chapter 9 – Future Work

## Chapter 1 – Introduction
- What Savant is: a small, focused framework to build MCP-compatible services that run locally and speak JSON-RPC over stdio or HTTP.
- Problems it solves: consistent transport, robust logging, strict schemas, and editor-friendly integration without exposing secrets or raw DB access.
- High-level architecture: optional Indexer writes repo content into Postgres; engines expose tools; the framework hosts exactly one engine per server process.
- When to use: need fast private code search or Jira access via MCP; want a minimal Ruby stack with batteries-included DX.

## Chapter 2 – Getting Started
- Prerequisites: Ruby + Bundler, Docker (optional), Postgres (local or Docker).
- Configure settings: copy `config/settings.example.json` to `config/settings.json` and adjust repos, DB URL, and engine settings. See `config/schema.json`.
- Start an engine (stdio, default):
  ```bash
  # DB + FTS (if using Context)
  make migrate && make fts
  # Index repos (Context)
  make repo-index-all
  # Run server (stdio)
  MCP_SERVICE=context bundle exec ruby ./bin/mcp_server
  ```
- Start an engine (HTTP transport):
  ```bash
  MCP_SERVICE=context LISTEN_HOST=0.0.0.0 LISTEN_PORT=8765 \
    bundle exec ruby ./bin/mcp_server --http
  ```
- Start via Docker (Postgres + Indexer):
  ```bash
  docker compose build && make dev
  make repo-index-all
  ```
- Quick verification: run `make mcp-test q='User'` or invoke a JSON-RPC call against the HTTP endpoint.

## Chapter 3 – Framework
- What it is: a host for a single active engine that provides transport, tool registration, config, logging, and optional DB wiring.
- Why it’s needed: normalizes MCP boilerplate, encourages strict schemas and observability, and makes engines portable across editors and runtimes.
- How it helps: stdio/HTTP transports, a declarative tool DSL with middleware, simple DI for config/logger/db, and structured logs.

Framework Logger
- JSON by default to stdout; per-engine and core file sinks are optional.
- Levels: trace, debug, info, warn, error. Helper: `with_timing`.
- Configure in `config/settings.json` under `logging`:
  - `level`: "info" | "debug" | "trace" | "warn" | "error"
  - `format`: "json" | "text"
  - `stdout_enabled`: true by default
  - `core_file_path`: optional (e.g., `logs/savant.log`)
  - `engine_file_path`: optional dir or file; dir yields `logs/<engine>.log`

### 3.1 Transport Layer
- Stdio JSON-RPC 2.0 compatible with editors like Cline/Claude Code.
- HTTP JSON-RPC optional mode for network testing and service embedding. See Chapter 7 for end-to-end HTTP example and curl snippet.
- WebSocket transport supported with JSON-RPC framing over ws://. See Chapter 7 for a minimal WebSocket client example.

### 3.2 Tool Registrar and Middleware
- Tool DSL: declare `tool 'ns/name'` with JSON schema and Ruby handler.
- Middleware: layer validation, timing, logging, and auth consistently.

### 3.3 Runtime and Services
- Engine loading via `MCP_SERVICE=<engine>`; convention maps to `lib/savant/<engine>`.
- Engine DI: `db`, `config`, `logger` accessible inside handlers.

## Chapter 4 – Engines
- What engines are: self-contained MCP implementations exposing tools (namespaces, schemas, handlers).
- Why they exist: separation of concerns, reuse, and clean integration with editors.
- How to start: select via `MCP_SERVICE`, set required env vars, then run `bin/mcp_server`.
- Benefits: encapsulation of domain logic, consistent transport, and easy local-first workflows.

## Chapter 5 – Current Engines

### 5.1 Context
- Purpose: Fast, ranked repo search via Postgres FTS populated by the Indexer.
- Workflow: Indexer scans repos, dedupes blobs, chunks content, writes to DB; Context engine queries FTS and returns ranked snippets.

Variables (env/config)

| Key | Purpose | Example/Default |
|---|---|---|
| `DATABASE_URL` | Postgres connection string | `postgres://context:contextpw@localhost:5432/contextdb` |
| `SETTINGS_PATH` | Config path | `config/settings.json` |
| `SAVANT_PATH` | Repo base for logs/config | `./` |
| `LOG_LEVEL` | Logging level | `info` |
| `LISTEN_HOST` | HTTP transport host | `0.0.0.0` |
| `LISTEN_PORT` | HTTP transport port | `8765` |

Make commands

| Command | Description | Example |
|---|---|---|
| `make migrate` | Recreate DB schema | `make migrate` |
| `make fts` | Ensure FTS index | `make fts` |
| `make repo-index-all` | Index all repos | `make repo-index-all` |
| `make repo-status` | Show per-repo stats | `make repo-status` |
| `make mcp-test` | Test FTS search | `make mcp-test q='User' [repo=<name>] [limit=5]` |

Ruby commands

| Command | Purpose |
|---|---|
| `bundle exec ruby ./bin/mcp_server` (with `MCP_SERVICE=context`) | Run Context MCP over stdio |
| `bundle exec ruby ./bin/mcp_server --http` | Run HTTP JSON-RPC (use `LISTEN_HOST/PORT`) |

Docker commands

| Command | Purpose |
|---|---|
| `docker compose build && make dev` | Build containers and start Postgres |
| `make repo-index-all` | Index repos in containers |

### 5.2 Jira
- Purpose: Jira JQL search and self-check tools via Jira REST v3.
- Workflow: Engine calls Jira REST with credentials from env or config; returns issues and metadata.

Variables (env/config)

| Key | Purpose | Example/Default |
|---|---|---|
| `JIRA_BASE_URL` | Jira base URL | `https://your.atlassian.net` |
| `JIRA_EMAIL` / `JIRA_API_TOKEN` | Jira Cloud credentials | — |
| `JIRA_USERNAME` / `JIRA_PASSWORD` | Jira Server credentials | — |
| `JIRA_CONFIG_PATH` | Path to Jira config JSON | `config/jira.json` |
| `LOG_LEVEL` | Logging level | `info` |

Make commands

| Command | Description | Example |
|---|---|---|
| `make jira-test` | Run a JQL search | `make jira-test jql='project = ABC order by updated desc' [limit=10]` |
| `make jira-self` | Verify auth | `make jira-self` |

Ruby commands

| Command | Purpose |
|---|---|
| `MCP_SERVICE=jira bundle exec ruby ./bin/mcp_server` | Run Jira MCP over stdio |

Docker commands

| Command | Purpose |
|---|---|
| `docker compose run --rm -T mcp-jira` | Run in a container (if defined) |

## Chapter 6 – Scaffolding an Engine
- Use the generator CLI to scaffold a new engine and optional DB wiring:
  ```bash
  bundle exec ruby ./bin/savant generate engine myengine [--with-db]
  ```
- Resulting layout: `lib/savant/myengine/{engine.rb,ops.rb,tools.rb}` with registrar, schemas, and handlers.
- Add tools: declare with the DSL, provide JSON schema, implement handler in `ops`.
- Test and run: `bundle exec rubocop -A` and `bundle exec rspec` (if present), then run with `MCP_SERVICE=myengine`.

## Chapter 7 – IDE Integration
- Overview: Editors launch Savant as a child process and communicate via stdio using JSON-RPC 2.0. No ports required. Alternatively, you can run HTTP mode for testing.

### Cline (VS Code) – Stdio
- Settings JSON example (User or Workspace settings):
  ```jsonc
  {
    "cline.mcpServers": {
      "Savant (Context)": {
        "command": "bash",
        "args": ["-lc", "MCP_SERVICE=context SAVANT_PATH=${workspaceFolder} DATABASE_URL=postgres://context:contextpw@localhost:5432/contextdb bundle exec ruby ./bin/mcp_server"],
        "env": {
          "LOG_LEVEL": "info"
        }
      },
      "Savant (Jira)": {
        "command": "bash",
        "args": ["-lc", "MCP_SERVICE=jira SAVANT_PATH=${workspaceFolder} bundle exec ruby ./bin/mcp_server"],
        "env": {
          "JIRA_BASE_URL": "https://your.atlassian.net"
        }
      }
    }
  }
  ```
- How it runs: Cline spawns the command, sends JSON-RPC over stdio, and lists tools from `tools/list`. Your queries route to `tools/call`.

### Cline (VS Code) – Docker
- Use containers defined in `docker-compose.yml` to keep deps isolated:
  ```jsonc
  {
    "cline.mcpServers": {
      "Savant (Context-Docker)": {
        "command": "docker",
        "args": ["compose", "run", "--rm", "-T", "mcp-context"]
      },
      "Savant (Jira-Docker)": {
        "command": "docker",
        "args": ["compose", "run", "--rm", "-T", "mcp-jira"]
      }
    }
  }
  ```
- How it runs: Cline talks stdio to the container’s process. Compose mounts your repo and injects env per service config.

### Claude Code (VS Code)
- Settings example (may vary by version):
  ```jsonc
  {
    "mcpServers": {
      "savant-context": {
        "command": "bash",
        "args": ["-lc", "MCP_SERVICE=context SAVANT_PATH=${workspaceFolder} DATABASE_URL=postgres://context:contextpw@localhost:5432/contextdb bundle exec ruby ./bin/mcp_server"]
      },
      "savant-jira": {
        "command": "bash",
        "args": ["-lc", "MCP_SERVICE=jira SAVANT_PATH=${workspaceFolder} bundle exec ruby ./bin/mcp_server"]
      }
    }
  }
  ```
- How it runs: Claude Code launches the process and communicates via stdio. Tools appear in its MCP panel; invoke them directly or via chat.

### GPT/Codex-style MCP Clients
- Stdio mode (preferred): run `MCP_SERVICE=<engine> bundle exec ruby ./bin/mcp_server` and configure the client to connect via stdio.
- HTTP mode (optional for testing): run `bundle exec ruby ./bin/mcp_server --http` with `LISTEN_HOST/PORT`, then point your client at the JSON-RPC endpoint.
- How it talks: the client sends `initialize`, then `tools/list` and `tools/call` per the MCP/JSON-RPC contract.

### Quick Start Checklist
- Ensure `config/settings.json` exists and Postgres is reachable (for Context).
- Verify indexing completed: `make repo-status` and `make repo-index-all` if needed.
- Use stdio commands in your editor settings; prefer absolute DB URLs in dev.
- Check logs under `logs/<service>.log` or console for troubleshooting.

### HTTP Transport Example
- Start server (Context) over HTTP:
  ```bash
  MCP_SERVICE=context LISTEN_HOST=0.0.0.0 LISTEN_PORT=8765 \
    bundle exec ruby ./bin/mcp_server --http
  ```
- Call a tool via curl:
  ```bash
  curl -s http://localhost:8765/jsonrpc \
    -H 'content-type: application/json' \
    -d '{
      "jsonrpc":"2.0",
      "id":1,
      "method":"tools/call",
      "params":{
        "name":"fts/search",
        "arguments":{"q":"User","limit":5}
      }
    }'
  ```
- Expected response: JSON-RPC 2.0 with `result` containing hits.

### WebSocket Transport Example
- Start server (Context) over WebSocket:
  ```bash
  MCP_SERVICE=context LISTEN_HOST=127.0.0.1 LISTEN_PORT=8765 \
    bundle exec ruby ./bin/mcp_server --websocket
  ```
- Connect with a WebSocket client (Node.js example):
  ```js
  import WebSocket from 'ws';

  const ws = new WebSocket('ws://127.0.0.1:8765/jsonrpc');
  ws.on('open', () => {
    ws.send(JSON.stringify({
      jsonrpc: '2.0', id: 1, method: 'tools/list'
    }));
  });
  ws.on('message', (msg) => {
    console.log('message:', msg.toString());
  });
  ```
- Message format: same JSON-RPC payloads as HTTP; path `/jsonrpc` by default.

## Chapter 8 – Additional Information
- Project layout: `docs/`, `config/`, `bin/`, `docker-compose.yml`; generator at `bin/savant`.
- Database notes: run `make migrate && make fts`; index with `make repo-index-all`.
- Ports: Context `8765`, Jira `8766` (for HTTP mode and Docker debugging; stdio does not require ports).
- Troubleshooting: tail with `make logs`; ensure `chmod +x bin/*`; reset DB with `docker compose down -v` then `make dev && make migrate && make fts`.

## Chapter 9 – Future Work
- Upcoming features informed by PRDs: richer resources and memory bank, improved editor UX, additional transports and auth strategies.
- Roadmap: stability of core framework, more built-in tools, and expanded scaffolding options.

## Chapter 1 – Introduction

### Core Concepts
- **Savant Framework** – Provides the stdio JSON-RPC 2.0 transport, tool registrar,
  middleware, logging, and config loading. The framework is engine-agnostic: it just
  mounts whatever engine you name via `MCP_SERVICE`.
- **Engines** – Self-contained MCP implementations that expose tools. Savant ships with
  two engines out of the box:
  - `context` MCP for repo indexing and retrieval.
  - `jira` MCP for Jira REST search and CRUD.
  Custom engines live under `lib/savant/<engine>` and are mounted automatically by name.
- **Indexer** – Optional companion that ingests repos into Postgres FTS for the Context
  engine. Engines that need persistence can share the same DB plumbing.

## Chapter 2 – Building Engines

### Building Engines with Savant
- Tool DSL: declare `tool 'ns/name'` with JSON schema and a Ruby handler.
- Registrar + middleware stack: register tools and layer validation, logging, or auth.
- Dynamic service loading: `MCP_SERVICE=<engine>` auto-loads
  `lib/savant/<engine>/{engine,tools}.rb`.
- Engine-owned DI: share `db`, `logger`, and `config` through the engine instance and
  pass them to handlers as context.
- Transport: stdio JSON-RPC 2.0 compatible with popular MCP editor clients.

### Generator
- Scaffold a new engine with the CLI:
  - Create engine + tools + spec skeletons:
    - `bundle exec ruby ./bin/savant generate engine <name>`
    - Make: no target (CLI only)
    - Options:
      - `--with-db`: include a shared `Savant::DB` handle in the engine constructor.
      - `--force`: overwrite existing files.
  - Generated files:
    - `lib/savant/<name>/engine.rb` with `server_info` metadata (name, version, description)
    - `lib/savant/<name>/tools.rb` using the Tool DSL with an example `'<name>/hello'` tool
    - `spec/savant/<name>/engine_spec.rb` exercising the example tool

### Mounting an Engine
- Convention-based mounting — no server code changes required:
  - Files at `lib/savant/<engine>/engine.rb` and `lib/savant/<engine>/tools.rb`
  - Engine class: `Savant::<CamelCase>::Engine`
  - Tools module: `Savant::<CamelCase>::Tools.build_registrar(engine)`
  - Start the MCP server for an engine:
    - `MCP_SERVICE=<engine> ruby ./bin/mcp_server`
    - Make: `make mcp-test q='<term>'` (Context helper)
  - The server uses engine-provided `server_info` for the MCP `initialize` response.

### Using Engines in Editors
- Cline / Claude Code MCP
  - Configure a custom MCP with stdio command:
    - Command: `ruby ./bin/mcp_server`
    - Env:
      - `MCP_SERVICE=context`
      - `DATABASE_URL=postgres://context:contextpw@localhost:5433/contextdb`
      - Optional: `SAVANT_PATH=$(pwd)`
  - Tools available (Context): `fts/search`, `memory/search`, `memory/resources/*`, `fs/repo/*`.
  - Make: `make mcp-test q='<term>' [repo=<name>] [limit=5]`

- WebSocket transport (optional)
  - Start the server in WebSocket mode (default host/port/path):
    - `MCP_SERVICE=context ruby ./bin/mcp_server --transport=websocket`
  - Override host/port/path:
    - `ruby ./bin/mcp_server --transport=websocket --host=127.0.0.1 --port=8765 --path=/mcp`
  - Configure via `config/settings.json` (optional):
    - `transport: { mode: "websocket", websocket: { host: "127.0.0.1", port: 8765, path: "/mcp" } }`

### Environment Variables (Engines)
- Common
  - `MCP_SERVICE`: selects the engine to mount (e.g., `context`, `jira`).
  - `SAVANT_PATH`: base path for resolving `config/settings.json` and `logs/` (defaults to repo root).
  - `SETTINGS_PATH`: optional override for settings JSON when using library APIs.
  - `LISTEN_HOST` / `LISTEN_PORT`: reserved for network transports; stdio ignores these.
  - `LOG_LEVEL`: `debug|info|warn|error` (default `info`).
  - `SLOW_THRESHOLD_MS`: marks slow operations in logs when exceeded (optional).
- Engine-specific
  - Context requires `DATABASE_URL` for Postgres.
  - Jira requires Jira credentials; see “Jira” engine section below.

### Raw MCP (no Docker)
- Run Postgres locally or point to an existing instance.
- Prepare DB and FTS index:
  - `DATABASE_URL=... ruby ./bin/db_migrate` (destructive reset)
  - `DATABASE_URL=... ruby ./bin/db_fts`
  - Make: `make migrate && make fts`
- Index your repos:
  - `DATABASE_URL=... ruby ./bin/context_repo_indexer index all`
  - Make: `make repo-index-all`
- Start MCP server (stdio):
  - `MCP_SERVICE=context DATABASE_URL=... ruby ./bin/mcp_server`
  - Use any JSON-RPC client to send `initialize`, `tools/list`, `tools/call`.
  - Make: `make mcp-test q='<term>' [repo=<name>] [limit=5]`
  - Env quick reference:
    - `MCP_SERVICE=context`
    - `DATABASE_URL=postgres://user:pass@host:port/db`
    - Optional: `SAVANT_PATH=$(pwd)`, `LOG_LEVEL=debug`

## Chapter 3 – Running Savant

### Overview
- Savant framework: single MCP server process that mounts one engine by name.
- Built-in engines: Context MCP (repo indexing/search) and Jira MCP (Jira REST access).
- Indexer + Postgres power the Context engine’s search pipeline; Jira engine talks to Jira REST.
- Docs: see `docs/README.md` and `config/` examples.

### Runtime Modes
- Docker (Postgres + Indexer), host (MCP servers): Postgres and the indexer run in Docker; MCP servers run on your host.
- Host-only (advanced): You may run everything on host if you configure Postgres separately.

### HTTP Transport
- Savant can expose tools via JSON-RPC over HTTP instead of stdio.
- Start the server:
  - `MCP_SERVICE=context MCP_TRANSPORT=http bundle exec ruby ./bin/savant serve`
  - Options:
    - `--transport=http`: CLI override for transport (defaults to env).
    - `--port=<PORT>` / `SAVANT_PORT`: choose listening port (default `9292`).
    - `--host=<HOST>` / `SAVANT_HOST`: bind interface (default `0.0.0.0`).
- Endpoints:
  - `POST /rpc`: accepts JSON-RPC 2.0 payload `{ "method": "tool/ns", "params": {...}, "id": <uuid> }`.
  - `GET /healthz`: replies `{ "status": "ok", "service": "savant-http" }`.
- Example call:
  ```bash
  curl -X POST http://localhost:9292/rpc \
    -H 'Content-Type: application/json' \
    -d '{"method":"logger.log","params":{"message":"Hello"},"id":1}'
  ```
  Response:
  ```json
  {"jsonrpc":"2.0","result":{"ok":true},"error":null,"id":1}
  ```
- Logs are written to `logs/http.log`; adjust `LOG_LEVEL` for verbosity.

## Chapter 4 – Configuration
- Provide `config/settings.json` (see `config/settings.example.json`, schema in `config/schema.json`).
- Mount host repos in `docker-compose.yml` so the indexer can read them.

### Indexer-Specific Settings
- `indexer.maxFileSizeKB`: skip files larger than this (KB)
- `indexer.languages`: allowed file extensions (lowercase); others are skipped
- `indexer.chunk`: `{ mdMaxChars, codeMaxLines, overlapLines }`
- `indexer.repos`: list of repos (`{ name, path, ignore[] }`)
- `indexer.scanMode` (optional): `auto | git | walk` (default `auto`)
  - `auto`: prefer Git if the repo has a `.git` directory and `git` is available; else walk the filesystem
  - `git`: force Git enumeration; falls back to walking if git fails
  - `walk`: force filesystem walk
- Per-repo override: each repo can optionally set its own `scanMode`

### Environment Variables
- Common
  - `SAVANT_PATH`: project root (for logs); defaults to repo root if not set
  - `DATABASE_URL`: Postgres connection URL (Context service)
  - `MCP_SERVICE`: selects the active service (`context` or `jira`)
- Context
  - Uses `DATABASE_URL` for DB; reads repo config from `config/settings.json` under project root
- Jira
  - `JIRA_BASE_URL`: e.g., `https://your.atlassian.net`
  - Jira Cloud: `JIRA_EMAIL` + `JIRA_API_TOKEN`
  - Jira Server/DC: `JIRA_USERNAME` + `JIRA_PASSWORD`
  - `JIRA_ALLOW_WRITES`: set to `true` to enable mutating tools


### Project Layout
- `docs/`: epics, PRD, ops notes
  - Memory Bank: see `docs/prds/memory-bank-resources.md`
- `config/`: settings and examples
- `bin/`: CLIs for index/DB/MCP
- `bin/savant`: generator CLI to scaffold new MCP engines
- `docker-compose.yml`: services and volumes

### Jira Configuration
- Option A: Env vars (quick start)
  - `JIRA_BASE_URL`, and either `JIRA_EMAIL` + `JIRA_API_TOKEN` (Cloud) or `JIRA_USERNAME` + `JIRA_PASSWORD` (Server).
  - Add to your shell or `.env` (Compose auto-loads `.env`).

- Option B: Config file (recommended)
  - Create `config/jira.json` from `config/jira.example.json`.
  - Compose mounts it and sets `JIRA_CONFIG_PATH=/app/config/jira.json` automatically.
  - File schema:
    - `baseUrl`: Jira base URL
    - `email` + `apiToken` (Cloud) or `username` + `password` (Server)
    - `fields`: optional list of fields to return
  - Env vars still work and are used as fallback. Precedence: config file > env > defaults.

Example file is provided at `config/jira.example.json`.


## Chapter 5 – Built-in Engines

### Running Engines (Host)

### Problem
- Tools and editors need a standard interface to local context search and Jira without exposing secrets or raw DB access.

### Solution
- Two Savant engines: Context (search via Postgres FTS) and Jira (JQL via Jira REST), both speaking MCP over stdio (JSON‑RPC 2.0) for easy client integration.

### Approach
- Stdio JSON‑RPC transport; strict schemas; timing + size logging for observability.
- Context MCP depends on DB; Jira MCP depends on Jira credentials or config file.



### Context Engine (Context MCP)

Problem
- Expose fast, ranked repo search to MCP-aware clients.

Solution
- `tool: fts/search` backed by Postgres FTS in the same DB the indexer maintains.

Approach
- Accept requests over stdio (JSON‑RPC); sanitize inputs; log timings and payload sizes; return hits with metadata/snippets.

Diagram
```mermaid
sequenceDiagram
  participant IDE as Client
  participant MCP as Context MCP
  participant DB as Postgres + FTS
  IDE->>MCP: tool fts/search(q, repo?, limit)
  MCP->>DB: FTS query + rank
  DB-->>MCP: hits + snippets
  MCP-->>IDE: results
```

Commands
- Run on host: `MCP_SERVICE=context SAVANT_PATH=$(pwd) DATABASE_URL=postgres://context:contextpw@localhost:5433/contextdb SETTINGS_PATH=config/settings.json ruby ./bin/mcp_server`
- Test: ``make mcp-test q='User' repo=<name> limit=5`` (runs host MCP against Docker Postgres)

### Adding a new MCP Service
- Scaffold with the generator:
  - `bundle exec ruby ./bin/savant generate engine <name>`
  - Options: `--with-db` to include a shared DB handle; `--force` to overwrite existing files.
- Files created:
  - `lib/savant/<name>/engine.rb` with `server_info` metadata
  - `lib/savant/<name>/tools.rb` using the MCP DSL (`build_registrar`)
  - `spec/savant/<name>/engine_spec.rb` with an example tool test
- Run the service:
  - `MCP_SERVICE=<name> ruby ./bin/mcp_server`
  - tools/list and tools/call route via the service’s registrar (no server code changes needed)

Memory Bank tools
- `tool: memory/search` — search markdown under `**/memory_bank/**` stored in DB FTS.
- `tool: memory/resources/list` — list memory bank resources (filesystem helper for browsing).
- `tool: memory/resources/read` — read a memory bank resource via `repo://<repo>/memory-bank/<path>`.

Tools
- fts/search: Full‑text search over indexed chunks via Postgres FTS.
  - Input: `{ q: string, repo?: string | string[], limit?: number }`
  - Output: `[ { repo, rel_path, chunk, lang, score } ]`
- memory/search: Full‑text search over memory_bank chunks in DB FTS.
  - Input: `{ q: string, repo?: string | string[], limit?: number }`
  - Output: `[ { repo, rel_path, chunk, lang, score } ]`
- memory/resources/list: List memory bank resources (filesystem helper).
  - Input: `{ repo?: string }`
  - Output: `[ { uri, mimeType, metadata: { path, title, modified_at, source } } ]`
- memory/resources/read: Read a memory bank resource by URI.
  - Input: `{ uri: string }` (e.g., `repo://<repo>/memory-bank/<path>`)
  - Output: `text`

#### Indexer (Context Engine)

##### Indexer Problem
- Large, evolving repos need fast local indexing with minimal overhead and zero data exfiltration.
- Keeping search results fresh requires reliable change detection and efficient upserts.

##### Indexer Solution
- Ruby indexer scans configured repos, hashes and deduplicates content, chunks intelligently, and stores everything in Postgres with FTS.

##### Indexer Approach
- Ignore rules and size limits keep noise low and runs deterministic.
- Hash + dedupe at blob level minimizes DB churn; chunking preserves context with overlaps.
- Postgres FTS (`tsvector` + GIN) powers ranking; counters and timestamps help status/health.
- Config-driven: repos and rules live in `config/settings.json`.

##### Indexer Diagram
```mermaid
flowchart LR
  R["Repos (host mounts)"] --> I["Indexer CLI<br/>scan → hash → chunk"]
  I --> DB["Postgres 16<br/>FTS tsvector + GIN"]

  classDef svc fill:#f0f7ff,stroke:#1e88e5,color:#0d47a1,stroke-width:1px
  classDef data fill:#f9fbe7,stroke:#7cb342,color:#33691e,stroke-width:1px
  class I svc
  class DB data
```

##### Indexer Commands

- Without Docker:
  - Migrate (destructive reset): `DATABASE_URL=postgres://context:contextpw@localhost:5432/contextdb SETTINGS_PATH=config/settings.json ruby ./bin/db_migrate`
  - FTS: `DATABASE_URL=... SETTINGS_PATH=... ruby ./bin/db_fts`
  - Smoke: `DATABASE_URL=... SETTINGS_PATH=... ruby ./bin/db_smoke`
  - Index all: `DATABASE_URL=... SETTINGS_PATH=... ruby ./bin/context_repo_indexer index all`
  - Index repo: `DATABASE_URL=... SETTINGS_PATH=... ruby ./bin/context_repo_indexer index <repo>`
  - Delete all: `DATABASE_URL=... SETTINGS_PATH=... ruby ./bin/context_repo_indexer delete all`
  - Delete repo: `DATABASE_URL=... SETTINGS_PATH=... ruby ./bin/context_repo_indexer delete <repo>`
  - Status: `DATABASE_URL=... SETTINGS_PATH=... ruby ./bin/context_repo_indexer status`
- Notes:
  - CLI start line shows configured `scanMode`.
  - Per-repo start line shows actual enumeration used: `using=gitls` (Git) or `using=ls` (filesystem).
- With Docker (Postgres + Indexer only):
  - Start stack: `make dev`
  - Migrate: `make migrate`
  - FTS: `make fts`
  - Smoke: `make smoke`
  - Index all: `make repo-index-all`
  - Index repo: `make repo-index-repo repo=<name>`
  - Delete all: `make repo-delete-all`
  - Delete repo: `make repo-delete-repo repo=<name>`
  - Status: `make repo-status`
- Docker image includes `git` to enable Git-based enumeration in containers.
- With Make:
  - `make migrate` · `make fts` · `make smoke`
  - `make repo-index-all` · ``make repo-index-repo repo=<name>``
  - ``make repo-delete-all`` · ``make repo-delete-repo repo=<name>``
  - `make repo-status`

#### Context Engine Details
- Purpose: fast code/doc search and repo indexing using Postgres FTS + chunking
- Tools:
  - `fts/search` · `memory/search` · `memory/resources/*`
  - `fs/repo/index` · `fs/repo/delete` · `fs/repo/status`
- Engine info: name `savant-context`, version `1.1.0` (exposed in MCP initialize)
- Flow (FTS):
```mermaid
flowchart LR
  A[tools/call fts/search] --> B[Context::Engine]
  B --> C[Context::Ops]
  C --> D[Context::FTS]
  D -->|SQL| PG[(Postgres FTS)]
  PG --> D --> C --> B --> A
```
- Flow (Repo Indexer):
```mermaid
flowchart LR
  X[fs/repo/index] --> E[FS::RepoIndexer]
  E --> I[Indexer::Facade]
  I --> R[Runner] --> S[RepositoryScanner]
  R --> DB[(DB writes: files/blobs/chunks)]
```
- Make helpers:
  - `make repo-index-all` · `make repo-index-repo repo=<name>`
  - `make repo-delete-all` · `make repo-delete-repo repo=<name>`
  - `make repo-status`

Environment (Context)
- `DATABASE_URL` (required): Postgres connection for FTS/indexing.
- Optional:
  - `SAVANT_PATH`, `SETTINGS_PATH`, `LOG_LEVEL`, `SLOW_THRESHOLD_MS` (see MCP section).

### Jira Engine (Jira MCP)
- Purpose: Jira issue search and CRUD via REST v3
- Tools: `jira_*` suite (search, get/update/create issues, comments, attachments, links)
- Engine info: name `savant-jira`, version `1.1.0`
- Flow:
```mermaid
flowchart LR
  A[jira_* tool] --> E[Jira::Engine]
  E --> O[Jira::Ops] --> C[Jira::Client]
  C -->|HTTP| Jira[(Jira Cloud/Server)]
```
- Make helpers:
  - `make jira-test jql='project = ABC order by updated desc' [limit=5]`
  - `make jira-self`

Environment (Jira)
- Required:
  - `JIRA_BASE_URL`: e.g., `https://your.atlassian.net` (Cloud) or Jira Server URL.
- Auth (choose one):
  - Cloud: `JIRA_EMAIL` + `JIRA_API_TOKEN`.
  - Server/DC: `JIRA_USERNAME` + `JIRA_PASSWORD`.
- Optional:
  - `JIRA_ALLOW_WRITES=true` to enable mutating tools (create/update/delete). Default: reads only.
  - `LOG_LEVEL`, `SAVANT_PATH` for logging and paths.

#### Jira MCP Details

##### Jira Problem
- Query Jira issues via JQL from the same client environment, with auth handled locally.

##### Jira Solution
- `tool: jira_search` and `tool: jira_self` proxied to Jira REST with credentials from env or `config/jira.json`.

##### Jira Approach
- Validate config on boot; map JQL + pagination to REST; limit fields; return concise JSON to clients.

##### Jira Diagram
```mermaid
sequenceDiagram
  participant IDE as Client
  participant J as Jira MCP
  participant API as Jira API
  IDE->>J: tool.jira_search(jql, limit)
  J->>API: REST JQL search
  API-->>J: issues
  J-->>IDE: results
```

##### Jira Commands
- Run on host: `MCP_SERVICE=jira SAVANT_PATH=$(pwd) SETTINGS_PATH=config/settings.json ruby ./bin/mcp_server`
- Test: ``make jira-test jql='project = ABC order by updated desc' limit=10``

##### Jira Tools (REST API v3)
- jira_search: JQL search with pagination.
  - Input: `{ jql: string, limit?: number, start_at?: number }`
  - Output: `[ { key, summary, status, assignee, updated, url } ]`
- jira_self: Verify credentials.
  - Input: `{}`
  - Output: user JSON
- jira_get_issue: Get issue JSON.
  - Input: `{ key: string, fields?: string[] }`
  - Output: issue JSON
- jira_create_issue: Create issue.
  - Input: `{ projectKey, summary, issuetype, description?, fields? }`
  - Output: `{ key, url }`
- jira_update_issue: Update fields.
  - Input: `{ key, fields: object }`
  - Output: `{ key, updated: true }`
- jira_transition_issue: Transition issue.
  - Input: `{ key, transitionName?, transitionId? }`
  - Output: `{ key, transitioned: true }`
- jira_add_comment: Add a comment.
  - Input: `{ key, body }`
  - Output: `{ id, created }`
- jira_delete_comment: Delete a comment.
  - Input: `{ key, id }`
  - Output: `{ deleted: true }`
- jira_download_attachments: Download attachments.
  - Input: `{ key }`
  - Output: `{ count, files: [ { id, filename, path } ] }`
- jira_add_attachment: Upload attachment.
  - Input: `{ key, filePath }`
  - Output: `{ id, filename }`
- jira_add_watcher_to_issue: Add watcher.
  - Input: `{ key, accountId }`
  - Output: `{ added: true }`
- jira_assign_issue: Assign issue.
  - Input: `{ key, accountId?, name? }`
  - Output: `{ key, assignee }`
- jira_bulk_create_issues: Bulk create.
  - Input: `{ issues: [ { projectKey, summary, issuetype, description?, fields? } ] }`
  - Output: `{ keys: string[] }`
- jira_delete_issue: Delete issue.
  - Input: `{ key }`
  - Output: `{ deleted: true }`
- jira_link_issues: Link issues.
  - Input: `{ inwardKey, outwardKey, linkType }`
  - Output: `{ created: true }`

## Make Targets

| Target | Description | Variables / Usage |
|---|---|---|
| `dev` | Start Docker stack (Postgres + services) | `make dev` |
| `logs` | Follow indexer + MCP logs | `make logs` |
| `ps` | List compose services | `make ps` |
| `down` | Stop stack and remove containers (keep volume) | `make down` |
| `migrate` | Create/upgrade tables (destructive reset) | `make migrate` |
| `fts` | Ensure FTS index exists | `make fts` |
| `smoke` | Quick DB check (migrate + FTS ok) | `make smoke` |
| `repo-index-all` | Index all repos; append to `logs/context_repo_indexer.log` | `make repo-index-all` |

## All Make Targets (Summary)

| Target | Purpose | Notes / Variables |
|---|---|---|
| `dev` | Start Docker services | Postgres + Ruby container |
| `logs` | Tail service logs | Follows `indexer-ruby` + `postgres` |
| `down` | Stop and remove containers | Keeps volume data |
| `ps` | List running containers | — |
| `migrate` | Drop/create tables then ensure schema | Destructive reset; uses `bin/db_migrate` |
| `fts` | Ensure FTS GIN index | Uses `bin/db_fts` |
| `smoke` | Basic DB sanity (migrate+fts) | Uses `bin/db_smoke` |
| `repo-index-all` | Index all repos | Writes to `logs/context_repo_indexer.log` |
| `repo-index-repo` | Index a single repo | `repo=<name>` |
| `repo-delete-all` | Delete all indexed data | — |
| `repo-delete-repo` | Delete a single repo’s data | `repo=<name>` |
| `repo-status` | Show per-repo counts | files/blobs/chunks + last_mtime |
| `mcp-test` | Run Context MCP fts/search via stdio | `q='<term>' [repo=<name>] [limit=5]` |
| `jira-test` | Run Jira JQL search via stdio | `jql='<JQL>' [limit=10]` |
| `jira-self` | Verify Jira credentials | — |
| `test` | Run RSpec | Bundler or system RSpec |

## Development & Tests

Run tests (host):
- Install dev/test gems: `bundle install --with development test`
- Run: `bundle exec rspec` (or `make test`)
- Optional: start Guard to re-run specs on file changes with `bundle exec guard`
- Check style locally with `bundle exec rubocop`

Test philosophy:
- No real DB or filesystem calls in unit specs. The indexer is tested with fakes and stubs.
- Runner: verifies unchanged cache, language allowlist, logging (including `using=gitls`).
- RepositoryScanner: verifies Git path and config ignores are applied; falls back to walk on failure.
| `repo-index-repo` | Index a single repo | `make repo-index-repo repo=<name>` |
| `repo-delete-all` | Delete all indexed data | `make repo-delete-all` |
| `repo-delete-repo` | Delete one repo’s indexed data | `make repo-delete-repo repo=<name>` |
| `repo-status` | Per‑repo files/blobs/chunks counters | `make repo-status` |
| `mcp-test` | Test Context MCP `fts/search` | `make mcp-test q='<term>' [repo=<name>] [limit=5]` |
| `jira-test` | Test Jira MCP JQL search | `make jira-test jql='<JQL>' [limit=10]` |
| `jira-self` | Quick Jira auth check | `make jira-self` |

## Make Variables

| Variable | Description | Example |
|---|---|---|
| `repo` | Repository name from `config/settings.json` | `make repo-index-repo repo=crawler` |
| `q` | Search query string for Context MCP | `make mcp-test q='User'` |
| `limit` | Max results for MCP tools | `make mcp-test q='User' limit=5` |
| `jql` | Jira JQL query string | `make jira-test jql='project = ABC order by updated desc'` |

## Environment Variables

| Env Var | Purpose | Default |
|---|---|---|
| `SETTINGS_PATH` | Path to settings JSON | `config/settings.json` (host) / `/app/settings.json` (container) |
| `DATABASE_URL` | Postgres connection string | `postgres://context:contextpw@localhost:5432/contextdb` (host) |
| `MCP_SERVICE` | Select MCP profile (`context` or `jira`) | `context` |
| `SAVANT_PATH` | Base path to Savant repo (used to derive `config/settings.json` and `logs/`) | `./` |
| `LISTEN_HOST` | Optional future network mode | `0.0.0.0` |
| `LISTEN_PORT` | Optional future network mode | `8765` (context), `8766` (jira) |
| `LOG_LEVEL` | Logging level | `info` |
| `JIRA_BASE_URL` | Jira base URL | — |
| `JIRA_EMAIL` / `JIRA_API_TOKEN` | Jira Cloud credentials | — |
| `JIRA_USERNAME` / `JIRA_PASSWORD` | Jira Server credentials | — |
| `JIRA_CONFIG_PATH` | Optional Jira config file path | Set by compose to `/app/config/jira.json` if provided |

## Ports

These are for Docker debugging only. Cline uses stdio and does not require ports.

| Service | Port |
|---|---|
| Context MCP | `8765` |
| Jira MCP | `8766` |

## Local PostgreSQL

- You can point Indexer and MCP to a Postgres running on your machine.
- Cline + Docker containers: set `DATABASE_URL` host to `host.docker.internal` (Linux: add `extra_hosts: ["host.docker.internal:host-gateway"]` under each service in `docker-compose.yml`).
- Cline without Docker: use `localhost` in `DATABASE_URL`.
- Indexer via Make (containers): either override per call
  - `docker compose exec -e DATABASE_URL=postgres://USER:PASS@host.docker.internal:5432/DBNAME -T indexer-ruby ./bin/db_migrate`
  - and similarly for `./bin/db_fts`, `./bin/context_repo_indexer index all`, `./bin/context_repo_indexer status`
  - or set `DATABASE_URL` in `docker-compose.yml` for `indexer-ruby`, `mcp-context`, and `mcp-jira`.
- If SSL interferes locally, append `?sslmode=disable` to `DATABASE_URL`.

## IDE Integration

### Cline (Docker, preferred)
- Open this repo folder in VS Code (workspace root must contain `docker-compose.yml`).
- Prepare services: `docker compose build` then `make dev` (starts Postgres). Ensure `config/settings.json` exists; Jira creds can be in `settings.json` (jira section), `.env`, or env vars.
- In Settings (JSON), add:

```jsonc
{
  "cline.mcpServers": {
    "savant-context": {
      "command": "docker",
      "args": ["compose", "run", "--rm", "-T", "mcp-context"]
    },
    "savant-jira": {
      "command": "docker",
      "args": ["compose", "run", "--rm", "-T", "mcp-jira"]
      // Optionally surface Jira creds to compose via this process env:
      // "env": { "JIRA_BASE_URL": "https://...", "JIRA_EMAIL": "you@company.com", "JIRA_API_TOKEN": "..." }
    }
  }
}
```

Notes
- Cline talks via stdio, so no ports are required. `compose run` launches a fresh container per session using the service env/volumes defined in `docker-compose.yml`.
- If your Jira config lives in `config/settings.json`, you don’t need to set `JIRA_*` env. If you prefer `.env`, keep it at repo root so compose picks it up.

### VS Code (Cline)
- Cline launches MCP servers as child processes and communicates over stdio (no ports).
- Install Cline and add entries under `cline.mcpServers`:

```jsonc
{
  "cline.mcpServers": {
    "savant-context": {
      "command": "ruby",
      "args": ["/absolute/path/to/savant/bin/mcp_server"],
      "env": {
        "MCP_SERVICE": "context",
        "SAVANT_PATH": "/absolute/path/to/savant",
        "DATABASE_URL": "postgres://context:contextpw@localhost:5432/contextdb"
      }
    },
    "savant-jira": {
      "command": "ruby",
      "args": ["/absolute/path/to/savant/bin/mcp_server"],
      "env": {
        "MCP_SERVICE": "jira",
        "SAVANT_PATH": "/absolute/path/to/savant",
        "DATABASE_URL": "postgres://context:contextpw@localhost:5432/contextdb",
        "JIRA_BASE_URL": "https://your-domain.atlassian.net",
        "JIRA_EMAIL": "you@company.com",
        "JIRA_API_TOKEN": "<token>"
      }
    }
  }
}
```

Notes
- Use your actual DB URL if different; Cline talks via stdio, so no port mapping is required.
- Docker alternative: set `command` to `docker` and `args` to `compose run --rm -T mcp-context` (or `mcp-jira`).

SAVANT_PATH notes
- Set `SAVANT_PATH` to the base directory of the Savant repo. The server derives `config/settings.json` and `logs/<service>.log` from this path.
- If you need a custom config location, set `SETTINGS_PATH` explicitly; `SAVANT_PATH` can still be used for logs. Example: `SETTINGS_PATH=/path/to/custom/settings.json`.

### Claude Code (VS Code)
- Claude Code also launches servers via stdio; add entries similarly (setting name may vary by version):

```jsonc
{
  "claudeCode.mcpServers": {
    "savant-context": {
      "command": "ruby",
      "args": ["./bin/mcp_server"],
      "env": {
        "MCP_SERVICE": "context",
        "SETTINGS_PATH": "${workspaceFolder}/config/settings.json",
        "DATABASE_URL": "postgres://context:contextpw@localhost:5432/contextdb"
      }
    },
    "savant-jira": {
      "command": "ruby",
      "args": ["./bin/mcp_server"],
      "env": {
        "MCP_SERVICE": "jira",
        "SETTINGS_PATH": "${workspaceFolder}/config/settings.json",
        "DATABASE_URL": "postgres://context:contextpw@localhost:5432/contextdb",
        "JIRA_BASE_URL": "https://your-domain.atlassian.net",
        "JIRA_EMAIL": "you@company.com",
        "JIRA_API_TOKEN": "<token>"
      }
    }
  }
}
```

Verify
- In the extension, open the MCP/Tools panel and confirm tools are listed: `search` for Context; `jira_search` and `jira_self` for Jira.
- Run a quick test: ask the assistant to use `search` for a term in your repo, or run the provided Make tests.

## MCP Testing
- Quick: ``make mcp-test q='User'`` · Repo filter: ``make mcp-test q='Foo' repo=<name>``
- Jira: ``make jira-test jql='project = ABC order by updated desc' limit=10`` · Auth: `make jira-self`

## Troubleshooting
- Indexer sees no files: use container paths in `config/settings.json` (e.g., `/host/...`) and mount repos in `docker-compose.yml`.
- Logs/permissions: tail with `make logs`; ensure `chmod +x bin/*`; check `logs/indexer.log`.
- Reset DB: `docker compose down -v` then `make dev && make migrate && make fts`.
- Skips: indexer ignores `.git`, ignored/binary/oversize files; tune limits in `config/settings.json`.
- Empty search results: confirm indexing finished (`make status`) and loosen `q`.
