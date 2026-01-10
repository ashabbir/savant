# Savant Product Features Document

**Version:** 1.0
**Date:** 2025-12-06
**Status:** MVP → Full Rails Product
**Author:** Product Team

---

## 1. Executive Summary

This document outlines the complete feature set for Savant's evolution from MVP to full-scale Rails product. Savant is positioned as an **Agent Infrastructure Platform (AIP)** — a developer-first, local-first runtime for building and orchestrating autonomous AI agents.

**Core Value Proposition:**
- Build AI agents with maximum speed, control, and safety
- Run agents locally or in enterprise environments
- Extend with MCP tools, custom workflows, and multi-agent orchestration
- Maintain privacy, ownership, and autonomy

---

## 2. Feature Categorization

### 2.1 Core Platform Features (Current MVP)

#### 2.1.1 Agent Runtime System
- **Autonomous Reasoning Loop**
  - Reasoning Worker–driven decisions
  - LLM support for complex tool outputs
  - Token budget management for LLM contexts
  - Step-based execution with configurable limits
  - Dry-run mode for testing
  - Force-tool execution for debugging

- **Memory System**
  - Ephemeral state per session
  - Persistent memory (`.savant/session.json`)
  - LRU trimming for token budget compliance
  - Session snapshots with summarization

- **LLM Adapter Layer**
  - Provider abstraction (Ollama, Anthropic, OpenAI)
  - Local-first via Ollama
  - Model switching per task
  - Temperature and max-token controls

#### 2.1.2 MCP Framework
- **Multiplexer**
  - Unified tool surface across engines
  - Per-engine process isolation
  - Automatic restart on failure
  - Namespaced tool routing (e.g., `context.fts_search`, `git.diff`)
  - Real-time metrics and status

- **Core Engines**
  - **Context Engine**: FTS search over repository chunks, memory bank helpers
  - **Think Engine**: Workflow orchestration (plan/next), driver prompts
  - **Git Engine**: Local read-only git intelligence (diffs, hunks, file context)
  - **Jira Engine**: Jira REST v3 integration (issues, projects, comments)
  - **Personas Engine**: Persona catalog with YAML schema
  - **Rules Engine**: Shared guardrails, telemetry hooks, best practices

- **Tool Registry**
  - Dynamic tool registration via DSL
  - JSON-RPC 2.0 over stdio/HTTP
  - Schema validation
  - Middleware support (logging, metrics, tracing, user headers)

#### 2.1.3 Workflow System
- **YAML Workflow Executor**
  - Deterministic execution
  - Tool and agent steps
  - Parameter interpolation
  - Conditional logic
  - Per-step telemetry

- **Workflow Management**
  - List workflows
  - Run workflows with params
  - Saved runs with state persistence
  - Trace logs (JSONL format)
  - Workflow editor UI (graph-based)

#### 2.1.4 Database & Indexing
- **Repository Indexing**
  - File scanning with `.gitignore` and `.git/info/exclude` support
  - SHA256-based deduplication at blob level
  - Multi-strategy chunking (code by lines, markdown by chars)
  - Language detection and filtering
  - Incremental updates via cache

- **Postgres Schema**
  - `repos`, `files`, `blobs`, `file_blob_map`, `chunks`
  - GIN FTS index on chunk_text
  - Ranked search results

#### 2.1.5 Hub API & UI
- **HTTP Hub**
  - REST endpoints for tool calls
  - Diagnostics endpoints per engine
  - SSE streaming for live logs
  - Static UI serving
  - Health and status checks

- **React UI**
  - Dashboard: System overview, engine status
  - Engines: Per-engine tool execution, testing
  - Diagnostics: Overview, Requests, Agents, Logs, Routes
  - Workflow Editor: Graph-based visual editing
  - Agent Monitor: Timeline/grouped views, live streaming

#### 2.1.6 Observability
- **Logging**
  - Structured logging with levels
  - Per-engine log files
  - Aggregated event logs
  - Slow operation tracking

- **Metrics**
  - Counters and distributions
  - Prometheus export format
  - Tool execution timing

- **Audit Trail**
  - Policy-based audit configuration
  - Persistent audit store
  - Request replay buffer

#### 2.1.7 Boot & Runtime
- **Boot System**
  - RuntimeContext initialization
  - Persona loading
  - AMR (Asset Management Rules) system
  - Git repository detection
  - Driver prompt loading

