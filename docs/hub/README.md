Savant MCP Hub (HTTP + SSE)

The Savant Hub is a multi-engine, multi-user HTTP/SSE gateway for MCP tools. It mounts existing engines (e.g., context, jira, think) under paths and exposes simple REST-style endpoints with Server-Sent Events for streaming.

Highlights
- Multi-engine mounting under `/:engine`
- Multi-user via `x-savant-user-id` header
- SSE endpoints for logs and heartbeats
- File-backed secrets per user with ENV fallbacks
- Docker service on port `9999` with Make targets

Quick Start (Docker)
- Build and start services:
  - `docker compose build`
  - `make dev`
  - `make hub`
  - `make hub-logs` (follow logs)
- Optional: copy secrets template and edit (repo root):
  - `cp secrets.example.yml secrets.yml`
- Call the Hub (header required):
  - `H='x-savant-user-id: amd'`
  - `curl -s -H "$H" http://localhost:9999/`
  - `curl -s -H "$H" http://localhost:9999/context/tools`
  - `curl -s -H "$H" 'http://localhost:9999/context/logs?n=50'`
  - `curl -s -H "$H" 'http://localhost:9999/context/logs?stream=1&once=1&n=10'`

Ports
- Exposed: `9999` (host → container)
- Service path: `/:engine/...` (e.g., `/context/tools`)

Make Targets
- `make hub`: start the Hub service
- `make hub-logs`: follow Hub logs
- `make hub-down`: stop the Hub container

Configuration
- Header (required): `x-savant-user-id: <user-id>` used for per-user secrets and isolation
- Secrets (file-backed):
  - Path: repo root `secrets.yml` (autoloaded), or override with `SAVANT_SECRETS_PATH`. If root file is absent, falls back to `config/secrets.yml`.
  - Shape:
    - users:
      - amd:
        - jira:
          - base_url: https://your-domain.atlassian.net
          - email: amd@example.com
          - api_token: your-jira-api-token
          - # or username + password
          - # username: amd
          - # password: secret
  - ENV fallbacks: `JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN`, `JIRA_USERNAME`, `JIRA_PASSWORD`
- Mounts: `config/mounts.yml` (optional)
  - mounts:
    - engine: "context"
      path: "/context"
    - engine: "think"
      path: "/think"
    - engine: "jira"
      path: "/jira"
- Transport: `config/transport.yml` (optional)
  - transport:
    - mode: "sse"
    - host: "0.0.0.0"
    - port: 9999

Endpoints
- Hub: `GET /` → `{ service, version, transport, hub: {pid, uptime_seconds}, engines: [...] }`
- Per-engine:
  - `GET /:engine/status` → `{ engine, status, uptime_seconds, info }`
  - `GET /:engine/tools` → `{ engine, tools: [...] }`
  - `POST /:engine/tools/:name/call` → tool execution result
  - `GET /:engine/logs?n=100` → last N lines `{ lines: [...] }`
  - `GET /:engine/logs?stream=1[&once=1][&n=100]` → SSE stream of logs (emits `event: log`)
  - `GET /:engine/stream` → SSE heartbeats (emits `event: heartbeat`)

SSE Notes
- Headers: `Content-Type: text/event-stream`, `Cache-Control: no-cache`
- Events: `event: log|heartbeat`, `data: { ... }`
- `once=1` closes the stream after initial events (useful for tests)

Security
- Local dev only; no auth/authz. Do not expose publicly.
- Secrets are never logged; typical secret keys are redacted.
- Per-user credentials resolved from `x-savant-user-id`.

Troubleshooting
- Missing header → 400: add `x-savant-user-id`
- No secrets for a user → falls back to ENV Jira creds if present
- Logs empty → ensure engine writes to `/tmp/savant/<engine>.log`
- Port in use → change Compose port mapping or update `--port` in the hub command
