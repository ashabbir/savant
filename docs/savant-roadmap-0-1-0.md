# PRD — Savant Engine MVP (v0.1.0)
**Product:** Savant Engine  
**Owner:** Amd  
**Goal:** Deliver a developer-first, local-first agent runtime with MCP multiplexer  
**Release Target:** 3.5 Weeks  
**Status:** ACTIVE

---

# 1. Purpose
The purpose of Savant Engine MVP is to deliver the minimum viable execution layer for running autonomous agents for developers — locally, securely, and fast.

This is **not** the full Savant Platform.  
This is the **core runtime** required to prove Savant’s category:

> **Agent Infrastructure Platform (AIP)** for developers.

The MVP is designed for:
- Early adopters  
- GitLab/GitHub devs  
- FinTech teams needing local security  
- Early community contributors  
- Fast GTM showing Savant is real

---

# 2. Problem Statement
Developers today lack:
- a local-agent runtime  
- secure on-device agent execution  
- a unified MCP router  
- real agent autonomy over codebases  
- composable workflows  
- predictable agent behavior via AMR  

There is **no agent OS for engineers**.  
Savant fills that gap.

---

# 3. MVP Objectives
### 1. Agents run locally  
### 2. Agents call tools via MCP  
### 3. Agents analyze repos  
### 4. Agents run a workflow  
### 5. Agents provide immediate developer value (MR Review Agent)

---

# 4. Target Users
**Primary:**  
- Backend engineers  
- Full-stack developers  
- Platform engineers  
- DevOps / FinTech engineers  

**Secondary:**  
- AI engineers  
- Data engineers  
- OSS tool builders  

---

# 5. Non-Goals (MVP)
❌ Savant Hub UI  
❌ Savant Cloud  
❌ Multi-agent supervisor  
❌ Plugin marketplace  
❌ CI/CD orchestration  
❌ Hosted environment  

---

# 6. Core Features (MVP)

## 6.1 Savant Boot Sequence
### Requirements
- Load Driver Prompt  
- Load AMR (Ahmed Matching Rules)  
- Load Persona Template  
- Initialize runtime + logging  
- Initialize local model adapter (Ollama)

### Acceptance Criteria
- `savant run` loads AMR + persona + driver  
- Boot errors logged cleanly  
- Minimal context initialized  

---

## 6.2 MCP Multiplexer (SSE + STDIO)
### Requirements
- Support STDIO + SSE  
- Mount multiple MCP servers  
- Auto-discover tools  
- Unified registry + call interface  

### Acceptance Criteria
- Mount 2+ MCPs  
- Tools discovered correctly  
- Agent can call any tool  
- Logs show routing  

---

## 6.3 Agent Runtime
### Requirements
- Reasoning loop  
- Tool selection engine  
- Error handling + retry  
- Session memory  
- End/stop logic  

### Acceptance Criteria
- Agent reasons → selects → calls tool → processes result  
- Can recover from bad calls  
- Structured logs  
- No infinite loops  

---

## 6.4 Git Integration
### Requirements
- Load repo  
- Read files  
- Read diffs  
- Extract changed lines  
- Provide repo context  

### Acceptance Criteria
- Git repo loads  
- Diffs extracted  
- Agent reads and uses context  

---

## 6.5 MR Review Agent (Killer Feature)
### Requirements
- Use Git diff  
- Analyze changes  
- Generate comments + summary  
- Use AMR rules  

### Acceptance Criteria
- `savant review` produces an MR review summary  
- Works with any repo  
- Comments are meaningful and specific  
- 100% local execution  

---

## 6.6 Workflow Engine (YAML)
### Requirements
- Load workflow.yaml  
- Execute steps sequentially  
- Pass output between steps  
- Support tool calls + agent calls  

### Acceptance Criteria
- Simple workflows run end-to-end  
- Failures logged clearly  
- Designed to be compatible with future Hub UI  

---

# 7. Technical Constraints
- Must run fully local  
- No cloud dependency  
- Must support Ollama  
- Must support MCP via STDIO + SSE  
- Ruby preferred (your strength)  
- Open-source friendly  

---

# 8. Release Definition
**MVP is complete when:**  
- Savant Engine can boot  
- Mount 2 MCP servers  
- Run MR Review agent  
- Execute YAML workflow  
- Produce structured logs  
- Passes manual tests on 3 repos  

---

# 9. Risks
- Runtime complexity  
- Tool-call stability  
- Git diff accuracy  
- Developer onboarding complexity  

---

# 10. Future (Post-MVP)
- Savant Hub UI  
- Savant Cloud  
- Agent marketplace  
- Multi-agent supervisor  
- Plugin system  
- Analytics + observability  
