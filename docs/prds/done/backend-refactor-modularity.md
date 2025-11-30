# Product Requirements Document: Backend Refactoring for Modularity

## Executive Summary

Refactor the Savant MCP backend to achieve clear separation of concerns across four distinct modules: Hub API, Logging & Observability, Framework, and Engines. Additionally, extract the frontend into a completely separate area.

**Document Version**: 1.0
**Date**: 2025-11-28
**Status**: Draft

---

## 1. Current State Analysis

### 1.1 Current Directory Structure

```
lib/savant/
├── ai/                    # Engine: Agent orchestration
├── amr/                   # Engine: Asset management rules
├── audit/                 # Logging/Framework: Audit trails
├── boot.rb                # Framework: Bootstrap
├── config.rb              # Framework: Configuration loader
├── connections.rb         # Hub API: Connection registry
├── context/               # Engine: Search and memory
├── core/                  # Framework: Base classes
├── db.rb                  # Framework: Database abstraction
├── generator.rb           # Framework: Code generation
├── http/                  # Hub API: HTTP routing, SSE
├── hub.rb                 # Hub API: Main entry point
├── indexer/               # Engine: Repository indexing
├── jira/                  # Engine: Jira integration
├── logger.rb              # Logging: Structured logger
├── logging/               # Logging: Event recording
├── mcp/                   # Framework: MCP core
├── middleware/            # Framework: Request middleware
├── personas/              # Engine: Persona catalog
├── rules/                 # Engine: Rules catalog
├── sdk/                   # Framework: Ruby client
├── secret_store.rb        # Framework: Secrets management
├── service_manager.rb     # Hub API: Service dispatcher
├── telemetry/             # Logging: Metrics and replay
├── think/                 # Engine: Workflow orchestration
└── transports/            # Framework: HTTP, stdio, WebSocket
```

### 1.2 Problems with Current Structure

1. **Mixed Concerns**: Hub API, framework, logging, and engines all reside in the same directory
2. **Unclear Boundaries**: Difficult to identify what belongs to which module
3. **Tight Coupling**: Components reference each other without clear module boundaries
4. **Frontend Integration**: Static UI served directly by Router, not separated
5. **Scalability Issues**: Adding new engines or framework features creates clutter
6. **Maintenance Burden**: Changes to one concern can inadvertently affect others

### 1.3 Lines of Code Distribution

- **Total Ruby Files**: ~101 files
- **Total Lines**: ~9,085 lines
- **Engines**: ~4,500 lines (6 engines)
- **Framework**: ~2,500 lines
- **Hub API**: ~1,200 lines
- **Logging**: ~885 lines

---

## 2. Goals and Objectives

### 2.1 Primary Goals

1. **Clear Separation of Concerns**: Each module should have a single, well-defined responsibility
2. **Improved Maintainability**: Changes to one module should not affect others
3. **Better Discoverability**: Developers should easily find where functionality lives
4. **Scalable Architecture**: Easy to add new engines, middleware, or transports
5. **Frontend Independence**: Complete separation of frontend from backend

### 2.2 Success Criteria

- [ ] All files organized into 4 distinct backend modules + 1 frontend module
- [ ] No circular dependencies between modules
- [ ] Clear module boundaries with documented interfaces
- [ ] All existing tests pass without modification
- [ ] Zero functional regressions
- [ ] Improved developer experience (easier to navigate, understand, extend)

---

## 3. Proposed Architecture

### 3.1 New Directory Structure

```
savant/
├── lib/
│   └── savant/
│       ├── hub/              # MODULE 1: Hub API
│       ├── logging/          # MODULE 2: Logging & Observability
│       ├── framework/        # MODULE 3: Framework
│       ├── engines/          # MODULE 4: Engines
│       └── version.rb
├── frontend/                 # MODULE 5: Frontend (separate)
├── config/
├── docs/
├── spec/
└── bin/
```

### 3.2 Module Breakdown

#### MODULE 1: Hub API (`lib/savant/hub/`)

**Purpose**: HTTP API serving tool calls, diagnostics, and engine management

