# Savant Rails Product Architecture

**Version:** 1.0
**Date:** 2025-12-06
**Status:** MVP → Full Rails Product Design
**Author:** Engineering Team

---

## 1. Executive Summary

This document outlines the architecture for transforming Savant from a Ruby-based MVP into a full-scale Rails application with multi-tenancy, web UI, APIs, and enterprise capabilities.

**Design Principles:**
- **Rails-native**: Leverage Rails conventions and ecosystem
- **API-first**: All features accessible via REST/GraphQL APIs
- **Modular**: Maintain engine-based architecture
- **Scalable**: Support 10,000+ concurrent users
- **Secure**: Multi-tenancy with data isolation
- **Observable**: Comprehensive logging, metrics, tracing

---

## 2. High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         SAVANT PLATFORM                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐       │
│  │  Web UI      │   │  Mobile App  │   │  CLI         │       │
│  │  (React SPA) │   │  (iOS/And)   │   │  (Ruby)      │       │
│  └──────┬───────┘   └──────┬───────┘   └──────┬───────┘       │
│         │                   │                   │               │
│         └───────────────────┴───────────────────┘               │
│                             │                                   │
│                   ┌─────────▼─────────┐                         │
│                   │   API Gateway     │                         │
│                   │   (Rails Router)  │                         │
│                   └─────────┬─────────┘                         │
│                             │                                   │
│         ┌───────────────────┼───────────────────┐               │
│         │                   │                   │               │
│  ┌──────▼──────┐   ┌────────▼────────┐   ┌─────▼─────┐        │
│  │  REST API   │   │  GraphQL API    │   │  WebSocket│        │
│  │  (v1, v2)   │   │  (Optional)     │   │  (SSE)    │        │
│  └──────┬──────┘   └────────┬────────┘   └─────┬─────┘        │
│         │                   │                   │               │
│         └───────────────────┴───────────────────┘               │
│                             │                                   │
│                   ┌─────────▼─────────┐                         │
│                   │  Business Logic   │                         │
│                   │  (Controllers +   │                         │
│                   │   Services)       │                         │
│                   └─────────┬─────────┘                         │
│                             │                                   │
│         ┌───────────────────┼───────────────────┐               │
│         │                   │                   │               │
│  ┌──────▼──────┐   ┌────────▼────────┐   ┌─────▼─────┐        │
│  │   Agent     │   │   Workflow      │   │   MCP     │        │
│  │   Runtime   │   │   Executor      │   │   Engines │        │
│  └──────┬──────┘   └────────┬────────┘   └─────┬─────┘        │
│         │                   │                   │               │
│         └───────────────────┴───────────────────┘               │
│                             │                                   │
│                   ┌─────────▼─────────┐                         │
│                   │  Data Layer       │                         │
│                   │  (ActiveRecord +  │                         │
│                   │   Postgres)       │                         │
│                   └───────────────────┘                         │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  Background Jobs (Sidekiq)                             │    │
│  │  • Agent execution                                     │    │
│  │  • Workflow execution                                  │    │
│  │  • Repository indexing                                 │    │
│  │  • Scheduled tasks                                     │    │
│  │  • Webhooks delivery                                   │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  External Services                                     │    │
│  │  • Redis (caching, sessions, jobs)                     │    │
│  │  • S3/GCS (file storage)                               │    │
│  │  • Elasticsearch (advanced search, optional)           │    │
│  │  • Prometheus (metrics)                                │    │
│  │  • Sentry (error tracking)                             │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Rails Application Structure

### 3.1 Directory Layout

