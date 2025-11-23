# PRD: Savant – Personas MCP (Done)

Status: Done
Date: 2025-11-23
Branch: feature/savant-personas_mcp

## Summary
A lightweight MCP engine that exposes curated “Savant” personas as structured prompts for LLMs and agent runtimes. Provides discovery and lookup tools; integrates with the Hub; appears in the React UI.

## Scope Delivered (MVP)
- Engine: `personas` with stdio/HTTP via Hub.
- Tools:
  - `personas.list` — list personas (names/titles/versions/tags/summary).
  - `personas.get` — fetch a persona by name with `prompt_md`.
- Data: file‑backed catalog `lib/savant/personas/personas.yml`.
- Hub: Auto-mounted at `/personas` (via mounts) and visible in Engine grid.
- UI: Added Personas engine card + Personas tab with list + YAML viewer and prompt dialog (copy actions).
- Docs: Added `memory_bank/engine_personas.md`; consolidated README to point to Memory Bank.

## Acceptance Criteria
- [x] Exactly two tools: `personas.list` and `personas.get`.
- [x] YAML includes at least `savant-engineer` and `savant-architect` with complete `prompt_md`.
- [x] Hub lists `personas` and mounts it under `/personas`.
- [x] React dashboard shows the Personas engine in the engines grid.
- [x] Personas docs live in Memory Bank; README links to it.

## Notes
- Logs at `/tmp/savant/personas.log` (Hub) and `logs/personas.log` (stdio).
- Per‑engine logs are generated on tool calls to aid Diagnostics.

## Pointers
- Engine: `lib/savant/personas/{engine.rb,ops.rb,tools.rb}`
- Data: `lib/savant/personas/personas.yml`
- Docs: `memory_bank/engine_personas.md`
- UI: `frontend/src/pages/personas/Personas.tsx`, `frontend/src/components/EngineCard.tsx`