**Components**:
```
lib/savant/hub/
├── builder.rb              # Hub.build_from_config (from hub.rb)
├── router.rb               # HTTP routing (from http/router.rb)
├── sse.rb                  # Server-Sent Events (from http/sse.rb)
├── service_manager.rb      # Engine loader and dispatcher
├── connections.rb          # Connection registry
└── static_ui.rb            # Static file serving (from http/static_ui.rb)
```

**Responsibilities**:
- HTTP request routing
- SSE connection management
- Service/engine discovery and loading
- Hub-level diagnostics and status
- Connection tracking
- Static asset serving (bridge to frontend)

**Key Endpoints**:
- `GET /` - Dashboard
- `GET /routes`, `/diagnostics`, `/hub/status`
- `GET /logs`, `/logs/stream` - Aggregated logs
- `GET /:engine/tools/:name/call` - Tool invocation
- `POST /:engine/tools/:name/call`

**Dependencies**:
- Framework (Registrar, Transport)
- Logging (EventRecorder, Logger)
- Engines (dynamically loaded)

---

#### MODULE 2: Logging & Observability (`lib/savant/logging/`)

**Purpose**: Centralized logging, metrics, audit trails, and telemetry

**Components**:
```
lib/savant/logging/
├── logger.rb               # Structured logger
├── event_recorder.rb       # In-memory + file event store
├── metrics.rb              # Counters and distributions (from telemetry/)
├── replay_buffer.rb        # Request replay buffer (from telemetry/)
├── exporter.rb             # Metrics export (from telemetry/)
├── audit/
│   ├── policy.rb           # Audit configuration
│   └── store.rb            # Audit log persistence
└── formatters/
    ├── json_formatter.rb
    └── text_formatter.rb
```

**Responsibilities**:
- Structured logging (trace, debug, info, warn, error)
- Event recording and streaming
- Metrics collection (tool invocations, errors, duration)
- Audit trail enforcement and storage
- Replay buffer for debugging
- Export to external observability systems

**Key APIs**:
- `Logger.new(service:, tool:)` - Create scoped logger
- `EventRecorder.record(event)` - Record event
- `EventRecorder.last(n, mcp:, type:)` - Query events
- `EventRecorder.stream(mcp:, type:)` - SSE stream
- `Metrics.increment(metric, labels)` - Record metric
- `Metrics.snapshot()` - Get current state

**Dependencies**:
- None (standalone module)

---

#### MODULE 3: Framework (`lib/savant/framework/`)

**Purpose**: MCP framework core, middleware, transports, and shared utilities

**Components**:
```
lib/savant/framework/
├── mcp/
│   ├── core/
│   │   ├── tool.rb         # Tool specification
│   │   ├── registrar.rb    # Tool registry
│   │   ├── dsl.rb          # Tool DSL
│   │   ├── middleware.rb   # Middleware chain
│   │   └── validation.rb   # Schema validation
│   ├── server.rb           # MCP server (from mcp_server.rb)
│   └── dispatcher.rb       # JSON-RPC dispatcher (from mcp_dispatcher.rb)
├── engine/
│   ├── base.rb             # Engine base class (from core/engine.rb)
│   └── context.rb          # Runtime context (from core/context.rb)
├── middleware/
│   ├── trace.rb            # Trace middleware
│   ├── logging.rb          # Logging middleware
│   ├── metrics.rb          # Metrics middleware
│   └── user_header.rb      # User header middleware
├── transports/
│   ├── http/
│   │   └── rack_app.rb     # Minimal Rack app
│   ├── mcp/
│   │   ├── stdio.rb        # Stdio transport
│   │   └── websocket.rb    # WebSocket transport
│   └── base.rb             # Transport abstraction
├── config.rb               # Configuration loader
├── db.rb                   # Database abstraction
├── secret_store.rb         # Secrets management
├── boot.rb                 # Bootstrap
└── sdk/
    └── ruby_client.rb      # Ruby SDK
```

