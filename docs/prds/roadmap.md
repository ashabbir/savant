# SAVANT ENGINE — MASTER ROADMAP  
Author: Amd  
Purpose: Architecture & Long-Term Vision Project  
Focus: Developer-first, fast GTM, local-first agent platform

---

# 1. Overview  
This roadmap defines the delivery path for the entire Savant Platform:

**Phase 1 — Engine (MVP)  
Phase 2 — Hub (UI)  
Phase 3 — Cloud (Enterprise)  
Phase 4 — Marketplace (Ecosystem)**

Your goal: Move as fast as possible with limited hours using agents for 80–90% of all coding.

---

# 2. High-Level Timeline  

## **0–3.5 Weeks → Savant Engine MVP (v0.1.0)**  
Deliver core runtime + MR Review agent + workflows.

## **4–10 Weeks → Savant Engine v0.2–v0.4**  
Add reliability, safety, better workflows, plugin loaders.

## **3–6 Months → Savant Hub (UI layer)**  
Visual workflow builder, MCP graph, logs, multi-agent viewer.

## **6–12 Months → Savant Cloud (Enterprise)**  
RBAC, audit logs, compliance mode, on-prem/Cloud Run.

## **12–24 Months → Savant Marketplace**  
Agents, tools, workflows, templates.

---

# 3. Detailed 12-Month Roadmap  

---

# **Phase 1 — Engine MVP (Now → 3.5 Weeks)**  
**Outcome:** Local agent runtime that beats Wand AI in developer value.

### Deliverables:
- Boot Sequence (Driver + AMR + Persona)
- MCP Multiplexer (SSE + STDIO)
- Agent Runtime (reason, select, execute)
- Git Integration
- MR Review Agent
- YAML Workflow Engine
- Logging Layer
- CLI (`savant run`, `savant review`, `savant workflow`)

### Milestone:
**Publish Savant Engine v0.1.0**  
Demo: MR Review agent + workflow execution.

---

# **Phase 2 — Engine v0.2–v0.4 (4–10 Weeks)**  
Tighten reliability + add missing foundation.

### Improvements:
- Restart & recovery logic
- Advanced tool selection engine
- Memory persistence
- Repo indexer agent
- Migration Agent (React/TS + Rails-specific upgrades)
- TDD/Test Generator agent
- Local vector store for code understanding
- Config file: `savant.yaml`

### Milestone:
**First “Developer Agent Pack” release.**

---

# **Phase 3 — Savant Hub (3–6 Months)**  
Visual UI for workflows, observability, and tools.

### Features:
- Web dashboard
- Workflow visual builder (like n8n but agent-aware)
- Live agent execution panel
- Tool catalog UI
- Logs + token viewer
- Error tracing UI
- Credentials vault
- Repo viewer + context map
- Local model configuration UI

### Milestone:
**Public Hub Beta**  
This is the feature that competes with Wand AI directly.

---

# **Phase 4 — Savant Cloud (6–12 Months)**  
Enterprise go-to-market.

### Features:
- Team workspaces
- Multi-agent orchestration
- Scheduled workflows
- Agent pipelines
- RBAC + audit logs
- On-prem deploy (Docker/K8s)
- Cloud logs + metrics
- Model governance
- Billing

### Milestone:
**First paid enterprise customer.**

---

# **Phase 5 — Marketplace (12–24 Months)**  
Ecosystem expansion.

### Features:
- Agent marketplace
- MCP tool marketplace
- Workflow template marketplace
- Rating + versioning
- “One-click install” modules
- Enterprise store for compliance-approved agents

### Milestone:
**1,000 monthly active developers  
50+ third-party agents  
30+ enterprise workflows**

---

# 4. Strategic Themes  

### **1. Developer First**  
CLI-first, fast, powerful, easy to integrate.

### **2. Local First**  
Ollama, on-device RAG, no cloud mandatory.

### **3. Extensible**  
Everything modular:
- agents
- workflows
- tools
- multiplexer
- models

### **4. Fast GTM**  
You ship small modules aggressively:
- weekly demos  
- biweekly micro-releases  
- constant public updates  

---

# 5. 12-Month Deliverable Summary  

## **Q1 — Engine**
- v0.1.0 MVP  
- MR Review Agent  
- Workflow Engine  
- Logging  
- Repo indexer beta  

## **Q2 — Engine Expansion**
- Migration agents  
- TDD agent  
- Repo search  
- RAG engine  
- Local vector index  

## **Q3 — Hub (UI Layer)**
- MVP UI  
- Visual workflow builder  
- MCP manager UI  
- Agent execution visualizer  

## **Q4 — Cloud & Marketplace**
- Enterprise cluster  
- RBAC + audit logs  
- Marketplace alpha  
- Paid customers  

---

# 6. Vision Alignment  
This roadmap ensures Savant becomes:

**The Agent Infrastructure Platform for developers.  
The local-first alternative to Wand AI.  
The runtime every engineering team adopts.**