```
savant/
├── app/
│   ├── controllers/
│   │   ├── api/
│   │   │   ├── v1/
│   │   │   │   ├── agents_controller.rb
│   │   │   │   ├── workflows_controller.rb
│   │   │   │   ├── personas_controller.rb
│   │   │   │   ├── rulesets_controller.rb
│   │   │   │   ├── repositories_controller.rb
│   │   │   │   ├── tools_controller.rb
│   │   │   │   ├── runs_controller.rb
│   │   │   │   └── ...
│   │   │   └── v2/ (future)
│   │   ├── application_controller.rb
│   │   ├── agents_controller.rb
│   │   ├── workflows_controller.rb
│   │   ├── dashboards_controller.rb
│   │   └── ...
│   ├── models/
│   │   ├── user.rb
│   │   ├── team.rb
│   │   ├── workspace.rb
│   │   ├── agent.rb
│   │   ├── workflow.rb
│   │   ├── persona.rb
│   │   ├── ruleset.rb
│   │   ├── repository.rb
│   │   ├── tool.rb
│   │   ├── run.rb (polymorphic: agent_run, workflow_run)
│   │   ├── agent_run.rb
│   │   ├── workflow_run.rb
│   │   ├── step.rb (workflow steps, agent steps)
│   │   ├── trace.rb (execution traces)
│   │   └── ...
│   ├── services/
│   │   ├── agents/
│   │   │   ├── creator.rb
│   │   │   ├── executor.rb
│   │   │   ├── updater.rb
│   │   │   └── destroyer.rb
│   │   ├── workflows/
│   │   │   ├── creator.rb
│   │   │   ├── executor.rb
│   │   │   ├── validator.rb
│   │   │   └── graph_builder.rb
│   │   ├── repositories/
│   │   │   ├── indexer.rb
│   │   │   ├── connector.rb (GitHub/GitLab)
│   │   │   └── scanner.rb
│   │   ├── tools/
│   │   │   ├── builder.rb
│   │   │   ├── installer.rb
│   │   │   └── registry.rb
│   │   └── ...
│   ├── jobs/
│   │   ├── agent_execution_job.rb
│   │   ├── workflow_execution_job.rb
│   │   ├── repository_indexing_job.rb
│   │   ├── webhook_delivery_job.rb
│   │   └── scheduled_run_job.rb
│   ├── serializers/ (or app/views for JSON)
│   │   ├── agent_serializer.rb
│   │   ├── workflow_serializer.rb
│   │   └── ...
│   ├── policies/ (Pundit)
│   │   ├── agent_policy.rb
│   │   ├── workflow_policy.rb
│   │   └── ...
│   └── mailers/
│       ├── user_mailer.rb
│       ├── notification_mailer.rb
│       └── ...
├── lib/
│   └── savant/
│       ├── agent/           # Keep existing agent runtime
│       ├── engines/         # Keep existing MCP engines
│       ├── framework/       # Keep existing MCP framework
│       ├── hub/             # Keep existing hub logic
│       ├── llm/             # Keep existing LLM adapters
│       ├── logging/         # Keep existing logging
│       └── multiplexer/     # Keep existing multiplexer
├── db/
│   ├── migrate/
│   │   ├── 001_create_users.rb
│   │   ├── 002_create_teams.rb
│   │   ├── 003_create_workspaces.rb
│   │   ├── 004_create_agents.rb
│   │   ├── 005_create_workflows.rb
│   │   ├── 006_create_personas.rb
│   │   ├── 007_create_rulesets.rb
│   │   ├── 008_create_repositories.rb
│   │   ├── 009_create_tools.rb
│   │   ├── 010_create_runs.rb
│   │   ├── 011_create_steps.rb
│   │   ├── 012_create_traces.rb
│   │   └── ...
│   └── schema.rb
├── config/
│   ├── routes.rb
│   ├── database.yml
│   ├── application.rb
│   ├── environments/
│   │   ├── development.rb
│   │   ├── test.rb
│   │   └── production.rb
│   └── initializers/
│       ├── sidekiq.rb
│       ├── cors.rb
│       ├── inflections.rb
│       └── ...
├── spec/ (or test/)
│   ├── models/
│   ├── controllers/
│   ├── services/
│   ├── jobs/
│   ├── requests/
│   └── ...
├── frontend/ (separate React app)
│   ├── src/
│   │   ├── components/
│   │   ├── pages/
│   │   ├── api/
│   │   └── ...
│   └── package.json
└── ...
```

---

## 4. Database Schema

### 4.1 Core Tables

#### users
```sql
CREATE TABLE users (
  id BIGSERIAL PRIMARY KEY,
  email VARCHAR(255) UNIQUE NOT NULL,
  encrypted_password VARCHAR(255) NOT NULL,
  name VARCHAR(255),
  avatar_url VARCHAR(500),
  role VARCHAR(50) DEFAULT 'user', -- user, admin, superadmin
  confirmed_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);
CREATE INDEX idx_users_email ON users(email);
```

#### teams
```sql
CREATE TABLE teams (
  id BIGSERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  slug VARCHAR(255) UNIQUE NOT NULL,
  description TEXT,
  created_by_id BIGINT REFERENCES users(id),
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);
CREATE INDEX idx_teams_slug ON teams(slug);
```

#### team_members
```sql
CREATE TABLE team_members (
  id BIGSERIAL PRIMARY KEY,
  team_id BIGINT REFERENCES teams(id) ON DELETE CASCADE,
  user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
  role VARCHAR(50) DEFAULT 'member', -- owner, admin, member, viewer
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  UNIQUE(team_id, user_id)
);
CREATE INDEX idx_team_members_team_id ON team_members(team_id);
CREATE INDEX idx_team_members_user_id ON team_members(user_id);
```

