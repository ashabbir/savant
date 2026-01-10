# Savant v0.1.0

Savant is a lightweight Ruby framework for building and running local MCP services with autonomous agent capabilities. The current release is **v0.1.0**, aligning the CLI, MCP services, and React UI to a single version surface.

**Key Features:**
- **Multiplexer**: Unified MCP surface merging tools from all engines (Context, Git, Think, Jira, Personas, Rules)
- **Agent Runtime**: Autonomous reasoning loops powered by the Redis Reasoning Worker
- **Boot System**: RuntimeContext with persona loading, AMR rules, and repo detection
- **React UI**: Real-time diagnostics with agent monitoring, logs, and route exploration

**System Overview:**
```
┌──────────────────────────────────────────────────────────────┐
│                         SAVANT                               │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────┐     ┌──────────────┐     ┌──────────────┐  │
│  │  React UI  │────►│  Hub (HTTP)  │────►│ Multiplexer  │  │
│  └────────────┘     └──────────────┘     └──────┬───────┘  │
│                                                   │           │
│  ┌────────────┐                          ┌───────▼───────┐  │
│  │   Agent    │◄────────────────────────►│   Engines     │  │
│  │  Runtime   │  (routes via mux)        │ Context Think │  │
│  │            │                          │ Jira Personas │  │
│  │ Reasoning Worker│                      │     Rules     │  │
│  └────────────┘                          └───────────────┘  │
│        │                                                     │
│        ▼                                                     │
│  ┌────────────────────────────────────────────────────────┐ │
│  │         Logs + Telemetry + Memory Bank                 │ │
│  │  • agent_runtime.log    • session.json                 │ │
│  │  • agent_trace.log      • multiplexer.log              │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## Multiplexer Overview

- `bin/mcp_server` defaults to the multiplexer. It spawns one stdio MCP process per engine (`context`, `git`, `think`, `personas`, `rules`, `jira` by default), namespaces their tools (`context.fts_search`, `git.diff`, `jira.issue.get`, etc.), and serves them to connected editors.
- Each engine failure is isolated—if a child dies the multiplexer removes its tools, logs the event, and restarts it in the background.
- Metrics and status are written to `logs/multiplexer.log` and surfaced via the Hub (`curl /` now includes a `multiplexer` object) and CLI helpers (`savant engines`, `savant tools`).

```
# Inspect engines + status
SAVANT_PATH=$(pwd) bundle exec ruby ./bin/savant engines

# List namespaced tools
SAVANT_PATH=$(pwd) bundle exec ruby ./bin/savant tools
```

This README is intentionally concise. For a step-by-step guide, see docs/getting-started.md. Full, detailed docs (with diagrams) live in the Memory Bank:

## Council (Multi‑Agent) Engine

AI Council enables explicit escalation from lightweight chat to a structured, multi‑agent deliberation with roles (Analyst, Skeptic, Pragmatist, Safety/Ethics, Moderator). Safety has hard veto; sessions always return to chat when a council run completes.

- UI: open the Hub and click the Council tab (`/council`). Left panel lists sessions; right panel shows transcript and live council status.
- API: Council is exposed as MCP tools under the `council` engine via Hub HTTP routes: `/{engine}/tools/{tool}/call`.
- Minimum to escalate: at least two agents in the session.
- Env: `COUNCIL_DEMO_MODE=1` to run without the Reasoning Worker; `COUNCIL_AUTO_AGENT_STEP=1` to append an auto agent step on user messages in chat.

Quick examples (HTTP via Hub)
```
# Create a session
curl -s -H 'content-type: application/json' -H 'x-savant-user-id: me' \
  -X POST http://localhost:9999/council/tools/council_session_create/call \
  -d '{"params": {"title": "Tech Decision", "agents": ["a1","a2"]}}'

# Append user message
curl -s -H 'content-type: application/json' -H 'x-savant-user-id: me' \
  -X POST http://localhost:9999/council/tools/council_append_user/call \
  -d '{"params": {"session_id": 1, "text": "Microservices or monolith?"}}'