**Responsibilities**:
- MCP protocol implementation (JSON-RPC, tools spec)
- Tool registration and dispatch via Registrar
- Middleware chain execution
- Transport layer (HTTP, stdio, WebSocket)
- Engine base class and lifecycle hooks
- Configuration and secrets management
- Database connection pooling
- SDK for client applications

**Key APIs**:
- `Savant::Framework::MCP::Core::DSL.build { ... }` - Define tools
- `Registrar.add_tool(tool)` - Register tool
- `Registrar.call(name, args, ctx:)` - Invoke tool
- `Engine#before_call`, `Engine#after_call` - Lifecycle hooks
- `Config.load(path)` - Load configuration
- `SecretStore.get(key)` - Retrieve secret

**Dependencies**:
- Logging (Logger, Metrics)

---

#### MODULE 4: Engines (`lib/savant/engines/`)

**Purpose**: All MCP engine implementations

**Components**:
```
lib/savant/engines/
├── context/
│   ├── engine.rb
│   ├── tools.rb
│   ├── ops.rb
│   ├── fts.rb
│   ├── memory_bank/
│   │   ├── markdown.rb
│   │   ├── search.rb
│   │   └── snippets.rb
│   └── fs/
│       └── repo_indexer.rb
├── think/
│   ├── engine.rb
│   ├── tools.rb
│   ├── ops.rb
│   ├── prompts.yml
│   ├── prompts/
│   └── workflows/
├── rules/
│   ├── engine.rb
│   ├── tools.rb
│   ├── ops.rb
│   └── rules.yml
├── personas/
│   ├── engine.rb
│   ├── tools.rb
│   ├── ops.rb
│   └── personas.yml
├── jira/
│   ├── engine.rb
│   ├── tools.rb
│   ├── client.rb
│   └── ops.rb
├── indexer/
│   ├── engine.rb
│   ├── tools.rb
│   ├── runner.rb
│   ├── repository_scanner.rb
│   ├── blob_store.rb
│   ├── cache.rb
│   ├── chunker/
│   │   ├── code_chunker.rb
│   │   ├── markdown_chunker.rb
│   │   └── plaintext_chunker.rb
│   ├── language.rb
│   ├── config.rb
│   └── admin.rb
├── ai/
│   ├── engine.rb
│   ├── tools.rb
│   └── agent_runner.rb
└── amr/
    ├── engine.rb
    └── tools.rb
```

**Responsibilities**:
- Implement domain-specific MCP tools
- Business logic for each engine
- Integration with external services (Jira, etc.)
- Data persistence and retrieval
- Resource management

**Engine Pattern**:
Each engine follows a consistent structure:
- `engine.rb` - Extends `Framework::Engine::Base`, defines lifecycle hooks
- `tools.rb` - Uses `Framework::MCP::Core::DSL` to register tools
- `ops.rb` - Business logic operations
- Additional modules as needed (client, config, etc.)

**Dependencies**:
- Framework (Engine::Base, MCP::Core::DSL, Config, DB)
- Logging (Logger, Metrics)

---

#### MODULE 5: Frontend (`frontend/`)

**Purpose**: Completely separate frontend application

**Proposed Structure**:
```
frontend/
├── package.json
├── vite.config.js
├── index.html
├── src/
│   ├── main.js
│   ├── App.vue
│   ├── components/
│   ├── views/
│   ├── router/
│   └── api/
├── public/
└── dist/              # Build output
```

**Responsibilities**:
- Dashboard UI
- Engine management interface
- Log viewer and streaming
- Diagnostics display
- Tool invocation interface

**Build Process**:
- Standalone build process (npm/yarn)
- Outputs static assets to `frontend/dist/`
- Backend serves from `frontend/dist/` (or separate static server)

**Dependencies**:
- None from backend Ruby code
- Communicates via HTTP API only

---

## 4. Module Dependencies