- **CLI**
  - `savant run` - Boot engine with options
  - `savant review` - Boot for MR review
  - `savant workflow` - Execute workflows
  - `savant engines` - List engine status
  - `savant tools` - List available tools
  - `savant generate` - Scaffold engines/tools

#### 2.1.8 Distribution & Licensing
- **Offline Activation**
  - Username:key validation
  - Local license storage (`~/.savant/license.json`)
  - Dev mode bypass for git checkouts
  - Environment variable controls

- **Packaging**
  - Homebrew formula
  - Single binary distribution
  - Release automation (artifacts, checksums)

---

### 2.2 Features to Build (Rails Product)

#### 2.2.1 User Management & Authentication
- **Multi-tenancy**
  - User registration and login
  - Email verification
  - Password reset flow
  - OAuth providers (GitHub, Google, GitLab)

- **Teams & Workspaces**
  - Create and manage teams
  - Invite members
  - Role-based access control (Owner, Admin, Member, Viewer)
  - Workspace isolation

- **User Profiles**
  - Personal settings
  - API key management
  - Notification preferences
  - Activity history

#### 2.2.2 Agent Management (Database-Backed)
- **Agent CRUD**
  - Create agents via wizard (Persona → Driver → Rules)
  - List agents with filters (name, status, created date)
  - View agent details (config, runs, metrics)
  - Edit agent configuration
  - Delete agents
  - Duplicate/clone agents

- **Agent Configuration**
  - Persona selection
  - Driver prompt customization
  - Ruleset assignment
  - Tool allowlist/blocklist
  - LLM preferences (for heavy tool outputs)
  - Token budget overrides

- **Agent Execution**
  - Start agent runs
  - Monitor progress in real-time
  - View transcripts (chat-like UI)
  - Stop/pause/resume runs
  - Retry failed runs
  - Schedule recurring runs

- **Agent Library**
  - Public agent templates
  - Private team agents
  - Favorites and bookmarks
  - Sharing and collaboration

#### 2.2.3 Workflow Management (Database-Backed)
- **Workflow CRUD**
  - Create workflows via wizard
  - Visual graph editor (drag-and-drop nodes)
  - List workflows with filters
  - View workflow details
  - Edit workflow steps
  - Version control for workflows

- **Workflow Authoring**
  - Add tool steps
  - Add agent steps
  - Conditional branching
  - Parallel execution paths
  - Error handling and retries
  - YAML preview and validation

- **Workflow Execution**
  - Run workflows manually
  - Schedule workflows (cron-like)
  - Trigger workflows via webhooks
  - View run history
  - Drill into run traces
  - Export run results

- **Workflow Marketplace**
  - Browse public workflows
  - Search by category/tag
  - Import/export workflows
  - Community ratings and reviews

#### 2.2.4 Persona Management
- **Persona CRUD**
  - Create custom personas
  - Edit persona attributes (name, description, instructions)
  - Delete personas
  - List personas with filters

- **Persona Templates**
  - System-provided personas (architect, developer, reviewer)
  - Team-shared personas
  - Personal personas
  - Import from YAML

#### 2.2.5 Ruleset Management
- **Ruleset CRUD**
  - Create rulesets
  - Edit rule content
  - Delete rulesets
  - List rulesets with filters

- **Rule Application**
  - Assign rulesets to agents
  - Assign rulesets to workflows
  - Rule priority and ordering
  - Rule validation

#### 2.2.6 Repository Management
- **Repository Registration**
  - Connect GitHub/GitLab repositories
  - Register local repositories
  - Auto-discovery of repos
  - Repository metadata (name, path, language)

- **Repository Indexing**
  - Manual index trigger
  - Scheduled re-indexing
  - Index status monitoring
  - Index configuration (languages, chunk sizes)

- **Repository Access Control**
  - Per-repo permissions
  - Team-level access
  - Public/private visibility

#### 2.2.7 Tool Management
- **Custom Tool Builder**
  - Define tool schema
  - Implement tool logic (Ruby/JavaScript)
  - Test tools in sandbox
  - Publish tools to registry

- **Tool Marketplace**
  - Browse available tools
  - Search by category
  - Install tools to workspace
  - Manage tool versions
  - Community ratings

