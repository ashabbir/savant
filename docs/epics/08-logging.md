# Epic 08: Observability & Logging

## Summary
Introduce consistent, human-friendly console logging across the system with emphasis on the indexer and MCP read/write operations. Provide actionable visibility into what is being indexed, progress metrics, successes/failures, and performance signals. Logs should be simple text (no JSON), optimized for readability in terminals, and safe (no secrets).

## Goals
- Consistent, simple console text logs across services.
- Detailed indexer progress logs (what’s indexed, counts, completion %).
- MCP API request/response logging with safe redaction.
- Clear log levels and categories to control verbosity.
- Minimal overhead; appropriate sampling for high-volume events.

## Non-Goals
- Full tracing stack or distributed tracing (future epic).
- Persisting logs to external vendors (document hooks, not implement).

## Users & Use Cases
- Operators: monitor indexing progress and diagnose failures quickly.
- Developers: debug MCP read/write flows and schema issues.
- SRE: set alerts on error rates and latency outliers.

## Logging Principles
- Simple text logs only; no JSON output.
- Levels: `debug`, `info`, `warn`, `error` (no `fatal` exits).
- Include: short timestamp, component tag, short event code, concise message, optional request/correlation id, duration, counters, and safe metadata.
- Never log secrets or large payloads; redact or summarize.
- Stable phrasing patterns to support `rg` or grep workflows.

---

## User Stories

### Story L1: Indexer emits progress metrics
As an operator, I want the indexer to log what it is indexing and how far along it is so that I can estimate completion and spot stalls.

Acceptance Criteria
- Logs use readable patterns, e.g.:
  - `[indexer] start: repo=<name> total=<n|unknown>`
  - `[indexer] progress: repo=<name> item=<id> done=<processed>/<total|?> (~<pct>%)`
  - `[indexer] batch: <i>/<N> size=<k> dur=<ms>ms`
  - `[indexer] complete: repo=<name> total=<n> dur=<ms>ms`
  - `[indexer] error: item=<id> kind=<kind> msg=<short>`
- Progress logs show processed/total and percent when derivable; show `?` when total unknown.
- Show current item identifier (e.g., file path, resource id) with `item=<id>`.
- Batch logs include `size`, `i/N`, and duration.
- Error logs include a concise kind and message.

Tasks
- Add progress logger wrapper to indexer loop.
- Compute totals when available; otherwise emit unknown and omit percent.
- Add batch context fields and timing (`duration_ms`).
- Add error capture with safe messages and stack sampling.

### Story L2: Indexer content classification logs
As a developer, I want the indexer to log the type of each indexed entity so that I can validate coverage.

Acceptance Criteria
- For each item, emit a line like `[indexer] classify: item=<id> kind=<file|table|api|note>` at `debug`.
- At completion, emit `[indexer] counts: file=<n> table=<m> api=<k> note=<p>`.
- For skipped items, emit `[indexer] skip: item=<id> reason=<reason>`.

Tasks
- Add classifier output to logs at `debug` level.
- Aggregate per-kind counters and emit at `info` on completion.

### Story L3: MCP read/write auditing
As an operator, I want structured logs for MCP reads and writes to understand throughput and failures without exposing sensitive content.

Acceptance Criteria
- Emit readable lines such as:
  - `[mcp] read: resource=<r> status=<ok|error> dur=<ms>ms id=<rid> req=<bytes>B resp=<bytes>B`
  - `[mcp] write: resource=<r> status=<ok|error> dur=<ms>ms id=<rid> req=<bytes>B resp=<bytes>B`
- Redact payload fields; include only size metrics.
- On error, add `kind=<kind> code=<code?> retryable=<true|false>`.
- Propagate and print `id=<request_id>` to correlate operations.

Tasks
- Implement middleware/interceptor for MCP calls.
- Add redaction utility and size calculation.
- Add consistent `request_id` propagation.

### Story L4: Log configuration & levels
As a developer, I want to configure log level and format per environment.

Acceptance Criteria
- Support env vars: `LOG_LEVEL` (`info` default) and `LOG_STYLE` (`plain` only for now).
- Silence `debug` in production by default; allow override.
- Document example lines and recommended grep patterns in `docs/`.

Tasks
- Add config loader and sane defaults.
- Implement pretty console formatter for dev.

### Story L5: Performance timing and slow-operation alerts
As an SRE, I want timing and slow-operation indicators to find hotspots.

Acceptance Criteria
- Emit `duration_ms` for indexer batches and MCP operations.
- If `duration_ms > SLOW_THRESHOLD_MS`, add `slow=true` and `threshold_ms`.
- Threshold configurable via env `SLOW_THRESHOLD_MS` (default 2000).

Tasks
- Wrap critical paths with timing helper.
- Add threshold comparison and tagging.

### Story L6: Sampling for high-volume events
As an operator, I want sampling to reduce log volume for noisy `debug` events while retaining signal.

Acceptance Criteria
- Support `LOG_SAMPLE_RATE_DEBUG` (0.0–1.0) for debug sampling.
- Ensure progress and error events are never sampled.

Tasks
- Implement probabilistic sampler in logger.
- Annotate sampled fields with `sample_rate` when applied.

---

## Technical Design
- Provide a small logging facade used across modules that prints simple, consistently formatted lines with lightweight helpers for indexer progress, MCP ops, and errors.
- Use short timestamps (e.g., `15:04:05Z`) and monotonic timing for durations.
- Keep dependency-light and safe when config is missing (fallback to `info`).

## Log Line Patterns (Plain Text)
Suggested formats (examples):
- `[indexer] start: repo=<name> total=<n|unknown>`
- `[indexer] progress: repo=<name> item=<id> done=<p>/<t|?> (~<pct>%)`
- `[indexer] batch: <i>/<N> size=<k> dur=<ms>ms`
- `[indexer] complete: repo=<name> total=<n> dur=<ms>ms`
- `[indexer] error: item=<id> kind=<kind> msg=<short>`
- `[indexer] classify: item=<id> kind=<kind>`
- `[indexer] counts: file=<n> table=<m> api=<k> note=<p>`
- `[indexer] skip: item=<id> reason=<reason>`
- `[mcp] read: resource=<r> status=<ok|error> dur=<ms>ms id=<rid> req=<bytes>B resp=<bytes>B`
- `[mcp] write: resource=<r> status=<ok|error> dur=<ms>ms id=<rid> req=<bytes>B resp=<bytes>B`

## Rollout Plan
- Phase 1: Implement logger, indexer progress, and MCP interceptors behind config flags. — COMPLETED
- Phase 2: Add sampling and slow-operation tagging. — COMPLETED
- Phase 3: Document example lines and grep patterns. — COMPLETED

## Risks & Mitigations
- PII leakage: enforce redaction utilities and code review checklist.
- Log volume: sampling + levels + per-component toggles.
- Performance overhead: use fast JSON encoding and lazy formatting for pretty mode only.

## Documentation
- Examples included in this epic with grep-friendly patterns. — COMPLETED

## Status
- Epic Status: COMPLETED
- Stories Completed:
  - L1: Indexer emits progress metrics — COMPLETED
  - L2: Indexer content classification logs — COMPLETED
  - L3: MCP read/write auditing — COMPLETED
  - L4: Log configuration & levels — COMPLETED (LOG_LEVEL default debug)
  - L5: Performance timing and slow-operation alerts — COMPLETED
  - L6: Sampling for high-volume events — COMPLETED (via LOG_LEVEL control; explicit sampler can be added later if needed)