# Escalate to council (starts a run and flips mode to council)
curl -s -H 'content-type: application/json' -H 'x-savant-user-id: me' \
  -X POST http://localhost:9999/council/tools/council_escalate/call \
  -d '{"params": {"session_id": 1}}'

# Run protocol (positions → debate → synthesis), then auto return to chat
curl -s -H 'content-type: application/json' -H 'x-savant-user-id: me' \
  -X POST http://localhost:9999/council/tools/council_run/call \
  -d '{"params": {"session_id": 1}}'
```

Data model (Postgres)
- `council_sessions(id, title, user_id, agents TEXT[], description, mode, context JSONB, artifacts JSONB, created_at, updated_at)`
- `council_messages(id, session_id, role, agent_name, run_id, status, text, created_at)`
- `council_runs(id, session_id, run_id UNIQUE, status, phase, query, context JSONB, positions JSONB, debate_rounds JSONB, synthesis JSONB, votes JSONB, veto, veto_reason, started_at, completed_at, error)`

Full PRD: docs/prds/done/PRD_AI_Council_Combined.md

## Homebrew Install (after releases are published)

```
brew tap <org/tap>   # e.g., ashabbir/savant
brew install <org/tap>/savant
savant version
```

Activate (offline) and run:

```
savant activate <username>:<key>
savant status
```

Notes
- Activation is fully offline. The key is validated locally at runtime.
- Brew installs enforce activation by default. No network calls are made.
- For development, see the License & Activation section below for bypass options.

| Doc | Summary |
| --- | --- |
| [Framework](memory_bank/framework.md) | Core concepts, lifecycle, and configuration surface. |
| [Architecture](memory_bank/architecture.md) | System topology, data model, and component responsibilities. |
| [Boot Runtime](memory_bank/engine_boot.md) | Boot initialization, RuntimeContext, AMR system, and CLI commands. |
| **[Agent Runtime](memory_bank/runtime.md)** | **Autonomous reasoning loop via the Redis Reasoning Worker, memory system, and telemetry.** |
| [Multiplexer](memory_bank/multiplexer.md) | Unified tool surface across engines; process model and routing. |
| [Hub](memory_bank/hub.md) | HTTP endpoints, UI mounting, diagnostics, logs, and routes. |
| [Database](memory_bank/database.md) | Schema, FTS index, migrations, and context engine queries. |
| [Logging](memory_bank/logging.md) | Structured logs, metrics, and audit hooks. |
| [Indexer Engine](memory_bank/engine_indexer.md) | Scan pipeline, dedupe/chunking, DB model, CLI. |
| [Context Engine](memory_bank/engine_context.md) | FTS search flow, cache/indexer coordination, and tool APIs. |
| [Think Engine](memory_bank/engine_think.md) | Plan/next workflow orchestration and prompt drivers. |
| [Jira Engine](memory_bank/engine_jira.md) | Jira integration details, auth requirements, and tool contracts. |
| [Git Engine](memory_bank/engine_git.md) | Local, read‑only Git intelligence (diffs, hunks, file context, changed files). |
| [Personas Engine](memory_bank/engine_personas.md) | Persona catalog shape, YAML schema, and exposed tools. |
| [Engine Rules](memory_bank/engine_rules.md) | Shared guardrails, telemetry hooks, and best-practice playbooks. |
| [Distribution](memory_bank/distribution.md) | Packaging, artifacts, release flow, and Homebrew formula. |
| [License & Activation](memory_bank/license_activation.md) | Offline gate design and CLI.

## Getting Started

Prereqs: Ruby 3.2 + Bundler, and a local Postgres instance. Docker is not required.

> Postgres Only: SQLite is not supported. Savant targets Postgres (tested on 13+) and relies on JSONB and GIN indexes for FTS. Ensure a local Postgres is running and accessible.

### Run (Rails API + UI, no Docker)

1) Configure Postgres (example):

```
export DATABASE_URL=postgres://context:contextpw@localhost:5432/contextdb
```

2) Prepare the database (idempotent):

```
# Run migrations and ensure FTS indexes
make db-migrate
make db-fts

# Optional smoke/seed helpers
make db-smoke
make db-seed

