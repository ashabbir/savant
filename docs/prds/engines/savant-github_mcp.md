# Savant – GitHub MCP (MVP)

> Integrate GitHub API actions into the Savant MCP Framework  
> Purpose: Enable AI-driven workflows (PR reviews, issue automation, and repo introspection)

---

## 🧩 Overview

The **GitHub MCP** is a Machine-Callable Protocol (MCP) service within the Savant ecosystem.  
It exposes a structured toolset that allows AI agents and local developers to interact with GitHub repositories — fetching, commenting, and analyzing data — via standardized JSON-RPC calls.

This makes it possible for Savant workflows (e.g., code review, ticket validation, coverage checks) to seamlessly integrate with GitHub without hard-coding API logic.

---

## 🎯 MVP Goals

| Goal | Description |
|------|--------------|
| 🔗 Standardize GitHub integration | Replace ad-hoc API scripts with consistent MCP-based tools |
| 🤖 Enable AI review loops | Allow Cline / Claude / Copilot agents to analyze PRs contextually |
| 🧠 Improve automation | Provide reusable endpoints for PR checks, issue creation, and commits |
| ⚙️ Support self-hosted or cloud GitHub | Compatible with both github.com and enterprise instances |

---

## ⚙️ Scope (MVP)

| Category | Tools Included | Description |
|-----------|----------------|-------------|
| **Pull Requests** | `github/get_pr`, `github/comment_pr` | Fetch and comment on PRs |
| **Issues** | `github/create_issue` | Allow AI or user to open an issue |
| **Repositories** | `github/get_repo`, `github/list_commits` | Fetch repo metadata or commit history |
| **Files** | `github/get_file` | Retrieve file content for context |
| **Search** | `github/search_code` | Search within repo for keyword/snippet matches |

---

## 🔐 Auth

---

## Acceptance + TDD TODO (Compact)
- Criteria: MVP tools operational (PRs, Issues, Repo, Files, Search); auth works for GH.com/Enterprise; JSON-RPC tools exposed; basic error handling.
- TODO:
  - Red: specs for each tool contract and auth flows.
  - Green: implement tool handlers and GitHub client; wire to registrar.
  - Refactor: pagination, rate limit handling; docs and examples.

Use a GitHub Personal Access Token (PAT) scoped for `repo`, `read:org`, and `user:email`.  
Stored securely in `.env` or Savant’s secrets store.

```
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxx
```

All tool handlers use:
```ruby
HTTP.auth("Bearer #{ENV['GITHUB_TOKEN']}")
```

---

## 🧠 Tool Registry (DSL Definition)

Each tool follows Savant’s MCP DSL standard:

### Example — `github/get_pr`
```ruby
tool 'github/get_pr' do
  input do
    {
      owner: String,
      repo: String,
      pr_number: Integer
    }
  end

  output do
    {
      title: String,
      body: String,
      files: Array,
      comments: Array
    }
  end

  handler do |ctx, input|
    url = "https://api.github.com/repos/#{input[:owner]}/#{input[:repo]}/pulls/#{input[:pr_number]}"
    pr = HTTP.auth("Bearer #{ENV['GITHUB_TOKEN']}").get(url).parse
    {
      title: pr['title'],
      body: pr['body'],
      files: pr['changed_files'],
      comments: pr['comments']
    }
  end
end
```

---

## 🧩 Integration Points

| System | Purpose |
|---------|----------|
| **Savant Corext** | Pulls PR and Issue data as part of context reasoning |
| **Cline** | Executes review or ticket automation using MCP calls |
| **Jira MCP** | Syncs ticket → PR → comment lifecycle |
| **Prompts MCP** | Triggers from code review prompts (`initial_code_review`) |

---

## 🧱 Directory Structure

```
lib/savant/github/
 ├── engine.rb        # Registers the engine + shared ctx
 ├── tools.rb         # Tool definitions
 ├── client.rb        # Wrapper for API calls
spec/savant/github/
 ├── tools_spec.rb    # Unit tests for handlers
.env.example          # GITHUB_TOKEN placeholder
```

---

## 🧪 MVP Test Cases

| Scenario | Tool | Expected Output |
|-----------|------|----------------|
| Fetch PR metadata | `get_pr` | Returns title, body, comments |
| Comment on PR | `comment_pr` | Returns confirmation |
| Create issue | `create_issue` | Returns new issue URL |
| Fetch file | `get_file` | Returns file content |
| Search code | `search_code` | Returns file paths with matches |

---

## 🚀 Future Enhancements (Post-MVP)

| Feature | Description |
|----------|-------------|
| Webhook MCP | React to PR events automatically |
| Auto-Labeler | AI-generated PR labels |
| Reviewer MCP | Inline code comments using LLM |
| GitHub Actions bridge | Trigger workflows via MCP |
| PR Summary | Generate concise LLM-based summaries |

---

## 🧭 MVP Completion Definition

- ✅ Tools implemented and registered under `lib/savant/github/tools.rb`
- ✅ Auth via PAT working for public & private repos
- ✅ Basic unit tests pass
- ✅ Verified manually via `savant call github/get_pr` and `github/create_issue`
- ✅ Documentation in `/docs/mcp/github_mcp_prd.md`

---

## 📅 MVP Timeline (2 Weeks)

| Week | Milestone | Deliverable |
|------|------------|-------------|
| Week 1 | Setup & Tool Scaffolding | engine.rb, tools.rb, PAT auth |
| Week 2 | Testing & Integration | specs + Cline workflow validation |

---

**Owner:** Amd  
**Language:** Ruby  
**Framework:** Savant MCP  
**Version:** MVP-1.0  
**Status:** Draft (Ready for Implementation)
