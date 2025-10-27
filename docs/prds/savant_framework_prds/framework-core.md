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