```
┌─────────────────────────────────────────────┐
│                  Hub API                    │
│  (Router, SSE, ServiceManager, Connections) │
└────────────┬───────────────────┬────────────┘
             │                   │
             ▼                   ▼
┌────────────────────┐  ┌────────────────────┐
│   Framework        │  │   Logging          │
│  (MCP, Engine,     │  │  (Logger, Metrics, │
│   Middleware)      │  │   EventRecorder)   │
└─────────┬──────────┘  └────────────────────┘
          │
          ▼
┌────────────────────┐
│   Engines          │
│  (Context, Think,  │
│   Rules, etc.)     │
└────────────────────┘

┌────────────────────┐
│   Frontend         │
│  (Vue/React app)   │
│  [HTTP calls only] │
└────────────────────┘
```

**Dependency Rules**:
1. **Hub API** depends on: Framework, Logging, Engines
2. **Framework** depends on: Logging
3. **Logging** depends on: Nothing (standalone)
4. **Engines** depend on: Framework, Logging
5. **Frontend** depends on: Nothing (HTTP API only)

**No circular dependencies allowed**

---

## 5. Migration Strategy

### 5.1 Phase 1: Preparation (Risk: Low)

**Objective**: Set up new directory structure without moving files

**Tasks**:
1. Create new directories: `lib/savant/hub/`, `logging/`, `framework/`, `engines/`
2. Create `frontend/` at project root
3. Update `.gitignore` if needed
4. Document module boundaries in README

**Success Criteria**:
- New directories exist
- No code changes yet

---

### 5.2 Phase 2: Logging Module Migration (Risk: Low)

**Objective**: Move all logging-related code to `lib/savant/logging/`

**Tasks**:
1. Move `logger.rb` → `logging/logger.rb`
2. Move `logging/event_recorder.rb` → `logging/event_recorder.rb`
3. Move `telemetry/*` → `logging/` (metrics, replay_buffer, exporter)
4. Move `audit/*` → `logging/audit/`
5. Update all `require` statements
6. Update namespace from `Savant::Logger` to `Savant::Logging::Logger`
7. Run tests to verify

**Success Criteria**:
- All logging code in `lib/savant/logging/`
- All tests pass
- No references to old paths

---

### 5.3 Phase 3: Framework Module Migration (Risk: Medium)

**Objective**: Move framework components to `lib/savant/framework/`

**Tasks**:
1. Move `mcp/` → `framework/mcp/`
2. Move `core/` → `framework/engine/` (rename for clarity)
3. Move `middleware/` → `framework/middleware/`
4. Move `transports/` → `framework/transports/`
5. Move `config.rb`, `db.rb`, `secret_store.rb`, `boot.rb` → `framework/`
6. Move `sdk/` → `framework/sdk/`
7. Move `mcp_server.rb`, `mcp_dispatcher.rb` → `framework/mcp/`
8. Move `runtime_context.rb` → `framework/engine/runtime_context.rb`
9. Update all `require` statements
10. Update namespaces:
    - `Savant::MCP::Core` → `Savant::Framework::MCP::Core`
    - `Savant::Core::Engine` → `Savant::Framework::Engine::Base`
    - `Savant::Core::Context` → `Savant::Framework::Engine::Context`
11. Run tests to verify

**Success Criteria**:
- All framework code in `lib/savant/framework/`
- All tests pass
- Engines still load correctly

---

### 5.4 Phase 4: Engines Module Migration (Risk: Medium)

**Objective**: Move all engines to `lib/savant/engines/`

**Tasks**:
1. Move `context/` → `engines/context/`
2. Move `think/` → `engines/think/`
3. Move `rules/` → `engines/rules/`
4. Move `personas/` → `engines/personas/`
5. Move `jira/` → `engines/jira/`
6. Move `indexer/` → `engines/indexer/`
7. Move `ai/` → `engines/ai/`
8. Move `amr/` → `engines/amr/`
9. Update all `require` statements in engines
10. Update ServiceManager to load from `engines/` directory
11. Update `config/mounts.yml` if paths are hardcoded
12. Update all engine base class references:
    - `Savant::Core::Engine` → `Savant::Framework::Engine::Base`
13. Run tests to verify all engines load

**Success Criteria**:
- All engines in `lib/savant/engines/`
- All tests pass
- Hub can discover and load all engines

---