# Seeds include default LLM providers:
# - ollama (base_url from $OLLAMA_HOST or http://127.0.0.1:11434)
# - google (Generative Language API). If $GOOGLE_API_KEY is set and $SAVANT_ENC_KEY is configured,
#   the key is stored encrypted; otherwise the provider is created without a key and you can update it later via the UI or tools.
```

3) Build the UI bundle (optional; for Rails to serve static UI at /ui):

```
make ui-build-local
```

4) Start dev servers (Rails API + Vite):

```
# Terminal A: Rails API on http://localhost:9999
make dev-server

# Terminal B: Frontend with HMR on http://localhost:5173
make dev-ui
```

Notes:
- UI (dev): http://localhost:5173 (HMR; edits reflect immediately)
- API:      http://localhost:9999 (Hub endpoints mounted in Rails)
- Health:   GET http://localhost:9999/healthz
- JSON-RPC: POST http://localhost:9999/rpc

Indexing via Rake (Rails)
- All repos: `cd server && DATABASE_URL=$DATABASE_URL bundle exec rake savant:index_all`
- Single repo: `cd server && DATABASE_URL=$DATABASE_URL bundle exec rake 'savant:index[myrepo]'`
- Status: `cd server && DATABASE_URL=$DATABASE_URL bundle exec rake savant:status`

### Boot Runtime (Quick Start)

The Boot Runtime is the foundation for the Savant Engine. Run it first to initialize all core components:

```bash
./bin/savant run
```

This boots the engine and displays runtime status including session ID, persona, driver prompt, AMR rules, and repo context. Files created:
- `.savant/runtime.json` - Persistent runtime state
- `logs/engine_boot.log` - Structured boot logs

**Options:**
```bash
./bin/savant run --persona=savant-architect  # Use different persona
./bin/savant run --skip-git                  # Skip git detection
./bin/savant review                          # Boot for MR review
./bin/savant workflow <name>                 # Boot for workflow execution
```

See [Boot Runtime docs](memory_bank/engine_boot.md) for complete reference.

## Workflows (YAML Executor)

Savant includes a deterministic YAML workflow executor that can call tools (via the Multiplexer) and agents.

### How to Run a Workflow

- CLI (boots the runtime and executes the workflow):

```bash
# From project root
./bin/savant workflow <name> --params='{"ticket":"JIRA-123"}'
```

- HTTP (Hub → Workflow tools via MCP registrar):

```bash
# List workflows known to the Workflow engine
curl -s -H 'content-type: application/json' -H 'x-savant-user-id: me' \
  -X POST http://localhost:9999/workflow/tools/workflow_list/call \
  -d '{}'

# Run a workflow by ID with params
curl -s -H 'content-type: application/json' -H 'x-savant-user-id: me' \
  -X POST http://localhost:9999/workflow/tools/workflow_run/call \
  -d '{"params": {"ticket":"JIRA-123"}, "workflow": "example_workflow"}'
```

### Saved Runs & Telemetry

- Run state is persisted to `.savant/workflow_runs/<workflow>__<run_id>.json`.
- Per-step telemetry is appended to `logs/workflow_trace.log` (JSONL).

### Diagnostics UI

- Open Diagnostics → Workflows in the UI to see:
  - Recent workflow events (with timing, step, and type)
  - Saved Runs table with drill-down into full traces

### Authoring Workflows

- Place YAML files in the repo `workflows/` directory. Minimal schema:

```yaml
steps:
  - name: diff
    tool: git.diff

  - name: summarize
    agent: summarizer
    with:
      goal: "Summarize the diff concisely"
