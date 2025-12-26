# Savant Agentic AI Development System - Claude Project Instructions

**Version:** 1.0
**Date:** 2025-12-06
**Purpose:** Comprehensive guide for AI-assisted development on Savant platform

---

## 1. System Overview

### What is Savant?

Savant is an **Agent Infrastructure Platform (AIP)** - a developer-first, local-first runtime for building and orchestrating autonomous AI agents. It's designed to give developers maximum speed, control, and safety when building AI-powered automation.

**Core Value Proposition:**
- Build AI agents with maximum speed, control, and safety
- Run agents locally or in enterprise environments
- Extend with MCP tools, custom workflows, and multi-agent orchestration
- Maintain privacy, ownership, and autonomy

### Current Status

**MVP (v0.1.0):** Fully functional Ruby-based system with:
- Agent runtime with autonomous reasoning loops
- MCP framework with 6+ engines (Context, Git, Think, Jira, Personas, Rules)
- YAML-based workflow execution
- Repository indexing with FTS search
- React UI for diagnostics and monitoring
- CLI tools for local development

**Target:** Transform into a full-scale Rails product with multi-tenancy, web-based agent/workflow management, marketplace, and enterprise features.

---

## 2. Architecture Overview

### High-Level System Design

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
│  │ Reasoning API│                         │     Rules     │  │
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

### Core Modules

**Module 1: Hub API** (`lib/savant/hub/`)
- HTTP routing and service management
- SSE streaming for live logs
- Engine lifecycle management
- Static UI serving

**Module 2: Framework** (`lib/savant/framework/`)
- MCP core (tool registry, JSON-RPC dispatcher)
- Middleware (logging, metrics, tracing)
- Transports (stdio, HTTP, WebSocket)
- Configuration and database abstraction

**Module 3: Engines** (`lib/savant/engines/`)
- **Context:** FTS search over repository chunks
- **Git:** Local read-only git intelligence
- **Think:** Workflow orchestration (plan/next)
- **Jira:** Jira REST v3 integration
- **Personas:** Persona catalog (YAML)
- **Rules:** Shared guardrails and best practices
- **Agents:** Agent execution engine
- **Indexer:** Repository scanning and chunking

**Module 4: Agent Runtime** (`lib/savant/agent/`)
- Autonomous reasoning loop (decisions via Reasoning API)
- Prompt builder with telemetry snapshots
- Action parsing and policy enforcement
- Memory system (ephemeral + persistent)

**Module 5: LLM Adapters** (`lib/savant/llm/`)
- Ollama (default, local-first)
- Anthropic API stub
- OpenAI API stub

**Module 6: Logging** (`lib/savant/logging/`)
- Structured logging
- Event recording
- Metrics collection
- Audit trails

---

## 3. Key Concepts

### Agent Runtime

**Autonomous Reasoning Loop:**
- **Reasoning API decisions:** Externalized intent selection (v1)
- **LLM support:** Complex tool outputs may use LLMs as configured
- **Step-based execution:** Configurable max steps (default 25)
- **Tool routing:** Via MCP multiplexer to all engines
- **Memory persistence:** Session snapshots in `.savant/session.json`

**Execution Flow:**
1. Load goal and runtime context (persona, driver, rules)
2. Build prompt with token budget management
3. Call Reasoning API (decide action)
4. Parse output (JSON extraction, schema validation)
5. Route tool calls via multiplexer
6. Update memory and telemetry
7. Repeat until goal achieved or max steps reached

### MCP Framework

**Multiplexer Pattern:**
- Single stdio process spawns child processes per engine
- Namespaced tools (e.g., `context.fts_search`, `git.diff`)
- Process isolation with automatic restart on failure
- Unified tool surface for agents and workflows

**Tool Registry:**
- Tools defined via DSL in `tools.rb` files
- JSON-RPC 2.0 protocol
- Schema validation and middleware hooks
- Dynamic registration at boot

### Workflow System

**YAML Executor:**
- Deterministic step-by-step execution
- Tool steps and agent steps
- Parameter interpolation
- Per-step telemetry and state persistence
- Saved runs in `.savant/workflow_runs/`

**Visual Editor:**
- Graph-based editing in React UI
- Drag-and-drop nodes
- YAML preview and validation
- Diagram rendering

### Repository Indexing

