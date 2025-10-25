# PRD: Optional WebSocket Transport for MCP (Ruby Server)

## Problem
- Current MCP server communicates over stdio using JSON-RPC 2.0.
- Some clients prefer persistent, bidirectional network transports (e.g., browser-based tooling, remote hosts).
- We need WebSocket support without breaking existing stdio workflows.

## Goals
- Add optional WebSocket transport while keeping stdio as the default.
- Reuse existing JSON-RPC 2.0 message schema and method contracts.
- Provide a simple server bootstrap to listen on a configurable address/port.
- Support multiple concurrent WebSocket clients with isolated sessions.

## Non-Goals
- Changing JSON-RPC message shapes or MCP method semantics.
- Introducing authentication/authorization beyond basic configuration (can be added later).
- Encrypted transport management (recommend running behind TLS terminator/reverse proxy in v1).

## Users & Use Cases
- Editor/IDE extensions running out-of-process connecting via ws://localhost.
- Browser-hosted MCP clients using WebSocket to reach a local or remote server.
- Remote CI/tooling connecting to a long-running MCP service.

## Scope
- Transport abstraction that supports two modes: `stdio` (default) and `websocket`.
- WebSocket endpoint that accepts JSON-RPC 2.0 messages framed as text.
- Graceful lifecycle: start, stop, and per-connection session cleanup.
- Configurable listen address, port, and optional path.

## Backward Compatibility
- Stdio remains the default; no changes required for existing users.
- JSON-RPC payloads are identical across transports.
- Feature is opt-in via config and/or CLI flag; disabled by default.

## Configuration
```yaml
transport:
  mode: stdio   # enum: stdio|websocket (default: stdio)
  websocket:
    host: 127.0.0.1
    port: 8765
    path: "/mcp"
    max_connections: 100
    # tls is out-of-scope for v1; recommend proxy-terminating TLS
```

## CLI
- `bin/mcp_server` gains an optional flag `--transport=stdio|websocket`.
- WebSocket mode prints a startup line with bound address and path.

## Protocol
- Message format: JSON-RPC 2.0 as text frames over WebSocket.
- One session per WebSocket connection; requests/responses correlate by `id`.
- Keepalive: optional ping/pong at configurable interval.

## Server Behavior
- On connection: create session, send optional `server/hello` event (if applicable).
- On message: validate JSON, enforce JSON-RPC schema, dispatch to existing handlers.
- On close/error: tear down session, cancel in-flight requests, release resources.

## Error Handling
- Invalid JSON: close with code 1003 (unsupported data) after sending error if possible.
- Protocol violation: close with code 1002 (protocol error).
- Backpressure: apply send queue limits; drop connection if exceeded with explicit log.

## Telemetry & Logging
- Log startup config (transport, host, port, path).
- Track active connections, total accepted, graceful/abrupt closes, and error counts.

## Implementation Notes (Ruby)
- Introduce a transport interface, e.g., `Savant::Transport` with `start`, `stop`, and a message callback.
- `StdioTransport` reuses current code; `WebSocketTransport` uses a lightweight WS library (e.g., `faye-websocket` or `websocket-driver`).
- Event loop: prefer `async`/`falcon` or standard `EventMachine` depending on chosen library; keep dependencies minimal and Bundler-managed.
- Ensure thread-safety or evented design for per-connection state; avoid global mutable state.

## Security
- Default bind to `127.0.0.1` to avoid unintended remote exposure.
- Recommend TLS termination via reverse proxy when exposing beyond localhost.
- Document that no authentication is provided in v1.

## Acceptance Criteria
- Default run (no flags, no config) continues to use stdio unchanged.
- With `transport.mode=websocket`, server accepts ws connections and processes JSON-RPC requests successfully.
- Multiple concurrent connections operate independently with correct request/response correlation.
- Graceful shutdown closes all connections without leaking resources.
- Documentation updated with config, CLI flags, and examples.

## Developer Workflow
- Make targets unchanged; when implemented, add example run docs: `bundle exec bin/mcp_server --transport=websocket`.
- New gems, if any, added to `Gemfile` under a clear group with minimal footprint.

