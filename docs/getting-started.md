# Getting Started with Savant (Homebrew)

This guide assumes you install Savant via Homebrew and want a fast path to activation and running the MCP server and Hub. An advanced “From Source” flow is included at the end for Context search and indexing.

## 1) Install

```bash
brew tap <org/tap>   # e.g., ashabbir/savant
brew install <org/tap>/savant
savant version
```

## 2) Activate (offline)

Savant uses an offline activation file at `~/.savant/license.json`.

```bash
# Format: <username>:<key>
savant activate myuser:MYKEY
savant status
```

To reset:

```bash
savant deactivate
```

## 3) Run MCP (stdio) or Hub (HTTP)

- MCP (stdio, multiplexer of all engines):

```bash
savant serve --transport=stdio
```

- Hub (HTTP, serves minimal diagnostics; UI shown if available):

```bash
savant hub --host=0.0.0.0 --port=9999
open http://localhost:9999/ui || true
```

Tip: Most engines (Git, Think, Personas, Rules) work without a database. Context search requires a Postgres DB and indexing (see Advanced below).

### 3.2) Council Quickstart

- Open the Hub UI and click the Council tab (`/council`). Create a session by naming it and selecting at least two agents. Chat normally; when ready, click “Escalate to Council” to run the multi‑agent protocol. The UI live‑updates during deliberation and automatically returns to chat when done.

Or use HTTP directly:

```bash
# Create a session
curl -s -H 'content-type: application/json' -H 'x-savant-user-id: me' \
  -X POST http://localhost:9999/council/tools/council_session_create/call \
  -d '{"params": {"title": "Tech Decision", "agents": ["a1","a2"]}}'

# Append a user message
curl -s -H 'content-type: application/json' -H 'x-savant-user-id: me' \
  -X POST http://localhost:9999/council/tools/council_append_user/call \
  -d '{"params": {"session_id": 1, "text": "Microservices or monolith?"}}'

# Escalate to council and run
curl -s -H 'content-type: application/json' -H 'x-savant-user-id: me' \
  -X POST http://localhost:9999/council/tools/council_escalate/call \
  -d '{"params": {"session_id": 1}}'

curl -s -H 'content-type: application/json' -H 'x-savant-user-id: me' \
  -X POST http://localhost:9999/council/tools/council_run/call \
  -d '{"params": {"session_id": 1}}'
```

Environment flags:
- `COUNCIL_DEMO_MODE=1` → demo positions/synthesis without Reasoning API
- `COUNCIL_AUTO_AGENT_STEP=1` → optional auto agent step on user messages (chat mode)

## 3.1) Dev Mode (Rails + Vite, hot reload)

- One command: `make dev`
- Starts Rails, the Vite dev server, and the Hub together; hub logs go to `logs/hub.log`.
- `make ls` now prints only `dev`, keeping the focus on this single entrypoint.
- Opens two servers:
  - API: http://localhost:9999 (Hub endpoints)
  - UI (HMR): http://localhost:5173
- Edits to `frontend/` hot-reload instantly in the browser.

To serve static UI under Rails (no hot reload):
- Build UI: `make ui-build-local` (copies `frontend/dist` into `public/ui`).
- Start API: `make rails-up` (serves static UI from `/ui`).
- Open: `http://localhost:9999/ui`.

Indexing via Rake (inside Rails):

```bash
cd server
export DATABASE_URL=postgres://context:contextpw@localhost:5432/contextdb
bundle exec rake savant:index_all            # all repos
bundle exec rake 'savant:index[myrepo]'      # single repo
bundle exec rake savant:status               # status
```

Tips
- The UI calls the Hub at `http://localhost:9999` by default; override in the UI settings (top-right gear) or via `VITE_HUB_BASE` when using dev server.
- `make dev` is the only target you need to launch the local dev stack; the new `make ls` output simply reiterates this command.
- When you need to build or inspect the static UI, use `make ui-build-local`; start Rails alone with `make rails-up`.

## 4) Optional: use a cloned repo for UI/config

Some features (static UI, custom settings) work best with a local repo clone. Set `SAVANT_PATH` to point at the repo so the binary picks up config and assets.

```bash
git clone https://github.com/ashabbir/savant.git
export SAVANT_PATH="$(pwd)/savant"
savant hub
```

## 5) Advanced: Context search (DB + indexing)

Context search requires Postgres and indexing. No Docker is required:

```bash
# Clone the repo and set settings
git clone https://github.com/ashabbir/savant.git
cd savant
cp config/settings.example.json config/settings.json
export SAVANT_PATH="$(pwd)"
export DATABASE_URL=postgres://context:contextpw@localhost:5432/contextdb

# Prepare DB (local Postgres, zero-setup)
# Defaults (override with DB_ENV, PG* env or DATABASE_URL):
#  - development: savant_development
#  - test:        savant_test
make db-create                 # create DB if missing (env=development by default)
make db-migrate                # apply only new migrations (idempotent)
make db-fts                    # ensure GIN FTS index on chunks.chunk_text
make db-smoke                  # quick connectivity + tables check (non-destructive)

# Switch to test database
make db-create DB_ENV=test
make db-migrate DB_ENV=test

# Index your repos (edit config/settings.json first)
make repo-index-all

# Option A: Use Rails JSON-RPC endpoint
curl -s -H 'content-type: application/json' \
  -X POST http://localhost:9999/rpc \
  -d '{"id":1,"method":"context.fts_search","params":{"q":"term","limit":5}}'

# Option B: Use stdio MCP server directly
MCP_SERVICE=context bundle exec ruby ./bin/mcp_server
```

## Troubleshooting

- Activation: `savant status` shows current state and license file path.
- DB connectivity: ensure your local Postgres is reachable; set `DATABASE_URL`.
 - No search results: verify `config/settings.json` repo paths; re-run `make repo-index-all`.
 - UI: if `/ui` is empty, run `make ui-build-local` then start Rails.

## From Source (alternative)

If you prefer running entirely from source (Ruby + Bundler), follow the README “Full Stack Setup” steps in the repo. In short:

```bash
git clone https://github.com/ashabbir/savant.git
cd savant
bundle install
make quickstart && make repo-index-all && make ui-build
./bin/savant run --skip-git
```

## Agents UI — Create and Run

Create an agent from the UI:
- Open the UI → MCPs tab → select “agents”.
- Click the “+” (New Agent).
- Fill fields:
  - Name: unique id for the agent
  - Persona: pick from Personas engine
  - Driver: mission + endpoint description (free text)
  - Rules: optional list from Rules engine
- Save Agent. The agent appears in the list.

Run an agent (UI):
- Select an agent from the list.
- Enter input in “Enter input for run…” and click Run.
- Recent runs show below; click View to open the chat-style transcript.