#### workspaces
```sql
CREATE TABLE workspaces (
  id BIGSERIAL PRIMARY KEY,
  team_id BIGINT REFERENCES teams(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  slug VARCHAR(255) NOT NULL,
  description TEXT,
  settings JSONB DEFAULT '{}',
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  UNIQUE(team_id, slug)
);
CREATE INDEX idx_workspaces_team_id ON workspaces(team_id);
CREATE INDEX idx_workspaces_slug ON workspaces(slug);
```

#### agents
```sql
CREATE TABLE agents (
  id BIGSERIAL PRIMARY KEY,
  workspace_id BIGINT REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id BIGINT REFERENCES users(id),
  name VARCHAR(255) NOT NULL,
  slug VARCHAR(255) NOT NULL,
  description TEXT,
  persona_id BIGINT REFERENCES personas(id),
  driver_prompt TEXT,
  config JSONB DEFAULT '{}', -- { slm_model, llm_model, max_steps, token_budget }
  status VARCHAR(50) DEFAULT 'active', -- active, paused, archived
  visibility VARCHAR(50) DEFAULT 'private', -- private, team, public
  tags VARCHAR(255)[] DEFAULT '{}',
  created_by_id BIGINT REFERENCES users(id),
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  UNIQUE(workspace_id, slug)
);
CREATE INDEX idx_agents_workspace_id ON agents(workspace_id);
CREATE INDEX idx_agents_persona_id ON agents(persona_id);
CREATE INDEX idx_agents_status ON agents(status);
CREATE INDEX idx_agents_tags ON agents USING GIN(tags);
```

#### agent_rulesets
```sql
CREATE TABLE agent_rulesets (
  id BIGSERIAL PRIMARY KEY,
  agent_id BIGINT REFERENCES agents(id) ON DELETE CASCADE,
  ruleset_id BIGINT REFERENCES rulesets(id) ON DELETE CASCADE,
  priority INTEGER DEFAULT 0,
  created_at TIMESTAMP NOT NULL,
  UNIQUE(agent_id, ruleset_id)
);
CREATE INDEX idx_agent_rulesets_agent_id ON agent_rulesets(agent_id);
CREATE INDEX idx_agent_rulesets_ruleset_id ON agent_rulesets(ruleset_id);
```

#### agent_tools
```sql
CREATE TABLE agent_tools (
  id BIGSERIAL PRIMARY KEY,
  agent_id BIGINT REFERENCES agents(id) ON DELETE CASCADE,
  tool_id BIGINT REFERENCES tools(id) ON DELETE CASCADE,
  allowed BOOLEAN DEFAULT true, -- true = whitelist, false = blacklist
  created_at TIMESTAMP NOT NULL,
  UNIQUE(agent_id, tool_id)
);
CREATE INDEX idx_agent_tools_agent_id ON agent_tools(agent_id);
CREATE INDEX idx_agent_tools_tool_id ON agent_tools(tool_id);
```

#### workflows
```sql
CREATE TABLE workflows (
  id BIGSERIAL PRIMARY KEY,
  workspace_id BIGINT REFERENCES workspaces(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  slug VARCHAR(255) NOT NULL,
  description TEXT,
  definition JSONB NOT NULL, -- YAML parsed to JSON
  graph JSONB, -- visual graph representation
  version INTEGER DEFAULT 1,
  status VARCHAR(50) DEFAULT 'active',
  visibility VARCHAR(50) DEFAULT 'private',
  tags VARCHAR(255)[] DEFAULT '{}',
  created_by_id BIGINT REFERENCES users(id),
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  UNIQUE(workspace_id, slug, version)
);
CREATE INDEX idx_workflows_workspace_id ON workflows(workspace_id);
CREATE INDEX idx_workflows_status ON workflows(status);
CREATE INDEX idx_workflows_tags ON workflows USING GIN(tags);
```

#### personas
```sql
CREATE TABLE personas (
  id BIGSERIAL PRIMARY KEY,
  workspace_id BIGINT REFERENCES workspaces(id) ON DELETE CASCADE, -- NULL for system personas
  name VARCHAR(255) NOT NULL,
  slug VARCHAR(255) NOT NULL,
  description TEXT,
  instructions TEXT NOT NULL,
  visibility VARCHAR(50) DEFAULT 'private',
  created_by_id BIGINT REFERENCES users(id),
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);
CREATE INDEX idx_personas_workspace_id ON personas(workspace_id);
CREATE INDEX idx_personas_slug ON personas(slug);
```

#### rulesets
```sql
CREATE TABLE rulesets (
  id BIGSERIAL PRIMARY KEY,
  workspace_id BIGINT REFERENCES workspaces(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  slug VARCHAR(255) NOT NULL,
  description TEXT,
  rules JSONB NOT NULL, -- Array of rule objects
  visibility VARCHAR(50) DEFAULT 'private',
  created_by_id BIGINT REFERENCES users(id),
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);
CREATE INDEX idx_rulesets_workspace_id ON rulesets(workspace_id);
CREATE INDEX idx_rulesets_slug ON rulesets(slug);
```