**Indexer Pipeline:**
1. Scan configured repos (respect `.gitignore`)
2. SHA256 deduplication at blob level
3. Multi-strategy chunking (code by lines, markdown by chars)
4. Language detection and filtering
5. Postgres FTS index on `chunks.chunk_text`
6. Incremental updates via `.cache/indexer.json`

---

## 4. Development Workflows

### Setting Up Development Environment

```bash
# Prerequisites: Ruby 3.2+, Bundler, Postgres

# Clone and install
git clone https://github.com/ashabbir/savant.git
cd savant
bundle install

# Set database URL
export DATABASE_URL=postgres://context:contextpw@localhost:5432/contextdb

# Setup database
make rails-migrate
make rails-fts
cd server && bundle exec rake savant:setup

# Build UI (optional)
make ui-build-local

# Start dev mode (Rails + Vite + Hub)
make dev
```

**Dev Mode URLs:**
- UI (HMR): http://localhost:5173
- API: http://localhost:9999
- Health: http://localhost:9999/healthz

### CLI Commands Reference

```bash
# Boot runtime
./bin/savant run [--persona=NAME] [--skip-git]
./bin/savant review          # Boot for MR review
./bin/savant workflow NAME   # Execute workflow

# Agent execution
./bin/savant run --agent-input="Summarize recent changes"
./bin/savant run --agent-file=goal.txt --max-steps=50

# Engine management
./bin/savant engines         # List engine status
./bin/savant tools           # List available tools

# Generators
./bin/savant generate engine NAME [--with-db]
```

### Working with Agents

**Creating an Agent (UI):**
1. Open UI → MCPs tab → select "agents"
2. Click "+" (New Agent)
3. Fill fields: Name, Persona, Driver prompt, Rules
4. Save Agent

**Executing an Agent (CLI):**
```bash
# Direct execution
./bin/savant run \
  --agent-input="Review the git diff and suggest improvements" \
  --persona=savant-reviewer \
  --max-steps=25

# Debug mode
./bin/savant run \
  --agent-input="Test context search" \
  --force-tool=context.fts_search \
  --force-args='{"q":"agent runtime","limit":5}' \
  --dry-run
```

### Working with Workflows

**Creating a Workflow (YAML):**
```yaml
# workflows/example.yml
steps:
  - name: diff
    tool: git.diff

  - name: search_context
    tool: context.fts_search
    with:
      q: "authentication"
      limit: 10

  - name: summarize
    agent: summarizer
    with:
      goal: "Summarize the diff and context"
```

**Executing a Workflow:**
```bash
# CLI
./bin/savant workflow example --params='{"ticket":"JIRA-123"}'

# HTTP
curl -H 'content-type: application/json' \
     -H 'x-savant-user-id: me' \
     -X POST http://localhost:9999/workflow/tools/workflow_run/call \
     -d '{"params":{"ticket":"JIRA-123"},"workflow":"example"}'
```

### Repository Indexing

```bash
# Via Rake (Rails)
cd server
export DATABASE_URL=postgres://context:contextpw@localhost:5432/contextdb

bundle exec rake savant:index_all              # All repos
bundle exec rake 'savant:index[myrepo]'        # Single repo
bundle exec rake savant:status                 # Index status

# Via Make
make repo-index-all
make repo-index-repo repo=myrepo
make repo-status
```

---

## 5. Code Structure and Conventions

### Directory Layout

```
savant/
├── lib/savant/              # Core Ruby modules
│   ├── agent/               # Agent runtime
│   ├── engines/             # MCP engines
│   ├── framework/           # MCP framework
│   ├── hub/                 # HTTP hub
│   ├── llm/                 # LLM adapters
│   └── logging/             # Observability
├── frontend/                # React UI (Vite + TypeScript)
│   ├── src/
│   │   ├── components/
│   │   ├── pages/
│   │   └── api/
├── server/                  # Rails API (future)
├── config/                  # Configuration files
├── docs/                    # Documentation
│   ├── getting-started.md
│   └── mvp-to-product/      # Product roadmap docs
├── memory_bank/             # Detailed system docs
├── spec/                    # RSpec tests
└── workflows/               # YAML workflows
```

### Engine Pattern

Every engine follows this structure:

