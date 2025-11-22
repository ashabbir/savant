
# Savant MCP Hub — Multi-Engine, Multi-User, SSE Transport  
**Product Requirements Document (PRD)**  
**Version:** 3.0  
**Owner:** Amd  
**Status:** Final  
**Target Release:** Q4 2025  

---

# 1. Purpose

Upgrade Savant from a single-engine STDIO MCP server into a **multi-engine, multi-user, multiplexed MCP Hub** supporting:

- HTTP JSON-RPC  
- SSE (Server-Sent Events) streaming  
- Per-user secret isolation  
- Per-request identity headers  
- Hub-level orchestration  
- Full backward compatibility with STDIO  

This enables Savant to operate as a central MCP gateway for:

- Cline (VS Code)  
- Claude Desktop  
- Local/remote agents  
- Future Savant UI  
- Team-shared workflows  
- Cloud deployments  

---

# 2. Goals

## 2.1 Primary Goals
1. Implement **SSE transport** with real-time streaming.  
2. Add **Multiplex Engine Hub** with mountable engines.  
3. Support **multi-user operation** through per-request identity headers.  
4. Implement **SecretStore** for per-user JIRA/GitLab/etc. tokens.  
5. Provide a root-level **Hub Dashboard** (`GET /`).  
6. Maintain full **STDIO backward compatibility**.

## 2.2 Secondary Goals
- Enable a future Savant UI.  
- Support remote/cloud MCP hosting.  
- Improve observability and maintainability.

---

# 3. Non-Goals
- No UI implementation (separate PRD).  
- No auth/authz or API keys.  
- No integration with a distributed vault.  
- No clustering or multi-host support.  

---

# 4. Architecture Overview

Savant will run in three transport modes:

| Mode | Description | Multi-User | Multi-Engine | Streaming |
|------|-------------|------------|--------------|-----------|
| STDIO | Tool server via stdin/stdout | ❌ | ❌ | ❌ |
| HTTP | JSON-RPC via POST | ✔ | ✔ | ❌ |
| SSE | Streaming + JSON-RPC | ✔ | ✔ | ✔ |

STDIO remains unchanged (single-engine, single-user).

HTTP/SSE modes activate the **Savant MCP Hub**.

---

# 5. Configuration

## 5.1 Multi-Engine Mounts

`config/mounts.yml`:

```yaml
mounts:
  - engine: "context"
    path: "/context"
  - engine: "think"
    path: "/think"
  - engine: "jira"
    path: "/jira"
````

## 5.2 Transport

`config/transport.yml`:

```yaml
transport:
  mode: "sse"   # stdio | http | sse
  host: "0.0.0.0"
  port: 8765
```

## 5.3 Cline Configuration (Per User)

Each developer sets their own header:

```json
"cline.mcpServers": {
  "savant": {
    "url": "http://localhost:8765",
    "transport": "sse",
    "headers": {
      "x-savant-user-id": "amd"
    }
  }
}
```

This header identifies the user for secret resolution.

---

# 6. Functional Requirements

---

## 6.1 Multiplex Engine Hub

### 6.1.1 Engine Mounting

* Load all engines defined in `mounts.yml`.
* Mount each engine under its configured `path`.
* Each engine exposes a uniform REST+MCP API.

### 6.1.2 Engine Endpoints

Every engine MUST expose:

| Method | Route                         | Description            |
| ------ | ----------------------------- | ---------------------- |
| GET    | `/<engine>/status`            | engine uptime + health |
| GET    | `/<engine>/tools`             | list tools             |
| POST   | `/<engine>/tools/:name/ccall` | execute tool           |
| GET    | `/<engine>/logs`              | logs                   |
| GET    | `/<engine>/stream`            | SSE endpoint           |

All tool calls follow normal JSON-RPC MCP contract.

---

## 6.2 SSE Transport

### 6.2.1 Endpoint

```
GET /<engine>/stream
```

### 6.2.2 Event Format

```
event: log
data: {"message":"..."} 

event: progress
data: {"percent":45}

event: result
data: {...}

