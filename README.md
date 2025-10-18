# Savant

Local repo indexer + MCP search layer (Ruby + Postgres FTS, optional Docker).

## Overview
- Index local repos, store chunks in Postgres FTS, and expose fast search via MCP.
- Components: Indexer CLI, Postgres 16 (GIN/tsvector), MCP servers for Context and Jira.
- Docs: see `docs/README.md` and `config/` examples.

## Configuration
- Provide `config/settings.json` (see `config/settings.example.json`, schema in `config/schema.json`).
- Mount host repos in `docker-compose.yml` so the indexer can read them.

## Project Layout
- `docs/`: epics, PRD, ops notes
- `config/`: settings and examples
- `bin/`: CLIs for index/DB/MCP
- `docker-compose.yml`: services and volumes

## Jira Configuration
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



## Indexer

### Problem
- Large, evolving repos need fast local indexing with minimal overhead and zero data exfiltration.
- Keeping search results fresh requires reliable change detection and efficient upserts.

### Solution
- A Ruby indexer that scans configured repos, hashes and deduplicates content, chunks intelligently, and stores everything in Postgres with FTS.

### Approach
- Ignore rules and size limits keep noise low and runs deterministic.
- Hash + dedupe at blob level minimizes DB churn; chunking preserves context with overlaps.
- Postgres FTS (`tsvector` + GIN) powers ranking; counters and timestamps help status/health.
- Config-driven: repos and rules live in `config/settings.json`.

### Diagram
```mermaid
flowchart LR
  R["Repos (host mounts)"] --> I["Indexer CLI<br/>scan → hash → chunk"]
  I --> DB["Postgres 16<br/>FTS tsvector + GIN"]

  classDef svc fill:#f0f7ff,stroke:#1e88e5,color:#0d47a1,stroke-width:1px
  classDef data fill:#f9fbe7,stroke:#7cb342,color:#33691e,stroke-width:1px
  class I svc
  class DB data
```

### Commands

Without Docker
- Migrate: `DATABASE_URL=postgres://context:contextpw@localhost:5432/contextdb SETTINGS_PATH=config/settings.json ruby ./bin/db_migrate`
- FTS: `DATABASE_URL=... SETTINGS_PATH=... ruby ./bin/db_fts`
- Smoke: `DATABASE_URL=... SETTINGS_PATH=... ruby ./bin/db_smoke`
- Index all: `DATABASE_URL=... SETTINGS_PATH=... ruby ./bin/index all`
- Index repo: `DATABASE_URL=... SETTINGS_PATH=... ruby ./bin/index <repo>`
- Delete all: `DATABASE_URL=... SETTINGS_PATH=... ruby ./bin/index delete all`
- Delete repo: `DATABASE_URL=... SETTINGS_PATH=... ruby ./bin/index delete <repo>`
- Status: `DATABASE_URL=... SETTINGS_PATH=... ruby ./bin/status`

With Docker
- Migrate: `docker compose exec -T indexer-ruby ./bin/db_migrate`
- FTS: `docker compose exec -T indexer-ruby ./bin/db_fts`
- Smoke: `docker compose exec -T indexer-ruby ./bin/db_smoke`
- Index all: `docker compose exec -T indexer-ruby ./bin/index all`
- Index repo: `docker compose exec -T indexer-ruby ./bin/index <repo>`
- Delete all: `docker compose exec -T indexer-ruby ./bin/index delete all`
- Delete repo: `docker compose exec -T indexer-ruby ./bin/index delete <repo>`
- Status: `docker compose exec -T indexer-ruby ./bin/status`

With Make
- `make migrate` · `make fts` · `make smoke`
- `make index-all` · ``make index-repo repo=<name>``
- ``make delete-all`` · ``make delete-repo repo=<name>``
- `make status`

---

## MCP

### Problem
- Tools and editors need a standard interface to local context search and Jira without exposing secrets or raw DB access.

### Solution
- Two Ruby MCP servers: Context (search via Postgres FTS) and Jira (JQL via Jira REST), each exposed over WebSocket/stdin for easy client integration.

### Approach
- Config-driven ports and credentials; strict outputs; timing + size logging for observability.
- Context MCP depends on DB; Jira MCP depends on Jira credentials or config file.



### Context MCP

Problem
- Expose fast, ranked repo search to MCP-aware clients.

Solution
- `tool: search` backed by Postgres FTS in the same DB the indexer maintains.

Approach
- Accept requests over ws/stdin; sanitize inputs; log timings and payload sizes; return hits with metadata/snippets.

Diagram
```mermaid
sequenceDiagram
  participant IDE as Client
  participant MCP as Context MCP
  participant DB as Postgres + FTS
  IDE->>MCP: tool.search(q, repo?, limit)
  MCP->>DB: FTS query + rank
  DB-->>MCP: hits + snippets
  MCP-->>IDE: results
```

