# Savant LLM Model Registry — PRD

## Summary
- Introduce a first‑class Model Registry backed by Postgres to manage multiple LLM providers and models (initially Google and Ollama).
- Allow users to add providers, supply credentials, validate connectivity, enumerate available models, and register selected models for use.
- Enable binding an “Agent” to a specific registered model for runtime usage (MCP engines and other agents can reference the registry).
- Preserve current behavior (local Ollama via config), while migrating to DB‑backed configuration.

## Goals
- Provider management: create, read, update, delete (CRUD) for providers and credentials.
- Connectivity validation: verify credentials and reachability; surface errors usefully.
- Model discovery: fetch and display available models per provider; register chosen models.
- Model registry: store provider+model metadata, capabilities, limits, and status.
- Agent binding: assign a registered model to an agent for use at runtime.
- Interfaces: CLI, MCP tools, and a minimal admin web UI.
- Security: encrypt credentials at rest; avoid storing secrets in code or plain text.

## Non‑Goals
- Rich prompt orchestration, retries, or routing logic beyond selecting a model.
- Provider fine‑tuning workflow or dataset management.
- Billing dashboards; only store optional pricing metadata if available.
- Full parity for all providers in v1 (ship Google + Ollama first; stub adapters for others).

## Definitions
- Provider: An LLM platform (Google, Ollama, OpenAI, Azure OpenAI, Anthropic).
- Model: A concrete model identifier on a provider (e.g., `gemini-2.0-pro`, `llama3.1` in Ollama).
- Registered Model: A selected provider+model with known metadata, enabled/disabled state.
- Agent: A logical actor (MCP engine instance or named agent) that uses a specific Registered Model.

## Users & Personas
- DevOps/Admin: Configures providers and credentials, validates connections, curates registry.
- Developer: Binds agents to models, tests via CLI/MCP, iterates on usage.

## Functional Requirements
- Provider CRUD
  - Create provider with fields depending on type
    - Google: `api_key` required
    - Ollama: `base_url` required; `api_key` optional
  - Update/delete/list providers
  - Secrets stored encrypted at rest
- Connectivity Validation
  - On demand “Test Connection” attempts a harmless provider call
  - Returns status (ok/error), reason, and round‑trip timing
- Model Discovery
  - Google: list models endpoint filtered to generative models
  - Ollama: list local tags via `/api/tags`
  - Display name, id, modalities (text, vision, tool use), context window (if available)
- Model Registration
  - Persist selected models to the registry with provider linkage and metadata
  - Enable/disable registered models; store last validated timestamp
- Agent Binding
  - Create/update/delete agent definitions (name, description)
  - Assign a registered model to each agent (1:1 for v1)
  - Expose lookup utility at runtime (e.g., `Savant::LLM.for_agent(name)`)
- Interfaces
  - CLI: manage providers, test, list models, register, assign agents
  - MCP: tools to perform the same operations programmatically
  - Web UI (minimal admin): two‑panel layout for provider + model management and agent binding
- Backwards Compatibility
  - Continue supporting existing OLLAMA config in `config/settings.json`
  - Migration tool to seed DB from config on first run

## Non‑Functional Requirements
- Security
  - Encrypt credentials using AES‑256‑GCM with a master key from `SAVANT_ENC_KEY`
  - Keys never logged; redact in UI and logs
- Reliability
  - Timeouts on provider calls (default 5s connect, 10s read)
  - Retries for transient errors (up to 2)
- Observability
  - Log validations, model listings (counts, durations)
  - Metrics counters: provider_validation_success/failure, model_list_success/failure
- Performance
  - Model lists cached per provider for 10 minutes (configurable)
- Compliance
  - Avoid storing PII in logs; credentials scoped to purpose

## Architecture Overview
- New `Savant::LLM` subsystem
  - Registry service: provider CRUD, credential storage, model registry, agent binding
  - Provider adapters: `GoogleAdapter`, `OllamaAdapter`, future `OpenAIAdapter`, `AzureOpenAIAdapter`, `AnthropicAdapter`
  - Connector contracts: `test_connection!`, `list_models`, `load_credentials`
  - Credential vault: envelope encryption utilities
- Interfaces
  - CLI: `bin/llm` with subcommands (see CLI spec)
  - MCP: new service `llm` (or extend `context` tools) exposing admin operations
  - Web UI: lightweight Sinatra app under `bin/llm_admin` (optional process) following UI layout rules
- Backward compatibility
  - Bootstrap migration reads `config/settings.json` to create Ollama provider if present
  - Runtime lookup favors DB registry when available; falls back to config

## Data Model (Postgres)
Tables are created by new migrations via `Savant::DB.migrate_tables` extension.

