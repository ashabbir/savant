# PRD --- Savant MCP Multiplexer (MVP-Critical)

**Owner:** Amd\
**Status:** ACTIVE\
**Priority:** P0\
**Purpose:** Provide a unified tool surface across all Savant engines
with minimal complexity.

------------------------------------------------------------------------

# 1. Purpose

The current Savant architecture runs **one MCP engine per process**.\
MVP requires a unified MCP interface that merges all tools across all
engines into a single clean tool registry with minimal complexity.

------------------------------------------------------------------------

# 2. Design Principles

## 2.1 Keep It Clean

-   No magical dynamic loading\
-   No deep orchestration\
-   No unnecessary complexity\
-   Engines remain independent\
-   Multiplexer only routes, merges, and monitors

## 2.2 Keep Backward Complexity Low

-   No unnecessary abstractions\
-   Only add complexity when strictly required\
-   Keep naming, routing, and processes simple

## 2.3 Developer-First Readability

Any engineer should understand this module in under 10 minutes.

------------------------------------------------------------------------

# 3. Problem Statement

Agents currently cannot call tools across engines through a single MCP
interface.\
The agent runtime cannot operate without a unified tool layer.

------------------------------------------------------------------------

# 4. Goals

1.  Mount multiple MCP engines\
2.  Merge their tools into a unified registry\
3.  Route calls to the correct engine\
4.  Provide one stdio/SSE interface\
5.  Maintain minimal complexity\
6.  Update memory bank + README

------------------------------------------------------------------------

# 5. Features & Requirements

## 5.1 Engine Mounting

Child process per engine using simple process management.\
If engine fails → mark offline.

## 5.2 Tool Registry

Namespace tools per engine:

    context.fts.search
    jira.issue.get
    rules.get
    personas.get
    think.plan

## 5.3 Routing Layer

Route calls to correct engine based on namespace.

## 5.4 SSE Support (Minimal)

Add SSE only if needed.\
Avoid building a heavy streaming server.

## 5.5 Failure Handling

If an engine dies: - Remove its tools\
- Continue running\
- Log incident

## 5.6 Integration with Boot Runtime

Multiplexer injected into:

    Savant::Runtime.current.multiplexer

## 5.7 Logging

`logs/multiplexer.log`\
Log: - boot - engine status - routing - failures

------------------------------------------------------------------------

# 6. Deliverables

-   `lib/savant/multiplexer.rb`
-   `lib/savant/multiplexer/engine_process.rb`
-   `lib/savant/multiplexer/router.rb`
-   Updated **memory bank**
-   Updated **README**
-   CLI commands:
    -   `savant tools`
    -   `savant engines`

------------------------------------------------------------------------

# 7. Non-Goals

❌ Hot swapping engines\
❌ Remote MCP routing\
❌ Plugin system\
❌ Multi-agent orchestrator

------------------------------------------------------------------------

# 8. Success Criteria

-   Single MCP interface exposing all tools\
-   Clean namespaced registry\
-   Route calls correctly\
-   Minimal complexity\
-   README + Memory Bank updated

------------------------------------------------------------------------

# 9. Risks

-   Engine crashes\
-   Over-engineering\
-   SSE complexity

Mitigation: keep everything minimal.

------------------------------------------------------------------------

# 10. Technical Notes

File layout:

    lib/savant/multiplexer.rb
    lib/savant/multiplexer/engine_process.rb
    lib/savant/multiplexer/router.rb
    logs/multiplexer.log