```

- The Think engine ships a Workflow Editor (Engines → Think → Workflows) that allows graph editing, validation, YAML preview, and diagram rendering.

### Agent Runtime (Reasoning Worker)

The Agent Runtime orchestrates autonomous reasoning loops by delegating decisions to the Redis‑backed Reasoning Worker.

**Architecture Overview:**
```
┌─────────────────────────────────────────────────────────────┐
│                    AGENT RUNTIME LOOP                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Prompt Builder  ──► Reasoning Worker ──► Action Parser    │
│       │                                    │                │
│       ▼                                    ▼                │
│  Memory System ◄────── Multiplexer ◄── Tool Router         │
│  (Ephemeral +           (Context,                           │
│   Persistent)           Think, Jira)                        │
│                                                             │
│  Artifacts:                                                 │
│  • logs/agent_runtime.log  (execution logs + timings)       │
│  • logs/agent_trace.log    (telemetry per step)            │
│  • .savant/session.json    (persistent memory)             │
│                                                             │
│  Decisions: Reasoning Worker                               │
│  Budget:   LLM context as configured (tools may use LLM)   │
└─────────────────────────────────────────────────────────────┘
```

**Quick Start:**
```bash
# Install Ollama + models
ollama pull phi3.5:latest
ollama pull llama3:latest

# Run agent session
./bin/savant run --skip-git --agent-input="Summarize recent changes"
```

**CLI Options:**
- `--agent-input=TEXT` or `--agent-file=PATH` for goal input
- `--llm=MODEL` to suggest an LLM for heavy tasks
- `--max-steps=N` to cap the loop (default 25)
- `--dry-run` to simulate tool calls without executing them
- `--quiet` to suppress JSON logs to console (logs still written to files)
- `--force-tool=NAME` and `--force-args=JSON` to force the first step to call a specific tool (use fully-qualified name like `think_prompts_list` or `context.fts_search`)
- `--force-finish` to immediately finish after the forced tool (or finish at step 1 if no forced tool), optionally with `--force-final="text"`
- `--force-finish-only` to finish immediately without executing any tool (ignores `--force-tool`)

**Artifacts:**
- `logs/agent_runtime.log` – runtime logs with timings and decisions
- `logs/agent_trace.log` – telemetry events (one per reasoning step)
- `.savant/session.json` – per-step memory snapshot

**Web UI Diagnostics:**
- Open the Hub UI at `http://localhost:9999/ui`.
  - Each Engine card now has quick links: Diagnostics (opens `/diagnostics/mcp/<engine>`) and Logs (opens `/<engine>/logs`).
  - The Agent page is accessible under Diagnostics.
```
http://localhost:9999/diagnostics/agent
  ├─ Timeline View    (chronological event stream)
  ├─ Grouped View     (events grouped by step)
  ├─ Live Streaming   (real-time updates)
  └─ Export           (download traces + session)
```

**HTTP Diagnostics & Logs Endpoints:**
- Some diagnostics require a user header. Include `x-savant-user-id: <you>` in requests.
- Examples:
  - Per‑engine diagnostics (Git): `curl -H 'x-savant-user-id: me' http://localhost:9999/diagnostics/mcp/git`
  - Per‑engine logs (tail JSON): `curl -H 'x-savant-user-id: me' 'http://localhost:9999/git/logs?n=200'`
  - Aggregated events (filter by engine): `curl -H 'x-savant-user-id: me' 'http://localhost:9999/logs?mcp=git&n=100'`
  - Agent summary: `curl -H 'x-savant-user-id: me' http://localhost:9999/diagnostics/agent`
  - Agent trace (plain text): `curl -H 'x-savant-user-id: me' http://localhost:9999/diagnostics/agent/trace`
  - SSE log stream: `curl -N -H 'x-savant-user-id: me' 'http://localhost:9999/logs/stream'`

See [Agent Runtime docs](memory_bank/runtime.md) for detailed architecture, memory system, and telemetry.

### LLM Registry

The LLM Registry provides centralized management of LLM providers, models, and agent configurations. It supports multiple providers (Google Cloud, Ollama, etc.) with encrypted API key storage.

**Access the Registry:**
- **UI**: http://localhost:5173/llm-registry (Web interface with 3 tabs: Providers, Models, Agents)
- **CLI**: `./bin/llm <command> <subcommand> [options]`

**CLI Commands:**

Provider Management:
```bash
# Add a provider (Google with API key)
./bin/llm provider add --type google --name "Google Primary" --api-key YOUR_API_KEY

# Add a provider (Ollama with base URL)
./bin/llm provider add --type ollama --name "Local Ollama" --base-url http://localhost:11434

# List all providers
./bin/llm provider list

# Test a provider's connection
./bin/llm provider test --name "Google Primary"

# Delete a provider
./bin/llm provider delete --name "Google Primary"
```

