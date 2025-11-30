# PRD --- Savant Agent Runtime (SLM + LLM, Local-First, Telemetry-Ready)

**Owner:** Amd\
**Priority:** P0 (Critical Path for MVP)\
**Status:** ACTIVE\
**Depends on:** Boot Runtime + Multiplexer\
**Target:** Week 1.5--2.5

## Agent Implementation Plan

1. Core scaffolding
   - Create runtime modules: `lib/savant/agent/runtime.rb`, `prompt_builder.rb`, `output_parser.rb`, `memory.rb`.
   - Wire logs: `logs/agent_runtime.log` (runtime) and `logs/agent_trace.log` (telemetry via EventRecorder).
2. LLM adapter (Ollama-first)
   - Add `lib/savant/llm/adapter.rb` delegating to provider backends.
   - Implement `lib/savant/llm/ollama.rb` using `POST /api/generate` with model, temperature, max tokens.
   - Add stubs `lib/savant/llm/anthropic.rb` and `openai.rb` raising "not configured".
   - Defaults: SLM=`phi3.5`, LLM=`llama3:latest`; env overrides `SLM_MODEL`, `LLM_MODEL`, `OLLAMA_HOST`.
3. Prompt builder
   - Deterministic assembly: persona, driver, AMR rule names, repo sketch, memory summaries, last tool output, system JSON schema instructions.
   - Enforce SLM budget (<8k tokens) using a simple estimator and LRU trimming (older memory → repo context → extras).
   - Trace-log prompt hash and section sizes for debugging.
4. Output parser
   - Strict JSON extraction to schema: `{action, tool_name, args, final, reasoning}`.
   - Auto-correct path: ask SLM to output valid JSON-only when malformed; coerce `args` to Hash.
   - Validate `tool_name` against multiplexer routes; on mismatch → `action=error` with reason.
5. Memory system
   - Ephemeral store on `Runtime.current.memory[:ephemeral]` with `{steps, errors, summaries, state}`.
   - Persist snapshot per step to `.savant/session.json`; keep under ~4k tokens with periodic SLM summarization of older steps.
   - Attach tool outputs and errors per step for reproducibility.
6. Reasoning loop
   - Steps: build → SLM call → parse → tool route → append → emit telemetry → loop until `finish`.
   - Limits: max 25 steps; retry transient errors (2 attempts, backoff); escalate to LLM only when heavy work or driver flags require it.
   - Determinism: SLM temperature ~0–0.2 for stable actions.
7. Multiplexer integration
   - Execute tools via `Runtime.current.multiplexer.call(tool_name, args)`.
   - Handle `ToolNotFound`/`EngineOffline`/timeouts; record in memory and telemetry; single retry on failure.
8. Telemetry + logging
   - Emit one `reasoning_step` event per loop with `{step, model, prompt_tokens, output_tokens, action, tool_name, metadata}` to `logs/agent_trace.log`.
   - Runtime log includes step timings, model switches, tool calls, retries, and final summary in `logs/agent_runtime.log`.
9. Config + schema
   - Add optional `agent` and `llm` blocks to `config/settings.json` with defaults:
     - `agent: { maxSteps, retryLimit, prompt: { slmBudgetTokens, llmBudgetTokens } }`
     - `llm: { provider: 'ollama', slmModel: 'phi3.5', llmModel: 'llama3:latest', ollamaHost: 'http://127.0.0.1:11434' }`
   - Extend `config/schema.json` to accept these blocks; ENV takes precedence.
10. CLI integration (minimal)
    - Extend `bin/savant run` to accept agent input from file/STDIN and flags: `--slm`, `--llm`, `--max-steps`, `--dry-run`.
11. Testing
    - Unit: prompt budget trimming; parser correction; memory snapshot/truncate; adapter happy/timeout/error; mux call mock.
    - Integration: 2–3 step loop with stubbed SLM returning valid actions; verify telemetry/log lines and step cap.