#### repositories
```sql
CREATE TABLE repositories (
  id BIGSERIAL PRIMARY KEY,
  workspace_id BIGINT REFERENCES workspaces(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  slug VARCHAR(255) NOT NULL,
  source VARCHAR(50), -- local, github, gitlab
  remote_url VARCHAR(500),
  local_path VARCHAR(500),
  branch VARCHAR(255) DEFAULT 'main',
  indexed_at TIMESTAMP,
  index_status VARCHAR(50), -- pending, indexing, completed, failed
  index_config JSONB DEFAULT '{}',
  created_by_id BIGINT REFERENCES users(id),
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  UNIQUE(workspace_id, slug)
);
CREATE INDEX idx_repositories_workspace_id ON repositories(workspace_id);
CREATE INDEX idx_repositories_index_status ON repositories(index_status);
```

#### tools
```sql
CREATE TABLE tools (
  id BIGSERIAL PRIMARY KEY,
  workspace_id BIGINT REFERENCES workspaces(id) ON DELETE CASCADE, -- NULL for built-in tools
  name VARCHAR(255) NOT NULL,
  slug VARCHAR(255) NOT NULL,
  description TEXT,
  engine VARCHAR(100), -- context, git, jira, custom
  schema JSONB NOT NULL, -- input/output schema
  implementation TEXT, -- Ruby or JS code
  version VARCHAR(50) DEFAULT '1.0.0',
  visibility VARCHAR(50) DEFAULT 'private',
  published BOOLEAN DEFAULT false,
  created_by_id BIGINT REFERENCES users(id),
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);
CREATE INDEX idx_tools_workspace_id ON tools(workspace_id);
CREATE INDEX idx_tools_engine ON tools(engine);
CREATE INDEX idx_tools_published ON tools(published);
```

#### runs (polymorphic for agent_runs and workflow_runs)
```sql
CREATE TABLE runs (
  id BIGSERIAL PRIMARY KEY,
  runnable_type VARCHAR(50) NOT NULL, -- Agent, Workflow
  runnable_id BIGINT NOT NULL,
  workspace_id BIGINT REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id BIGINT REFERENCES users(id),
  status VARCHAR(50) DEFAULT 'pending', -- pending, running, completed, failed, stopped
  goal TEXT,
  config JSONB DEFAULT '{}',
  result JSONB,
  error_message TEXT,
  started_at TIMESTAMP,
  completed_at TIMESTAMP,
  duration_ms INTEGER,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);
CREATE INDEX idx_runs_runnable ON runs(runnable_type, runnable_id);
CREATE INDEX idx_runs_workspace_id ON runs(workspace_id);
CREATE INDEX idx_runs_user_id ON runs(user_id);
CREATE INDEX idx_runs_status ON runs(status);
CREATE INDEX idx_runs_created_at ON runs(created_at DESC);
```

#### steps (execution steps for runs)
```sql
CREATE TABLE steps (
  id BIGSERIAL PRIMARY KEY,
  run_id BIGINT REFERENCES runs(id) ON DELETE CASCADE,
  step_number INTEGER NOT NULL,
  step_type VARCHAR(50), -- tool, agent, condition, parallel
  tool_name VARCHAR(255),
  agent_id BIGINT REFERENCES agents(id),
  status VARCHAR(50) DEFAULT 'pending',
  input JSONB,
  output JSONB,
  error_message TEXT,
  started_at TIMESTAMP,
  completed_at TIMESTAMP,
  duration_ms INTEGER,
  created_at TIMESTAMP NOT NULL,
  UNIQUE(run_id, step_number)
);
CREATE INDEX idx_steps_run_id ON steps(run_id);
CREATE INDEX idx_steps_status ON steps(status);
```

#### traces (detailed telemetry for debugging)
```sql
CREATE TABLE traces (
  id BIGSERIAL PRIMARY KEY,
  run_id BIGINT REFERENCES runs(id) ON DELETE CASCADE,
  step_id BIGINT REFERENCES steps(id) ON DELETE CASCADE,
  event_type VARCHAR(100), -- tool_call_started, tool_call_completed, reasoning_step, etc.
  payload JSONB NOT NULL,
  timestamp TIMESTAMP NOT NULL,
  created_at TIMESTAMP NOT NULL
);
CREATE INDEX idx_traces_run_id ON traces(run_id);
CREATE INDEX idx_traces_step_id ON traces(step_id);
CREATE INDEX idx_traces_event_type ON traces(event_type);
CREATE INDEX idx_traces_timestamp ON traces(timestamp DESC);
```

### 4.2 Sharing & Permissions

