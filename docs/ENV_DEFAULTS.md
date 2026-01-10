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

Reasoning Worker (Redis)
- REDIS_URL: default 'redis://localhost:6379/0'
- REASONING_TIMEOUT_MS: default 60000 (0 = wait indefinitely)
- REASONING_RETRIES: default 2 (reserved)

Agent Runtime
- AGENT_MAX_STEPS: default 25
- AGENT_ENABLE_WORKFLOW_AUTODETECT: default enabled (auto-detect workflow runs)
- AGENT_DISABLE_WORKFLOW_AUTODETECT: default unset; when '1', disables auto-detect
- SAVANT_QUIET: default unset; when '1', reduces stdout logging

LLM / Providers
- LLM_MODEL: default 'llama3:latest'
- OLLAMA_HOST: default 'http://127.0.0.1:11434'
- ANTHROPIC_API_KEY, OPENAI_API_KEY: unset by default
Notes:
- SLM_MODEL is deprecated and ignored by the Agent Runtime.

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
- Reasoning uses Redis exclusively; ensure `REDIS_URL` is reachable from the Hub and worker.
- Agent cancellation uses per‑run keys and checks before tools/LLM, so Stop is responsive. Tool engines may need cooperative cancel for long‑running calls.
- Council intent is always async; callbacks use COUNCIL_ASYNC_CALLBACK_URL or SAVANT_HUB_URL (base) to reach `/callbacks/reasoning/agent_intent`.
- For async Council intent callbacks, set COUNCIL_ASYNC_CALLBACK_URL or SAVANT_HUB_URL (base) so callbacks can reach `/callbacks/reasoning/agent_intent`.
- Council protocol role calls use COUNCIL_ROLE_TIMEOUT_MS (default 30000) before timing out.
