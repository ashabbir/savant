# PRD --- Savant Workflow Engine Integration (MVP Final Component)

**Owner:** Amd\
**Priority:** P0 (Blocks MVP Release)\
**Status:** NEW\
**Depends On:**\
- Boot Runtime\
- Multiplexer\
- Agent Runtime\
- Git Engine\
- MR Review Agent\
- Think Engine (existing execution core)

------------------------------------------------------------------------

# 1. Purpose

Integrate the **Think Workflow Executor** into the Savant Engine so
workflows can orchestrate:

-   MCP tool calls\
-   Agent calls (MR Review, Summarizer, Test Agent, etc.)\
-   Mixed sequences (tool → agent → tool → agent)\
-   Structured data passing\
-   Telemetry for each step

This creates the **top-level automation layer** of Savant.

When complete, users can run:

    savant workflow run review

And Think will orchestrate:

    git.diff → cross_repo_search → mr_review → summarize → output

------------------------------------------------------------------------

# 2. Problem Statement

Savant's core modules exist:

-   Git Engine\
-   Agent Runtime\
-   MR Review Agent\
-   Multiplexer\
-   Think engine

BUT they are **not connected**.

Current limitations:

-   Think cannot call agents\
-   Think cannot call MCP tools\
-   No step-to-step data passing\
-   No workflow CLI command\
-   No telemetry per step\
-   No unified execution path

Without this integration, the engine cannot execute full automation
flows.

------------------------------------------------------------------------

# 3. Goals

### ✔ Connect Think → Multiplexer

### ✔ Connect Think → Agent Runtime

### ✔ Add full workflow execution support

### ✔ Support YAML workflow definitions

### ✔ Support tool steps + agent steps

### ✔ Data passing between steps

### ✔ Telemetry and logging

### ✔ CLI entrypoint (`savant workflow run`)

### ✔ Deterministic + local-first execution

------------------------------------------------------------------------

# 4. Design Principles

### Clean separation

-   Think: orchestration\
-   Agent Runtime: reasoning\
-   Multiplexer: tool routing\
-   MCP engines: capabilities

### Keep backward complexity low

-   No loops\
-   No conditions\
-   No branching yet\
-   Deterministic linear execution

### Local-first

-   Zero cloud dependency

### Deterministic

-   Each step must produce predictable output\
-   Workflows cannot "decide" things --- agents do that

------------------------------------------------------------------------

# 5. Workflow Model

Example workflow:

``` yaml
steps:
  - name: diff
    tool: git.diff

  - name: cross_repo
    tool: context.fts.search
    with:
      query: "{{ diff.files }}"

  - name: review
    agent: mr_review
    with:
      diff: "{{ diff }}"
      cross_repo: "{{ cross_repo }}"

  - name: summarize
    agent: summarizer
    with:
      review: "{{ review }}"

  - name: output
    tool: output.write
    with:
      content: "{{ summarize }}"
```

------------------------------------------------------------------------

# 6. Features & Requirements

------------------------------------------------------------------------

## 6.1 Step Types

### A. Tool Step

Runs through the Multiplexer:

    tool: git.diff
    tool: context.fts.search

### B. Agent Step

Runs via Agent Runtime:

    agent: mr_review
    agent: summarizer

### C. Mixed Workflows

Allowed:

    tool → agent → tool → agent

------------------------------------------------------------------------

## 6.2 Input Interpolation

Use:

    {{ step_name.key }}

Workflow context must support:

-   Strings\
-   Arrays\
-   Hashes\
-   Numbers\
-   Null

------------------------------------------------------------------------

## 6.3 Execution Flow

Think must:

1.  Load workflow YAML\
2.  Build execution plan\
3.  For each step:
    -   resolve inputs\
    -   execute (tool or agent)\
    -   capture outputs\
    -   store in workflow context\
    -   emit telemetry

------------------------------------------------------------------------

## 6.4 Telemetry

Each step emits an event:

``` json
{
  "step": "review",
  "type": "agent",
  "status": "success",
  "duration_ms": 3421,
  "input_summary": {...},
  "output_summary": {...}
}
```

Stored in:

    logs/workflow_trace.log

------------------------------------------------------------------------

## 6.5 CLI Integration

Command:

    savant workflow run <workflow_name>

Requirements:

-   load workflow\
-   run via Think\
-   print formatted output\
-   print errors clearly

------------------------------------------------------------------------

## 6.6 Error Handling

-   Missing tool → stop\
-   Missing agent → stop\
-   Invalid interpolation → stop\
-   Bad MCP result → stop\
-   Agent failure → stop

No silent failures.

------------------------------------------------------------------------

## 6.7 Workflow Storage

Workflows stored in:

    workflows/
      mr_review.yaml
      summarize.yaml
      migration.yaml

------------------------------------------------------------------------

## 6.8 Deterministic Execution

-   No loops\
-   No parallel execution\
-   No dynamic branching\
-   No remote calls

MVP stays simple & predictable.

------------------------------------------------------------------------

# 7. Deliverables

### Code

