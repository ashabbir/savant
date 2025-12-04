# Logging & Observability

## Overview
Structured JSON logging with levels, per-service files, and simple metrics. Optimized for CLI and long-running MCP processes.

## Key Files
- `lib/savant/logging/logger.rb` – main logger (levels, timing helper)
- `lib/savant/logging/event_recorder.rb` – in-memory/file event storage
- `lib/savant/logging/metrics.rb` – counters/distributions
- `lib/savant/logging/audit/{policy,store}.rb` – audit logging hooks

## Usage
```ruby
logger = Savant::Logging::Logger.new(io: $stdout, file_path: 'logs/service.log', level: 'info', json: true, service: 'context')
logger.info(event: 'scan_start', repo: 'app')
logger.with_timing(label: 'index_repo') { index_repo('app') }
```

## Files & Locations
- Engine/Hubs write to `logs/<service>.log`
- Boot writes to `logs/engine_boot.log`
- Multiplexer writes to `logs/multiplexer.log`

## Slow Operation Flag
`with_timing(label:)` records duration and flags operations exceeding `ENV['SLOW_THRESHOLD_MS']`.

## Notes
- Keep payloads small and consistent; prefer explicit `event:` keys.
- Use `json: true` for machine-friendly output; CLI tools print human context as needed.