Model Management:
```bash
# Discover available models from a provider
./bin/llm models discover --provider "Google Primary"

# Register a model for use
./bin/llm models register --provider "Google Primary" --id gemini-2.0-pro

# List all registered models
./bin/llm models list
```

Agent Management:
```bash
# Create a new agent
./bin/llm agent add --name context-agent --description "Context analysis agent"

# Assign a model to an agent
./bin/llm agent assign --name context-agent --model-id 1

# List all agents with their assigned models
./bin/llm agent list

# Delete an agent
./bin/llm agent delete --name context-agent
```

**Configuration:**
```bash
# Set the encryption key (required for API key storage)
export SAVANT_ENC_KEY=$(ruby -e "require 'securerandom'; puts SecureRandom.hex(32)")


```

**Database:**
- LLM Registry uses 5 tables: `llm_providers`, `llm_models`, `llm_agents`, `llm_agent_model_assignments`, `llm_cache`
- API keys are encrypted with AES-256-GCM before storage
- Run migrations: `make db-migrate`

**HTTP API (via Hub):**
```bash
# List providers
curl -H 'x-savant-user-id: me' -X POST http://localhost:9999/llm/tools/llm_providers_list/call -d '{}'

# Create provider
curl -H 'x-savant-user-id: me' -X POST http://localhost:9999/llm/tools/llm_providers_create/call \
  -d '{"params": {"name": "Google", "provider_type": "google", "api_key": "KEY"}}'

# List models
curl -H 'x-savant-user-id: me' -X POST http://localhost:9999/llm/tools/llm_models_list/call -d '{}'

# Discover models
curl -H 'x-savant-user-id: me' -X POST http://localhost:9999/llm/tools/llm_models_discover/call \
  -d '{"params": {"provider_name": "Google Primary"}}'

# Create agent
curl -H 'x-savant-user-id: me' -X POST http://localhost:9999/llm/tools/llm_agents_create/call \
  -d '{"params": {"name": "my-agent", "description": "Test agent"}}'

# Assign model to agent
curl -H 'x-savant-user-id: me' -X POST http://localhost:9999/llm/tools/llm_agents_assign_model/call \
  -d '{"params": {"agent_name": "my-agent", "model_id": 1}}'

# List agents
curl -H 'x-savant-user-id: me' -X POST http://localhost:9999/llm/tools/llm_agents_list/call -d '{}'
```

**Future: LangChain/LangGraph Integration**
- The LLM Registry pairs with a separate reasoning service for agent/workflow intelligence
- See `docs/prds/langchain-graph-api.md` for the intent API specification and implementation roadmap

### Full Stack Setup

1) Database setup (Postgres + FTS):
```
make db-migrate && make db-fts
```

2) Index repos (see config/settings.json):
```
make repo-index-all
```

3) Offline activation
   - Production (brew/packaged): required before engine/MCP boot.
   - Development (git checkout): bypassed automatically; see below for details.
```
./bin/savant activate <username>:<key>
./bin/savant status
```

4) UI
- Static: `make ui-build-local` then open http://localhost:9999/ui
- Dev: `make dev-ui` then open http://localhost:5173 (Hub at http://localhost:9999)

6) MCP Multiplexer (stdio)
```
# Unified multiplexer (default)
SAVANT_PATH=$(pwd) bundle exec ruby ./bin/mcp_server

# Run a single engine (optional override)
MCP_SERVICE=context  SAVANT_PATH=$(pwd) bundle exec ruby ./bin/mcp_server
MCP_SERVICE=git      SAVANT_PATH=$(pwd) bundle exec ruby ./bin/mcp_server
MCP_SERVICE=jira     SAVANT_PATH=$(pwd) bundle exec ruby ./bin/mcp_server
```

## Architecture

Savant is organized into six main backend modules plus a separate frontend:

