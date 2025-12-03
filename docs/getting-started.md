# Getting Started with Savant (Homebrew)

This guide assumes you install Savant via Homebrew and want a fast path to activation and running the MCP server and Hub. An advanced “From Source” flow is included at the end for Context search and indexing.

## 1) Install

```bash
brew tap <org/tap>   # e.g., ashabbir/savant
brew install <org/tap>/savant-os
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

## 4) Optional: use a cloned repo for UI/config

Some features (static UI, custom settings) work best with a local repo clone. Set `SAVANT_PATH` to point at the repo so the binary picks up config and assets.

```bash
git clone https://github.com/ashabbir/savant.git
export SAVANT_PATH="$(pwd)/savant"
savant hub
```

## 5) Advanced: Context search (DB + indexing)

Context search requires Postgres and indexing. Use Docker for a quick setup, and point the brew-installed `savant` at the repo for config and UI:

```bash
# Clone the repo and set SAVANT_PATH so Savant finds config and UI
git clone https://github.com/ashabbir/savant.git
cd savant
cp config/settings.example.json config/settings.json
export SAVANT_PATH="$(pwd)"

# Start Postgres + Hub via Docker, run migrations and FTS
make quickstart

# Index your repos (edit config/settings.json first)
make repo-index-all

# Start MCP Context with DB
DATABASE_URL=postgres://context:contextpw@localhost:5433/contextdb \
  MCP_SERVICE=context savant serve --transport=stdio
```

## Troubleshooting

- Activation: `savant status` shows current state and license file path.
- DB connectivity: ensure Docker is running; `make logs` for Postgres/indexer logs.
- No search results: verify `config/settings.json` repo paths; re-run `make repo-index-all`.
- UI: if `/ui` is empty, run `make ui-build` in the repo then `savant hub` with `SAVANT_PATH` pointing at the repo.

## From Source (alternative)

If you prefer running entirely from source (Ruby + Bundler), follow the README “Full Stack Setup” steps in the repo. In short:

```bash
git clone https://github.com/ashabbir/savant.git
cd savant
bundle install
make quickstart && make repo-index-all && make ui-build
./bin/savant run --skip-git
```
