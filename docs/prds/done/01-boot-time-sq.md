# PRD --- Savant Boot Runtime (Critical Path for MVP)

**Owner:** Amd\
**Status:** ACTIVE\
**Priority:** P0 --- *Everything else depends on this.*\
**Target:** This week

------------------------------------------------------------------------

# 1. Purpose

The Boot Runtime is the **core initializer** for the Savant Engine.\
It prepares everything required for any agent, workflow, or multiplexer
to function.

Without this module, the Engine cannot run agents, select tools, perform
MR review, or initialize workflows.

This is the **first mandatory component** for finishing the Savant
Engine MVP.

------------------------------------------------------------------------

# 2. Problem Statement

Current Savant codebase has: - engines (context, jira, personas, rules,
think) - indexer - MCP stdio server - workflows

But it does **not** have: - unified runtime - unified boot flow -
persona loading - AMR loading - driver prompt loading - global session
memory - repo context loading - CLI entrypoint to run agents

Agents cannot operate without a structured runtime container.

------------------------------------------------------------------------

# 3. Goals

## 3.1 Initialize the Engine

Load the core ingredients needed by **every** agent: - Persona\
- Driver prompt\
- AMR ruleset\
- Repo context\
- Memory store\
- Session ID\
- Logging

## 3.2 Provide Global Runtime Object

Expose a canonical runtime:

    Savant::Runtime.current

## 3.3 Provide CLI Boot

Allow commands:

    savant run
    savant review
    savant workflow

All commands must pass through the boot runtime.

------------------------------------------------------------------------

# 4. Features & Requirements

## 4.1 Persona Loader

**Requirements** - Load default persona (e.g., `savant-engineer`) from
personas engine - Provide structured persona object (name, version,
prompt_md)

**Acceptance Criteria** - `Savant::Runtime.current.persona` returns
persona hash - Error if persona not found

------------------------------------------------------------------------

## 4.2 Driver Prompt Loader

**Requirements** - Load Think engine's canonical driver prompt -
Validate version - Store in runtime

**Acceptance Criteria** - `Savant::Runtime.current.driver_prompt`
returns full markdown

------------------------------------------------------------------------

## 4.3 AMR Loader

**Requirements** - Load AMR (Ahmed Matching Rules) from YAML - Provide
internal rule-matching API - Missing file should error with helpful
message

**Acceptance Criteria** - `Savant::Runtime.current.amr_rules` returns
parsed ruleset

------------------------------------------------------------------------

## 4.4 Repo Context Loader

**Requirements** - Detect current repo (git) - Store path + metadata -
Store branch + last commit (optional in phase 1)

**Acceptance Criteria** - `Savant::Runtime.current.repo` returns valid
repo object or nil

------------------------------------------------------------------------

## 4.5 Session Memory

**Requirements** - Create `.savant/` directory in project root -
Maintain: - session_id - ephemeral memory hash (in-RAM) - persistent
memory file: `.savant/runtime.json`

**Acceptance Criteria** - All boot sessions generate UUID - Memory
persists between calls unless reset

------------------------------------------------------------------------

## 4.6 Logging Layer Integration

**Requirements** - Integrate `Savant::Logger` - Boot logs must
include: - session ID\
- persona name\
- driver version\
- repo path

**Acceptance Criteria** - `logs/engine_boot.log` created automatically

------------------------------------------------------------------------

## 4.7 RuntimeContext Class

**Requirements** Define struct-like class:

    Savant::RuntimeContext = Struct.new(
      :session_id,
      :persona,
      :driver_prompt,
      :amr_rules,
      :repo,
      :memory,
      :logger,
      :multiplexer,
      keyword_init: true
    )

**Acceptance Criteria** - Must be accessible globally as
`Savant::Runtime.current`

------------------------------------------------------------------------

## 4.8 CLI Integration

**Requirements** Create CLI commands:

    bin/savant run
    bin/savant review
    bin/savant workflow

All commands: - call Boot Runtime - receive RuntimeContext instance -
print error if boot fails

**Acceptance Criteria** - Running any command displays boot
diagnostics - CLI available globally via `bundle exec savant`

------------------------------------------------------------------------

# 5. Non-Goals (for this PRD)

❌ Agent runtime loop\
❌ MR review logic\
❌ Git diff engine\
❌ Workflow execution\
❌ Multiplexer routing\
❌ Model selection

These all depend on Boot Runtime.

------------------------------------------------------------------------

# 6. Success Criteria

Boot Runtime is complete when:

-   `savant run` starts and loads:
    -   persona\
    -   driver prompt\
    -   AMR\
    -   session memory\
    -   repo context
-   RuntimeContext is populated and accessible\
-   Logs print boot sequence\
-   CLI runs without errors\
-   `.savant/runtime.json` exists after boot

This completes the **foundation of the MVP**.

------------------------------------------------------------------------

# 7. Risks

-   Missing persona or AMR could block runtime\
-   Boot errors could break all commands\
-   Multi-engine integration later could require RuntimeContext updates\
-   Requires careful path management (`SAVANT_PATH`)

------------------------------------------------------------------------

# 8. Technical Notes

### File layout:

    lib/savant/boot.rb
    lib/savant/runtime_context.rb
    lib/savant/amr/ rules.yml
    bin/savant
    .savant/runtime.json

Boot runtime must run before **any** engine or agent loads.