-   `workflow/engine.rb`\
-   `workflow/executor.rb`\
-   `workflow/loader.rb`\
-   `workflow/interpolator.rb`\
-   `workflow/context.rb`

### Integration

-   Think → Agent Runtime adapter\
-   Think → Multiplexer adapter

### CLI

-   `savant workflow run` command

### Docs

-   Workflow syntax reference\
-   Examples

------------------------------------------------------------------------

# 8. Success Criteria

Workflow Engine is complete when:

-   Think can execute tool-only workflows\
-   Think can execute agent-only workflows\
-   Think can execute mixed workflows\
-   MR Review workflow runs end-to-end\
-   Telemetry produced\
-   CLI works reliably\
-   Local execution only

After this, Savant Engine v0.1.0 is **DONE**.

------------------------------------------------------------------------

# 9. Risks

-   invalid interpolation\
-   agent runtime failures\
-   multiplexer routing errors\
-   hard-to-debug errors without telemetry\
-   YAML formatting issues

------------------------------------------------------------------------

# 10. Implementation Strategy (Clean, Actionable)

------------------------------------------------------------------------

# Phase 1 --- Core Workflow Engine (Day 1--2)

Implement:

-   loader\
-   parser\
-   workflow context\
-   step model

------------------------------------------------------------------------

# Phase 2 --- Connect Think → Multiplexer (Day 3--4)

Implement:

-   tool step executor\
-   error & timeout handling

------------------------------------------------------------------------

# Phase 3 --- Connect Think → Agent Runtime (Day 4--6)

Implement:

-   agent step executor\
-   pass context inputs\
-   validate outputs

------------------------------------------------------------------------

# Phase 4 --- Telemetry (Day 7)

Implement:

-   per-step log\
-   step summary\
-   duration\
-   failure trace

------------------------------------------------------------------------

# Phase 5 --- CLI (Day 8)

Command:

    savant workflow run <file>

Features:

-   pretty output\
-   JSON output mode\
-   error inspection

------------------------------------------------------------------------

# Phase 6 --- Test Suites (Day 9--10)

Tests for:

-   tool-only\
-   agent-only\
-   mixed workflows\
-   invalid YAML\
-   missing tool\
-   missing agent\
-   real MR Review workflow

------------------------------------------------------------------------

## Agent Implementation Plan — Executable Architecture

This section captures the concrete, code-oriented plan the agent will implement.

Architecture
- Core modules under `lib/savant/engines/workflow/`:
  - `engine.rb`: public API, server_info, run/list/read/delete, delegates to Executor, exposes MCP tools.
  - `executor.rb`: linear step runner, resolves inputs, calls tool/agent adapters, captures outputs, emits telemetry.
  - `loader.rb`: loads YAML workflows from `workflows/` (root), validates shape, returns a normalized model.
  - `interpolator.rb`: `{{ path.to.value }}` templating across Strings/Arrays/Hashes; supports `params.*` and prior step names.
  - `context.rb`: runtime context holding `params`, `steps` outputs, and utility getters.
- Integrations:
  - Tool steps via Multiplexer (`context.<tool>` etc.); robust errors when multiplexer is unavailable.
  - Agent steps via `Savant::Agent::Runtime` (goal provided via `with.goal` or auto-composed from inputs).
  - Telemetry using `Savant::Logging::EventRecorder.global` and a dedicated file log `logs/workflow_trace.log`.

Workflow YAML (MVP)
```yaml
steps:
  - name: diff
    tool: git.diff

  - name: cross_repo
    tool: context.fts_search
    with:
      q: "{{ diff.files }}"

  - name: review
    agent: mr_review
    with:
      goal: "Review MR using supplied diff and context"
      diff: "{{ diff }}"
      cross_repo: "{{ cross_repo }}"

  - name: summarize
    agent: summarizer
    with:
      goal: "Summarize the review for humans"
      review: "{{ review }}"

  - name: output
    tool: output.write
    with:
      content: "{{ summarize }}"
```

CLI
- Implement `savant workflow run <name> --params='{}'` invoking `Savant::Workflow::Engine.run(workflow:, params:)`.
- Pretty-print final artifact and write per-step telemetry.

Telemetry & Diagnostics
- Emit events per step: `workflow_step_started|completed|error` with `step`, `type`, `duration_ms`, and `*_summary`.
- Persist JSONL to `logs/workflow_trace.log` in addition to the global recorder.
- Add Hub diagnostics endpoints: `/diagnostics/workflows` (recent summary) and `/diagnostics/workflows/trace` (download log).
- UI: add a Diagnostics page section to visualize recent workflow events (reusing Hub aggregated logs).

Tests
- Loader + Interpolator unit specs (no external engines required).
- Executor dry-run spec for tool steps when Multiplexer is disabled.
- CLI smoke test path existence and argument parsing.

Non-goals (MVP)
- No loops/branching/parallelism.
- No remote dependencies beyond existing local MCP engines.

# Phase 7 --- Final Docs & Cleanup (Day 11)

-   README\
-   samples\
-   workflow best practices\
-   integration notes

------------------------------------------------------------------------

# END OF PRD