- `llm_providers`
  - `id` (PK)
  - `name` (text, unique) – user‑friendly name (e.g., “Local Ollama”, “Google Primary”)
  - `provider_type` (text, enum: `google`, `ollama`, `openai`, `azure_openai`, `anthropic`)
  - `base_url` (text, nullable) – used for Ollama or custom endpoints
  - `encrypted_api_key` (bytea, nullable)
  - `api_key_nonce` (bytea, nullable) – GCM nonce
  - `api_key_tag` (bytea, nullable) – GCM auth tag
  - `created_at` (timestamptz), `updated_at` (timestamptz)
  - `last_validated_at` (timestamptz, nullable)
  - `status` (text, default `unknown`, values: `unknown`, `valid`, `invalid`)

- `llm_models`
  - `id` (PK)
  - `provider_id` (FK → `llm_providers.id`)
  - `provider_model_id` (text) – canonical id from provider
  - `display_name` (text)
  - `modality` (text, array: e.g., `{text, vision, tools}`)
  - `context_window` (integer, nullable)
  - `input_cost_per_1k` (numeric, nullable)
  - `output_cost_per_1k` (numeric, nullable)
  - `enabled` (boolean, default true)
  - `meta` (jsonb)
  - Unique (`provider_id`, `provider_model_id`)

- `agents`
  - `id` (PK)
  - `name` (text, unique) – logical agent name
  - `description` (text)
  - `created_at`, `updated_at`

- `agent_model_assignments`
  - `agent_id` (FK → `agents.id`)
  - `llm_model_id` (FK → `llm_models.id`)
  - PK (`agent_id`)
  - Foreign key ON DELETE CASCADE

- `llm_cache`
  - `id` (PK)
  - `provider_id` (FK)
  - `key` (text) – e.g., `models:list`
  - `value` (jsonb)
  - `expires_at` (timestamptz)
  - Unique (`provider_id`, `key`)

## Backend Design
### Ruby Modules
- `lib/savant/llm/registry.rb`
  - Provider CRUD, credential encrypt/decrypt via `Savant::LLM::Vault`
  - Model registration CRUD
  - Agent CRUD and assignment management
- `lib/savant/llm/vault.rb`
  - `encrypt(plaintext) → {ciphertext, nonce, tag}` using AES‑256‑GCM
  - `decrypt(ciphertext, nonce, tag) → plaintext`
  - Master key from `ENV['SAVANT_ENC_KEY']`
- `lib/savant/llm/adapters/base_adapter.rb`
  - Interface: `initialize(provider_row)`, `test_connection!`, `list_models`
  - Helpers for HTTP (timeouts, retries)
- `lib/savant/llm/adapters/google_adapter.rb`
  - Endpoint: `GET https://generativelanguage.googleapis.com/v1/models?key=API_KEY`
  - Map models with supported modalities
- `lib/savant/llm/adapters/ollama_adapter.rb`
  - Endpoint: `GET {base_url}/api/tags`
  - Map `models[].name` to `provider_model_id`
- `lib/savant/llm/runtime.rb`
  - `for_agent(agent_name) → {provider, model, credentials}`
  - Used by engines to select the configured model

### Error Handling
- Use `Savant::ConfigError` for misconfiguration; new `Savant::LLM::Error` for runtime adapter errors.
- Log with `Savant::Logger.with_timing` and mark slow ops with `SLOW_THRESHOLD_MS`.

## MCP Service
- New service: `MCP_SERVICE=llm` handled by `lib/savant/mcp_server.rb` via registrar `lib/savant/llm/tools.rb` and engine `lib/savant/llm/engine.rb`.
- Tools
  - `llm/providers/list` → list providers
  - `llm/providers/create` → params by provider_type
  - `llm/providers/test` → run connection test
  - `llm/providers/delete`
  - `llm/models/discover` → fetch available models from provider
  - `llm/models/register` → persist selected models
  - `llm/models/list` → list registered models
  - `llm/agents/list|create|delete`
  - `llm/agents/assign_model` → bind agent to a registered model

## CLI
- New `bin/llm` with subcommands:
  - `provider add --type google --name "Google Primary" --api-key $KEY`
  - `provider add --type ollama --name "Local Ollama" --base-url http://localhost:11434`
  - `provider list`
  - `provider test --name "Google Primary"`
  - `models discover --provider "Local Ollama"`
  - `models register --provider "Google Primary" --id gemini-2.0-pro`
  - `models list`
  - `agent add --name context-agent`
  - `agent assign --name context-agent --model gemini-2.0-pro@Google Primary`
  - `agent show --name context-agent`