- **Tool Permissions**
  - Whitelist/blacklist tools per agent
  - Approve tool execution
  - Audit tool usage

#### 2.2.8 Integration Hub
- **Git Platform Integrations**
  - GitHub: PR review, issue creation, commit history
  - GitLab: MR review, pipeline triggers
  - Bitbucket: PR insights

- **Project Management Integrations**
  - Jira (enhanced): Epic/story management, sprint planning
  - Linear: Issue sync, project updates
  - Asana: Task automation

- **Communication Integrations**
  - Slack: Notifications, bot commands
  - Discord: Alerts, agent interactions
  - Microsoft Teams: Workflow updates

- **CI/CD Integrations**
  - GitHub Actions: Trigger workflows
  - GitLab CI: Agent-driven pipelines
  - Jenkins: Build automation

- **Cloud Provider Integrations**
  - AWS: S3 storage, Lambda functions
  - GCP: Cloud Storage, Cloud Functions
  - Azure: Blob Storage, Functions

#### 2.2.9 Advanced Analytics & Reporting
- **Usage Dashboards**
  - Agent execution stats (count, duration, success rate)
  - Workflow performance metrics
  - Tool usage frequency
  - Token consumption by model
  - Cost analysis (if using paid LLMs)

- **Reports**
  - Weekly/monthly summaries
  - Team performance reports
  - Export to PDF/CSV
  - Scheduled email reports

- **Insights**
  - Agent efficiency recommendations
  - Workflow optimization suggestions
  - Cost-saving opportunities

#### 2.2.10 Search & Discovery
- **Global Search**
  - Search agents, workflows, personas, rules
  - Search codebase via FTS
  - Search run transcripts
  - Recent items and history

- **Tagging & Categorization**
  - Tag agents and workflows
  - Category hierarchies
  - Filter by tags/categories

#### 2.2.11 Collaboration Features
- **Comments & Annotations**
  - Comment on agent runs
  - Annotate workflow steps
  - Mention team members
  - Comment threads

- **Sharing**
  - Share agent links
  - Share workflow results
  - Public/private sharing
  - Embed workflows in docs

- **Activity Feeds**
  - Team activity stream
  - Per-agent activity
  - Notifications for mentions

#### 2.2.12 Security & Compliance
- **Secrets Management**
  - Secure credential vault
  - API key storage
  - Environment variable management
  - Secret rotation policies

- **Audit Logs**
  - Comprehensive audit trail
  - Compliance reporting
  - Data retention policies
  - Export audit logs

- **Access Control**
  - RBAC (Role-Based Access Control)
  - Fine-grained permissions
  - IP whitelisting
  - Two-factor authentication

- **Data Privacy**
  - GDPR compliance
  - SOC 2 compliance
  - Data encryption at rest and in transit
  - Data export and deletion

#### 2.2.13 API & Webhooks
- **REST API**
  - Full CRUD for all resources
  - API versioning
  - Rate limiting
  - Comprehensive documentation (OpenAPI)

- **Webhooks**
  - Subscribe to events (agent.started, workflow.completed, etc.)
  - Webhook retry logic
  - Webhook logs and debugging

- **GraphQL API (Optional)**
  - Flexible querying
  - Real-time subscriptions
  - Schema introspection

#### 2.2.14 Enterprise Features
- **On-Premises Deployment**
  - Docker-based distribution
  - Kubernetes manifests
  - Air-gapped installation support

- **SSO Integration**
  - SAML 2.0
  - LDAP/Active Directory
  - Okta, Auth0

- **Advanced Compliance**
  - Custom data retention
  - Legal hold
  - Export controls

- **Dedicated Support**
  - Priority support channels
  - SLA guarantees
  - Dedicated account manager

#### 2.2.15 Developer Experience
- **SDK & Libraries**
  - Ruby SDK (current)
  - Python SDK
  - JavaScript/TypeScript SDK
  - Go SDK

- **CLI Enhancements**
  - Interactive mode
  - Configuration wizard
  - Autocomplete
  - Plugin system

- **Documentation**
  - Interactive tutorials
  - API reference
  - Video guides
  - Example projects

- **IDE Extensions**
  - VSCode extension
  - JetBrains plugin
  - Sublime Text package

#### 2.2.16 Mobile & Desktop Apps
- **Mobile Apps (iOS/Android)**
  - Monitor agent runs
  - View workflows
  - Push notifications
  - Quick actions

