# Savant Framework — Core Runtime & Developer Experience (PRD)

> **Version:** 1.0  
> **Component:** Framework Layer (Core)  
> **Goal:** Establish a standardized runtime, configuration, and developer toolkit shared across all Savant engines.

---

## 🎯 Purpose

This document defines the **core runtime layer** for Savant — the foundation that powers every engine (e.g., Cortex, Scope, Logger).  
It provides consistent tool registration, lifecycle orchestration, dependency injection, and developer utilities.

---

## 🧩 Functional Overview

| Layer | Description | Example |
|-------|--------------|----------|
| **Runtime Core** | Base classes, lifecycle management | `Savant::Engine`, `Savant::Tool`, `Savant::Context` |
| **Middleware Stack** | Ordered interceptors | Logging, auth, metrics |
| **Registry & Discovery** | Engine-agnostic tool registry | Auto-register `tools/` |
| **Developer Toolkit** | CLI, config, docs | `savant call`, `savant list tools` |

---

## ⚙️ Core Runtime Features

### 1. Lifecycle Hooks
```ruby
before_call :authenticate
after_call :audit
```
Hooks receive `ctx` and payload, allowing global behaviors such as validation, security, or cleanup.

### 2. Middleware Stack
Rack-inspired middleware system:
```ruby
use Savant::Middleware::Logger
use Savant::Middleware::Metrics
```

### 3. Context Injection (DI)
Each engine gets a shared `ctx` object containing:
```ruby
ctx.db
ctx.logger
ctx.config
```

### 4. Session State
Optional ephemeral in-memory session context — supports multi-step agent flows.

---

## 🧰 Developer Experience

### CLI Toolkit
Commands:
```
savant new engine <name>
savant list tools
savant call <tool> --input='{}'
savant test
```

### Config System
Global config file:
```yaml
# config/savant.yml
db_url: postgres://localhost/savant
env: development
```

### Tool Registry Introspection
```
savant describe scope/search
```

### Hot Reload (Dev Mode)
Auto-reload tools when code changes locally.

---

## 🚀 Acceptance Criteria

- Framework boots any engine with `MCP_SERVICE=<name>`.
- Tools auto-register under a global registry.
- CLI and config functional across engines.
- Shared context available in all tools.
- Lifecycle hooks and middleware operational.

---

## 📂 Directory Structure (Core)
```
lib/savant/
├── engine.rb
├── tool.rb
├── context.rb
├── middleware/
│   ├── logger.rb
│   └── metrics.rb
├── cli/
│   ├── main.rb
│   └── commands/
└── config/
    └── loader.rb
```

---

**Author:** Ahmed Shabbir  
**Date:** Oct 2025  
**Status:** PRD v1 — Core Runtime

---

## Acceptance + TDD TODO (Compact)
- Criteria: boots via `MCP_SERVICE`; auto tool registry; shared `ctx`; lifecycle hooks; middleware; CLI+config functional.
- TODO:
  - Red: specs for `Savant::Engine`, `Tool`, `Context` lifecycles and registry.
  - Red: middleware contract (call/next), hooks `before_call`/`after_call`.
  - Red: CLI smoke (`savant list tools`, `savant call` dry-run); config loader.
  - Green: implement base classes, registry discovery, DI context wiring.
  - Green: implement middleware stack and hook execution order.
  - Green: minimal CLI commands and config loader integration.
  - Refactor: align naming and directory structure; add docs.

---

## Agent Implementation Plan

- Branch: feature/framework-core
- Strategy: Strict TDD in small phases with focused commits.

Phases
- Phase 1 — Core Engine Hooks (TDD)
  - Red: spec for `Savant::Core::Engine` lifecycle hooks `before_call`/`after_call` and execution order around a tool call.
  - Green: implement `lib/savant/core/engine.rb` with hook DSL + `wrap_call` and integrate via a registrar middleware in `MCP::Dispatcher`.
  - Commit: “core(engine): add lifecycle hooks and dispatcher integration (TDD)”

- Phase 2 — Shared Context (TDD)
  - Red: spec for `Savant::Core::Context` exposing `logger`, `config`, and optional `db` lazy construction.
  - Green: implement `lib/savant/core/context.rb` and attach instance to all engines via base class.
  - Commit: “core(context): shared ctx with logger/config (TDD)”

- Phase 3 — Config Loader (TDD)
  - Red: spec for `Savant::Core::Config::Loader` that reads `config/savant.yml` and falls back to existing JSON settings.
  - Green: implement `lib/savant/core/config/loader.rb` with precedence: YAML > env > defaults; non‑breaking with current JSON.
  - Commit: “core(config): YAML loader with JSON fallback (TDD)”

- Phase 4 — CLI DX (TDD)
  - Red: CLI specs for `savant list tools` and `savant call <tool> --input` (dry‑run friendly; no DB required for list).
  - Green: extend `bin/savant` with `list` and `call` subcommands using existing registrar discovery.
  - Commit: “cli: add list/call for all engines (TDD)”

- Phase 5 — Polish
  - RuboCop auto‑correct and doc touch‑ups.
  - Move PRD to `docs/prds/done/framework-core.md` and mark Status to Done.
  - Commit: “docs(prd): framework-core → Done; polish & rubocop”

Notes
- Backwards compatible with existing Context/Jira tools and server.
- No DB required for `list` or describe commands; `call` constructs engine on demand.