```
lib/savant/engines/NAME/
├── engine.rb      # Engine class (extends Framework::Engine::Base)
├── tools.rb       # Tool definitions (uses Framework::MCP::Core::DSL)
├── ops.rb         # Business logic (operations)
└── config/        # Optional config files
```

**Example Engine Implementation:**

```ruby
# lib/savant/engines/example/engine.rb
module Savant::Engines::Example
  class Engine < Savant::Framework::Engine::Base
    def initialize(config = {})
      super
      @ops = Ops.new
    end

    def tools
      Tools.build
    end
  end
end

# lib/savant/engines/example/tools.rb
module Savant::Engines::Example::Tools
  extend Savant::Framework::MCP::Core::DSL

  tool :example_search do
    description "Search example data"
    param :query, type: :string, required: true
    param :limit, type: :integer, default: 10

    handler do |args, ctx|
      ops.search(args[:query], limit: args[:limit])
    end
  end
end

# lib/savant/engines/example/ops.rb
class Savant::Engines::Example::Ops
  def search(query, limit: 10)
    # Implementation
    { results: [...] }
  end
end
```

### Service Object Pattern

For complex operations, use service objects:

```ruby
# app/services/agents/executor.rb
module Agents
  class Executor
    def initialize(agent:, goal:, config: {})
      @agent = agent
      @goal = goal
      @config = config
    end

    def call
      setup_runtime
      execute_agent
      persist_results
    rescue StandardError => e
      handle_error(e)
    end

    private

    def setup_runtime
      # Load persona, rules, tools
    end

    def execute_agent
      # Run agent runtime loop
    end

    def persist_results
      # Save to database
    end
  end
end
```

### UI Component Conventions

**Compact Design System:**
- 11px base typography
- List/table rows: 28-32px
- Tight paddings (8px, 12px, 16px)
- Border radius: 6px
- Buttons: `size="small"`
- Icons: ~18px

**Layout Rules:**
- **Two-panel layout:** Action panel (left), Result panel (right)
- **Sizing:** 4/8 split on md+ screens (left md:4, right md:8)
- **Dialogs:** Always include close icon in title bar
- **Consistency:** Apply across all pages

---

## 6. Testing Strategy

### Backend Tests (RSpec)

```bash
# Run all tests
bundle exec rspec

# Run specific test
bundle exec rspec spec/lib/savant/agent/runtime_spec.rb

# Run with coverage
COVERAGE=1 bundle exec rspec

# Watch mode
bundle exec guard
```

**Test Structure:**
```ruby
# spec/lib/savant/agent/runtime_spec.rb
RSpec.describe Savant::Agent::Runtime do
  describe '#run' do
    let(:runtime) { described_class.new(goal: "Test goal") }

    it 'executes successfully' do
      result = runtime.run(max_steps: 5)
      expect(result[:status]).to eq('completed')
    end

    it 'respects max steps limit' do
      expect(runtime.run(max_steps: 3)[:steps]).to have_at_most(3).items
    end
  end
end
```

### Frontend Tests (Vitest)

```bash
cd frontend

# Run tests
npm run test

# Watch mode
npm run test:watch

# Coverage
npm run test:coverage
```

**Test Structure:**
```typescript
// src/components/ToolRunner.test.tsx
import { render, screen, fireEvent } from '@testing-library/react'
import { ToolRunner } from './ToolRunner'

describe('ToolRunner', () => {
  it('renders tool form', () => {
    render(<ToolRunner tool={mockTool} />)
    expect(screen.getByText('Execute')).toBeInTheDocument()
  })

  it('executes tool with params', async () => {
    const onExecute = vi.fn()
    render(<ToolRunner tool={mockTool} onExecute={onExecute} />)

    fireEvent.click(screen.getByText('Execute'))
    await waitFor(() => expect(onExecute).toHaveBeenCalled())
  })
})
```

### Quality Checks

```bash
# Linting
bundle exec rubocop
bundle exec rubocop -A  # Auto-correct

# Frontend linting
cd frontend
npm run lint

# Type checking
npm run type-check
```

---

## 7. MVP to Product Roadmap

### Current MVP Capabilities

✅ Agent execution (Reasoning API decisions)
✅ Workflow execution (YAML-based)
✅ Repository indexing (local)
✅ Code search (FTS)
✅ Git intelligence (diffs, hunks)
✅ Built-in tools (6 engines)
✅ CLI interface
✅ React UI (diagnostics, monitoring)
✅ Logging and metrics

