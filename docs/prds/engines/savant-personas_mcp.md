# Savant – Personas MCP (MVP)

> A lightweight MCP engine that exposes curated “Savant” personas (e.g., Savant Engineer, Savant Architect) as structured prompts for LLMs and agent runtimes. Provides discovery and lookup tools, integrates with the Hub for auto‑mounting, and surfaces in the React UI.

## Problem & Outcome
- Problem: Users repeatedly ask LLMs/agents to “act as a Savant engineer/architect,” but lack consistent, versioned, and discoverable role prompts.
- Outcome: A dedicated MCP engine that stores canonical personas and exposes simple tools to list and fetch persona prompts by name. Personas are easy to mount, query, and reuse across editors and flows.

## In Scope (MVP)
- Engine: `personas` (a.k.a. “savant personas”) with stdio/HTTP MCP support like other engines.
- Tools:
  - `personas.list` — returns all personas (names, titles, versions, brief summaries/tags).
  - `personas.get` — returns a single persona by name with full prompt text and metadata.
- Data: File‑backed personas catalog in repo (YAML), versioned entries; no DB required.
- Hub: Auto‑mount under `/personas` (default) and appear in Hub root `engines` listing.
- React UI: Show as a mounted engine card (like context/think/jira). Optional detail view may follow later; MVP only requires presence in the dashboard as a mounted engine.
- Docs: Engine README with stdio usage AND explicit “Hub mount” instructions, plus a memory bank page.

## Out of Scope (MVP)
- Persona authoring UI (manual edits to YAML only).
- Remote or user‑scoped persona stores (future optional backends).
- LLM execution or persona application logic (consumers apply prompt themselves).

## Personas Data Model
- Location: `lib/savant/personas/personas.yml`
- Schema (YAML list of objects):
  - `name` (string, required, unique): machine‑friendly key (e.g., `savant-engineer`).
  - `title` (string, required): display name (e.g., `Savant Engineer`).
  - `version` (string, required): semantic or date tag (e.g., `v1.0.0`, `stable-2025-01`).
  - `summary` (string, required): short one‑liner on persona purpose.
  - `tags` (string[] optional): keywords (e.g., [`code`, `architecture`, `ruby`]).
  - `prompt_md` (string, required): full markdown prompt for the persona.
  - `notes` (string, optional): guidance for usage or limits.

Example snippet:
```yaml
- name: savant-engineer
  title: Savant Engineer
  version: v1.0.0
  summary: Pragmatic code implementer with strong Ruby/Postgres focus.
  tags: ["engineering", "ruby", "postgres", "mcp"]
  prompt_md: |
    You are the Savant Engineer. You implement small, well‑scoped changes...

- name: savant-architect
  title: Savant Architect
  version: v1.0.0
  summary: Systems‑level thinker for clean boundaries and maintainability.
  tags: ["architecture", "design", "review"]
  prompt_md: |
    You are the Savant Architect. You design clear seams, enforce...
```

## Engine Structure
- Files (mirror existing engine patterns):
  - `lib/savant/personas/engine.rb` — entrypoint; dispatches tool calls.
  - `lib/savant/personas/ops.rb` — loads YAML catalog; implements list/get.
  - `lib/savant/personas/tools.rb` — MCP registrar with input/output schemas.
  - `logs/personas.log` — engine logs (via `Savant::Logger`).
- Service selection: `MCP_SERVICE=personas`.
- Transport: stdio (default) or HTTP (test mode) via `bin/mcp_server` flags.

## MCP Tools (Contracts)
1) `personas.list`
   - Purpose: discover available personas.
   - Input: `{ filter?: string }` (substring on `name|title|tags|summary`).
   - Output: `{ personas: [{ name, title, version, summary, tags? }] }`.
   - Errors: `invalid_input`, `load_error`.

2) `personas.get`
   - Purpose: fetch one persona by `name`.
   - Input: `{ name: string }`.
   - Output: `{ name, title, version, summary, tags?, prompt_md, notes? }`.
   - Errors: `not_found`, `invalid_input`, `load_error`.