event: heartbeat
data: {}
```

### 6.2.3 Requirements

* Heartbeat every 10 seconds.
* Streaming must flush each event.
* No secrets in any event.
* Multiple users may stream concurrently.

---

## 6.3 Multi-User Support

### 6.3.1 Identity Header (Required)

Every HTTP/SSE request MUST include:

```
x-savant-user-id: <user-id>
```

Set by each developer in Cline settings.

### 6.3.2 User Identification Middleware

Middleware MUST:

* Extract `x-savant-user-id`
* Validate presence
* Attach `request.user_id`

### 6.3.3 SecretStore

Internal structure:

```ruby
SecretStore[user_id][:jira][:api_token]
```

### 6.3.4 Behavior

* Each user executes tools using their own secrets.
* No cross-user contamination.
* No tokens appear in:

  * tool input
  * tool output
  * SSE
  * logs
  * error traces
  * LLM context

---

## 6.4 Root Hub Endpoint

### Endpoint

`GET /`

### Response

```json
{
  "service": "Savant MCP Hub",
  "version": "3.0.0",
  "transport": "sse",
  "hub": {
    "pid": 12345,
    "uptime_seconds": 1023
  },
  "engines": [
    {
      "name": "context",
      "path": "/context",
      "tools": 14,
      "status": "running",
      "uptime_seconds": 1022
    },
    {
      "name": "jira",
      "path": "/jira",
      "tools": 7,
      "status": "running",
      "uptime_seconds": 1019
    }
  ]
}
```

Hub MUST display:

* service name
* version
* transport
* uptime
* PID
* list of mounted engines
* per-engine stats

---

## 6.5 STDIO Backward Compatibility

### 6.5.1 Behavior

STDIO mode:

* Supports single engine only
* No SSE
* No HTTP
* No multi-user
* No hub dashboard

### 6.5.2 Cline Behavior

Existing STDIO-based flows remain unchanged:

```
cline -> savant (stdio)
```

No regressions permitted.

---

# 7. Technical Requirements

## 7.1 New Components

* `lib/savant/hub.rb`
* `lib/savant/engine_registry.rb`
* `lib/savant/http/router.rb`
* `lib/savant/http/engine_router.rb`
* `lib/savant/http/sse.rb`
* `lib/savant/middleware/user_header.rb`
* `lib/savant/secret_store.rb`

## 7.2 SSE Requirements

* Implement via Rack `response.stream.write` or chunked bodies.
* Must flush after each event.
* Must auto-close on disconnect.
* Must not block main request thread.

## 7.3 SecretStore Requirements

* Per-user secrets keyed by `user_id`.
* Support ENV + config fallback.
* MUST NOT log tokens.
* MUST NOT emit secrets via SSE or errors.

---

# 8. Observability

* Engine logs at `/tmp/savant/<engine>.log`
* Hub logs at `/tmp/savant/hub.log`
* `/status` per engine
* `/` for global hub overview

---

# 9. Acceptance Criteria

### AC1 — SSE works

* Logs, progress, results stream correctly
* Heartbeats emitted
* Multiple concurrent clients supported

### AC2 — Multi-engine mount works

* Engines mount under correct paths
* `/` lists all engines with accurate metadata

### AC3 — Multi-user secret isolation works

* Each user’s JIRA/GitLab credentials remain isolated
* No secrets leak into logs or LLM context

### AC4 — STDIO backward compatibility

* Legacy usage remains 100% functional
* No change in existing flows

### AC5 — Engines respond to all required routes

* `/tools`
* `/tools/:name/call`
* `/logs`
* `/status`
* `/stream`

---

# 10. Future Enhancements (Not in This PRD)

* Savant Web UI
* Authentication & API keys
* External secrets vault integration
* Job history and replay
* Metrics, Prometheus exporter
* Multi-host scaling

```

## Agent Implementation Plan

Goal: Ship minimal, test-covered HTTP + SSE Hub that mounts existing engines, enforces per-request user identity, and exposes required endpoints while keeping STDIO unchanged.

Plan (TDD, incremental commits):
- Add specs for Hub routes, engine mounting, and SSE headers/body contract.
- Add specs for User header middleware and SecretStore no-leak behavior.
- Implement `Savant::HTTP::Router` with per-engine routing for `/status`, `/tools`, `/tools/:name/call`, `/logs` (stub), and `/stream`.
- Implement `Savant::HTTP::SSE` body writer that emits `event:`/`data:` lines and supports heartbeat events.
- Implement `Savant::EngineRegistry` to load engines via existing `ServiceManager` and provide stats for Hub root `GET /`.
- Implement `Savant::Middleware::UserHeader` to require `x-savant-user-id` and attach `env['savant.user_id']`.
- Implement `Savant::SecretStore` (in-memory + ENV fallback) and sanitize any log payloads.
- Wire a simple `Savant::Hub` boot helper and add a CLI entry to run the HTTP server.
- Keep existing STDIO/WebSocket behavior intact; do not modify `bin/mcp_server` defaults.

Tests to add:
- `spec/savant/http/hub_spec.rb`: root hub JSON, engine endpoints shape, 404s.
- `spec/savant/http/sse_spec.rb`: correct headers (`text/event-stream`, no cache), basic event formatting, heartbeat scheduling (simulated).
- `spec/savant/middleware/user_header_spec.rb`: rejects when header missing, passes user id through env.
- `spec/savant/secret_store_spec.rb`: per-user isolation and sanitized logs.

Acceptance alignment:
- AC1: SSE events/heartbeat validated by SSE specs.
- AC2: Mounted engines and hub stats validated by hub specs.
- AC3: Secret isolation via SecretStore + middleware specs.
- AC4: No changes to STDIO paths; smoke run unchanged.
- AC5: Route coverage via hub specs for all required endpoints.

Operational notes:
- Logs write to `/tmp/savant/hub.log` and `/tmp/savant/<engine>.log`.
- Heartbeat interval configurable; default 10s.

Out of scope in this change:
- Full persistent secret backend and UI.