- **Desktop App (Electron)**
  - Native notifications
  - System tray integration
  - Offline mode

---

## 3. Feature Prioritization (Rails Product Roadmap)

### Phase 1: Foundation (Months 1-2)
1. User authentication and multi-tenancy
2. Agent database schema and CRUD
3. Workflow database schema and CRUD
4. Basic UI for agent/workflow management
5. REST API endpoints

### Phase 2: Core Capabilities (Months 3-4)
1. Agent execution with UI monitoring
2. Workflow visual editor
3. Persona and ruleset management
4. Repository registration and indexing
5. Search and discovery

### Phase 3: Collaboration (Months 5-6)
1. Teams and workspaces
2. Sharing and permissions
3. Comments and activity feeds
4. Tool marketplace foundation
5. Integration hub (GitHub, Slack)

### Phase 4: Enterprise (Months 7-9)
1. SSO and advanced security
2. Audit logs and compliance
3. Advanced analytics
4. Webhooks and event system
5. On-premises deployment

### Phase 5: Scale & Polish (Months 10-12)
1. Mobile apps
2. Desktop app
3. SDK expansion
4. Performance optimization
5. Enterprise support infrastructure

---

## 4. Feature Dependencies

```
User Auth & Multi-tenancy
  ├─> Teams & Workspaces
  ├─> Agent Management
  ├─> Workflow Management
  ├─> Repository Management
  └─> Access Control

Agent Management
  ├─> Agent Execution
  ├─> Persona Management
  ├─> Ruleset Management
  └─> Tool Permissions

Workflow Management
  ├─> Workflow Editor
  ├─> Workflow Execution
  └─> Workflow Marketplace

Repository Management
  ├─> Repository Indexing
  └─> Repository Access Control

Integration Hub
  ├─> Webhooks
  └─> API

Analytics & Reporting
  ├─> Usage Dashboards
  └─> Cost Analysis

Security & Compliance
  ├─> Secrets Management
  ├─> Audit Logs
  └─> SSO
```

---

## 5. Success Metrics by Feature Category

### User Engagement
- Daily/monthly active users
- Average session duration
- Feature adoption rates
- User retention (30/60/90 day)

### Agent & Workflow Usage
- Agents created per user
- Workflows created per user
- Agent runs per day
- Workflow runs per day
- Success rate of runs

### Collaboration
- Teams created
- Team size distribution
- Shares per user
- Comments per agent/workflow

### Performance
- P50/P95/P99 response times
- Agent execution time
- Workflow completion time
- Database query performance

### Business
- Conversion rate (free → paid)
- Monthly recurring revenue
- Customer acquisition cost
- Lifetime value
- Churn rate

---

## 6. Feature Flags & Rollout Strategy

### Use Feature Flags For:
- New UI components
- Experimental workflows
- Beta integrations
- Enterprise features
- Performance optimizations

### Rollout Stages:
1. **Internal**: Savant team only
2. **Alpha**: Invited users
3. **Beta**: Opt-in users
4. **GA**: All users

---

## 7. Backward Compatibility

### MVP → Rails Migration Strategy:
- Preserve existing CLI commands
- Maintain MCP stdio interface
- Support legacy YAML workflows
- Migrate existing `.savant/` data
- Provide migration scripts for users

### Deprecation Policy:
- Announce deprecations 6 months in advance
- Provide migration guides
- Maintain deprecated features for 12 months
- Sunset with clear communication

---

## 8. Appendix: Feature Comparison

| Feature | MVP | Rails Product |
|---------|-----|---------------|
| User Auth | None | Full OAuth, SSO |
| Multi-tenancy | Single user | Teams & workspaces |
| Agent Management | CLI + YAML | Database + UI + API |
| Workflow Management | YAML files | Database + Visual editor |
| Repository Indexing | Local only | Local + GitHub/GitLab |
| Tool Registry | Built-in only | Marketplace |
| Integrations | Basic (Jira, Git) | Extensive (10+) |
| Analytics | Basic logs | Advanced dashboards |
| Mobile Access | None | iOS + Android apps |
| Enterprise Features | None | SSO, compliance, on-prem |

---

**Document Status:** Draft
**Next Review:** 2025-12-20
**Owner:** Product Team