## React UI Integration (MVP)
- Dashboard: must appear as a mounted engine card with name “Personas” (or “Savant Personas”), mount `/personas`, and tool count `2`.
- Card icon/color: align with existing pattern in `EngineCard` (e.g., add a `personas` icon/color mapping if needed in a follow‑up PR).
- No dedicated route/view is required for MVP (optional future: simple browser calling `personas.list` and rendering summaries).

## Hub Mounting & Auto‑Discovery
- Default path: `/personas`.
- Auto‑mount behavior: if mounts config is absent, Hub should mount known engines including `personas` when its engine files are present.
- Config file (optional): `config/mounts.yml` may include:
  ```yaml
  mounts:
    - engine: "context"
      path: "/context"
    - engine: "think"
      path: "/think"
    - engine: "jira"
      path: "/jira"
    - engine: "personas"
      path: "/personas"
  ```
- Verification:
  - `curl -s -H "x-savant-user-id: me" http://localhost:9999/` lists `personas` in `engines`.
  - `curl -s -H "x-savant-user-id: me" http://localhost:9999/personas/tools` shows two tools.

## Engine README + Mounting Instructions
- Add `docs/engines/personas.md` covering:
  - What/why, tool docs, and examples.
  - Stdio usage:
    - `MCP_SERVICE=personas SAVANT_PATH=$(pwd) ruby ./bin/mcp_server`
  - Hub mount usage (explicit, near every stdio example):
    - Start Hub: `bundle exec ruby ./bin/savant hub` (or `make hub`).
    - Ensure mounts include `/personas` (auto or via config).
    - Example calls to `GET /personas/tools` and `POST /personas/tools/:name/call`.

## Docs, Memory Bank, and Cline Setup
- Memory Bank: add `memory_bank/engine_personas.md` (summary, API, data file path, usage pattern). Keep it linked from any memory index if present.
- README: add a brief Personas section under Engines with stdio + mount examples, linking to `docs/engines/personas.md`.
- Cline (VS Code) — Stdio configuration:
  - Settings JSON snippet:
    ```json
    {
      "cline.mcpServers": {
        "savant-personas": {
          "command": "/bin/zsh",
          "args": [
            "-lc",
            "MCP_SERVICE=personas SAVANT_PATH=${workspaceFolder} bundle exec ruby ./bin/mcp_server"
          ],
          "env": {
            "LOG_LEVEL": "info"
          }
        }
      }
    }
    ```
  - How it runs: Cline launches the MCP via stdio; tools appear under “savant-personas”. Use tools/call to fetch `personas.get` and apply `prompt_md` as system prompt.

## Memory Bank Entry
- Add `memory_bank/engine_personas.md` summarizing:
  - Engine purpose and quick usage.
  - YAML data location and schema.
  - Typical integration pattern: client fetches a persona, injects `prompt_md` as system prompt.

## Ops & Logging
- Logs to `logs/personas.log` in MCP mode; include tool calls, durations, and errors.
- Env: `LOG_LEVEL` honored; no secrets required.

## Acceptance Criteria
- MCP engine exposes exactly two tools: `personas.list` and `personas.get`.
- Personas YAML supports at least `savant-engineer` and `savant-architect` with complete `prompt_md`.
- Hub lists the engine and mounts it under `/personas` by default (or via config file).
- React dashboard shows the Personas engine in the engines grid.
- `docs/engines/personas.md` includes stdio AND mounting instructions wherever stdio is mentioned.
- `memory_bank/engine_personas.md` exists and is linked from the main README’s memory section if applicable.

## Follow‑Ups (Post‑MVP)
- Add a simple UI view to browse personas (`/personas` route) and copy prompts.
- User‑scoped personas (merge user file into base catalog).
- Validation via JSON Schema and CI checks for persona YAML.
- Version pinning and deprecation warnings in `personas.get`.