#### shares (polymorphic for agents, workflows, etc.)
```sql
CREATE TABLE shares (
  id BIGSERIAL PRIMARY KEY,
  shareable_type VARCHAR(50) NOT NULL,
  shareable_id BIGINT NOT NULL,
  shared_with_type VARCHAR(50), -- User, Team, Public
  shared_with_id BIGINT,
  permission VARCHAR(50) DEFAULT 'view', -- view, edit, execute, admin
  token VARCHAR(255) UNIQUE, -- for link-based sharing
  expires_at TIMESTAMP,
  created_by_id BIGINT REFERENCES users(id),
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);
CREATE INDEX idx_shares_shareable ON shares(shareable_type, shareable_id);
CREATE INDEX idx_shares_shared_with ON shares(shared_with_type, shared_with_id);
CREATE INDEX idx_shares_token ON shares(token);
```

### 4.3 Audit & Compliance

#### audit_logs
```sql
CREATE TABLE audit_logs (
  id BIGSERIAL PRIMARY KEY,
  workspace_id BIGINT REFERENCES workspaces(id),
  user_id BIGINT REFERENCES users(id),
  action VARCHAR(100) NOT NULL, -- create, update, delete, execute, etc.
  resource_type VARCHAR(50),
  resource_id BIGINT,
  metadata JSONB DEFAULT '{}',
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMP NOT NULL
);
CREATE INDEX idx_audit_logs_workspace_id ON audit_logs(workspace_id);
CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);
CREATE INDEX idx_audit_logs_resource ON audit_logs(resource_type, resource_id);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at DESC);
```

### 4.4 Webhooks

#### webhooks
```sql
CREATE TABLE webhooks (
  id BIGSERIAL PRIMARY KEY,
  workspace_id BIGINT REFERENCES workspaces(id) ON DELETE CASCADE,
  url VARCHAR(500) NOT NULL,
  events VARCHAR(100)[] NOT NULL, -- ['agent.started', 'workflow.completed']
  secret VARCHAR(255),
  active BOOLEAN DEFAULT true,
  created_by_id BIGINT REFERENCES users(id),
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);
CREATE INDEX idx_webhooks_workspace_id ON webhooks(workspace_id);
CREATE INDEX idx_webhooks_active ON webhooks(active);
```

#### webhook_deliveries
```sql
CREATE TABLE webhook_deliveries (
  id BIGSERIAL PRIMARY KEY,
  webhook_id BIGINT REFERENCES webhooks(id) ON DELETE CASCADE,
  event VARCHAR(100) NOT NULL,
  payload JSONB NOT NULL,
  status VARCHAR(50), -- pending, delivered, failed
  response_code INTEGER,
  response_body TEXT,
  attempts INTEGER DEFAULT 0,
  delivered_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL
);
CREATE INDEX idx_webhook_deliveries_webhook_id ON webhook_deliveries(webhook_id);
CREATE INDEX idx_webhook_deliveries_status ON webhook_deliveries(status);
CREATE INDEX idx_webhook_deliveries_created_at ON webhook_deliveries(created_at DESC);
```

---

## 5. API Design

### 5.1 REST API (v1)

#### Authentication
All API requests require authentication via:
- **Session cookies** (for web UI)
- **API keys** (for CLI/SDKs)
- **OAuth tokens** (for third-party integrations)

#### Base URL
```
https://api.savant.dev/v1
```

#### Endpoints

**Agents**
```
GET    /agents                  # List agents
POST   /agents                  # Create agent
GET    /agents/:id              # Get agent details
PATCH  /agents/:id              # Update agent
DELETE /agents/:id              # Delete agent
POST   /agents/:id/execute      # Execute agent
GET    /agents/:id/runs         # List agent runs
```

**Workflows**
```
GET    /workflows               # List workflows
POST   /workflows               # Create workflow
GET    /workflows/:id           # Get workflow details
PATCH  /workflows/:id           # Update workflow
DELETE /workflows/:id           # Delete workflow
POST   /workflows/:id/execute   # Execute workflow
GET    /workflows/:id/runs      # List workflow runs
```

**Runs**
```
GET    /runs                    # List all runs
GET    /runs/:id                # Get run details
POST   /runs/:id/stop           # Stop a run
POST   /runs/:id/retry          # Retry a run
GET    /runs/:id/steps          # Get run steps
GET    /runs/:id/traces         # Get run traces
```

**Personas**
```
GET    /personas                # List personas
POST   /personas                # Create persona
GET    /personas/:id            # Get persona details
PATCH  /personas/:id            # Update persona
DELETE /personas/:id            # Delete persona
```

**Rulesets**
```
GET    /rulesets                # List rulesets
POST   /rulesets                # Create ruleset
GET    /rulesets/:id            # Get ruleset details
PATCH  /rulesets/:id            # Update ruleset
DELETE /rulesets/:id            # Delete ruleset
```