### Phase 1: Foundation (Months 1-2)

**Goal:** Multi-tenancy and database-backed agent/workflow management

**Features:**
- User authentication (Devise)
- Teams and workspaces
- Agent CRUD (database schema)
- Workflow CRUD (database schema)
- REST API (v1)
- Basic UI for management

**Database Schema (Key Tables):**
```sql
users, teams, team_members, workspaces
agents, agent_rulesets, agent_tools
workflows, personas, rulesets, repositories
runs (polymorphic), steps, traces
```

### Phase 2: Core Capabilities (Months 3-4)

**Features:**
- Real-time agent monitoring UI
- Visual workflow editor (graph-based)
- Repository registration (GitHub/GitLab integration)
- Custom tool builder
- Search and discovery

### Phase 3: Collaboration (Months 5-6)

**Features:**
- Sharing and permissions
- Comments and activity feeds
- Integration hub (Slack, GitHub, Linear)
- Tool marketplace foundation

### Phase 4: Enterprise (Months 7-9)

**Features:**
- SSO integration (SAML, LDAP)
- Advanced compliance (GDPR, SOC 2)
- Secrets vault
- Analytics dashboards
- Webhooks

### Phase 5: Scale & Polish (Months 10-12)

**Features:**
- Mobile apps (iOS/Android)
- Desktop app (Electron)
- Multi-language SDKs (Python, JS, Go)
- IDE extensions (VSCode, JetBrains)
- Performance optimization

---

## 8. Best Practices

### Development Principles

1. **Rails-native:** Leverage Rails conventions (CoC, DRY)
2. **API-first:** All features accessible via REST API
3. **Modular:** Keep engine-based architecture
4. **Backward compatible:** Preserve CLI and MCP stdio
5. **Observable:** Comprehensive logging and metrics
6. **Secure:** Multi-tenancy with data isolation

### Code Quality

**Ruby Style:**
- Follow RuboCop rules (`.rubocop.yml`)
- Use service objects for complex logic
- Keep controllers thin (delegate to services)
- Write descriptive method names
- Add comments only where logic isn't self-evident

**TypeScript Style:**
- Use strict mode
- Avoid `any` types
- Prefer functional components
- Use React Query for data fetching
- Keep components small and focused

### Performance Guidelines

**Backend:**
- Avoid N+1 queries (use `includes`, `preload`)
- Index all foreign keys
- Use background jobs for long operations
- Cache frequently accessed data (Redis)

**Frontend:**
- Code splitting for large bundles
- Lazy load components
- Optimize images (WebP, lazy loading)
- Use virtualization for long lists

### Security Guidelines

- **Never commit secrets** (use ENV vars or Rails credentials)
- **Validate all inputs** (use strong params in Rails)
- **Sanitize outputs** (prevent XSS)
- **Enforce authorization** (use Pundit policies)
- **Use HTTPS only** in production
- **Rate limit APIs** (Rack Attack)

---

## 9. Common Tasks

### Adding a New Engine

```bash
# Generate engine scaffold
./bin/savant generate engine my_engine --with-db

# This creates:
# - lib/savant/engines/my_engine/engine.rb
# - lib/savant/engines/my_engine/tools.rb
# - lib/savant/engines/my_engine/ops.rb
# - spec/lib/savant/engines/my_engine/engine_spec.rb

# Add tools in tools.rb
# Implement logic in ops.rb
# Register in config/settings.json

# Run the engine
MCP_SERVICE=my_engine bundle exec ruby ./bin/mcp_server
```

### Adding a New API Endpoint

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :agents do
      member do
        post :execute
      end
    end
  end
end

# app/controllers/api/v1/agents_controller.rb
class Api::V1::AgentsController < Api::V1::BaseController
  def execute
    agent = current_workspace.agents.find(params[:id])
    authorize agent, :execute?

    run = Agents::Executor.new(
      agent: agent,
      goal: params[:goal],
      user: current_user
    ).call

    render json: RunSerializer.new(run), status: :created
  end
end
```

### Adding a New UI Page

```tsx
// frontend/src/pages/agents/AgentList.tsx
import { useQuery } from '@tanstack/react-query'
import { api } from '@/api'

