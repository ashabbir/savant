# Savant Reasoning API (LangChain/LangGraph Gateway)

This service exposes intent endpoints used by Savant to decouple agent/workflow reasoning from tool execution. The Agent Runtime requires the Reasoning API for decisions.

- Endpoints: `POST /agent_intent`, `POST /workflow_intent`, `GET /healthz`
- Version: v1 (via `Accept-Version` header)

## Setup

- Create a Python venv and install dependencies:
  - `make reasoning-setup`
- Run the API locally:
  - `make reasoning-api`
  - Service listens on `127.0.0.1:9000` by default.

## Wire Ruby → API

Set environment variables for the Savant process (Hub/MCP):

- `REASONING_API_URL`: e.g. `http://127.0.0.1:9000`
- `REASONING_API_TOKEN`: optional bearer token
- `REASONING_API_TIMEOUT_MS`: default 5000
- `REASONING_API_RETRIES`: default 2

`Savant::Agent::Runtime` always routes step decisions through the Reasoning API. Local SLM/LLM fallbacks are no longer used.

## Contract Schema

Reference `config/reasoning_api_schema.json` for request/response shapes. Minimal examples:

- Agent request:
  ```json
  {"session_id":"s1","persona":{},"goal_text":"search project for TODOs"}
  ```
- Agent response:
  ```json
  {"status":"ok","intent_id":"agent-1","tool_name":"context.fts_search","tool_args":{"query":"search project for TODOs"},"finish":false}
  ```

## Troubleshooting

- Timeouts: Increase `REASONING_API_TIMEOUT_MS` or investigate server logs.
- Invalid tools: The client validates tool names against the Multiplexer; adjust graph/chain or enable a valid engine.
- Health: `curl http://127.0.0.1:9000/healthz` should return `{ "status": "ok" }`.
