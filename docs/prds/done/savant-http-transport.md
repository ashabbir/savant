# PRD — Savant HTTP/REST Transport

## 📘 Overview
This PRD defines the addition of an **HTTP/REST Transport Layer** to the Savant framework, enabling external systems, tools, and MCP-compatible agents to interact with Savant engines over standard HTTP routes instead of stdio.

This module will allow tools registered inside Savant to be executed via simple HTTP POST requests, returning structured JSON-RPC–like responses.

---

## 🧩 Goal

Add a lightweight, Rack-compatible transport (e.g. Sinatra or Roda) that:
- Exposes `POST /rpc` endpoint for invoking tools.
- Preserves Savant’s JSON-RPC 2.0 message schema.
- Enables calling any registered tool (e.g. `context.index`, `jira.fetch`, `logger.log`) via HTTP.
- Supports both local and Cloud Run deployment.

---

## ⚙️ Scope

### **In Scope**
- Add `Savant::Transport::HTTP` module.
- Start HTTP server when `MCP_TRANSPORT=http` or via CLI flag.
- Handle JSON-RPC 2.0 requests: `{ "method": "tool/ns", "params": {...}, "id": <uuid> }`
- Return standard JSON-RPC response: `{ "result": {...}, "error": nil, "id": <uuid> }`
- Include health check at `/healthz` route.
- Configurable port via `SAVANT_PORT` (default 9292).
- Log all requests/responses through the framework logger.

### **Out of Scope**
- Authentication (future phase).
- Web UI / dashboard.
- Streaming responses.
- Async tool execution queue.

---

## 🧱 Technical Design

### 1. Directory Structure
```
lib/savant/
 ├── transport/
 │    ├── base.rb
 │    ├── http.rb      # <-- new file
 │    └── stdio.rb
 └── server/
      └── http_runner.rb
```

### 2. HTTP Transport Implementation

```ruby
# lib/savant/transport/http.rb
require "sinatra/base"
require "json"

module Savant
  module Transport
    class HTTP < Sinatra::Base
      set :port, ENV.fetch("SAVANT_PORT", 9292)
      set :bind, "0.0.0.0"

      post "/rpc" do
        content_type :json
        payload = JSON.parse(request.body.read)
        method = payload["method"]
        params = payload["params"] || {}
        id     = payload["id"]

        result = Savant::Engine.call_tool(method, params)
        { result: result, error: nil, id: id }.to_json
      rescue => e
        status 500
        { result: nil, error: e.message, id: id }.to_json
      end

      get "/healthz" do
        content_type :json
        { status: "ok", service: "savant-http" }.to_json
      end
    end
  end
end
```

---

### 3. Engine Hook

```ruby
# lib/savant/server/http_runner.rb
require "savant/transport/http"

module Savant
  module Server
    class HTTPRunner
      def self.start
        Savant.logger.info "🚀 Starting Savant HTTP Transport on port #{ENV.fetch('SAVANT_PORT', 9292)}"
        Savant::Transport::HTTP.run!
      end
    end
  end
end
```

---

### 4. CLI Integration
```ruby
# bin/savant
when "serve"
  transport = ENV.fetch("MCP_TRANSPORT", "stdio")
  if transport == "http"
    require "savant/server/http_runner"
    Savant::Server::HTTPRunner.start
  else
    Savant::Server::STDIO.start
  end
end
```

---

## 🧪 Testing

### 1. Unit Tests
- `spec/transport/http_spec.rb`
  - Handles valid JSON-RPC call.
  - Returns correct response body and code.
  - Handles invalid JSON gracefully.
  - Responds to `/healthz`.

### 2. Manual Test (Curl)
```bash
curl -X POST http://localhost:9292/rpc   -H "Content-Type: application/json"   -d '{"method":"logger.log","params":{"message":"Hello"},"id":1}'
```

Expected response:
```json
{"result":{"ok":true},"error":null,"id":1}
```

---

## 📦 Deliverables

| Item | Description | Status |
|------|--------------|--------|
| `lib/savant/transport/http.rb` | Sinatra-based HTTP transport | ⏳ |
| `lib/savant/server/http_runner.rb` | CLI runner for HTTP mode | ⏳ |
| `spec/transport/http_spec.rb` | RSpec coverage | ⏳ |
| Update `README.md` | Add HTTP usage docs | ⏳ |

---

## 📘 Documentation Update

Add section to `README.md`:

```
### HTTP Transport

To start Savant in HTTP mode:
```bash
MCP_TRANSPORT=http bundle exec ruby bin/savant serve
```

Then call:
```bash
curl -X POST http://localhost:9292/rpc   -H "Content-Type: application/json"   -d '{"method":"logger.log","params":{"msg":"Hello"},"id":1}'
```
```

---

## 🧩 Future Enhancements
- Add token-based auth header (JWT).
- Support multipart/form-data for file uploads.
- Streaming output for long-running tools.
- OpenAPI spec auto-generation from tool registry.

---

## 📅 Estimated Effort
| Task | Owner | Estimate |
|------|--------|----------|
| HTTP transport module | Backend | 1 day |
| CLI integration | Backend | 0.5 day |
| RSpec coverage | Backend | 0.5 day |
| Docs update | DevRel | 0.5 day |

**Total:** ~2.5 days

---

## ✅ Acceptance Criteria
- [x] Savant runs in HTTP mode with `MCP_TRANSPORT=http`.
- [x] `/rpc` endpoint executes tools and returns JSON-RPC 2.0 format.
- [x] `/healthz` returns `{status: "ok"}`.
- [x] Logger records each call.
- [x] Unit tests pass.
- [x] Documented in README.

---

## Agent Implementation Plan

- [x] Implement lightweight Rack HTTP transport (no new heavy deps).
- [x] Implement `Savant::Transport` base, stdio shim, and new HTTP transport.
- [x] Create `Savant::Server::HTTPRunner` with logging/startup wiring.
- [x] Extend `bin/savant` with `serve` command honoring `MCP_TRANSPORT` and env port.
- [x] Cover HTTP transport with RSpec (success, error, health check).
- [x] Document HTTP usage and curl example in README.

---

**Author:** Ahmed Shabbir  
**Project:** Savant  
**Version:** v1.0 HTTP Transport  
**Date:** 2025-10-25
