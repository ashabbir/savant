# PRD — Full Logging & Diagnostics for Savant MCP Hub

## 1. Overview
Savant needs centralized, structured, real-time logging for every MCP engine mounted in the hub.  
This logging layer must capture:

1. All requests  
   - HTTP inbound  
   - STDIO messages  
2. All tool calls  
3. All client connections  
4. Per-MCP metrics & diagnostics  
5. Historical logs + live streaming logs

This is infrastructure, not optional sugar.

---

## 2. Goals
- Full observability over every MCP engine.
- One consistent logging format across STDIO, HTTP, SSE.
- Ability to track connected clients and which MCP instance they’re talking to.
- Diagnostics endpoint/page for per-MCP health, clients, tools invoked, timestamps.

---

## 3. Non-Goals
- External log shipping (ELK, Datadog, Loki).  
- Rate limiting or alerting.  
- Machine learning anomaly detection.

---

## 4. Requirements

### 4.1 Logging Requirements

#### 4.1.1 Every HTTP request
Log:
- Timestamp  
- HTTP method  
- Path  
- Query params  
- Body  
- Response status  
- Response time  
- Associated MCP engine  
- Associated client  

---

#### 4.1.2 Every STDIO message
Log:
- Raw inbound message  
- Processed payload  
- Tool calls  
- Responses  
- Duration  

---

#### 4.1.3 Every tool call
Log:
- MCP engine  
- Tool name  
- Arguments  
- Caller  
- Start/end/duration  
- Result  
- Errors  

---

#### 4.1.4 Connection Tracking
Track:
- Client count  
- MCP they talk to  
- Connection type (HTTP/SSE/STDIO)  
- Connected since  
- Last activity  

Endpoint: `/diagnostics/connections`

---

#### 4.1.5 Error Logging
Must include:
- stacktrace  
- context  
- engine  
- client  
- method/route  

---

#### 4.1.6 Log Storage
Two layers:
- In-memory rolling buffer (last 10k events)  
- File-based rotating logs (`logs/savant.log`)  

---

### 4.2 Diagnostics Requirements

#### 4.2.1 Per-MCP Diagnostic View
Endpoint: `/diagnostics/mcp/:name`

Must show:
- Core info  
- Active clients  
- Tool metrics  
- Recent logs filtered by MCP  
- Version info  
- Health check  

---

#### 4.2.2 Global Diagnostics Page
Endpoint: `/diagnostics`

Shows:
- Total engines  
- Total clients  
- Traffic summary  
- Error rate  
- CPU/memory per MCP (if local)  
- Top tools  
- Links to per-MCP diagnostics  

---

#### 4.2.3 Live Log Stream
Endpoint: `/diagnostics/log/stream` using SSE.

Events:
- request_received  
- tool_call_started  
- tool_call_completed  
- client_connected  
- client_disconnected  
- error  

---

## 5. Architecture Changes

### 5.1 Logging Layer
New module: `Savant::Logging::EventRecorder`

Responsibilities:
- Standard log structure  
- Write to memory buffer  
- Write to rotated file  
- Broadcast to SSE  
- Filtering  

---

### 5.2 Connection Manager
`Savant::Connections`

Tracks connections for:
- SSE  
- HTTP sessions  
- STDIO processes  

---

### 5.3 MCP Registry Enhancement
Add:
- last_seen  
- connection_count  
- total_requests  
- total_tool_calls  

---

## 6. API Endpoints

### 6.1 Logs
| Endpoint | Description |
|---------|-------------|
| `/logs` | Paginated logs (filter by engine/type) |
| `/logs/:mcp` | Logs for specific MCP |
| `/logs/stream` | SSE stream |

---

### 6.2 Diagnostics
| Endpoint | Description |
|---------|-------------|
| `/diagnostics` | Global dashboard |
| `/diagnostics/mcp/:name` | Per-engine diagnosis |
| `/diagnostics/connections` | List connections |

---

## 7. Logging Format Example

```json
{
  "ts": "2025-11-27T14:04:31Z",
  "type": "tool_call",
  "mcp": "context",
  "tool": "list_dir",
  "client_id": "cline-55",
  "args": {"path": "/app"},
  "duration_ms": 31,
  "status": "success"
}
```
8. Performance Requirements
Logging must not block MCP engines.

File writing done in background thread.

Memory buffer capped at 10k entries.

SSE using async queue.

9. Backward Compatibility
STDIO flows unchanged.

Logging automatically wraps all transports.

Diagnostics is additive, not breaking.

10. Open Questions
Do you want per-MCP log-level overrides?

Logs in UTC or local TZ?

Auto-delete logs after X days?

---

## Agent Implementation Plan (executed)

1) Add global `Savant::Logging::EventRecorder` with in-memory ring buffer (10k), JSONL rotating file (`logs/savant.log`, 5MB), and SSE subscription API.
2) Add `Savant::Connections` registry tracking SSE/stdio connections with connect/disconnect and last activity.
3) Integrate EventRecorder + Connections into HTTP Router:
   - Record unified `http_request` events with method/path/status/duration/user.
   - New endpoints:
     - `GET /logs` (aggregated events, with `?mcp`/`?type` filters)
     - `GET /logs/stream` (SSE live event stream, filters supported)
     - `GET /diagnostics/connections` (active connections)
     - `GET /diagnostics/mcp/:name` (per-engine diagnostics: info, connections, request stats, recent events)
   - Track SSE connections for `/hub/...`, `/:engine/logs?stream=1`, `/:engine/stream`, and `/:engine/tools/:name/stream`.
4) Enhance `ServiceManager` to emit `tool_call_started`, `tool_call_completed`, and `tool_call_error` events and track `total_tool_calls` and `last_seen`.
5) Enhance stdio transport to emit `stdio_message` in/out events and register a pseudo-connection for the process lifecycle.
6) Keep existing per-engine file-tailing endpoints intact for UI compatibility (`/:engine/logs`, `/:engine/logs?stream=1`).
7) Add README section documenting new diagnostics/log endpoints.
