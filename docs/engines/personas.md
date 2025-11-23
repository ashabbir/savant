# Personas MCP Engine

Purpose: expose curated Savant personas as versioned prompts via MCP tools.

Tools
- personas.list: List personas (names, titles, versions, summaries, tags)
- personas.get: Fetch a persona by name with full `prompt_md`

Data
- File: `lib/savant/personas/personas.yml`
- Schema: name, title, version, summary, tags?, prompt_md, notes?

Stdio Usage
- MCP_SERVICE=personas SAVANT_PATH=$(pwd) ruby ./bin/mcp_server
- tools/list → two tools; tools/call with `{name:"personas.get", arguments:{name:"savant-engineer"}}`

Hub Mount
- Start Hub: `bundle exec ruby ./bin/savant hub` (or `make hub`)
- Auto‑mount path: `/personas` (auto‑discovered when engine files exist)
- Verify:
  - GET `/` shows `personas` in `engines`
  - GET `/personas/tools` returns two tools
  - POST `/personas/tools/personas.get/call` with `{ "params": { "name": "savant-engineer" } }`

Cline (VS Code)
```
{
  "cline.mcpServers": {
    "savant-personas": {
      "command": "/bin/zsh",
      "args": ["-lc", "MCP_SERVICE=personas SAVANT_PATH=${workspaceFolder} ruby ./bin/mcp_server"],
      "env": { "LOG_LEVEL": "info" }
    }
  }
}
```

Notes
- Logs write to `/tmp/savant/personas.log` (Hub) or `logs/personas.log` (stdio with settings).
- No DB required; YAML‑backed catalog.