```
lib/savant/
├── hub/              # MODULE 1: Hub API (HTTP routing, SSE, service management)
├── logging/          # MODULE 2: Logging & Observability (structured logging, metrics, audit)
├── framework/        # MODULE 3: Framework (MCP core, middleware, transports, config)
├── engines/          # MODULE 4: Engines (context, think, jira, personas, rules, etc.)
├── agent/            # MODULE 5: Agent Runtime (reasoning loop, prompt builder, parser, memory)
└── llm/              # MODULE 6: LLM Adapters (Ollama, Anthropic, OpenAI)
```

### Module 1: Hub API (`lib/savant/hub/`)

**Purpose**: HTTP API serving tool calls, diagnostics, and engine management

**Key Files**:
- `builder.rb` - Hub construction from config
- `router.rb` - HTTP request routing
- `sse.rb` - Server-Sent Events for live streaming
- `service_manager.rb` - Engine loader and dispatcher
- `connections.rb` - Connection registry
- `static_ui.rb` - Static asset serving

**Key Endpoints**: `/`, `/routes`, `/diagnostics`, `/hub/status`, `/logs`, `/:engine/tools/:name/call`

### Module 2: Logging & Observability (`lib/savant/logging/`)

**Purpose**: Centralized logging, metrics, audit trails, and telemetry

**Key Files**:
- `logger.rb` - Structured logger with levels and timing
- `event_recorder.rb` - In-memory + file event store
- `metrics.rb` - Counters and distributions
- `replay_buffer.rb` - Request replay buffer
- `exporter.rb` - Metrics export (Prometheus format)
- `audit/policy.rb` - Audit configuration
- `audit/store.rb` - Audit log persistence

**Key APIs**: `Logger.new(service:, tool:)`, `EventRecorder.record(event)`, `Metrics.increment(metric, labels)`

### Module 3: Framework (`lib/savant/framework/`)

**Purpose**: MCP framework core, middleware, transports, and shared utilities

**Key Files**:
- `mcp/core/` - Tool specification, Registrar, DSL, middleware, validation
- `mcp/server.rb` - MCP server implementation
- `mcp/dispatcher.rb` - JSON-RPC dispatcher
- `engine/base.rb` - Engine base class
- `engine/context.rb` - Runtime context
- `middleware/` - trace.rb, logging.rb, metrics.rb, user_header.rb
- `transports/http/rack_app.rb` - Minimal Rack app
- `transports/mcp/stdio.rb` - Stdio transport
- `transports/mcp/websocket.rb` - WebSocket transport
- `config.rb` - Configuration loader
- `db.rb` - Database abstraction
- `secret_store.rb` - Secrets management
- `boot.rb` - Bootstrap
- `generator.rb` - Code generation

**Key APIs**: `Framework::MCP::Core::DSL.build { ... }`, `Registrar.call(name, args, ctx:)`, `Engine#before_call`

### Module 4: Engines (`lib/savant/engines/`)

**Purpose**: All MCP engine implementations

**Engines** (under `lib/savant/engines/`):
- **Context** (`context/`): DB-backed FTS over repo chunks; memory bank helpers. See [memory_bank/engine_context.md](memory_bank/engine_context.md)
- **Think** (`think/`): Workflow orchestration (`plan/next`) with driver prompts. See [memory_bank/engine_think.md](memory_bank/engine_think.md)
- **Jira** (`jira/`): Jira REST v3 integration. See [memory_bank/engine_jira.md](memory_bank/engine_jira.md)
- **Personas** (`personas/`): YAML personas catalog. See [memory_bank/engine_personas.md](memory_bank/engine_personas.md)
- **Rules** (`rules/`): Shared guardrails and best practices. See [memory_bank/engine_rules.md](memory_bank/engine_rules.md)
- **Indexer** (`indexer/`): Repository indexing and chunking
- **AI** (`ai/`): Agent orchestration
- **AMR** (`amr/`): Asset management rules

> ℹ️  The Boot Runtime (`lib/savant/framework/boot.rb`) lives in the Framework module because it wires config, personas, prompts, AMR rules, and runtime state before engines run. See [memory_bank/engine_boot.md](memory_bank/engine_boot.md) for full details.

