# Savant Reasoning Worker Flow

This directory contains the core logic for the **Reasoning Worker**, a standalone Python service that processes agent intents using LLMs (Google Gemini or Ollama).

## Architecture Overview

The reasoning system follows a distributed, asynchronous architecture using **Redis** as the message broker.

1. **Request**: A client (typically the Ruby `Savant::Council::Ops` engine) pushes a job JSON to the `savant:queue:reasoning` Redis list.
2. **Worker**: The `worker.py` process pops the job, validates it, and calls the reasoning API.
3. **LLM Execution**: `api.py` orchestrates the LLM call, formatting the prompt with personas, rules, and conversation history.
4. **Result**: The result is stored back in Redis (`savant:result:{job_id}`) and/or sent to a `callback_url`.

## Key Components

### `worker.py` (The Runner)

- **Queue Management**: uses `BLPOP` on `savant:queue:reasoning` for low-latency job pickup.
- **Job Tracking**: Registers itself in `savant:workers:registry` and tracks live jobs in `savant:jobs:running`.
- **Cancellation**: Periodically checks `savant:jobs:cancel:requested` to abort long-running tasks.
- **Diagnostics**: Records completions in `savant:jobs:completed` and failures in `savant:jobs:failed`.

### `api.py` (The Brain)

- **Prompt Engineering**: Constructs the system instructions from `Persona` and `Driver` markdown.
- **History Management**: Formats previous conversation turns into a clean chronological log for the LLM.
- **Tool Selection**: Uses a "Diversified Search" strategy to prevent the LLM from repeating failed searches.
- **Extraction**: Parses the raw LLM output (structured as `ACTION/RESULT/REASONING`) into a machine-readable `AgentIntentResponse`.

## LLM Calling Mechanism

The worker uses the `_compute_intent_sync` function which follows this flow:

1. **Preparation**: Filters available tools and prepares the goal text.
2. **Providers**:
   - **Google**: Direct REST calls to `generativelanguage.googleapis.com` for high-performance reasoning.
   - **Ollama**: Local execution via `langchain_community.llms` for private/offline usage.
3. **Prompt Structure**:

   ```text
   ## Persona
   {agent_description}
   
   ## Driver
   {core_directives}
   
   ## Previous Actions and Results
   1. tool search: {results...}
   
   Goal: {user_query}
   
   Respond with:
   ACTION: [tool_name | finish]
   RESULT: [args | answer]
   REASONING: [why]
   ```

4. **Tracing**: Captures `llm_input` (the exact prompt) and `llm_output` (the raw response) for debugging in the **Reasoning Diagnostics** UI.

## Diagnostics and Monitoring

You can monitor the workers via the Savant Hub under the **Diagnostics > Workers** tab.

- **Queued**: Jobs waiting in Redis.
- **Running**: Jobs currently being processed by a worker PID.
- **Recent Results**: Inspect the raw JSON, including the full LLM trace.