export function AgentList() {
  const { data: agents, isLoading } = useQuery({
    queryKey: ['agents'],
    queryFn: () => api.agents.list()
  })

  if (isLoading) return <div>Loading...</div>

  return (
    <div>
      {agents.map(agent => (
        <AgentCard key={agent.id} agent={agent} />
      ))}
    </div>
  )
}

// Add route in routes.tsx
{
  path: 'agents',
  element: <AgentList />
}
```

### Debugging Agent Execution

```bash
# Enable verbose logging
export LOG_LEVEL=debug

# Run agent with dry-run
./bin/savant run \
  --agent-input="Test goal" \
  --dry-run \
  --quiet=false

# Check logs
tail -f logs/agent_runtime.log
tail -f logs/agent_trace.log

# View session state
cat .savant/session.json | jq .

# Test specific tool
./bin/savant run \
  --force-tool=context.fts_search \
  --force-args='{"q":"agent","limit":5}' \
  --force-finish
```

---

## 10. Key Files Reference

### Configuration
- `config/settings.json` - Main config (repos, indexer, MCP settings)
- `config/mounts.yml` - Volume mounts (if using Docker)
- `.env` - Environment variables (not committed)

### Documentation
- `README.md` - Quick start and overview
- `AGENTS.md` - Agent system overview
- `docs/getting-started.md` - Detailed setup guide
- `docs/mvp-to-product/` - Product roadmap
- `memory_bank/` - Detailed technical docs

### Core Runtime Files
- `lib/savant/agent/runtime.rb` - Agent execution loop
- `lib/savant/framework/mcp/core/registrar.rb` - Tool registry
- `lib/savant/hub/router.rb` - HTTP routing
- `lib/savant/multiplexer/` - MCP multiplexer

### CLI Entrypoints
- `bin/savant` - Main CLI (run, workflow, generate)
- `bin/mcp_server` - MCP stdio server

---

## 11. Troubleshooting

### Common Issues

**Database connection errors:**
```bash
# Verify DATABASE_URL is set
echo $DATABASE_URL

# Test connection
make smoke

# Reset database
make migrate-reset
```

**Agent execution fails:**
```bash
# Check Ollama is running
curl http://127.0.0.1:11434/api/tags

# Pull models
ollama pull phi3.5:latest
ollama pull llama3:latest

# Check agent logs
tail -f logs/agent_runtime.log
```

**UI not loading:**
```bash
# Rebuild UI
make ui-build-local

# Check Hub is running
curl http://localhost:9999/healthz

# Check frontend dev server
cd frontend && npm run dev
```

**Indexing fails:**
```bash
# Check repo paths in config/settings.json
cat config/settings.json | jq '.indexer.repos'

# Check permissions
ls -la /path/to/repo

# Re-index
make repo-delete-all
make repo-index-all
```

---

## 12. Additional Resources

### Documentation
- [Agent Runtime](memory_bank/agent_runtime.md)
- [Boot Runtime](memory_bank/engine_boot.md)
- [Multiplexer](memory_bank/multiplexer.md)
- [Framework](memory_bank/framework.md)
- [Architecture](memory_bank/architecture.md)

### External Links
- Ruby on Rails: https://rubyonrails.org
- Model Context Protocol: https://modelcontextprotocol.io
- Ollama: https://ollama.ai

### Getting Help
- GitHub Issues: https://github.com/ashabbir/savant/issues
- Discussions: https://github.com/ashabbir/savant/discussions

---

## 13. Quick Reference Commands

```bash
# Development
make dev                    # Start Rails + Vite + Hub
make rails-up               # Start Rails only
make ui-build-local         # Build UI

# Database
make rails-migrate          # Run migrations
make rails-fts              # Setup FTS index
make smoke                  # Test DB connection

# Indexing
make repo-index-all         # Index all repos
make repo-status            # Check index status

# Testing
bundle exec rspec           # Run backend tests
cd frontend && npm test     # Run frontend tests
bundle exec rubocop         # Lint Ruby code

# Agent Runtime
./bin/savant run            # Boot agent runtime
./bin/savant engines        # List engines
./bin/savant tools          # List tools

# Workflow
./bin/savant workflow NAME  # Execute workflow

# Generators
./bin/savant generate engine NAME
```

---

**Document Status:** Production Ready
**Last Updated:** 2025-12-06
**Maintainer:** Engineering Team
**For:** Claude AI Projects