Commands
- Docker: `docker compose up -d mcp-context` · Logs: `docker compose logs -f mcp-context`
- Make: `make mcp-context` · Debug: `make mcp-context-run`
- No Docker: `MCP_SERVICE=context DATABASE_URL=... SETTINGS_PATH=... ruby ./bin/mcp_server`
- Test: ``make mcp-test q='User' repo=<name> limit=5``

### Jira MCP

Problem
- Query Jira issues via JQL from the same client environment, with auth handled locally.

Solution
- `tool: jira_search` and `tool: jira_self` proxied to Jira REST with credentials from env or `config/jira.json`.

Approach
- Validate config on boot; map JQL + pagination to REST; limit fields; return concise JSON to clients.

Diagram
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

Commands
- Docker: `docker compose up -d mcp-jira` · Logs: `docker compose logs -f mcp-jira`
- Make: `make mcp-jira` · Debug: `make mcp-jira-run` · Auth check: `make jira-self`
- No Docker: `MCP_SERVICE=jira DATABASE_URL=... SETTINGS_PATH=... ruby ./bin/mcp_server`
- Test: ``make jira-test jql='project = ABC order by updated desc' limit=10``

## Make Targets

| Target | Description | Variables / Usage |
|---|---|---|
| `dev` | Start Docker stack (Postgres + services) | `make dev` |
| `logs` | Follow indexer + MCP logs | `make logs` |
| `ps` | List compose services | `make ps` |
| `down` | Stop stack and remove containers (keep volume) | `make down` |
| `migrate` | Create/upgrade tables | `make migrate` |
| `fts` | Ensure FTS index exists | `make fts` |
| `smoke` | Quick DB check (migrate + FTS ok) | `make smoke` |
| `index-all` | Index all repos; append to `logs/indexer.log` | `make index-all` |
| `index-repo` | Index a single repo | `make index-repo repo=<name>` |
| `delete-all` | Delete all indexed data | `make delete-all` |
| `delete-repo` | Delete one repo’s indexed data | `make delete-repo repo=<name>` |
| `status` | Per‑repo files/blobs/chunks counters | `make status` |
| `mcp` | Start both MCPs (context + jira) | `make mcp` |
| `mcp-test` | Test Context MCP `search` | `make mcp-test q='<term>' [repo=<name>] [limit=5]` |
| `mcp-context` | Start Context MCP (background) | `make mcp-context` |
| `mcp-context-run` | Run Context MCP in foreground (debug) | `make mcp-context-run` |
| `mcp-jira` | Start Jira MCP (background) | `make mcp-jira` |
| `mcp-jira-run` | Run Jira MCP in foreground (debug) | `make mcp-jira-run` |
| `jira-test` | Test Jira MCP JQL search | `make jira-test jql='<JQL>' [limit=10]` |
| `jira-self` | Quick Jira auth check | `make jira-self` |

## Make Variables

| Variable | Description | Example |
|---|---|---|
| `repo` | Repository name from `config/settings.json` | `make index-repo repo=crawler` |
| `q` | Search query string for Context MCP | `make mcp-test q='User'` |
| `limit` | Max results for MCP tools | `make mcp-test q='User' limit=5` |
| `jql` | Jira JQL query string | `make jira-test jql='project = ABC order by updated desc'` |

## Environment Variables

| Env Var | Purpose | Default |
|---|---|---|
| `SETTINGS_PATH` | Path to settings JSON | `config/settings.json` (host) / `/app/settings.json` (container) |
| `DATABASE_URL` | Postgres connection string | `postgres://context:contextpw@localhost:5432/contextdb` (host) |
| `MCP_SERVICE` | Select MCP profile (`context` or `jira`) | `context` |
| `LISTEN_HOST` | MCP listen host | `0.0.0.0` |
| `LISTEN_PORT` | MCP listen port | `8765` (context), `8766` (jira) |
| `LOG_LEVEL` | Logging level | `info` |
| `JIRA_BASE_URL` | Jira base URL | — |
| `JIRA_EMAIL` / `JIRA_API_TOKEN` | Jira Cloud credentials | — |
| `JIRA_USERNAME` / `JIRA_PASSWORD` | Jira Server credentials | — |
| `JIRA_CONFIG_PATH` | Optional Jira config file path | Set by compose to `/app/config/jira.json` if provided |

## Ports

| Service | Port |
|---|---|
| Context MCP | `8765` |
| Jira MCP | `8766` |

## IDE Integration

### VS Code (Cline)
- Install the Cline extension and open Settings (JSON).
- Add MCP servers under `cline.mcpServers` using stdio launch:

```jsonc
{
  "cline.mcpServers": {
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

Notes
- Use your actual DB URL if different; Cline launches the process and communicates via stdio, so no port mapping is required.
- To use Docker instead, point `command` to `docker` and `args` to a `compose run --rm mcp-context ruby ./bin/mcp_server` equivalent.

### Claude Code (VS Code)
- Install the Claude Code extension and open its Settings (JSON).
- Add MCP servers similarly (exact setting name may vary by version):

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
