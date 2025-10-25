# 🧾 PRD — Savant Logging Framework

> **Goal:** Evolve `logger` from a utility into a *core, observable, and queryable telemetry subsystem* — fully integrated into the Savant engine and accessible across all MCPs.

**Project:** Savant  
**Author:** Ahmed Shabbir  
**Version:** v1.0  
**Date:** Oct 2025  
**Status:** Draft — For Implementation

---

## 🎯 Purpose

The current Savant logger is a basic Ruby logger used for simple event tracking.  
To enable **AI-augmented observability**, **tracing**, and **MCP introspection**, we need a **robust, context-aware logging subsystem** that:

- Works **across all MCP services** (corext, scope, jira, gitlab, rspec, rubocop, etc.)
- Stores logs in **structured JSON** with contextual metadata (service, tool, input, output, duration, result)
- Supports **query, correlation, and replay** for debugging and benchmarking
- Is **language-agnostic** and **future compatible** with external dashboards (Grafana, Loki, Datadog)
- Feeds the **memory subsystem** for continuous learning and trend extraction

---

## 🧩 Scope

### In Scope
1. Framework-level unified logger accessible via `ctx.logger`
2. Structured JSON log schema (event-based)
3. Context-aware logging (service, tool, request_id, user/session)
4. Log storage backend (Postgres table + optional file append)
5. Log query and summary tools
6. Integration hooks for MCPs to emit structured telemetry
7. Optional streaming mode for live events (stdout / CLI)

### Out of Scope
- External monitoring integrations (Datadog, Grafana)
- AI anomaly detection (future phase)
- Real-time dashboards (future phase)

---

## 🏗️ Architecture Overview

```
Savant Engine
 ├── Logger (Framework Component)
 │    ├── Structured JSON events
 │    ├── Context injection (MCP, tool, request)
 │    ├── Persist to Postgres
 │    ├── Stream to stdout (if enabled)
 │    └── Expose query interface to MCPs
 ├── Core MCPs
 │    ├── corext / indexer / scope
 │    └── use ctx.logger for telemetry
 ├── Intelligence MCPs
 │    ├── jira, gitlab, rspec, rubocop, prompts
 │    └── emit structured logs automatically
 └── Knowledge MCPs
      └── use logs for pattern mining + memory sync
```

---

## 🧱 Core Design Components

### 1. **Logger API (Framework-Level)**

A unified interface shared across MCPs:

```ruby
ctx.logger.info(event: 'tool_call', service: 'gitlab', tool: 'get_mr', data: { mr_id: 42 })
ctx.logger.error(event: 'exception', message: e.message, backtrace: e.backtrace)
ctx.logger.trace(event: 'execution', duration_ms: 245, status: 'ok')
```

All events automatically include:
```ruby
{
  timestamp: Time.now.utc.iso8601,
  request_id: ctx.request_id,
  service: ctx.service,
  tool: ctx.tool,
  user: ctx.user,
  session: ctx.session_id
}
```

---

### 2. **Log Storage (Postgres)**

New table: `savant_logs`

| Column | Type | Description |
|--------|------|--------------|
| id | UUID | Primary key |
| timestamp | TIMESTAMP | UTC event time |
| level | TEXT | info, warn, error, trace |
| service | TEXT | MCP service name |
| tool | TEXT | Tool within service |
| event | TEXT | High-level event type |
| request_id | TEXT | Request correlation ID |
| data | JSONB | Arbitrary payload |
| duration_ms | INTEGER | Execution duration |
| status | TEXT | ok / failed |
| message | TEXT | Optional summary message |

---

### 3. **Log Query Interface**

Provide an internal tool set via `logger` MCP (optional or built-in):

```ruby
tool 'logger/query', input: { service: 'gitlab', level: 'error' } do |ctx, args|
  Savant::Logger.query(service: args[:service], level: args[:level])
end
```

Useful queries:
- `logger/query?service=rspec&level=error`
- `logger/summary?since=1h`
- `logger/show?request_id=xyz`

---

### 4. **Automatic Logging Middleware**

Wraps every MCP tool call to log start/end/duration/status automatically:

```ruby
before_tool_call do |ctx, tool, args|
  ctx.logger.trace(event: 'tool_start', service: ctx.service, tool:)
end

after_tool_call do |ctx, tool, result|
  ctx.logger.trace(event: 'tool_end', service: ctx.service, tool:, duration_ms: ctx.elapsed)
end
```

This ensures **zero-effort instrumentation** for developers.

---

### 5. **Configuration Options**

`savant.yml` additions:

```yaml
logging:
  level: info           # info, warn, error, trace
  format: json          # json, text
  output: postgres      # postgres, stdout, file
  stdout_enabled: true
  db_enabled: true
  file_path: ./log/savant.log
```

---

## ⚙️ Example Log Output

```json
{
  "timestamp": "2025-10-25T12:00:01Z",
  "level": "info",
  "service": "gitlab",
  "tool": "get_mr",
  "event": "tool_call",
  "request_id": "2b3d-44ff-9833",
  "status": "ok",
  "duration_ms": 232,
  "data": { "mr_id": 1024, "branch": "feature/guide" }
}
```

---

## 📈 Future Enhancements

| Feature | Description | Phase |
|----------|--------------|--------|
| **AI log summarizer** | Auto-summarize logs and extract failure patterns | 2 |
| **Log → Memory sync** | Feed logs into vector memory for pattern recall | 2 |
| **Distributed tracing** | Span-based correlation between MCPs | 3 |
| **Real-time CLI dashboard** | Tail + summarize logs live | 3 |

---

## ✅ Acceptance Criteria

- [ ] `ctx.logger` available in every MCP handler  
- [ ] All logs use structured JSON  
- [ ] Middleware wraps all tool calls for auto logging  
- [ ] Logs persist to Postgres and/or stdout  
- [ ] `logger/query` tool returns structured results  
- [ ] Configurable via `savant.yml`  
- [ ] Unit tests for log creation, storage, and query  
