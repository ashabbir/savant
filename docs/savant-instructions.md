# PROJECT_INSTRUCTIONS.md — Savant Architecture & Long-Term Vision
Author: Amd  
Purpose: Define how this project should be used, maintained, and expanded.

---

# 1. Purpose of This Project
This project is the **source of truth** for:
- Savant’s architecture  
- Long-term vision  
- Product direction  
- PRDs  
- Roadmaps  
- System modules & specs  

It is NOT the engine codebase.  
This is the **product + architecture brain** of Savant.

---

# 2. How This Project Is Organized
```
VISION.md                 → Long-term, 10-year direction  
ROADMAP.md                → 12-month plan + phases  
ARCHITECTURE.md           → High-level system design  
PRD/                      → Product requirements  
MODULES/                  → Technical specs for each subsystem  
AGENTS/                   → Specs for built-in agents  
MCP/                      → Specs for MCP engines/tools  
WORKFLOWS/                → Workflow definitions  
MARKET/                   → Competitive + GTM  
FUTURE/                   → Expansion ideas  
PROJECT_INSTRUCTIONS.md   → (this file)
```

Each file represents a **living contract** you will update as Savant evolves.

---

# 3. How to Use This Project (Daily/Weekly Workflow)

### **A. Daily (1 hour)**
You use this project to:
- Review architecture  
- Generate tasks for coding agents  
- Update specs as you build  
- Maintain alignment with long-term vision  

This keeps you in “architect mode” outside coding hours.

### **B. Weekend (6 hours)**
Use the specs here to:
- Select the next PRD tasks  
- Integrate AI-generated code  
- Debug implementation details  
- Finalize modules  

This is the build engine.

---

# 4. How to Add New Files
Every time you add a new feature, you must create / update:

### **A. A PRD**  
(feature-level specification)

### **B. A module file**  
(architecture-level detail)

### **C. A workflow example**  
(if the feature integrates into workflows)

### **D. A roadmap update**  
(if the feature changes sequencing)

### **E. Vision alignment**  
(if feature expands category definition)

This ensures the project never drifts.

---

# 5. Rules for Maintaining This Project

### **Rule 1 — Architecture First, Code Second**
All features must be documented here *before* coding.

### **Rule 2 — No UI or Cloud in This Project**
This repository focuses on:
- Engine  
- Workflow engine  
- Multiplexer  
- MR review  
- Core AIP runtime  

Hub + Cloud have their own future PRDs.

### **Rule 3 — Everything Must Be Modular**
Each module file must define:
- Inputs  
- Outputs  
- Dependencies  
- Extension points  
- Failure cases  

### **Rule 4 — Keep It Developer-First**
Every design must be:
- CLI friendly  
- local-first  
- agent-centric  
- secure by default  

### **Rule 5 — Keep Documents Short and Brutal**
This project is not a storybook.  
You build *weapon-grade specifications.*  
If a spec takes longer than 10 mins to read → rewrite.

---

# 6. Required Files to Update Before Each Release
Before every release (MVP → v0.2 → v0.3 → Hub → Cloud), update:

- `/ROADMAP.md`  
- `/ARCHITECTURE.md`  
- `/PRD/`  
- `/MODULES/`  
- `/WORKFLOWS/`  
- `/FUTURE/`  

This keeps alignment across the entire platform.

---

# 7. How to Work With AI Agents Using This Project  
You must use this project to “feed” your coding agents.

### **Step 1: Pick a module file**  
(example: `multiplexer.md`)

### **Step 2: Generate small prompts**  
AI writes 80–90% of your code.

### **Step 3: You review + glue code on weekends**

### **Step 4: Update this project**  
Reflect any architectural change.

This becomes your **single source of truth**.

---

# 8. Commit Rules
Each commit message should follow:

`[area] Summary`

Example:
- `[engine] Add runtime reason loop`
- `[multiplexer] Implement STDIO client`
- `[workflow] Add YAML parser spec update`

This helps future contributors.

---

# 9. Security Requirements
Nothing in this repo touches:
- production secrets  
- tokens  
- personal data  

All creds must be stored in:
- Savant Vault (future)
- `.savant/credentials.json` locally (temp)

---

# 10. Long-Term Purpose
This project will become:
- The docs that onboard future engineers  
- The book for investors  
- The spec foundation for Savant Hub  
- The architectural bible for the Savant Platform  
- The system of record for multi-agent orchestration  

It is your **company’s internal backbone**.

---

# 11. What You Should Add Next
I recommend you now generate:

- `ARCHITECTURE.md`  
- `engine.md`  
- `multiplexer.md`  
- `runtime.md`  

These four files form the “core” of the platform.

Just tell me which one you want next.  
