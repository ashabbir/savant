# Savant Framework — Tool System & Interoperability (PRD)

> **Version:** 1.0  
> **Component:** Framework Layer (Tools & Integrations)  
> **Goal:** Define how tools are registered, validated, composed, and exposed across different protocols and runtimes.

---

## 🎯 Purpose

This PRD defines the **Tool System layer**, responsible for how Savant frameworks discover, validate, execute, and expose MCP tools.  
It also covers interoperability via transports and SDKs for other languages.

---

## 🧩 Tool System Architecture

| Component | Description |
|------------|--------------|
| **Tool Registry** | Auto-discovers and registers Ruby tools |
| **Schema Validation** | Ensures input/output contract integrity |
| **Composition Engine** | Allows inter-tool invocation (`ctx.invoke`) |
| **Prompt Registry (optional)** | Stores reusable prompt templates |
| **Agent Mode** | Sequential execution of tools as a plan |

---

## ⚙️ Core Tool Features

### 1. Dynamic Tool Loading
All `.rb` files under `/tools` are auto-registered at boot.

### 2. Validation Schema
Input/output schema validated via JSON schema or Dry::Struct:
```ruby
class SearchInput < Dry::Struct
  attribute :query, Types::String
end
```

### 3. Tool Composition
```ruby
ctx.invoke('corext/search', query: 'ruby')
```

### 4. Tool Permissions
Optional role-based or scope-based restrictions for sensitive tools.

---

## 🌐 Interoperability

| Feature | Description |
|----------|--------------|
| **Transport Adapters** | StdIO (default), HTTP, WebSocket, gRPC |
| **Serialization Layer** | Canonical JSON encoder/decoder |
| **Cross-Language SDKs** | Ruby, JavaScript, Python clients for tool invocation |

### Example SDK
```js
await savant.invoke("scope/search", { query: "context" });
```

---

## 🧬 AI/Agent Extensions (Optional)

| Component | Description |
|------------|--------------|
| **Reasoning Contexts** | In-memory scratchpad for sequential reasoning |
| **Prompt Registry** | Versioned prompt templates per engine |
| **Agent Mode** | Chained tool execution (A→B→C) |

---

## ✅ Acceptance Criteria

- Tools self-register and validate via schema.
- `ctx.invoke` allows nested tool calls.
- Standardized JSON-RPC over stdio + HTTP.
- SDKs can call tools from external environments.
- Agent Mode supports sequential plans with memory persistence.

---

## 📂 Directory Structure (Tools & Adapters)
```
lib/savant/
├── tool.rb
├── registry.rb
├── adapters/
│   ├── stdio.rb
│   ├── http.rb
│   └── websocket.rb
├── sdk/
│   ├── ruby_client.rb
│   ├── js_client.js
│   └── python_client.py
└── ai/
    ├── prompt_registry.rb
    └── agent_runner.rb
```

---

**Author:** Ahmed Shabbir  
**Date:** Oct 2025  
**Status:** PRD v1 — Tool System & Interoperability
