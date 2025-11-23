# Rules Engine

Expose versioned rule sets (code review, backend, testing, style, security) as structured YAML + markdown for LLM clients.

## Structure
```mermaid
flowchart LR
  UI[Client/UI] -->|rules.list|get Registrar
  Registrar --> Engine
  Engine --> Ops
  Ops --> YAML[(rules.yml)]
```

## Data
- File: `lib/savant/rules/rules.yml`
- Schema: `name`, `title`, `version`, `summary`, `tags?`, `rules_md`, `notes?`

## Tools
- `rules.list` – list rule sets (filter by name/title/tags/summary)
- `rules.get` – fetch `{ name, title, version, summary, tags?, rules_md, notes? }`

## Usage
- Stdio: `MCP_SERVICE=rules SAVANT_PATH=$(pwd) ruby ./bin/mcp_server`
- Hub: `GET /rules/tools`, `POST /rules/tools/rules.get/call` with `{ params: { name } }`

## UI
- Second layer: Engines → Rules
- Third layer: Browse tab
- Page: list + YAML viewer + “View Rules” dialog (markdown) + copy icons

## Notes
- Logs at `/tmp/savant/rules.log` (Hub) and `logs/rules.log` (stdio).