## Admin Web UI (Minimal)
- Stack: Sinatra + ERB, served by `bin/llm_admin` (optional to run).
- Auth: Basic auth or local‑only by default; configurable.
- Layout (per UI rules): two‑panel layout (md: 4/8 split)
  - Left panel: navigation (Providers, Models, Agents)
  - Right panel: content (lists, forms, results)
- Pages
  - Providers: list, add, edit, delete; “Test Connection” inline
  - Discover Models: select provider, fetch models, select and register
  - Registered Models: list, enable/disable
  - Agents: list, add, assign model
- Dialogs: Use modal for large model lists; includes close controls

## Security
- Secrets never written to logs or returned by MCP/UI once saved (write‑only display).
- AES‑256‑GCM encryption; rotate master key via re‑encryption routine (`bin/llm key rotate`).
- Environment variables
  - `SAVANT_ENC_KEY` (32 bytes base64 or hex)
  - `GOOGLE_API_KEY` optional bootstrap for convenience

## Backward Compatibility & Migration
- If `config/settings.json` contains Ollama config, `bin/llm migrate` seeds `llm_providers` with that info.
- Runtime lookup order: DB agent assignment → default provider/model from DB → legacy config

## Provider Adapters — Details
- Google
  - Validation: GET `/v1/models` with API key; 200 OK indicates valid key
  - Discover: Parse response, filter `supportedGenerationMethods` for `generateContent`
  - Credentials: API key required
- Ollama
  - Validation: GET `{base_url}/api/tags`; 200 OK indicates reachable daemon
  - Discover: From tags list, map `name` as model id
  - Credentials: Key optional; URL required

## Testing Plan
- Unit Tests
  - Vault encryption/decryption roundtrip
  - Registry CRUD (providers, models, agents, assignments)
  - Adapters: mock HTTP responses for success/failure paths
- Integration Tests
  - In‑memory or test Postgres container (existing Makefile flows)
  - CLI smoke tests for provider add/test, model discovery and registration
  - MCP tools tests (`make mcp-test`) invoking llm tools
- Manual Tests
  - Local Ollama with/without key
  - Google key validity (valid/invalid key)

## Deployment & DevOps
- Migrations: new DB migration files run via `bin/db_migrate` / `make migrate`
- Docker: no new containers required; optional UI exposed via new service stanza
- Env: add `SAVANT_ENC_KEY` to `.env.example` (not checked in)

## Risks & Mitigations
- Provider API changes: isolate via adapters; add versioned endpoints
- Credential leakage: strict redaction; limit log exposure; encryption at rest
- Network instability: retries + timeouts; surface actionable errors
- Large model lists: paginate or lazy load in UI; cache results

## Milestones
- M0 (Core, MCP + CLI):
  - Schema, Vault, Registry, Google + Ollama adapters
  - MCP `llm` tools and CLI parity
  - Migration from legacy OLLAMA config
- M1 (Admin UI):
  - Sinatra app with two‑panel layout
  - Providers, Discover, Models, Agents pages
- M2 (More Providers):
  - OpenAI, Azure OpenAI, Anthropic adapters
  - Pricing metadata enrichment where available

## Acceptance Criteria
- Can add Google provider with key; test returns success; discover lists models; register a subset.
- Can add Ollama provider with URL (no key); test returns success; discover lists local models; register a subset.
- Registered models are persisted and visible via CLI and MCP tools.
- Can create an agent and assign a registered model; `Savant::LLM.for_agent(name)` returns a usable tuple.
- Credentials stored encrypted; never printed in logs; redacted in UI/MCP responses.
- Migration: existing Ollama config auto‑seeds a provider on first run when invoked.

## Open Questions
- Agent concept scope: Is an “agent” strictly an MCP engine instance or a named persona? For v1, implement generic agents table; engines can map names.
- REST API: Do we need a long‑running HTTP API beyond the admin UI? For now, scope to MCP + CLI; defer REST until needed.
- Multi‑model per agent: Future enhancement to allow primary + fallback or routing.

## UX Design Guidelines (Non‑Technical Friendly)
- Product Principles
  - Keep it simple: minimal choices on each screen; defaults provided.
  - Speak plainly: use everyday language, avoid jargon and acronyms.
  - Guide with next steps: every success screen offers a suggested next action.
  - Safe by default: hide secrets, confirm destructive actions, and allow undo when possible.
  - Progressive disclosure: advanced options tucked behind “Advanced settings”.

- Navigation
  - Two‑panel layout (left nav, right content). Left items: Providers, Discover Models, My Models, Agents, Settings.
  - Always show the current section title and short description on the right.

