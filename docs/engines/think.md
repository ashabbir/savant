# Think Engine (File‑by‑File)

Purpose: Deterministic orchestration and reasoning — plan → execute → next loop.

## Files
- Engine façade: [lib/savant/think/engine.rb](../../lib/savant/think/engine.rb)
- Tools registrar: [lib/savant/think/tools.rb](../../lib/savant/think/tools.rb)
- Workflows: [lib/savant/think/workflows/](../../lib/savant/think/workflows)
- Prompts registry: [lib/savant/think/prompts.yml](../../lib/savant/think/prompts.yml)
- Driver prompts: [lib/savant/think/prompts/](../../lib/savant/think/prompts)
- State files (runtime): `.savant/state/<workflow>.json`

## Tools
- `think.driver_prompt`: versioned bootstrap prompt `{version, hash, prompt_md}`
- `think.plan`: initialize a run and return the first instruction + state
- `think.next`: record step result and return next instruction or final summary
- `think.workflows.list`: list workflow IDs and metadata
- `think.workflows.read`: return raw workflow YAML

## Starter Workflows
- `review_v1`, `code_review_v1`, `develop_ticket_v1`, `ticket_grooming_v1`

## Run
- Stdio: `MCP_SERVICE=think SAVANT_PATH=$(pwd) ruby ./bin/mcp_server`
- HTTP (testing): `MCP_SERVICE=think ruby ./bin/mcp_server --http`

