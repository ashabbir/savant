# Memory: Personas Engine

- Purpose: Provide versioned Savant personas as prompts.
- Data file: `lib/savant/personas/personas.yml` (YAML list of entries)
- Schema: `name`, `title`, `version`, `summary`, `tags?`, `prompt_md`, `notes?`
- Typical usage: client fetches a persona then injects `prompt_md` as the system prompt.

MCP Stdio
- Start: `MCP_SERVICE=personas SAVANT_PATH=$(pwd) ruby ./bin/mcp_server`
- Call: `tools/call` name=`personas.get` arguments=`{"name":"savant-engineer"}`

Hub HTTP
- GET `/personas/tools` to list
- POST `/personas/tools/personas.get/call` with `{ "params": { "name": "savant-engineer" } }`

