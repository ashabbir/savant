# Think Engine

Deterministic orchestration for LLM‑driven workflows: plan → execute tool → next, repeat until done.

## What Is Think
Think is a lightweight workflow engine exposed over MCP (stdio/HTTP). It loads YAML workflows, enforces a directed acyclic graph (DAG) of steps, and coordinates tool calls by returning precise instructions to the client. It also provides a versioned driver prompt to keep agent behavior predictable across runs.

## Why It’s Needed
- Consistency: Reproducible, step‑by‑step execution for complex tasks (e.g., code review).
- Safety: Enforces payload discipline and schema checks (no invented tools; size limits).
- Portability: No database; workflows, prompts, and state live in the repo.
- Extensibility: Add or change workflows without code changes; Think validates and runs them.

## Tools (API Surface)
- `think.driver_prompt`: Returns the versioned driver prompt `{ version, hash, prompt_md }` from `prompts.yml`.
- `think.plan`: Starts a run for a given `workflow` with `params`; returns the first instruction and engine state.
- `think.next`: Records a step result (the tool snapshot) and returns the next instruction, or `done: true` when complete.
- `think.workflows.list`: Lists available workflows and basic metadata.
- `think.workflows.read`: Returns the raw YAML for a specific workflow (read‑only).

## What You Can Do With It
- Run the provided workflows:
  - `code_review_initial` (Phase 1) and `code_review_final` (Phase 2)
  - `review_v1`, `develop_ticket_v1`, `ticket_grooming_v1`
- Create your own workflows under `lib/savant/think/workflows/` and iterate quickly.
- See per‑workflow descriptions and diagrams here: [docs/engines/workflows](./workflows/)

## How It Works
1) Client calls `think.plan(workflow, params)` → Think loads YAML, validates schema, builds a DAG, injects the driver prompt if needed, and returns the first instruction `{ step_id, call, input_template }`.
2) Client executes exactly that tool (e.g., `local.read`, `gitlab.get_merge_request`, `fts/search`).
3) Client sends the tool’s snapshot to `think.next(workflow, run_id, step_id, result_snapshot)`.
4) Think persists state (`.savant/state/<workflow>__<run_id>.json`), marks the step complete, and returns the next instruction. Repeat until finished.

Details
- Workflows: `.yml|.yaml` accepted; each step defines `id`, `call`, `deps`, and an `input_template`; optional `capture_as` stores the tool snapshot in state.
- Driver prompt: Versioned via `lib/savant/think/prompts.yml` and returned by `think.driver_prompt`.
- Limits: Payload size caps with truncation/summarization to keep snapshots manageable.

## Run
- Stdio: `MCP_SERVICE=think SAVANT_PATH=$(pwd) ruby ./bin/mcp_server`
- HTTP (testing): `MCP_SERVICE=think ruby ./bin/mcp_server --http`

## Sample Flow
Example (CLI) showing the first loop of a workflow:

```bash
# 1) Start the engine (stdio)
MCP_SERVICE=think SAVANT_PATH=$(pwd) ruby ./bin/mcp_server

# 2) Client asks for available workflows
ruby ./bin/savant call 'think.workflows.list' --service=think --input='{}'

# 3) Plan the run (e.g., code_review_initial)
ruby ./bin/savant call 'think.plan' \
  --service=think \
  --input='{"workflow":"code_review_initial","params":{"mr_iid":"!12345"},"run_id":"cr-init-001","start_fresh":true}'

# -> returns: { instruction: { step_id, call, input_template }, state, run_id }

# 4) Execute the instructed tool (example: local.read of .cline/config.yml)
ruby ./bin/savant call 'local.read' --service=think \
  --input='{"files":[".cline/config.yml"]}'

# 5) Advance the workflow with that snapshot
ruby ./bin/savant call 'think.next' --service=think \
  --input='{"workflow":"code_review_initial","run_id":"cr-init-001","step_id":"load_config","result_snapshot":{"files":[".cline/config.yml"],"content":"..."}}'

# -> returns next instruction; repeat until done
```