### 5.5 Phase 5: Hub API Module Migration (Risk: Medium)

**Objective**: Move Hub API components to `lib/savant/hub/`

**Tasks**:
1. Move `hub.rb` → `hub/builder.rb`
2. Move `http/router.rb` → `hub/router.rb`
3. Move `http/sse.rb` → `hub/sse.rb`
4. Move `http/static_ui.rb` → `hub/static_ui.rb`
5. Move `service_manager.rb` → `hub/service_manager.rb`
6. Move `connections.rb` → `hub/connections.rb`
7. Update all `require` statements
8. Update namespaces:
    - `Savant::Hub.build_from_config` → `Savant::Hub::Builder.build_from_config`
    - `Savant::HTTP::Router` → `Savant::Hub::Router`
    - `Savant::ServiceManager` → `Savant::Hub::ServiceManager`
9. Update `bin/savant` to use new Hub::Builder
10. Run tests to verify

**Success Criteria**:
- All Hub API code in `lib/savant/hub/`
- All tests pass
- `bin/savant run` works correctly

---

### 5.6 Phase 6: Frontend Extraction (Risk: Low)

**Objective**: Move frontend to `frontend/` directory

**Tasks**:
1. Create `frontend/` directory structure
2. Move any existing static UI files from `lib/` or `public/`
3. Set up frontend build process (package.json, vite/webpack config)
4. Configure build output to `frontend/dist/`
5. Update `Hub::StaticUI` to serve from `frontend/dist/`
6. Update documentation for frontend development

**Success Criteria**:
- Frontend code in `frontend/`
- Independent build process
- Hub serves frontend from `frontend/dist/`
- Frontend communicates via HTTP API only

---

### 5.7 Phase 7: Cleanup and Documentation (Risk: Low)

**Objective**: Remove old files and update documentation

**Tasks**:
1. Verify `lib/savant/` only contains:
   - `hub/`
   - `logging/`
   - `framework/`
   - `engines/`
   - `version.rb`
2. Remove any old empty directories
3. Update README.md with new structure
4. Update ARCHITECTURE.md (if exists)
5. Update developer documentation
6. Update CONTRIBUTING.md with module guidelines
7. Create module-level README files:
   - `lib/savant/hub/README.md`
   - `lib/savant/logging/README.md`
   - `lib/savant/framework/README.md`
   - `lib/savant/engines/README.md`
   - `frontend/README.md`

**Success Criteria**:
- All old files removed
- Documentation updated
- Clear module guidelines

---

## 6. Technical Considerations

### 6.1 Namespace Migration

**Current**:
```ruby
require 'savant/mcp/core/dsl'
Savant::MCP::Core::DSL.build do ... end
```

**Proposed**:
```ruby
require 'savant/framework/mcp/core/dsl'
Savant::Framework::MCP::Core::DSL.build do ... end
```

**Strategy**:
- Use `git mv` to preserve history
- Update all `require` statements in one commit per module
- Update all namespace references in one commit per module
- Consider creating aliases for backward compatibility during transition

### 6.2 Service Discovery

**Current**: ServiceManager uses `require "savant/#{service}/engine"`

**Proposed**: ServiceManager uses `require "savant/engines/#{service}/engine"`

**Update**: Change ServiceManager#load_service path resolution

### 6.3 Configuration Updates

**Current**: `config/mounts.yml` may reference old paths

**Proposed**: Update any hardcoded paths to use new structure

### 6.4 Testing Strategy

**Per Phase**:
1. Run full test suite before changes
2. Make file moves with `git mv`
3. Update requires and namespaces
4. Run full test suite after changes
5. Fix any broken tests
6. Verify integration tests pass
7. Manual smoke test of `bin/savant run`

### 6.5 Backward Compatibility

**Option 1: Hard Cut** (Recommended)
- No backward compatibility
- Update all references in one release
- Clear, clean break

**Option 2: Transitional Aliases**
```ruby
# lib/savant.rb
module Savant
  MCP = Framework::MCP  # Alias for transition period
  Core = Framework::Engine  # Alias
end
```
- Provides temporary backward compatibility
- Remove in next major version
- More complex migration

