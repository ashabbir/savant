# Getting Started with Savant

This guide gets you from zero to a running Savant stack with context search and a working MCP server, including offline activation.

## Prerequisites

- macOS or Linux
- Docker (for Postgres + quickstart)
- Ruby 3.x + Bundler (for running CLIs locally)
- Git

Optional:
- Node 18+ (to build the React UI locally)

## 1) Clone and install gems

```bash
git clone https://github.com/ashabbir/savant.git
cd savant
bundle install
```

## 2) Configure settings

Copy the example settings and adjust repo paths as needed:

```bash
cp config/settings.example.json config/settings.json
```

Key fields to review:
- `indexer.repos[]` list, each with `name` and `path` to your local repositories
- `database` connection (leave defaults to use Docker quickstart)

## 3) Start the stack (Docker quickstart)

```bash
make quickstart
```

This boots Postgres + Hub, runs migrations and FTS. It does not index repos yet.

## 4) Index your repos

```bash
make repo-index-all
```

Re-run this anytime to refresh the index. For a single repo:

```bash
make repo-index-repo repo=<name>
```

## 5) Build or run the UI

- Static UI under Hub:

```bash
make ui-build
open http://localhost:9999/ui
```

- Dev server (hot reload):

```bash
make dev-ui
# UI at http://localhost:5173 (Hub at http://localhost:9999)
```

## 6) Offline activation

Savant uses an offline activation file at `~/.savant/license.json`.

```bash
# Format: <username>:<key>
./bin/savant activate myuser:MYKEY

# Check status
./bin/savant status
```

If you need to reset:

```bash
./bin/savant deactivate
```

Dev bypass (for local development only):

```bash
export SAVANT_DEV=1
```

## 7) Run the MCP server

Stdio multiplexer (all engines):

```bash
SAVANT_PATH=$(pwd) bundle exec ruby ./bin/mcp_server
```

Single engine (e.g., Context):

```bash
MCP_SERVICE=context SAVANT_PATH=$(pwd) bundle exec ruby ./bin/mcp_server
```

## 8) Quick smoke test

Search via MCP test helper (requires DB up and repos indexed):

```bash
make mcp-test q='README' limit=5
```

## Troubleshooting

- Activation failed: ensure you used `savant activate <username>:<key>` exactly; then check `savant status`.
- DB connectivity: verify Docker is running; `make logs` to see Postgres and indexer logs.
- No search results: confirm `config/settings.json` repo paths; re-run `make repo-index-all`.
- UI 404: run `make ui-build` and reload `http://localhost:9999/ui`.

## Next steps

- Explore tools via the UI (Engines → Context/Jira/Think).
- CLI lists: `SAVANT_PATH=$(pwd) bundle exec ruby ./bin/savant tools`.
- Run an agent session: `./bin/savant run --skip-git --agent-input="Summarize recent changes"`.

## Homebrew (when releases are published)

- Install from tap:

```bash
brew tap <org/tap>  # e.g., ashabbir/savant
brew install <org/tap>/savant
savant version
```

- Activate and run:

```bash
savant activate <username>:<key>
savant status
```

- Upgrade:

```bash
brew upgrade savant
```