12. Rollout
    - Phase 1: Scaffolding + stubs + unit specs.
    - Phase 2: Prompt+parser+memory; happy-path loop (stubbed LLM).
    - Phase 3: Ollama adapter + model switching + telemetry; integration spec.
    - Phase 4: CLI and docs; finalize rubocop/acceptance.
    - Phase 5: Hardening (retries, summaries, token estimator tuning).

Acceptance checklist (MVP):
- SLM-only loop completes; escalates to LLM on flagged tasks.
- Tools route via multiplexer; failures captured.
- `.savant/session.json` maintained under budget with summaries.
- `logs/agent_trace.log` has one event per step; `logs/agent_runtime.log` captures timings and final.

------------------------------------------------------------------------

# 1. Purpose

The Agent Runtime is the **brain** of the Savant Engine.\
It enables autonomous reasoning, tool selection, tool execution, and
final output generation.

This runtime uses:

-   **SLM** (Small Language Model) for planning, routing, and tool
    decisions\
-   **LLM** (Large Language Model) for deep reasoning, MR review,
    refactors\
-   **Ollama** as the default model provider (local-first, zero-cost)

It also emits **structured telemetry** for the future Savant Hub
Dashboard.

------------------------------------------------------------------------

# 2. Problem Statement

Per the MVP requirements:

-   The system needs a local agent that can reason → select → execute
    tools → summarize.\
-   No agent loop currently exists.\
-   No LLM integration exists.\
-   No planning engine or reasoning flow.\
-   No telemetry exists for later dashboard visualization.

This PRD defines the missing agent runtime.

------------------------------------------------------------------------

# 3. Goals

### ✔ Local-first reasoning engine

### ✔ Dual-model support (SLM for planning, LLM for deep reasoning)

### ✔ Deterministic tool selection behavior

### ✔ JSON-structured agent instructions

### ✔ Memory system for tool results & summaries

### ✔ Full telemetry stream for future dashboard

### ✔ Zero cloud dependencies (Ollama-first)

------------------------------------------------------------------------

# 4. Design Principles

### **Keep it clean**

-   No magic\
-   Clear prompt-builder\
-   Minimal nested logic\
-   Transparent reasoning steps

### **Keep backward complexity low**

-   Simple adapter layer\
-   Plain Ruby objects\
-   Static JSON action schema\
-   One loop, one brain

### **Local-first**

-   Ollama is default\
-   No network required\
-   No API keys required

### **Instrument everything**

-   Telemetry for dashboards\
-   Prompt snapshots\
-   Tool-call logs\
-   Memory mutations

------------------------------------------------------------------------

# 5. Features & Requirements

------------------------------------------------------------------------

## 5.1 Dual-Model System (SLM + LLM)

**SLM (Planning Engine):** - Used for tool decisions, workflow routing,
AMR rule application\
- Must be small enough to run **fast** on CPU\
- Default: `phi3.5` (Ollama)

**LLM (Deep Reasoning Engine):** - Used for large diffs, MR reviews,
refactors, multi-file analysis\
- Default: `llama3:latest` (Ollama)

**Acceptance Criteria** - Runtime can switch models dynamically\
- SLM used by default\
- LLM only used when needed (or explicitly instructed)

------------------------------------------------------------------------

## 5.2 LLM Adapter (Ollama-first)

Unified API:

    Savant::LLM.call(prompt, model: runtime.model)

Backends:

-   `ollama` → Required\
-   `anthropic` → Stub\
-   `openai` → Stub

**Acceptance Criteria** - Ollama backend fully functional\
- Other backends can throw "not configured" errors\
- No cloud dependencies for MVP

------------------------------------------------------------------------

## 5.3 Prompt Builder

Prompt components:

-   Persona\
-   Driver prompt\
-   AMR rules\
-   Repo context\
-   Memory\
-   Last tool output\
-   System instructions\
-   Required JSON schema

**Acceptance Criteria** - Prompt \< 8k tokens for SLM\
- Deterministic structure\
- Logged for debugging

------------------------------------------------------------------------

