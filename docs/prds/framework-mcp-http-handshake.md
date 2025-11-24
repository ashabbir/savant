# Savant Hub HTTP MCP Adapter PRD

## Problem

VS Code Codex and other MCP clients speak JSON-RPC 2.0 over a single MCP “initialize → tools/list → tools/call” flow. Savant’s hub only exposes per-engine REST endpoints (e.g., `/context/tools`), so Codex can’t connect via HTTP—it expects one MCP-compliant endpoint and receives 404s. Today users must run separate stdio servers per engine, which complicates setup and defeats the purpose of the multi-engine hub.

## Goal

Add a centralized JSON-RPC MCP adapter inside the hub so **one HTTP endpoint** negotiates the MCP handshake, answers `tools/list`, and proxies `tools/call` for every engine. Engines remain unchanged; the framework layer owns all MCP protocol details. After this work, Codex or any MCP client can point at `http://<host>/mcp` (or similar) and access context, jira, and future engines over HTTP without bespoke code.

## Requirements

1. **Single Adapter**: Implement `Savant::MCP::HttpAdapter` (name TBD) that knows how to:
   - Parse JSON-RPC 2.0 requests.
   - Handle MCP methods (`initialize`, `ping`, `list_tools`, `call_tool`, notifications).
   - Emit JSON-RPC responses and server-sent notifications (agent messages, tool outputs).
   - Authenticate via existing headers (`x-savant-user-id`) before dispatch.
2. **Engine-Agnostic Routing**:
   - Hub registry already tracks engines. Adapter receives `{ engine: "context", method: "tools/call", ... }` and fetches the appropriate registrar/engine objects.
   - No engine-specific HTTP handlers; the same adapter serves `/context`, `/jira`, `/think`, etc., via a shared code path.
3. **Session Handling**:
   - Maintain per-connection state so `initialize` runs once and subsequent calls reuse the negotiated capabilities (e.g., via a session cache keyed by request token or header).
   - Support Codex expectations for `ping`/keepalive.
4. **Streaming Support**:
   - Codex uses incremental `agent_message` notifications. Adapter must relay streaming output from engines (if available) or synthesize the minimal required notifications.
5. **Backwards Compatibility**:
   - Existing REST endpoints stay untouched so other clients are unaffected.
   - Stdio MCP server (`bin/mcp_server`) continues to work.

## Out of Scope

- Engine-specific protocol changes.
- Non-MCP HTTP features (dashboards, HTML) beyond what is needed for MCP JSON-RPC.
- Authentication redesign—reuse current header-based checks.

## Design Sketch

1. **Router Changes**:
   - Add routes such as `POST /mcp/:engine` (or `/engines/:engine/mcp`). Each route invokes the shared adapter with `engine_name` and raw request body.
2. **Adapter Structure**:
   - `initialize(engine_name, params)`:
     - Validate engine exists and user is authorized.
     - Retrieve tool metadata from the engine’s registrar (cacheable).
     - Return MCP capabilities (tool list, protocol version, server info).
   - `list_tools(engine_name)` reuses the same metadata fetch path.
   - `call_tool(engine_name, params)`:
     - Delegate to the engine’s existing tool executor (e.g., `ops.call_tool`).
     - Stream or buffer tool output and translate into MCP result objects / notifications.
   - Error handling maps internal exceptions to JSON-RPC error codes.
3. **Framework Hooks**:
   - Hub already knows each engine’s registrar (`context/tools.rb`, `jira/tools.rb`). Provide a registry accessor (e.g., `Hub.registry.fetch(engine_name)`).
   - Introduce utility classes for JSON-RPC encoding/decoding and response streaming so the adapter stays focused.
4. **Logging & Metrics**:
   - Wrap MCP calls in `Savant::Logger.with_timing` to log per-engine latency and failures.

## Testing Plan

1. Unit tests for JSON-RPC parsing and adapter dispatch (mock registrars).
2. Integration test hitting `POST /mcp/context` with `initialize` and `tools/call` (using a lightweight engine stub).
3. Manual validation with Codex HTTP MCP transport: connect, list tools, invoke `fts/search`.
4. Regression tests ensure legacy REST endpoints still respond to curl.

## Milestones

1. **Adapter Skeleton**: JSON-RPC parser, routing hook, `initialize`/`list_tools` support for one engine.
2. **Tool Invocation**: Wire `tools/call` → engine ops, handle streaming + logging.
3. **Multi-Engine Support**: Confirm hub registry iteration works; add tests covering multiple engines.
4. **Docs & Release**: Update README/docs (including this PRD reference) with instructions for Codex configuration over HTTP.

## Risks & Mitigations

- **Streaming Semantics**: Codex expects incremental messages. Mitigation: start with buffered responses (single `result`) and incrementally add streaming once behavior is confirmed.
- **Session Explosion**: If sessions are keyed per request header, memory could grow. Mitigation: expire sessions after inactivity; optionally rely on stateless requests if Codex tolerates re-initialization.
- **Protocol Drift**: MCP spec may evolve. Mitigation: encapsulate protocol constants/types in one module so updates are centralized.

Delivering this adapter lets developers configure Codex once (HTTP transport) instead of juggling multiple stdio servers, making Savant’s multi-engine hub truly plug-and-play for MCP clients.

---

## Agent Implementation Plan

1. Add `Savant::MCP::HttpAdapter` (initialize, tools/list, tools/call, ping).
2. Wire Hub routes: `POST /mcp/:engine`, `POST /:engine/mcp`, and `POST /mcp` (engine in params).
3. Reuse `ServiceManager` for engine-agnostic dispatch; include user_id in ctx.
4. Basic specs with `Rack::MockRequest` for handshake and tool calls.
5. Docker validate: start Hub, curl initialize/tools/list/tools/call.
6. Update Codex config to point to `http://localhost:9999/mcp/context` with header.
7. Add Make target `mcp-http-test` for quick HTTP MCP checks.

Status
- 1–3: Implemented.
- 4: Implemented basic adapter spec.
- 5: Validated against running Hub (Docker).
- 6: Updated local Codex config.
- 7: Added in Makefile.

Next
- Optional: Add SSE streaming notifications for incremental output.
- Optional: Session cache for capabilities across requests.
