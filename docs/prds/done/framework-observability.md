# Savant Framework — Observability, Security & Governance (PRD)

> **Version:** 1.0  
> **Component:** Framework Layer (Diagnostics & Compliance)  
> **Goal:** Provide consistent logging, tracing, auditing, and sandboxing capabilities across all Savant engines.

---

## 🎯 Purpose

This PRD defines the **diagnostic, security, and compliance layer** for Savant.  
It ensures every engine has observability, telemetry, and governance controls built in — without additional integration.

---

## 🩺 Observability Features

| Feature | Description |
|----------|--------------|
| **Structured Logging** | JSON logs with severity levels and correlation IDs |
| **Tracing** | Logs tool invocations with timing and outcome |
| **Metrics** | Counters and histograms per tool and per engine |
| **Replay Store** | Optionally stores last N tool calls for debugging |
| **Error Context** | Unified exception wrapper for human + machine readable output |

### Example Log (JSON)
```json
{
  "tool": "scope/search",
  "duration_ms": 134,
  "status": "success",
  "engine": "scope",
  "trace_id": "abc123"
}
```

---

## 🔐 Security & Governance

| Feature | Description |
|----------|--------------|
| **API Keys & Scopes** | For external MCP exposure |
| **Sandbox Mode** | Disables OS and network calls unless whitelisted |
| **Audit Log** | Persistent history of tool calls |
| **Version Locking** | Engines declare compatible Savant framework version |

---

## ⚙️ Configurable Policies

Policies defined in `config/policy.yml`:
```yaml
sandbox: true
audit:
  enabled: true
  store: log/savant_audit.json
```

---

## 📊 Metrics & Telemetry

- Built-in metrics endpoint for Prometheus/OpenTelemetry.
- Exposes counters like:
  - `tool_invocations_total`
  - `tool_errors_total`
  - `tool_duration_seconds`

---

## ✅ Acceptance Criteria

- Every tool invocation logged with trace and correlation ID.
- Framework can run in sandboxed mode.
- Metrics emitted per tool call.
- Audit log persisted for compliance.
- Backward compatible with existing engines.

---

## 📂 Directory Structure (Diagnostics)
```
lib/savant/
├── middleware/
│   ├── logger.rb
│   ├── metrics.rb
│   └── trace.rb
├── audit/
│   ├── store.rb
│   └── policy.rb
└── telemetry/
    ├── metrics.rb
    └── exporter.rb
```

---

**Author:** Ahmed Shabbir  
**Date:** Oct 2025  
**Status:** Done — Observability & Security delivered

---

## Agent Implementation Plan
- Build telemetry middleware (`lib/savant/middleware/trace.rb`, `metrics.rb`) that emits structured log events, counters, and durations per tool.
- Add governance modules (`lib/savant/audit/policy.rb`, `store.rb`) that load `config/policy.yml`, enforce sandbox toggles, and persist audit entries.
- Extend MCP registrar stack to apply logging + telemetry middleware plus a replay buffer for the last N calls.
- Surface metrics exporter (`lib/savant/telemetry/metrics.rb`, `exporter.rb`) to track tool invocation totals/errors/durations with thread-safe helpers.
- Update specs (`spec/savant/middleware/trace_spec.rb`, `spec/savant/audit/policy_spec.rb`, `spec/savant/telemetry/metrics_spec.rb`) to drive behavior end-to-end, and document policy file expectations.

---

## Acceptance + TDD TODO (Compact)
- Criteria: diagnostics hooks; security policies; governance controls as defined in PRD.
- TODO:
  - Red: specs for diagnostics events, policy enforcement, audit trails.
  - Green: implement hooks/policies; integrate with core middleware.
  - Refactor: unify config surface and docs.