## 5.4 Reasoning Loop

Main loop must:

1.  Build prompt\
2.  Call SLM\
3.  Parse JSON\
4.  Route tool call (via Multiplexer)\
5.  Append tool results to memory\
6.  Emit telemetry\
7.  Loop until `finish`

**Acceptance Criteria** - Max 25 steps\
- No infinite loops\
- Errors trigger retry\
- Escalate to LLM only when needed

------------------------------------------------------------------------

## 5.5 Action Schema (JSON Envelope)

Strict JSON:

``` json
{
  "action": "tool" | "reason" | "finish" | "error",
  "tool_name": "",
  "args": {},
  "final": "",
  "reasoning": ""
}
```

**Acceptance Criteria** - Reject malformed JSON\
- Automatically correct via SLM retry

------------------------------------------------------------------------

## 5.6 Memory System

Memory struct holds:

-   Step history\
-   Tool results\
-   Summaries\
-   Errors\
-   Current state

Stored in:

    .savant/session.json

**Acceptance Criteria** - Memory \< 4k tokens\
- Snapshotted each step

------------------------------------------------------------------------

## 5.7 Multiplexer Integration

Tool calls executed via:

    multiplexer.call(tool_name, args)

**Acceptance Criteria** - Tool call failures handled cleanly\
- Logged + attached to memory

------------------------------------------------------------------------

## 5.8 Telemetry (Dashboard Instrumentation)

Agent runtime must emit standardized events for the Hub Dashboard.

Event schema:

``` json
{
  "type": "reasoning_step",
  "step": 3,
  "model": "phi3.5",
  "prompt_tokens": 1432,
  "output_tokens": 201,
  "action": "tool",
  "tool_name": "context.search",
  "metadata": {
    "amr_rules_triggered": [],
    "decision_summary": ""
  },
  "timestamp": 1712341234
}
```

Events saved to:

    logs/agent_trace.log

**Acceptance Criteria** - One telemetry event per reasoning step\
- Dashboard-ready data

------------------------------------------------------------------------

## 5.9 Logging + Observability

Log:

-   model used (SLM or LLM)\
-   step number\
-   tool calls\
-   errors\
-   prompt metadata\
-   final output

Stored at:

    logs/agent_runtime.log

------------------------------------------------------------------------

# 6. Deliverables

### Code

-   `lib/savant/agent/runtime.rb`\
-   `lib/savant/agent/prompt_builder.rb`\
-   `lib/savant/agent/output_parser.rb`\
-   `lib/savant/agent/memory.rb`\
-   `lib/savant/llm/adapter.rb`\
-   `lib/savant/llm/ollama.rb`\
-   (stub) `lib/savant/llm/anthropic.rb`\
-   (stub) `lib/savant/llm/openai.rb`

### Docs & Config

-   Updated README\
-   Updated memory bank\
-   Session schema doc\
-   Telemetry schema doc

------------------------------------------------------------------------

# 7. Non-Goals (MVP)

❌ Multi-agent supervisor\
❌ Sandbox\
❌ Persistent RAG memory\
❌ Hub UI (dashboard is Phase 3)\
❌ Cloud mode

------------------------------------------------------------------------

# 8. Success Criteria

Agent Runtime is complete when:

-   A full reasoning loop runs with SLM\
-   Deep tasks switch to LLM\
-   Tool calls routed correctly\
-   Memory updated each step\
-   Telemetry emitted\
-   MR Review agent can run on top of it\
-   100% local execution

------------------------------------------------------------------------

# 9. Risks

-   SLM hallucination → strict JSON envelope solves\
-   Prompt length → enforce budgets\
-   Tool call errors → retries needed\
-   Too many reasoning steps → hard capped at 25

------------------------------------------------------------------------

# 10. Technical Notes

File structure:

    lib/savant/agent/
    lib/savant/llm/
    logs/agent_runtime.log
    logs/agent_trace.log
    .savant/session.json

Default models:

    SLM: phi3.5
    LLM: llama3:latest
