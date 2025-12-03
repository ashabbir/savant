# Hub (HTTP Server)

## Overview
Serves the React UI under `/ui`, exposes diagnostics, log streaming, and routes to call MCP tools over HTTP. Acts as an operational surface around the MCP processes.

## Key Files
- `lib/savant/hub/builder.rb`: Build Rack app from config
- `lib/savant/hub/router.rb`: Routes: `/`, `/routes`, `/diagnostics/*`, `/:engine/tools/:name/call`
- `lib/savant/hub/sse.rb`: Server-Sent Events for live logs
- `lib/savant/hub/service_manager.rb`: Connects HTTP to engine registrars

## Endpoints
- `/` – Hub status and health
- `/ui` – Static UI (if built to `public/ui`)
- `/routes` – List all HTTP routes
- `/logs`, `/logs/stream` – Aggregated logs + SSE
- `/diagnostics/*` – Per-engine and system diagnostics
- `/:engine/tools/:tool/call` – Call a tool via HTTP JSON

## Run Locally
```
# With Docker
make dev   # or make quickstart

# Without Docker
SAVANT_PATH=$(pwd) bundle exec ruby ./bin/savant hub
```

## Notes
- Choose Rack handler automatically (Puma preferred, fallback WEBrick).
- UI build via `make ui-build` copies frontend `dist/` into `public/ui`.