**Recommendation**: Hard cut with clear migration guide

---

## 7. Success Metrics

### 7.1 Code Organization Metrics

- [ ] 100% of files in correct module directory
- [ ] 0 files in old locations
- [ ] 0 circular dependencies between modules
- [ ] Clear module boundaries documented

### 7.2 Quality Metrics

- [ ] All existing tests pass
- [ ] No functional regressions
- [ ] Code coverage maintained or improved
- [ ] No new linting violations

### 7.3 Developer Experience Metrics

- [ ] Reduced time to locate code (measured subjectively)
- [ ] Easier to add new engines (documented process)
- [ ] Clear contribution guidelines per module
- [ ] Positive team feedback

---

## 8. Risks and Mitigations

### 8.1 Risk: Breaking Changes

**Likelihood**: Medium
**Impact**: High

**Mitigation**:
- Comprehensive test coverage before starting
- Phase-by-phase migration with tests after each phase
- Manual smoke testing at each phase
- Rollback plan (git revert)

### 8.2 Risk: Merge Conflicts

**Likelihood**: High (if active development continues)
**Impact**: Medium

**Mitigation**:
- Communicate refactoring timeline to team
- Coordinate with ongoing feature work
- Use feature branch for refactoring
- Frequent rebases on main
- Short migration timeline (1-2 weeks)

### 8.3 Risk: Overlooked Dependencies

**Likelihood**: Medium
**Impact**: Medium

**Mitigation**:
- Thorough code search for require statements
- Grep for old namespaces
- Integration tests for all engines
- Comprehensive test suite execution

### 8.4 Risk: Performance Regression

**Likelihood**: Low
**Impact**: Medium

**Mitigation**:
- Benchmark before and after
- Monitor load times for engines
- Check HTTP response times
- No algorithmic changes, only organization

---

## 9. Timeline Estimate

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1: Preparation | 0.5 days | None |
| Phase 2: Logging | 1 day | Phase 1 |
| Phase 3: Framework | 2 days | Phase 2 |
| Phase 4: Engines | 2 days | Phase 3 |
| Phase 5: Hub API | 1.5 days | Phase 4 |
| Phase 6: Frontend | 1 day | Phase 5 |
| Phase 7: Cleanup | 1 day | Phase 6 |
| **Total** | **9 days** | Sequential |

**Assumptions**:
- Single developer working full-time
- No major blockers or surprises
- Tests already exist and are passing
- No active feature development conflicts

---

## 10. Future Enhancements

### 10.1 Gemification (Post-Refactor)

Consider splitting into separate gems:
- `savant-framework` - Core MCP framework
- `savant-logging` - Logging and observability
- `savant-hub` - Hub API server
- `savant-engines-context` - Context engine
- `savant-engines-think` - Think engine
- etc.

### 10.2 Plugin System

With clear module boundaries, implement a plugin system:
- Third-party engines as gems
- Dynamic engine discovery
- Engine marketplace

### 10.3 Microservices

Post-refactor architecture enables future microservices:
- Each engine as a separate service
- Hub as API gateway
- Logging as centralized service

---

## 11. Open Questions

1. **Frontend Framework**: What framework should frontend use? (Vue, React, Svelte)
2. **Frontend Build Integration**: Should frontend build be part of main build process or separate?
3. **Frontend Deployment**: Same server or separate CDN?
4. **Backward Compatibility**: Hard cut or transitional aliases?
5. **Version Bump**: Major version (2.0.0) or minor (1.x.0)?
6. **Gem Split**: Should we split into multiple gems now or later?
7. **Engine Versioning**: Should engines have independent versions?

---

## 12. Approval and Sign-off

- [ ] Engineering Lead Review
- [ ] Architecture Review
- [ ] Timeline Approval
- [ ] Resource Allocation

---

## Appendix A: File Movement Checklist

