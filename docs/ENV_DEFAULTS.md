Savant Environment Defaults

This document lists the environment variables recognized across the Savant stack and their code‑level defaults. You do not need to set these unless you want to override the defaults.

Core
- SAVANT_DEV: default '1' (development conveniences enabled)
- SAVANT_PATH: default to repo root (varies by entrypoint)
- SAVANT_LOG_PATH: default '/tmp/savant' for hub server logs
- LOG_LEVEL: default 'error' (some scripts use 'info' in docs)
- LOG_FORMAT: default 'json' for stdio transports
- SLOW_THRESHOLD_MS: default 2000 (marks slow ops in logger)

HTTP Servers
- SAVANT_HOST / LISTEN_HOST: default 0.0.0.0 (via hub_server)
- SAVANT_PORT / LISTEN_PORT: default 9999 (Hub HTTP)

Database (PostgreSQL)
- DATABASE_URL: optional; if not set, Rails uses config/database.yml
- PGHOST: default 'localhost'
- PGPORT: default 5432
- PGUSER / PGPASSWORD: unset by default

MongoDB (Telemetry/Logs/Queue)
- MONGO_URI: default 'mongodb://<MONGO_HOST>/<db>'
- MONGO_HOST: default 'localhost:27017'
- SAVANT_ENV / RACK_ENV / RAILS_ENV: default 'development'; test -> DB 'savant_test' else 'savant_development'

Reasoning API
- REASONING_API_URL: default 'http://127.0.0.1:9000'
- REASONING_API_TIMEOUT_MS: default 30000
- REASONING_API_RETRIES: default 2
- REASONING_API_VERSION: default 'v1'
- REASONING_TRANSPORT: default 'mongo' (use 'http' to force HTTP transport)
- REASONING_QUEUE_WORKER: default '1' (Reasoning service starts background worker)

Agent Runtime
- AGENT_MAX_STEPS: default 25
- AGENT_ENABLE_WORKFLOW_AUTODETECT: default disabled (Reasoning API used by default)
- AGENT_DISABLE_WORKFLOW_AUTODETECT / FORCE_REASONING_API: default unset; can force disable auto-detect
- SAVANT_QUIET: default unset; when '1', reduces stdout logging

LLM / Providers
- LLM_MODEL: default 'llama3:latest'
- OLLAMA_HOST: default 'http://127.0.0.1:11434'
- ANTHROPIC_API_KEY, OPENAI_API_KEY: unset by default
Notes:
- SLM_MODEL is deprecated and ignored by the Agent Runtime (decisions use the Reasoning API).

Jira (Engine)
- JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN, JIRA_USERNAME, JIRA_PASSWORD: unset by default (read via SecretStore when present)

Multiplexer / MCP Services
- MCP_SERVICE: default varies by entrypoint ('multiplexer' for HTTP server)
- MCP_TRANSPORT / TRANSPORT: default 'stdio' for multiplexer children

Rails (Server)
- RAILS_MAX_THREADS: default 3
- PORT (puma): default 3000
- PIDFILE: unset by default

Build/Release
- RELEASE_BASE_URL: default 'https://github.com/ashabbir/savant/releases/download'
- SAVANT_BUILD_SALT: default 'DEVELOPMENT_ONLY_CHANGE_ME' (builder script)

Secrets / Licensing (optional)
- SAVANT_ENC_KEY: master key for LLM registry encryption (unset by default)
- SAVANT_SECRET_SALT: unset by default; provide in production
- SAVANT_POLICY_PATH: default 'config/policy.yml'
- SAVANT_LICENSE_PATH / SAVANT_ENFORCE_LICENSE: unset by default

Notes
- Reasoning transport defaults to 'mongo' so cancel and queue processing work out of the box. Set REASONING_TRANSPORT=http to use direct HTTP for /agent_intent.
- Agent cancellation uses per‑run keys and checks before tools/LLM, so Stop is responsive. Tool engines may need cooperative cancel for long‑running calls.
- Council intent mode defaults to async; set COUNCIL_INTENT_MODE=sync to keep Council reasoning steps blocking.
- For async Council intent callbacks, set COUNCIL_ASYNC_CALLBACK_URL or SAVANT_HUB_URL (base) so callbacks can reach `/callbacks/reasoning/agent_intent`.
- Council protocol role calls use COUNCIL_ROLE_TIMEOUT_MS (default 30000) before timing out.
