# PRD --- Transport Architecture Cleanup

**Owner:** Amd\
**Status:** ACTIVE\
**Priority:** P2\
**Purpose:** Eliminate confusing dual transport directory structure and clarify
separation between HTTP and MCP protocol layers.

------------------------------------------------------------------------

# 1. Purpose

Savant currently has two separate transport directories (`transport/` and
`transports/`) serving different purposes, creating confusion and
architectural ambiguity.\
This PRD defines a clean reorganization that makes the codebase easier to
understand and maintain.

------------------------------------------------------------------------

# 2. Design Principles

## 2.1 Clarity Over Convention

-   One directory for all transport implementations\
-   Clear naming that reflects purpose\
-   No duplicate file names across directories

## 2.2 Separation of Concerns

-   Core service loading (ServiceManager) is NOT transport-specific\
-   HTTP transports separate from MCP transports\
-   Shared infrastructure at top level

## 2.3 Developer-First Organization

Any engineer should understand the transport layer structure in under
5 minutes.

------------------------------------------------------------------------

# 3. Problem Statement

## Current Issues

1.  **Confusing directory names**: `transport/` (singular) vs `transports/`
    (plural)
2.  **Duplicate file names**: Two different `stdio.rb` files doing
    completely different things
3.  **Misplaced shared code**: `ServiceManager` lives in
    `transport/base.rb` but it's core infrastructure, not
    transport-specific
4.  **Unclear boundaries**: Not obvious which transport system to use or
    modify

## Current Structure

    lib/savant/
    ├── transport/              # HTTP/Web server (legacy)
    │   ├── base.rb            # ServiceManager (shared!)
    │   ├── http.rb            # HTTP transport
    │   └── stdio.rb           # 15-line helper module
    │
    └── transports/             # MCP protocol
        ├── stdio.rb           # MCP stdio transport (105 lines)
        └── websocket.rb       # MCP websocket transport

------------------------------------------------------------------------

# 4. Goals

1.  Single `transports/` directory for all transport implementations
2.  Move `ServiceManager` to top-level (transport-agnostic)
3.  Eliminate duplicate `stdio.rb` file names
4.  Clear separation between HTTP and MCP transports
5.  Update all require statements (4 files affected)
6.  Zero behavior changes—pure refactor

------------------------------------------------------------------------

# 5. Proposed Architecture

## 5.1 New Structure

    lib/savant/
    ├── service_manager.rb          # Core engine loading (was transport/base.rb)
    │
    └── transports/                 # Single source of truth
        ├── http/
        │   ├── rack_app.rb        # Rack application (was transport/http.rb)
        │   └── runner.rb          # HTTP server runner
        │
        └── mcp/                    # MCP protocol transports
            ├── stdio.rb           # MCP stdio transport (unchanged)
            └── websocket.rb       # MCP websocket transport (unchanged)

## 5.2 What Gets Deleted

-   `lib/savant/transport/base.rb` → moved to `service_manager.rb`
-   `lib/savant/transport/http.rb` → moved to `transports/http/rack_app.rb`
-   `lib/savant/transport/stdio.rb` → **deleted** (unused 15-line helper)
-   `lib/savant/transport/` directory → **removed**

## 5.3 Files Requiring Updates

### Require Statement Changes

1.  `lib/savant/hub.rb:7`\
    **Before:** `require_relative 'transport/base'`\
    **After:** `require_relative 'service_manager'`

2.  `lib/savant/server/http_runner.rb:9-10`\
    **Before:**
    ```ruby
    require_relative '../transport/base'
    require_relative '../transport/http'
    ```
    **After:**
    ```ruby
    require_relative '../service_manager'
    require_relative '../transports/http/rack_app'
    ```

3.  `lib/savant/mcp_server.rb:10-11` (path change)\
    **Before:**
    ```ruby
    require_relative 'transports/stdio'
    require_relative 'transports/websocket'
    ```
    **After:**
    ```ruby
    require_relative 'transports/mcp/stdio'
    require_relative 'transports/mcp/websocket'
    ```

4.  `spec/savant/transport/http_spec.rb:6`\
    **Before:** `require_relative '../../../lib/savant/transport/http'`\
    **After:** `require_relative '../../../lib/savant/transports/http/rack_app'`

