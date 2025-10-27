# 🧠 Savant Think  
### Deterministic Orchestration & Reasoning Engine  
> “The layer that decides what happens next.”

## 1. Purpose

**Savant Think** is the orchestration and reasoning engine for the Savant ecosystem.  
It doesn’t execute code — it **decides** how things should execute.  
Think acts as a **guide** for LLMs and other MCPs, translating workflows into deterministic, auditable steps.

In short, Context knows *what’s in the repo*, Jira knows *what’s in the backlog*, and **Think** knows *what to do next.*

## 2. Goals

| Goal | Description |
|------|--------------|
| **Deterministic flow** | Same inputs → same steps → same outcome. |
| **LLM-safe orchestration** | The LLM follows Think’s JSON instructions — no guessing. |
| **Tool independence** | Think doesn’t call MCPs; it instructs the LLM which MCP to call. |
| **Self-bootstrapping** | Provides its own driver prompt (`think.driver_prompt`). |
| **Explainable reasoning** | Every step has a schema, a policy, and a rationale. |

## 3. Architecture Overview

```mermaid
flowchart LR
  subgraph IDE["Editor (Cline / Claude)"]
    LLM["LLM Runtime"] -->|calls| MCP["Savant Think MCP"]
  end

  MCP --> WF["Workflow Interpreter"]
  MCP --> SM["State Manager"]
  MCP --> IE["Instruction Engine"]
  MCP --> DP["Driver Prompt"]

  WF -->|reads| YAML["workflows/*.yaml"]
  SM -->|stores| State[(Checkpoint State)]
  IE -->|returns| JSON["Instruction JSON"]

  classDef comp fill:#f0f7ff,stroke:#1e88e5,stroke-width:1px;

---

## Acceptance + TDD TODO (Compact)
- Criteria: deterministic workflow interpretation; instruction JSON schema; state checkpoints; driver prompt; editor MCP exposure.
- TODO:
  - Red: specs for workflow parsing, state transitions, instruction schemas.
  - Green: implement interpreter, state manager, driver prompt resource.
  - Refactor: simplify policies; add examples and docs.
  classDef data fill:#f9fbe7,stroke:#7cb342,stroke-width:1px;
  class MCP,WF,SM,IE,DP comp;
  class YAML,State,JSON data;
```

## 4. Core Responsibilities

### 4.1 Workflow Interpreter  
Reads and validates declarative YAML workflows.  
Supports conditional logic (`when`, `foreach`), data binding, and variable expansion.

### 4.2 Instruction Engine  
Turns workflow steps into structured JSON instructions for the LLM to execute.  
Each step defines the next action, expected schema, and completion criteria.

Example:
```json
{
  "step_id": "lint",
  "call": "context.search",
  "input_template": { "q": "rubocop offenses" },
  "capture_as": "lint_result",
  "success_schema": "FTSResultV1",
  "done": false
}
```

### 4.3 State Manager  
- Maintains persistent state per workflow (`.savant/state/<workflow>.json`).  
- Stores intermediate results, variables, and artifacts.  
- Supports resume, checkpoint, and reset operations.

### 4.4 Validator  
- Validates tool responses against expected schemas.  
- Detects skipped dependencies or invalid transitions.  
- Marks completion when the workflow graph resolves.

### 4.5 Driver Prompt Provider  
- Exposes `think.driver_prompt`, allowing editors to self-configure.  
- Returns versioned markdown with startup instructions and hash.

## 5. Tools

| Tool | Purpose |
|------|----------|
| `think.plan` | Initialize workflow and return the first step. |
| `think.next` | Accept `{ step_id, result_snapshot }` and return the next instruction. |
| `think.explain` | Explain what the current step is doing. |
| `think.reset` | Clear state and restart workflow. |
| `think.driver_prompt` | Provide the LLM’s system prompt and policy. |

## 6. Execution Flow

```bash
# 1. Plan
plan = call think.plan({workflow:"review_v1", params:{mr_id:"123"}})

# 2. Execute
result = call plan.instruction.call with plan.instruction.input_template

# 3. Advance
next = call think.next({step_id:plan.instruction.step_id, result_snapshot:result})

# 4. Repeat until next.done == true
```

Final output example:
```json
{
  "done": true,
  "summary": "All checks passed. Merge approved.",
  "artifacts": [{"type": "json", "name": "review_summary", "ref": "sha256:deadbeef"}]
}
```

## 7. LLM Bootstrap Logic

1. **Startup:** LLM enumerates MCP tools.  
2. **Detection:** Finds `think.driver_prompt`.  
3. **Load:** Calls it → gets markdown and version hash.  
4. **Inject:** Loads as the session system prompt.  
5. **Loop:** Follows protocol (`plan → execute → next → repeat`).  

Example prompt snippet:
```
# Driver: Savant Think (Guide Mode)

Always follow this loop:
1. Call `think.plan` first.
2. Execute exactly the tool in `instruction.call`.
3. Pass the result to `think.next`.
4. Stop when `done == true`.
5. If any tool is missing → abort and notify.
```

## 8. Directory Layout

```
lib/savant/think/
  engine.rb          # Engine entrypoint
  tools.rb           # MCP tool registry
  workflows/*.yaml   # Workflow definitions
  prompts/*.md       # Bootstrapped driver prompts
  prompts.yml        # Prompt version registry
spec/savant/think/
  engine_spec.rb
```

## 9. Environment Variables

| Env Var | Description | Default |
|----------|--------------|----------|
| `MCP_SERVICE` | must be `think` | — |
| `SAVANT_PATH` | base path for workflows/logs | `./` |
| `LOG_LEVEL` | `debug|info|warn|error` | `info` |
| `SLOW_THRESHOLD_MS` | warn threshold | optional |

## 10. Developer Flow

| Step | Command |
|------|----------|
| Scaffold | `bundle exec ruby ./bin/savant generate engine think` |
| Start MCP | `MCP_SERVICE=think ruby ./bin/mcp_server` |
| Test | `make think-test workflow=review_v1` |
| Inspect State | `cat .savant/state/review_v1.json` |

## 11. Success Metrics

| Metric | Target |
|---------|---------|
| Deterministic replay | 100% |
| Instruction latency | < 50 ms |
| Auto-bootstrap success | ≥ 99% |
| Policy compliance | < 1% violations |
| Setup time | < 10 s |

## 12. Future Enhancements
- Conditional branching & parallel execution.  
- Visual workflow graph inspector.  
- `think.debug` for step replay.  
- Integration with `memory` MCP for adaptive planning.  
- Workflow registry with versioned releases.  

### Summary

**Savant Think** is the reasoning brain of the Savant stack —  
a deterministic guide that plans, sequences, and validates every action the LLM takes.  

> *Not an agent. A guide that thinks before it acts.*