### Logging Module
- [ ] `logger.rb` → `logging/logger.rb`
- [ ] `logging/event_recorder.rb` → `logging/event_recorder.rb`
- [ ] `telemetry/metrics.rb` → `logging/metrics.rb`
- [ ] `telemetry/replay_buffer.rb` → `logging/replay_buffer.rb`
- [ ] `telemetry/exporter.rb` → `logging/exporter.rb`
- [ ] `audit/policy.rb` → `logging/audit/policy.rb`
- [ ] `audit/store.rb` → `logging/audit/store.rb`

### Framework Module
- [ ] `mcp/` → `framework/mcp/`
- [ ] `core/engine.rb` → `framework/engine/base.rb`
- [ ] `core/context.rb` → `framework/engine/context.rb`
- [ ] `middleware/` → `framework/middleware/`
- [ ] `transports/` → `framework/transports/`
- [ ] `config.rb` → `framework/config.rb`
- [ ] `db.rb` → `framework/db.rb`
- [ ] `secret_store.rb` → `framework/secret_store.rb`
- [ ] `boot.rb` → `framework/boot.rb`
- [ ] `sdk/` → `framework/sdk/`
- [ ] `mcp_server.rb` → `framework/mcp/server.rb`
- [ ] `mcp_dispatcher.rb` → `framework/mcp/dispatcher.rb`
- [ ] `runtime_context.rb` → `framework/engine/runtime_context.rb`

### Engines Module
- [ ] `context/` → `engines/context/`
- [ ] `think/` → `engines/think/`
- [ ] `rules/` → `engines/rules/`
- [ ] `personas/` → `engines/personas/`
- [ ] `jira/` → `engines/jira/`
- [ ] `indexer/` → `engines/indexer/`
- [ ] `ai/` → `engines/ai/`
- [ ] `amr/` → `engines/amr/`

### Hub API Module
- [ ] `hub.rb` → `hub/builder.rb`
- [ ] `http/router.rb` → `hub/router.rb`
- [ ] `http/sse.rb` → `hub/sse.rb`
- [ ] `http/static_ui.rb` → `hub/static_ui.rb`
- [ ] `service_manager.rb` → `hub/service_manager.rb`
- [ ] `connections.rb` → `hub/connections.rb`

### Frontend Module
- [ ] Create `frontend/` structure
- [ ] Move static UI assets
- [ ] Set up build process

---

## Appendix B: Namespace Migration Map

| Old Namespace | New Namespace |
|--------------|---------------|
| `Savant::Logger` | `Savant::Logging::Logger` |
| `Savant::EventRecorder` | `Savant::Logging::EventRecorder` |
| `Savant::Metrics` | `Savant::Logging::Metrics` |
| `Savant::Audit::Policy` | `Savant::Logging::Audit::Policy` |
| `Savant::MCP::Core` | `Savant::Framework::MCP::Core` |
| `Savant::Core::Engine` | `Savant::Framework::Engine::Base` |
| `Savant::Core::Context` | `Savant::Framework::Engine::Context` |
| `Savant::Middleware` | `Savant::Framework::Middleware` |
| `Savant::Transport` | `Savant::Framework::Transport` |
| `Savant::Config` | `Savant::Framework::Config` |
| `Savant::DB` | `Savant::Framework::DB` |
| `Savant::SecretStore` | `Savant::Framework::SecretStore` |
| `Savant::Hub` | `Savant::Hub::Builder` |
| `Savant::HTTP::Router` | `Savant::Hub::Router` |
| `Savant::ServiceManager` | `Savant::Hub::ServiceManager` |
| `Savant::Connections` | `Savant::Hub::Connections` |

---

## Appendix C: Require Statement Updates

**Example: Engine File**

**Before**:
```ruby
require 'savant/core/engine'
require 'savant/mcp/core/dsl'
require 'savant/logger'

module Savant
  module Context
    class Engine < Core::Engine
      # ...
    end
  end
end
```

**After**:
```ruby
require 'savant/framework/engine/base'
require 'savant/framework/mcp/core/dsl'
require 'savant/logging/logger'

module Savant
  module Engines
    module Context
      class Engine < Framework::Engine::Base
        # ...
      end
    end
  end
end
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-11-28 | System | Initial draft |