### Module/Class Name Changes

-   `Savant::Transport::ServiceManager` → `Savant::ServiceManager`
-   `Savant::Transport::HTTP` → `Savant::Transports::HTTP::RackApp`
-   `Savant::Transports::Stdio` → `Savant::Transports::MCP::Stdio`
-   `Savant::Transports::WebSocket` → `Savant::Transports::MCP::WebSocket`

------------------------------------------------------------------------

# 6. Migration Plan

## Phase 1: Create New Structure (Parallel)

1.  Create `lib/savant/service_manager.rb`
    -   Copy from `transport/base.rb`
    -   Change module from `Savant::Transport` to `Savant`

2.  Create `lib/savant/transports/http/` directory
    -   Move `transport/http.rb` → `transports/http/rack_app.rb`
    -   Update module namespace

3.  Create `lib/savant/transports/mcp/` directory
    -   Move `transports/stdio.rb` → `transports/mcp/stdio.rb`
    -   Move `transports/websocket.rb` → `transports/mcp/websocket.rb`
    -   Update module namespaces

## Phase 2: Update References

1.  Update all `require_relative` statements (4 files)
2.  Update all class/module references
3.  Run test suite to verify

## Phase 3: Cleanup

1.  Delete `lib/savant/transport/` directory
2.  Delete old `lib/savant/transports/stdio.rb` (after move)
3.  Delete old `lib/savant/transports/websocket.rb` (after move)

------------------------------------------------------------------------

# 7. Deliverables

-   [ ] New `lib/savant/service_manager.rb`
-   [ ] New `lib/savant/transports/http/rack_app.rb`
-   [ ] New `lib/savant/transports/http/runner.rb` (if HTTP logic extracted)
-   [ ] Moved `lib/savant/transports/mcp/stdio.rb`
-   [ ] Moved `lib/savant/transports/mcp/websocket.rb`
-   [ ] Updated require statements in 4 files
-   [ ] Deleted `lib/savant/transport/` directory
-   [ ] All tests passing
-   [ ] Update memory bank with new architecture

------------------------------------------------------------------------

# 8. Non-Goals

❌ Changing transport behavior or logic\
❌ Adding new transport types\
❌ Refactoring ServiceManager internals\
❌ Performance improvements\
❌ New features

------------------------------------------------------------------------

# 9. Success Criteria

-   ✅ Single `transports/` directory containing all transports
-   ✅ No duplicate file names (`stdio.rb` only exists once)
-   ✅ ServiceManager at top level as `Savant::ServiceManager`
-   ✅ Clear HTTP vs MCP separation
-   ✅ All tests passing
-   ✅ Zero behavior changes
-   ✅ Developer can understand transport structure in < 5 minutes

------------------------------------------------------------------------

# 10. Risks & Mitigation

## Risks

-   Breaking existing code that references old paths
-   Merge conflicts if other work in progress
-   Missing hidden dependencies

## Mitigation

-   Use grep to find ALL references before changing
-   Run full test suite after each phase
-   Keep git history clean (move operations preserve history)
-   Consider doing this in a feature branch

------------------------------------------------------------------------

# 11. Technical Notes

## Why ServiceManager Belongs at Top Level

`ServiceManager` is not transport-specific. It's core infrastructure that:
-   Loads MCP engines (context, jira, rules, etc.)
-   Manages tool registries
-   Handles tool calls

Both HTTP and MCP transports use it, so it belongs at
`lib/savant/service_manager.rb`.

## File Size Reference

-   `transport/base.rb` (ServiceManager): 156 lines
-   `transport/http.rb`: ~100 lines
-   `transport/stdio.rb`: 15 lines (unused helper, safe to delete)
-   `transports/stdio.rb`: 105 lines (active MCP transport)
-   `transports/websocket.rb`: ~150 lines

## Testing Strategy

Run existing test suite:
```bash
bundle exec rspec spec/savant/transport/http_spec.rb
# (update path after refactor)
```

------------------------------------------------------------------------

# 12. Future Considerations

After this cleanup, adding new transports becomes clearer:

-   gRPC transport → `transports/grpc/`
-   GraphQL transport → `transports/graphql/`
-   New MCP transport → `transports/mcp/new_transport.rb`

The architecture will scale naturally.