**Engine Pattern**: Each engine has `engine.rb` (extends `Framework::Engine::Base`), `tools.rb` (uses `Framework::MCP::Core::DSL`), and `ops.rb` (business logic).

### Module 5: Agent Runtime (`lib/savant/agent/`)

**Purpose**: Autonomous reasoning loop orchestrating LLM-driven tool execution

**Key Files**:
- `runtime.rb` - Core reasoning loop with step limits and retry logic
- `prompt_builder.rb` - Token budget management and deterministic prompt assembly
- `output_parser.rb` - JSON extraction, schema validation, auto-correction
- `memory.rb` - Ephemeral state + `.savant/session.json` persistence

**Key Concepts**:
- **Reasoning Worker decisions**: Externalized intent selection (Redis worker)
- **LLM support**: Heavy analysis for tool outputs where needed
- **Token budgets**: LLM context budgets with LRU trimming as applicable
- **Memory persistence**: Session snapshots with summarization

**Key APIs**: `Runtime.new(goal:, llm_model:).run(max_steps:, dry_run:)`

**See [memory_bank/runtime.md](memory_bank/runtime.md) for full architecture with visual diagrams.**

### Module 6: LLM Adapters (`lib/savant/llm/`)

**Purpose**: Pluggable LLM provider abstraction layer

**Key Files**:
- `adapter.rb` - Provider delegation based on ENV config
- `ollama.rb` - Ollama implementation (default, local-first)
- `anthropic.rb` - Anthropic API stub (Claude models)
- `openai.rb` - OpenAI API stub (GPT models)

**Configuration**:
```ruby
ENV['LLM_PROVIDER']  # ollama|anthropic|openai
# SLM_MODEL deprecated (decisions handled by Reasoning Worker)
ENV['LLM_MODEL']     # llama3:latest (default)
ENV['OLLAMA_HOST']   # http://127.0.0.1:11434 (default)
```

**Key APIs**: `LLM::Adapter.generate(model:, prompt:, temperature:, max_tokens:)`

## Generators

Scaffold a new engine in seconds:
```
ruby ./bin/savant generate engine <name> [--with-db] [--force]
```
Creates `lib/savant/engines/<name>/{engine.rb,tools.rb}` and a baseline spec. Then run with `MCP_SERVICE=<name> ruby ./bin/mcp_server`.

## Transport Layer

```mermaid
flowchart LR
  subgraph Hub[HTTP Hub]
    R[Router]-- ServiceManager --> E[Engine Registrar]
  end
  UI[React UI] -->|HTTP JSON| R
  CLI[Editor/CLI] -->|stdio JSON-RPC| EngineProc
  EngineProc[Single MCP Process] --> E
  E -->|call tool| Ops
  Ops --> DB[(Postgres)]
```

- **HTTP**: `lib/savant/framework/transports/http/rack_app.rb` - Rack app for Hub + UI
- **MCP**: `lib/savant/framework/transports/mcp/{stdio,websocket}.rb` - Stdio/WebSocket for editors
- **ServiceManager**: `lib/savant/hub/service_manager.rb` - Transport-agnostic engine loading
- Exactly one engine per MCP process; Hub multiplexes multiple engines via HTTP

## UI

- React UI under `/ui` (or dev at 5173) with three main sections:
  - **Dashboard**: Overview of all engines and system status
  - **Engines**: Per-engine tabs for tool execution and testing
  - **Diagnostics**: Five tabs for system monitoring
    - Overview: System configuration, DB connectivity, repos, personas, rules, LLM models
    - Requests: HTTP request logs and traffic statistics
    - **Agents**: Real-time agent runtime monitoring with timeline/grouped views, live streaming, trace export
    - Logs: Live event streaming with log-level filtering (All/Debug/Info/Warn/Error)
    - Routes: API route browser with filtering by module, method, and path
- Footer shows Dev-Mode/Build-Mode indicator

### UI Consistency & Testing

The React UI uses a compact design and consistent control sizes across the app.