- Forms & Validation
  - Minimal fields; clear labels and helper text under each input.
  - Inline validation with specific guidance (e.g., “Enter a full web address like http://localhost:11434”).
  - Disable primary buttons until required fields are valid.
  - Mask API keys after save; show last 4 chars only; include “Replace key” action.

- Language & Labels (examples)
  - Provider → “AI Provider”
  - API Key → “Secret Key” (helper: “Paste your key from the provider’s website.”)
  - Test Connection → “Test connection” (helper: “We’ll try a quick call to make sure this works.”)
  - Discover Models → “Find available models”
  - Register Model → “Add to My Models”
  - Assign Model → “Use this model”

- States & Feedback
  - Empty states: friendly message with a single clear CTA (e.g., “No providers yet. Add your first provider.”).
  - Loading: spinner with simple text (“Checking your connection…”).
  - Success: green check with next action (“Connection works. Next: Find available models”).
  - Errors: short, actionable copy that says what happened and how to fix it. Include retry.

- Accessibility
  - AA contrast minimum; keyboard focus rings; all form controls labeled.
  - Announce validation errors and successes to screen readers; use ARIA live regions for async results.
  - Do not use color alone to convey meaning; include icons and text.

- Security & Privacy
  - Do not display secrets after save; show last 4 chars only.
  - Redact secrets in logs and responses.
  - Copy‑to‑clipboard for IDs but never for stored secrets; allow re‑entry only.

- Responsiveness
  - Mobile: vertical stacking; keep primary actions visible without scrolling.
  - Desktop: md 4/8 split; dialog for large model lists.

- Destructive Actions
  - Use confirmation modal: “Delete provider?” with impact summary (e.g., “This also removes its models.”).
  - Require explicit checkbox “I understand” for irreversible actions.

## Primary User Flows
- First‑Run Onboarding (Wizard)
  1) Choose provider (Google or Ollama)
  2) Connect (enter Key for Google or URL for Ollama) → Test connection
  3) Find available models → show list
  4) Select models → Add to My Models
  5) Create an Agent → Name it → Use this model
  6) Done screen with tips and a link to try it in your editor

- Add Google Provider
  - Go to Providers → Add → Choose Google → Paste Secret Key → Test connection → Save.

- Add Ollama Provider
  - Go to Providers → Add → Choose Ollama → URL defaults to http://localhost:11434 → Test connection → Save.

- Discover and Register Models
  - Discover Models → Select provider → Fetch → Check boxes → Add to My Models.

- Create Agent and Assign Model
  - Agents → New Agent → Name → Choose from My Models → Save.

## UI Copy (Ready‑to‑Use)
- Empty Providers: “No AI providers yet. Add your first provider to get started.”
- Test Connection (success): “Connection works. You can now find available models.”
- Test Connection (failure): “We couldn’t connect. Check your internet, URL, or key and try again.”
- Discover Models (empty): “We didn’t find any models. Make sure your provider has models available.”
- Register Models (success): “Added X models to My Models.”
- Agent Saved: “Agent created. It will use ‘{model}’ for AI responses.”

## Visual Structure
- Providers list row: name, type badge, status (Valid/Invalid/Unknown), last validated time, actions (Test, Edit, Delete).
- Model discovery table: Model name, ID, Modality, Context window, Select checkbox.
- My Models list: same columns + Enabled toggle.
- Agent list row: name, assigned model chip, actions (Change model, Delete).

## Onboarding & Help
- Wizard appears when there are no providers or models.
- Each page has a “What is this?” link that opens a short explainer.
- “Need help?” footer links to docs FAQ section.

## FAQ (For Non‑Technical Users)
- What is an AI Provider? “It’s a service that runs AI models. Examples: Google or Ollama.”
- What is a Model? “It’s the specific AI brain you’ll use, like ‘Gemini’ or ‘Llama’.”
- Do I need a key? “Google requires a key. Ollama can work locally without one.”
- Can I change models later? “Yes, you can switch any time.”

## Usability Acceptance Criteria
- Setup time: A new user can add a provider, register one model, and create an agent in under 5 minutes without documentation.
- Error recovery: From a failed test, users can fix the issue and succeed within two attempts.
- Clarity: 90% of test users correctly explain the difference between Provider and Model after setup.
- Accessibility: Passes WCAG 2.1 AA for color contrast and keyboard navigation on core flows.

## Content & Naming Guidelines
- Prefer short, common words; avoid brand jargon unless strictly needed.
- Use sentence‑case for labels and buttons.
- Buttons start with verbs: “Add provider”, “Test connection”, “Find models”, “Use this model”.
- Show units and examples near inputs (e.g., URL examples).

## Success Metrics
- Time‑to‑first‑model (median) < 3 minutes.
- Test connection success rate > 80% on first attempt for valid keys.
- Drop‑off between “Add provider” and “Add to My Models” < 20%.

