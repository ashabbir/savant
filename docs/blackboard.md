# Savant Blackboard — Developer Guide

The Blackboard is Savant’s universal, append‑only coordination layer. All meaningful activity across humans, agents, councils, workflows, and workers is represented as immutable events in MongoDB and fanned out over Redis. UIs and services project from this source of truth.

If it didn’t go through the Blackboard, it didn’t happen.

- PRD: docs/prds/blackboard.md (Approved — Architecture Locked)
- API: implemented in Rails under `server/app/controllers/blackboard_controller.rb`
- Models: `server/app/models/blackboard/{session,event,artifact}.rb`
- Routes: `server/config/routes.rb` (`/blackboard/*`)
- UI Explorer: `/engine/blackboard` and `/engine/blackboard/sessions/:id`

## Overview

- Truth store: MongoDB (Mongoid models)
- Delivery: Redis pub/sub (fan‑out to workers, agents, UI)
- Replay: any client can reconstruct context for a session via GET `/blackboard/events` (deterministic reasoning)
- Immutability: events and artifacts are append‑only
- Separation: reasoning = compute; Blackboard = state

## Core Entities

Session

```json
{
  "session_id": "uuid",
  "type": "chat | council | workflow",
  "actors": ["actor_id"],
  "state": "active | paused | completed",
  "metadata": {}
}
```

Event (authoritative record)

```json
{
  "event_id": "uuid",
  "session_id": "uuid",
  "type": "string",
  "actor_id": "uuid",
  "actor_type": "human | agent | system | worker",
  "visibility": "public | agent_only | private",
  "parent_event_id": "uuid | null",
  "payload": {},
  "created_at": "timestamp",
  "version": 1
}
```

Artifact (immutable output referenced by events)

```json
{
  "artifact_id": "uuid",
  "type": "message | opinion | summary | diff | json",
  "content_ref": "file:// | s3:// | inline",
  "produced_by": "actor_id",
  "metadata": {}
}
```

Indexes

- Events: `{ event_id: 1 } (unique)`, `{ session_id: 1, created_at: 1 }`
- Sessions: `{ session_id: 1 } (unique)`
- Artifacts: `{ artifact_id: 1 } (unique)`

## API Summary

- POST `/blackboard/sessions` → create session
- POST `/blackboard/events` → append event
- GET `/blackboard/events?session_id=<id>` → replay timeline (ascending)
- GET `/blackboard/events/recent?limit=<n>` → recent events across all sessions (descending)
- GET `/blackboard/subscribe[?session_id=<id>]` → SSE stream of events
- POST `/blackboard/artifacts` → create artifact
- GET `/blackboard/artifacts/:id` → fetch artifact
- GET `/blackboard/stats` → counts (sessions, events, artifacts)

Strong params require nested keys: `{"session":{...}}`, `{"event":{...}}`, `{"artifact":{...}}`.

## Quickstart (Local)

Requirements

- MongoDB: `MONGODB_URI` (Hub also reads this; falls back to `MONGO_URI`) (default `mongodb://localhost:27017/savant_development`)
- Redis: `REDIS_URL` (default `redis://localhost:6379/0`)
- Rails server: `make dev-server` (defaults to `http://localhost:9999`)

Smoke test

```bash
BASE=${BASE:-http://localhost:9999}

# Health and stats
curl -s $BASE/healthz
curl -s $BASE/blackboard/stats

# Create a session
SID="sess-demo-$(date +%s)"
curl -s -X POST $BASE/blackboard/sessions -H 'Content-Type: application/json' \
  -d '{"session":{"session_id":"'"$SID"'","type":"chat"}}'

# Append an event
curl -s -X POST $BASE/blackboard/events -H 'Content-Type: application/json' \
  -d '{"event":{"session_id":"'"$SID"'","type":"message_posted","actor_id":"u1","actor_type":"human","payload":{"text":"hello"}}}'

# Replay
curl -s "$BASE/blackboard/events?session_id=$SID"

# SSE (open second terminal)
curl -N "$BASE/blackboard/subscribe?session_id=$SID"
```

Artifacts

```bash
AID="art-$(date +%s)"
curl -s -X POST $BASE/blackboard/artifacts -H 'Content-Type: application/json' \
  -d '{"artifact":{"artifact_id":"'"$AID"'","type":"message","content_ref":"inline","produced_by":"u1","metadata":{"text":"hello copy"}}}'
curl -s $BASE/blackboard/artifacts/$AID

# Event referencing the artifact
curl -s -X POST $BASE/blackboard/events -H 'Content-Type: application/json' \
  -d '{"event":{"session_id":"'"$SID"'","type":"result_emitted","actor_id":"agent-1","actor_type":"agent","payload":{"artifact_id":"'"$AID"'"}}}'
```

