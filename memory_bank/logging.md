# Logging & Observability

## Overview
Structured JSON logging with levels, per-service files, and simple metrics. Optimized for CLI and long-running MCP processes. Engines can also dual-write logs to MongoDB for centralized timelines.

## Key Files
- `lib/savant/logging/logger.rb` – main logger (levels, timing helper)
- `lib/savant/logging/event_recorder.rb` – in-memory/file event storage
- `lib/savant/logging/metrics.rb` – counters/distributions
- `lib/savant/logging/audit/{policy,store}.rb` – audit logging hooks
- `lib/savant/logging/mongo_logger.rb` – optional MongoDB sink (writes to collection + stdout)

## Usage
```ruby
# File + stdout JSON
file_logger = Savant::Logging::Logger.new(io: $stdout, file_path: 'logs/service.log', level: 'info', json: true, service: 'context')
file_logger.info(event: 'scan_start', repo: 'app')
file_logger.with_timing(label: 'index_repo') { index_repo('app') }

# Mongo + stdout JSON (collection defaults to "<service>_logs")
mongo_logger = Savant::Logging::MongoLogger.new(service: 'personas', collection: 'personas')
mongo_logger.info(event: 'personas_list', count: 12)
```

## Files & Locations
- Engine/Hubs write to `logs/<service>.log`
- Boot writes to `logs/engine_boot.log`
- Multiplexer writes to `logs/multiplexer.log`
- When Mongo is available, MCP engines also write to Mongo collections (e.g., `personas`, `drivers`, `hub`).

## MongoDB
- Default DB names follow environment:
  - `SAVANT_ENV=test` → `savant_test`
  - otherwise → `savant_development`
- Configure connection via `MONGO_URI` (defaults to `mongodb://localhost:27017/<db>`)
- Quick console: `make mongosh` (respects `DB_ENV` → `savant_development` / `savant_test`)

## Slow Operation Flag
`with_timing(label:)` records duration and flags operations exceeding `ENV['SLOW_THRESHOLD_MS']`.

## Notes
- Keep payloads small and consistent; prefer explicit `event:` keys.
- Use `json: true` for machine-friendly output; CLI tools print human context as needed.
- When using Mongo, logs are also emitted to stdout for easy tailing.
