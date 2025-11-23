## Savant – Rules MCP (MVP)

> Centralized, versioned “Savant Rules” surfaced over MCP so agents and editors can reliably discover and load the current rules we need to follow.

## Problem & Outcome
- Problem: Our engineering/architecture/product rules live in scattered docs and chats; agents inconsistently follow them.
- Outcome: A dedicated MCP engine that returns the canonical, versioned rules. Clients can list, search, and load specific rule sets and render them in the UI.

## In Scope (MVP)
- Engine: `rules` (Savant Rules) with stdio/HTTP support.
- Tools:
  - `rules.list` — list all rule sets with metadata; simple text filter.
  - `rules.get` — load a rule set by name (full markdown body + metadata).
- Data: File‑backed YAML catalog in repo; no DB.
- Hub: Auto‑mounted under `/rules` and visible in Hub engines list.
- React UI:
  - Dashboard: appears as a mounted engine card.
  - Rules Page (MVP): a minimal page to browse and view a rule set.
- Docs: Engine README with stdio usage and explicit Hub mounting instructions (next task after MVP PRD).

## Out of Scope (MVP)
- Web editor for rule authoring (manual YAML edits only).
- User‑scoped overrides or remote sources (future backends possible).
- Enforcement/validation in other engines (consumers remain responsible for applying rules).

## Rules Data Model
- Location: `lib/savant/rules/rules.yml`
- Schema (YAML list of objects):
  - `name` (string, required, unique): key (e.g., `savant-engineering-rules`).
  - `title` (string, required): display (e.g., `Savant Engineering Rules`).
  - `version` (string, required): semantic/date tag (e.g., `v1.0.0`).
  - `summary` (string, required): one‑liner.
  - `tags` (string[] optional): keywords (e.g., [`engineering`, `architecture`, `review`]).
  - `category` (string, optional): grouping (e.g., `engineering`, `architecture`, `process`).
  - `rules_md` (string, required): full markdown rules text.
  - `notes` (string, optional): extra guidance.

Example snippet:
```yaml
- name: savant-engineering-rules
  title: Savant Engineering Rules
  version: v1.0.0
  summary: Day‑to‑day coding, testing, and change management rules.
  tags: ["engineering", "ruby", "testing"]
  category: engineering
  rules_md: |
    ## Engineering Rules
    - Prefer small, focused changes; keep diffs tight.
    - Write clear commit messages: imperative mood, why + what.
    - Add/adjust tests when changing behavior; avoid unrelated fixes.

- name: savant-architecture-principles
  title: Savant Architecture Principles
  version: v1.0.0
  summary: Boundaries, data ownership, and coupling guidelines.
  tags: ["architecture", "design"]
  category: architecture
  rules_md: |
    ## Architecture Principles
    - Design clear module seams; minimize cross‑cutting concerns.
    - Prefer composition over inheritance.
```

## Engine Structure
- Files:
  - `lib/savant/rules/engine.rb` — entrypoint.
  - `lib/savant/rules/ops.rb` — YAML loading, list/get logic.
  - `lib/savant/rules/tools.rb` — MCP registrar and schemas.
- Service selector: `MCP_SERVICE=rules`.
- Logs: `logs/rules.log` via `Savant::Logger`.

## MCP Tools (Contracts)
1) `rules.list`
   - Purpose: discover rule sets.
   - Input: `{ filter?: string, category?: string }`
   - Output: `{ rules: [{ name, title, version, summary, tags?, category? }] }`
   - Errors: `invalid_input`, `load_error`.

2) `rules.get`
   - Purpose: fetch a rule set by `name`.
   - Input: `{ name: string }`
   - Output: `{ name, title, version, summary, tags?, category?, rules_md, notes? }`
   - Errors: `not_found`, `invalid_input`, `load_error`.

## React UI Integration (MVP)
- Dashboard card: display “Rules” (mount `/rules`) with tool count `2`.
- New page: `/rules`
  - Components:
    - Search input (client‑side filter against list response)
    - List of rule sets (title, version, summary, tags)
    - Detail panel showing `rules_md` for the selected item + copy button
  - Data source: Hub endpoints
    - `GET /rules/tools` (discovery)
    - `POST /rules/tools/rules.list/call` (list)
    - `POST /rules/tools/rules.get/call` (load)
- Minimal UI is acceptable; styling consistent with existing dashboard visuals.

## Hub Mounting & Auto‑Discovery
- Default path: `/rules`.
- Auto‑mount: If no mounts config, Hub mounts known engines including `rules` when code/assets are present.
- Optional config (`config/mounts.yml`):
  ```yaml
  mounts:
    - engine: "context"
      path: "/context"
    - engine: "think"
      path: "/think"
    - engine: "jira"
      path: "/jira"
    - engine: "rules"
      path: "/rules"
  ```
- Verification:
  - `curl -s -H "x-savant-user-id: me" http://localhost:9999/` shows `rules` in `engines`.
  - `curl -s -H "x-savant-user-id: me" http://localhost:9999/rules/tools` lists the tools.

## Engine README + Mounting Instructions
- Add `docs/engines/rules.md` (follow personas doc pattern):
  - Stdio: `MCP_SERVICE=rules SAVANT_PATH=$(pwd) ruby ./bin/mcp_server`
  - Mount: `bundle exec ruby ./bin/savant hub` → `GET /rules/tools`
  - Example calls for `rules.list` and `rules.get`.

## Memory Bank Entry
- Add `memory_bank/engine_rules.md` with quick usage and data location.

## Docs, Memory Bank, and Cline Setup
- Memory Bank: create `memory_bank/engine_rules.md` summarizing API, YAML schema, and typical usage (load rules into UI/agent context).
- README: add a short Rules section under Engines with stdio + mount examples, linking to `docs/engines/rules.md`.
- Cline (VS Code) — Stdio configuration:
  - Settings JSON snippet:
    ```json
    {
      "cline.mcpServers": {
        "savant-rules": {
          "command": "/bin/zsh",
          "args": [
            "-lc",
            "MCP_SERVICE=rules SAVANT_PATH=${workspaceFolder} bundle exec ruby ./bin/mcp_server"
          ]
        }
      }
    }
    ```
  - How it runs: Cline launches the MCP via stdio; tools appear under “savant-rules”. Use `rules.list` to browse and `rules.get` to render `rules_md` in the UI.

## Acceptance Criteria
- MCP engine exposes exactly two tools: `rules.list` and `rules.get`.
- Rules YAML includes at least two canonical sets (engineering rules, architecture principles) with complete `rules_md`.
- Hub lists and mounts the engine under `/rules`.
- React shows a “Rules” card on the dashboard and provides a minimal `/rules` page to browse and view rule sets.
- Engine README includes stdio AND Hub mounting instructions near any stdio example.

## Follow‑Ups (Post‑MVP)
- Validation schema and CI check for `rules.yml`.
- User‑scoped or team‑scoped overlays (merge rules).
- Version pinning warnings in `rules.get`.
- Export to clipboard/download as `.md` from the UI page.