## Redis Channels

- Global: `blackboard:events` (payload: `{ event_id, session_id, type }`)
- Per session: `blackboard:session:<session_id>:events` (payload: `{ event_id, type }`)

Events are always persisted first (Mongo) and then published (Redis). Missed pub/sub messages can be recovered by replaying the timeline from Mongo.

## Worker Integration Pattern

1) Subscribe to Redis (`blackboard:events` or session‑scoped channel)
2) On message, fetch the full session timeline via `GET /blackboard/events?session_id=...`
3) Run reasoning/compute; produce artifact(s) if needed
4) Append a new event referencing any artifacts

Ruby sketch

```ruby
require 'redis'
require 'net/http'
require 'json'

base = ENV['BASE'] || 'http://localhost:9999'
redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))

redis.subscribe('blackboard:events') do |on|
  on.message do |_ch, msg|
    data = JSON.parse(msg)
    sid = data['session_id']
    timeline = JSON.parse(Net::HTTP.get(URI("#{base}/blackboard/events?session_id=#{sid}")))
    # ...reason over timeline...
    # POST a new event or artifact as appropriate
  end
end
```

Browser SSE (UI) example

```js
const source = new EventSource(`/blackboard/subscribe?session_id=${sid}`)
source.onmessage = (e) => {
  const evt = JSON.parse(e.data)
  // Update projections/UI with evt
}
```

## Event Taxonomy (v1)

- Chat: `message_posted`, `context_attached`
- Council: `council_started`, `round_started`, `opinion_submitted`, `rebuttal_submitted`, `synthesis_requested`, `synthesis_completed`
- Workflow: `step_started`, `step_completed`, `step_failed`, `branch_taken`, `workflow_completed`
- Execution: `agent_invoked`, `tool_call_requested`, `tool_call_completed`, `result_emitted`, `error_raised`

## Operations

- Env vars: `MONGODB_URI`, `REDIS_URL`
- Health: `GET /healthz`
- Stats: `GET /blackboard/stats`
- Logs: Rails logs under `server/log/`; Redis pub/sub visible via any Redis CLI

SSE guardrails

- `BLACKBOARD_SSE_ENABLED` (default `1`): set to `0` to disable `/blackboard/subscribe` temporarily (returns `503`).
- `BLACKBOARD_SSE_MAX` (default `RAILS_MAX_THREADS - 4`, typically `12`): caps concurrent SSE connections. Excess receives `429 Too Many Requests` with `Retry-After: 5`.
- `BLACKBOARD_SSE_MAX_SECONDS` (default `300`): max duration in seconds for a single SSE connection before the server unsubscribes to free resources.

Operational notes

- Each SSE client consumes a Rails/Puma thread. Keep `RAILS_MAX_THREADS` high enough or run multiple Puma workers to avoid starvation.
- If clients hit 429, fall back to replay polling until a slot frees up.
- Prefer per‑session subscriptions over a global firehose in high‑traffic environments.

Polling guidance

- For per‑session timelines, poll `GET /blackboard/events?session_id=<id>` every 1–5s.
- For global diagnostics, poll `GET /blackboard/events/recent?limit=200` every 2–5s.

Reasoning jobs contract

- Queue: workers pull jobs from `savant:queue:reasoning` (Redis list).
- Result: write to `savant:result:<job_id>` as either:
  - string value (e.g., `SET`), or
  - list push (e.g., `RPUSH`) for BLPOP compatibility.
- Client behavior: Savant polls GET on `savant:result:<job_id>` with a short BLPOP probe first, so both result strategies are supported.

Callbacks integration

- Reasoning worker should POST results to `/callbacks/reasoning/agent_intent`.
- The hub mirrors each callback to the Blackboard by appending an `agent_intent` event to the session `council-<session_id>` (derived from the callback `correlation_id`).
- UIs can refresh chat state by polling `GET /blackboard/events?session_id=council-<id>`.

Resilience

- Redis outage: recover by replaying from Mongo
- Worker/UI restart: resubscribe to Redis; deterministic resume via replay
- Append‑only model eliminates partial/mutating state

## Security & Visibility

- `visibility`: `public | agent_only | private` — enforce audience in clients
- Do not place sensitive secrets in event payloads; prefer external `content_ref` for large blobs
- Authentication/authorization are out of scope at the Blackboard layer (apply at edges/clients or fronting proxy)

## Testing

- Controller tests: `server/test/controllers/blackboard_controller_test.rb`
- Model tests: `server/test/models/blackboard/*`
- Run from `server/`: `bundle install && bin/rails test test/controllers/blackboard_controller_test.rb`

## Design Law

Blackboard is the system. Everything else is a client.