**Repositories**
```
GET    /repositories            # List repositories
POST   /repositories            # Register repository
GET    /repositories/:id        # Get repository details
PATCH  /repositories/:id        # Update repository
DELETE /repositories/:id        # Delete repository
POST   /repositories/:id/index  # Trigger indexing
```

**Tools**
```
GET    /tools                   # List tools
POST   /tools                   # Create tool
GET    /tools/:id               # Get tool details
PATCH  /tools/:id               # Update tool
DELETE /tools/:id               # Delete tool
POST   /tools/:id/install       # Install tool to workspace
```

**Teams**
```
GET    /teams                   # List teams
POST   /teams                   # Create team
GET    /teams/:id               # Get team details
PATCH  /teams/:id               # Update team
DELETE /teams/:id               # Delete team
POST   /teams/:id/members       # Add member
DELETE /teams/:id/members/:user_id # Remove member
```

**Workspaces**
```
GET    /workspaces              # List workspaces
POST   /workspaces              # Create workspace
GET    /workspaces/:id          # Get workspace details
PATCH  /workspaces/:id          # Update workspace
DELETE /workspaces/:id          # Delete workspace
```

#### Response Format
```json
{
  "data": { /* resource object */ },
  "meta": {
    "request_id": "uuid",
    "timestamp": "2025-12-06T12:00:00Z"
  }
}
```

#### Error Format
```json
{
  "error": {
    "code": "validation_error",
    "message": "Name can't be blank",
    "details": {
      "name": ["can't be blank"]
    }
  },
  "meta": {
    "request_id": "uuid",
    "timestamp": "2025-12-06T12:00:00Z"
  }
}
```

### 5.2 GraphQL API (Optional)

#### Schema (excerpt)
```graphql
type User {
  id: ID!
  email: String!
  name: String
  teams: [Team!]!
  agents: [Agent!]!
}

type Agent {
  id: ID!
  name: String!
  slug: String!
  description: String
  persona: Persona
  config: JSON
  runs: [Run!]!
  createdAt: DateTime!
  updatedAt: DateTime!
}

type Workflow {
  id: ID!
  name: String!
  slug: String!
  definition: JSON!
  runs: [Run!]!
}

type Run {
  id: ID!
  status: RunStatus!
  goal: String
  steps: [Step!]!
  createdAt: DateTime!
  completedAt: DateTime
}

type Query {
  me: User
  agents(filter: AgentFilter, page: Int, perPage: Int): AgentConnection!
  agent(id: ID!): Agent
  workflows(filter: WorkflowFilter): [Workflow!]!
  workflow(id: ID!): Workflow
  runs(filter: RunFilter): [Run!]!
}

type Mutation {
  createAgent(input: CreateAgentInput!): AgentPayload!
  updateAgent(id: ID!, input: UpdateAgentInput!): AgentPayload!
  deleteAgent(id: ID!): DeletePayload!
  executeAgent(id: ID!, goal: String!): RunPayload!
}

type Subscription {
  runUpdated(runId: ID!): Run!
  agentExecutionStream(runId: ID!): Step!
}
```

---

## 6. Service Layer Architecture

### 6.1 Service Objects Pattern

**Purpose:** Encapsulate complex business logic outside of models and controllers.

**Example: Agent Creator Service**

```ruby
# app/services/agents/creator.rb
module Agents
  class Creator
    def initialize(user:, workspace:, params:)
      @user = user
      @workspace = workspace
      @params = params
    end

    def call
      validate!
      agent = build_agent
      assign_persona
      assign_rulesets
      assign_tools
      agent.save!
      audit_log_creation(agent)
      agent
    rescue ActiveRecord::RecordInvalid => e
      handle_error(e)
    end

    private

    def validate!
      raise ArgumentError, "User must belong to workspace" unless user_authorized?
      raise ArgumentError, "Invalid persona" unless persona_valid?
    end

    def build_agent
      @workspace.agents.build(
        name: @params[:name],
        slug: @params[:slug] || @params[:name].parameterize,
        description: @params[:description],
        driver_prompt: @params[:driver_prompt],
        config: @params[:config] || {},
        created_by: @user
      )
    end

    def assign_persona
      # ...
    end

    def assign_rulesets
      # ...
    end

    def assign_tools
      # ...
    end

    def audit_log_creation(agent)
      AuditLog.create!(
        workspace: @workspace,
        user: @user,
        action: 'create',
        resource_type: 'Agent',
        resource_id: agent.id,
        metadata: { name: agent.name }
      )
    end
  end
end
```

