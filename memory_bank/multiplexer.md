# MCP Multiplexer

## Overview
Runs as a parent process that manages one MCP child process per engine, merges their tool specs into a single surface, and exposes a unified stdio/WebSocket interface. Provides isolation, restarts crashed engines, and surfaces status and logs.

## Key Files
- `lib/savant/multiplexer.rb`: Ensure/start multiplexer
- `lib/savant/multiplexer/engine_process.rb`: Child process supervisor
- `lib/savant/multiplexer/router.rb`: Tool namespace routing and composition
- `lib/savant/framework/mcp/server.rb`: Transport bootstrap (stdio/websocket)

## Behavior
- Spawns children for engines: `context`, `git`, `think`, `personas`, `rules`, `jira` (defaults)
- Namespaces tools: `context.fts_search`, `jira.issue.get`, etc.
- Restarts engines on crash and removes tools while down
- Writes logs to `logs/multiplexer.log` and exposes `savant engines` / `savant tools`

## CLI
```
# List engines and status
SAVANT_PATH=$(pwd) bundle exec ruby ./bin/savant engines

# List all tools (merged)
SAVANT_PATH=$(pwd) bundle exec ruby ./bin/savant tools
```

## Transport Modes
- Stdio (default via `bin/mcp_server`)
- WebSocket (set `TRANSPORT=websocket` and host/port/path via config or flags)

## Notes
- Disable with `SAVANT_MULTIPLEXER_DISABLED=1` in test runs.
- Each child writes its own `logs/<engine>.log`.