- Compact theme: 11px base typography; list/table rows 28–32px; tight paddings; 6px radius.
- Controls: Buttons and IconButtons default to `size="small"`; icons default to small (~18px). Start/end icon spacing is standardized.
- Tools: All engine Tools pages use a single Tool Runner (schema‑driven forms, JSON input, presets/history, cURL/HTTPie copy).
- Diagnostics: Live logs/events streaming with filters; Requests inspector supports re‑execute and “Open in Tool Runner”.

Frontend tests are available (Vitest + Testing Library).

```bash
cd frontend
npm run test       # run once
npm run test:watch # watch mode
```

Key test files:
- `src/theme/compact.test.ts`: compact scale + button/icon defaults.
- `src/components/ToolRunner.test.tsx`: form/json modes and tool execution.
- `src/utils/tools.test.ts`: schema classification, defaults, cURL/CLI helpers.

## Diagnostics & Logs

- Aggregated logs (JSON events): `GET /logs?n=100[&mcp=context][&type=http_request]`
- Live event stream (SSE): `GET /logs/stream[?mcp=context][&type=tool_call_started]`
- Per-engine logs (file tail): `GET /:engine/logs?n=100` or stream with `?stream=1`
- **Agent diagnostics**: `GET /diagnostics/agent` (events + memory), `GET /diagnostics/agent/trace`, `GET /diagnostics/agent/session`
- Hub request stats: `GET /hub/stats`
- Connections list: `GET /diagnostics/connections`
- Per-engine diagnostics: `GET /diagnostics/mcp/:name`

 
## Memory Bank (Detailed Docs)

All detailed docs (with visual diagrams) live under `memory_bank/`. Use the table above (and the direct links below) to jump into the source of truth:

- Framework + architecture: [`framework.md`](memory_bank/framework.md), [`architecture.md`](memory_bank/architecture.md)
- Boot Runtime: [`engine_boot.md`](memory_bank/engine_boot.md) - RuntimeContext, boot sequence, AMR system, CLI reference
- **Agent Runtime: [`runtime.md`](memory_bank/runtime.md) - Reasoning loop, LLM adapters, memory system, token budgets, telemetry**

- Engines: [`engine_context.md`](memory_bank/engine_context.md), [`engine_think.md`](memory_bank/engine_think.md), [`engine_jira.md`](memory_bank/engine_jira.md), [`engine_personas.md`](memory_bank/engine_personas.md)
- Guardrails + patterns: [`engine_rules.md`](memory_bank/engine_rules.md)

These are the canonical references; the README stays short and points you there.

## Distribution & Activation (MVP)

Overview
- Savant ships as a single binary via Homebrew. Activation is offline-only using a username+key pair.
- Keys are validated locally using a salted SHA256. No license servers are contacted.

Commands
- `savant activate <username>:<key>` — stores the license at `~/.savant/license.json`.
- `savant status` — prints whether the license is valid and the stored path.
- `savant deactivate` — removes the local license file.

Dev vs Prod behavior
- Brew/packaged installs: license is enforced by default.
- Git checkout (development): license is bypassed automatically when `SAVANT_PATH` points to a directory that contains a `.git` folder.
- Make targets: default to `SAVANT_DEV=1`, so all `make` flows run without a key.
- Force enforcement in dev: set `SAVANT_ENFORCE_LICENSE=1` to require a valid license even from a git checkout.

Environment variables
- `SAVANT_PATH`: project base path (required for local runs; Brew sets this internally).
- `SAVANT_DEV`: when `1`, bypasses license checks. The Makefile exports this as `1` by default.
- `SAVANT_ENFORCE_LICENSE`: when `1`, forces license checks even in dev/git checkouts.

Build & Release (manual MVP)
- Build/package/checksum (artifacts in `dist/`):
  - `SAVANT_BUILD_SALT='<secret>' make build`
  - `make package && make checksum`
- Tag + Release (requires `gh`):
  - `make tag VERSION=v0.1.0`
  - `make release VERSION=v0.1.0`
- Homebrew formula:
  - `RELEASE_BASE_URL=https://github.com/<org>/savant/releases/download make formula`
  - Copy `packaging/homebrew/savant.rb` into your public tap.