**Usage in Controller:**
```ruby
class Api::V1::AgentsController < Api::V1::BaseController
  def create
    agent = Agents::Creator.new(
      user: current_user,
      workspace: current_workspace,
      params: agent_params
    ).call

    render json: AgentSerializer.new(agent), status: :created
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
```

### 6.2 Job Architecture

**Background Jobs (Sidekiq):**

```ruby
# app/jobs/agent_execution_job.rb
class AgentExecutionJob < ApplicationJob
  queue_as :agents

  def perform(run_id)
    run = Run.find(run_id)
    run.update!(status: 'running', started_at: Time.current)

    executor = Agents::Executor.new(run)
    executor.call

    run.update!(
      status: 'completed',
      completed_at: Time.current,
      duration_ms: (Time.current - run.started_at) * 1000
    )
  rescue StandardError => e
    run.update!(
      status: 'failed',
      error_message: e.message,
      completed_at: Time.current
    )
    raise
  end
end
```

**Job Priorities:**
- Critical: User-triggered executions
- High: Scheduled workflows
- Normal: Repository indexing
- Low: Analytics, cleanup

---

## 7. Multi-Tenancy Strategy

### 7.1 Scoping Pattern

**All queries scoped by workspace:**

```ruby
class Agent < ApplicationRecord
  belongs_to :workspace

  scope :for_workspace, ->(workspace) { where(workspace: workspace) }

  def self.accessible_by(user)
    joins(workspace: :team)
      .joins("INNER JOIN team_members ON team_members.team_id = teams.id")
      .where(team_members: { user_id: user.id })
  end
end
```

**Controller-level enforcement:**
```ruby
class ApplicationController < ActionController::API
  before_action :set_current_workspace

  private

  def set_current_workspace
    @current_workspace = current_user.workspaces.find(params[:workspace_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Workspace not found' }, status: :not_found
  end
end
```

### 7.2 Row-Level Security (Optional)

Use Postgres RLS for additional security:

```sql
ALTER TABLE agents ENABLE ROW LEVEL SECURITY;

CREATE POLICY workspace_isolation ON agents
  USING (workspace_id IN (
    SELECT workspace_id FROM workspaces
    WHERE team_id IN (
      SELECT team_id FROM team_members
      WHERE user_id = current_setting('app.current_user_id')::BIGINT
    )
  ));
```

---

## 8. Authentication & Authorization

### 8.1 Authentication (Devise)

```ruby
# app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable, :trackable, :omniauthable

  has_many :team_members
  has_many :teams, through: :team_members
  has_many :workspaces, through: :teams
end
```

### 8.2 Authorization (Pundit)

```ruby
# app/policies/agent_policy.rb
class AgentPolicy < ApplicationPolicy
  def index?
    user_in_workspace?
  end

  def show?
    user_in_workspace? && (record.visibility == 'public' || can_view?)
  end

  def create?
    user_in_workspace? && (user_role_in_team?('admin') || user_role_in_team?('owner'))
  end

  def update?
    user_in_workspace? && (record.created_by == user || user_role_in_team?('admin'))
  end

  def destroy?
    update?
  end

  def execute?
    show? && can_execute?
  end

  private

  def user_in_workspace?
    user.workspaces.include?(record.workspace)
  end

  def can_view?
    # Check shares table
    Share.exists?(
      shareable: record,
      shared_with_type: 'User',
      shared_with_id: user.id,
      permission: ['view', 'edit', 'execute', 'admin']
    )
  end

  def can_execute?
    # Similar to can_view? but check for execute permission
  end
end
```

---

## 9. Caching Strategy

### 9.1 Fragment Caching (Rails Cache)

```ruby
# app/controllers/api/v1/agents_controller.rb
def index
  @agents = Rails.cache.fetch(
    "workspace_#{current_workspace.id}_agents",
    expires_in: 5.minutes
  ) do
    current_workspace.agents.includes(:persona, :rulesets).to_a
  end

  render json: AgentSerializer.new(@agents)
end
```

### 9.2 Russian Doll Caching

```ruby
# app/serializers/agent_serializer.rb
class AgentSerializer < ActiveModel::Serializer
  cache key: 'agent', expires_in: 1.hour

  attributes :id, :name, :slug, :description, :config
  belongs_to :persona
  has_many :rulesets
end
```

### 9.3 Query Caching (Redis)

Use Redis for:
- Session storage
- Job queues (Sidekiq)
- Rate limiting
- Real-time features (pub/sub for SSE)

---

## 10. Performance Optimization

### 10.1 Database Optimization
- **N+1 queries:** Use `includes`, `preload`, `eager_load`
- **Indexing:** Add indexes for all foreign keys and frequently queried columns
- **Connection pooling:** Configure via `database.yml`
- **Read replicas:** For read-heavy queries (analytics, dashboards)

