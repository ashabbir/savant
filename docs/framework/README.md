# Framework Documentation

This section documents the Savant framework: transports, dispatcher, tool DSL, config, and logging — with a file‑by‑file map.

## Overview
- Single active service per process, selected via `MCP_SERVICE`.
- Transports: stdio (default), WebSocket, HTTP.
- Tool registrar DSL with middleware and JSON Schema validation.
- Structured logging and simple config loader.

## Key Files (file‑by‑file)
- Server launcher: [lib/savant/mcp_server.rb](../../lib/savant/mcp_server.rb)
  - Chooses transport and starts service based on `MCP_SERVICE`.
- Transports (stdio/websocket):
  - [lib/savant/transports/stdio.rb](../../lib/savant/transports/stdio.rb)
  - [lib/savant/transports/websocket.rb](../../lib/savant/transports/websocket.rb)
- JSON‑RPC dispatcher: [lib/savant/mcp_dispatcher.rb](../../lib/savant/mcp_dispatcher.rb)
  - Handles `initialize`, `tools/list`, `tools/call`; loads the active engine and registrar.
- Tool DSL and Core:
  - [lib/savant/mcp/core/dsl.rb](../../lib/savant/mcp/core/dsl.rb)
  - [lib/savant/mcp/core/tool.rb](../../lib/savant/mcp/core/tool.rb)
  - [lib/savant/mcp/core/middleware.rb](../../lib/savant/mcp/core/middleware.rb)
  - [lib/savant/mcp/core/registrar.rb](../../lib/savant/mcp/core/registrar.rb)
  - [lib/savant/mcp/core/validation.rb](../../lib/savant/mcp/core/validation.rb)
  - [lib/savant/mcp/core/validation_middleware.rb](../../lib/savant/mcp/core/validation_middleware.rb)
- Engine base + shared context:
  - [lib/savant/core/engine.rb](../../lib/savant/core/engine.rb)
  - [lib/savant/core/context.rb](../../lib/savant/core/context.rb)
- Logging + Config:
  - [lib/savant/logger.rb](../../lib/savant/logger.rb)
  - [lib/savant/config.rb](../../lib/savant/config.rb)

## Transports
- Stdio: line‑oriented JSON‑RPC 2.0. Default for editors (Cline, Claude Code).
- WebSocket: JSON‑RPC framed over ws:// for web apps and network clients.
- HTTP: optional for testing with curl/scripted tools.

## Tool DSL & Middleware
- Declare tools with JSON schema; middlewares enforce validation, logging, auth, etc.
- Registrars are built with `Savant::MCP::Core::DSL.build` and passed to the dispatcher.

## Initialize → List → Call
- Clients call `initialize` then `tools/list` to discover tools for the active engine.
- `tools/call` executes a tool by name with `arguments`.

## Configuration
- Primary: `config/settings.json` (see [config/schema.json](../../config/schema.json)).
- Env vars: `MCP_SERVICE`, `SAVANT_PATH`, `LOG_LEVEL`, plus engine‑specific.

## Logging
- JSON logs (default) to stdout and optional file sinks. See [lib/savant/logger.rb](../../lib/savant/logger.rb).