### 10.2 Background Jobs
- **Async execution:** All long-running tasks (agent execution, indexing)
- **Job prioritization:** Critical, high, normal, low queues
- **Retry logic:** Exponential backoff for failed jobs

### 10.3 CDN & Asset Pipeline
- **Static assets:** Serve via CDN (CloudFront, Cloudflare)
- **Frontend build:** Optimize React bundle size
- **Image optimization:** Use WebP, lazy loading

---

## 11. Deployment Architecture

### 11.1 Infrastructure (Kubernetes)

```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: savant-api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: savant-api
  template:
    metadata:
      labels:
        app: savant-api
    spec:
      containers:
      - name: api
        image: savant/api:latest
        ports:
        - containerPort: 3000
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: savant-secrets
              key: database-url
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: savant-secrets
              key: redis-url
```

### 11.2 Services

- **API servers:** 3+ replicas
- **Sidekiq workers:** 5+ replicas
- **Postgres:** Primary + read replicas
- **Redis:** Cluster mode
- **Load balancer:** NGINX or managed (ALB, GCP LB)

### 11.3 Scaling Strategy

- **Horizontal scaling:** Add more API/worker replicas
- **Vertical scaling:** Increase DB/Redis resources
- **Autoscaling:** Based on CPU/memory metrics

---

## 12. Monitoring & Observability

### 12.1 Metrics (Prometheus + Grafana)
- API response times (P50, P95, P99)
- Request rates
- Error rates
- Job queue length
- Database query times

### 12.2 Logging (ELK or Datadog)
- Structured JSON logs
- Request/response logs
- Error tracking (Sentry)
- Audit logs

### 12.3 Tracing (Datadog APM or Jaeger)
- Distributed tracing for requests
- Trace agent execution flows
- Identify performance bottlenecks

---

## 13. Migration Strategy (MVP → Rails)

### Phase 1: Setup Rails App
1. Create new Rails 7.1+ app
2. Configure Postgres, Redis, Sidekiq
3. Set up authentication (Devise)
4. Create base schema (users, teams, workspaces)

### Phase 2: Port Core Logic
1. Move `lib/savant` to Rails `lib/` (keep as-is)
2. Create models for agents, workflows, personas, rulesets
3. Build service layer (creators, executors)
4. Implement REST API (v1)

### Phase 3: Build UI
1. Port existing React UI to new structure
2. Add agent/workflow CRUD pages
3. Implement visual workflow editor
4. Add dashboards and analytics

### Phase 4: Data Migration
1. Write migration scripts for existing `.savant/` data
2. Import YAML workflows to database
3. Migrate personas and rules
4. Preserve run history

### Phase 5: Deploy & Test
1. Deploy to staging environment
2. Run load tests
3. Beta testing with early users
4. Gradual rollout to production

---

## 14. Security Considerations

### 14.1 Application Security
- **SQL injection:** Use parameterized queries (Rails default)
- **XSS:** Sanitize user inputs
- **CSRF:** Enable Rails CSRF protection
- **Secrets:** Use Rails credentials or ENV vars
- **Rate limiting:** Rack Attack gem

### 14.2 API Security
- **Authentication:** JWT or session-based
- **Authorization:** Pundit policies
- **API versioning:** `/v1`, `/v2` namespaces
- **HTTPS only:** Enforce SSL in production

### 14.3 Data Security
- **Encryption at rest:** Postgres encryption
- **Encryption in transit:** TLS 1.3
- **PII handling:** GDPR compliance
- **Backup strategy:** Daily automated backups

---

## 15. Appendix: Technology Stack

### Backend
- **Framework:** Ruby on Rails 7.1+
- **Language:** Ruby 3.2+
- **Database:** PostgreSQL 15+
- **Cache/Queue:** Redis 7+
- **Background Jobs:** Sidekiq
- **Authentication:** Devise
- **Authorization:** Pundit
- **Serialization:** ActiveModel::Serializer or Blueprinter
- **API Docs:** rswag (OpenAPI)

### Frontend
- **Framework:** React 18+
- **Language:** TypeScript
- **Build Tool:** Vite
- **State Management:** React Query + Zustand
- **UI Library:** Material-UI (MUI)
- **Routing:** React Router
- **Charts:** D3.js, Recharts

### DevOps
- **Containerization:** Docker
- **Orchestration:** Kubernetes
- **CI/CD:** GitHub Actions
- **Monitoring:** Prometheus, Grafana
- **Logging:** ELK or Datadog
- **Error Tracking:** Sentry

### Testing
- **Backend:** RSpec, FactoryBot
- **Frontend:** Vitest, Testing Library
- **E2E:** Cypress or Playwright
- **Load Testing:** k6

---

**Document Status:** Draft
**Next Review:** 2025-12-20
**Owner:** Engineering Team
