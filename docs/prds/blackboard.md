
# PRD — Savant Blackboard (v1)

**Owner:** Amd
**Status:** APPROVED (Architecture Locked)
**Scope:** Engine-level (no UI logic)
**Type:** Core Infrastructure
**Audience:** Engine, Agent, Worker implementers

---

## 1. Problem Statement

Savant supports:

* multi-human chat
* multi-agent chat
* councils & deliberations
* workflows
* reasoning workers
* tool workers

Without a **single coordination substrate**, the system becomes:

* state-divergent
* unreplayable
* unobservable
* impossible to debug
* impossible to scale to enterprise

**We need one source of truth for all intelligence coordination.**

---

## 2. Solution Overview

The **Savant Blackboard** is a **universal, append-only, event-driven coordination system** used by **all components**.

> If it didn’t go through the Blackboard, it didn’t happen.

The Blackboard:

* records all meaningful events
* exposes replayable history
* fans out signals via Redis
* enables agents, workers, and humans to collaborate without coupling

---

## 3. Design Principles (Non-Negotiable)

1. **Append-only**
2. **Event-first**
3. **One truth layer**
4. **Many subscribers**
5. **No direct agent-to-agent communication**
6. **Redis = delivery, Mongo = truth**
7. **Reasoning is compute, not state**

---

## 4. System Architecture (High Level)

![Image](https://www.researchgate.net/publication/4141312/figure/fig1/AS%3A646782220505095%401531216306457/Event-based-Blackboard-System.png)

![Image](https://www.researchgate.net/publication/236970121/figure/fig4/AS%3A299368772063244%401448386485360/The-Distributed-Agent-Based-System-Architecture.png)

![Image](https://media.geeksforgeeks.org/wp-content/uploads/20230914185841/redis-publish-subscriber.png)

![Image](https://miro.medium.com/v2/resize%3Afit%3A1400/0%2AuVCNQp4Oy3nFgkaQ)

### Components

| Component            | Role                    |
| -------------------- | ----------------------- |
| Rails Blackboard API | Validation + contract   |
| MongoDB              | Append-only truth store |
| Redis                | Fan-out + queues        |
| Agents               | Decision emitters       |
| Reasoning Workers    | Heavy cognition         |
| Tool Workers         | Side-effects            |
| UI / SSE             | Visualization only      |

---

## 5. Canonical End-to-End Flow (ALL CASES)

```
Actor (Human | Agent | Worker)
        |
        v
POST /blackboard/events
        |
        v
Rails API (validate + authorize)
        |
        v
MongoDB (append event)
        |
        v
Redis (publish event_id)
        |
        v
Subscribers react
        |
        v
New events emitted
```

This loop **never changes**.

---

## 6. Core Abstractions

### 6.1 Actor

```json
{
  "actor_id": "uuid",
  "type": "human | agent | system | worker",
  "metadata": {}
}
```

Actors are peers at the Blackboard layer.

---

### 6.2 Session (Universal Container)

```json
{
  "session_id": "uuid",
  "type": "chat | council | workflow",
  "actors": ["actor_id"],
  "state": "active | paused | completed",
  "metadata": {}
}
```

**Chat rooms, councils, workflows = sessions.**

---

### 6.3 Event (Authoritative Truth)

```json
{
  "event_id": "uuid",
  "session_id": "uuid",
  "type": "string",
  "actor_id": "uuid",
  "actor_type": "human | agent | system | worker",
  "visibility": "public | agent_only | private",
  "parent_event_id": "uuid | null",
  "payload": {},
  "created_at": "timestamp",
  "version": 1
}
```

No updates. No deletes.

---

### 6.4 Artifact (Immutable Output)

```json
{
  "artifact_id": "uuid",
  "type": "message | opinion | summary | diff | json",
  "content_ref": "file:// | s3:// | inline",
  "produced_by": "actor_id",
  "metadata": {}
}
```

Events reference artifacts.
Artifacts never mutate.

---

## 7. Event Taxonomy (v1)

### Chat

* `message_posted`
* `context_attached`

### Council

* `council_started`
* `round_started`
* `opinion_submitted`
* `rebuttal_submitted`
* `synthesis_requested`
* `synthesis_completed`

### Workflow

* `step_started`
* `step_completed`
* `step_failed`
* `branch_taken`
* `workflow_completed`

### Execution

* `agent_invoked`
* `tool_call_requested`
* `tool_call_completed`
* `result_emitted`
* `error_raised`

---

## 8. Reasoning Worker Integration (Critical)

### Trigger Model

* Redis queue receives `{ event_id }`
* Worker **never trusts payload**
* Worker pulls context from Blackboard

### Reasoning Flow

```
Redis → Reasoning Worker
           |
           v
GET /blackboard/events (session replay)
           |
           v
Reasoning (LLM / rules)
           |
           v
Create artifact
           |
           v
POST /blackboard/events
```

![Image](https://miro.medium.com/v2/resize%3Afit%3A1400/1%2AwTAxPM43AIhVkPoJK9iCMQ.png)

![Image](https://support.microsoft.com/images/en-us/30d9299b-7870-4e81-8cab-5526a120709b)

![Image](https://www.researchgate.net/publication/393965301/figure/fig1/AS%3A11431281556052798%401753327631783/System-architecture-of-the-LLM-Reasoning-Agent-comprising-two-components-the-QA-Chain.png)

### Guarantees

* Replayable
* Interruptible
* Parallelizable
* No partial state

---

## 9. Multi-Human + Multi-Agent Chat Flow

```
Human A ─┐
Human B ─┼─> message_posted
Agent X ─┘
              |
              v
          Blackboard
              |
              v
     Redis → UI / Agents / Workers
```

Messages are artifacts.
Chat is coordination, not UI.

---

## 10. Council Deliberation Flow

![Image](https://miro.medium.com/v2/resize%3Afit%3A1358/format%3Awebp/1%2Ab5A0U9WvduUbnoead74yrA.png)

![Image](https://miro.medium.com/1%2Axd3g1exjhH7_REWFYmnhVw.png)

![Image](https://images.ctfassets.net/kftzwdyauwt9/1IVANY7u7WClGLyl5JVVJS/519af8c34ad2904b4728d0e98a06b911/Agent_Flow_Consensus.png?fm=webp\&q=90\&w=3840)

```
council_started
      |
round_started
      |
opinion_submitted (A)
opinion_submitted (B)
rebuttal_submitted (C)
      |
synthesis_requested
      |
synthesis_completed
```

* Opinions preserved
* Dissent preserved
* Synthesis references inputs

---

## 11. Workflow Execution Flow

```
workflow_started
      |
step_started
      |
step_completed → artifact
      |
step_failed
      |
branch_taken
      |
workflow_completed
```

Workers react to steps.
Blackboard records truth.

---

## 12. APIs (Summary)

| Method                        | Purpose        |
| ----------------------------- | -------------- |
| POST /blackboard/sessions     | create session |
| POST /blackboard/events       | append event   |
| GET /blackboard/events        | replay         |
| GET /blackboard/subscribe     | SSE            |
| GET /blackboard/artifacts/:id | fetch output   |

---

## 13. Failure & Recovery

![Image](https://media.geeksforgeeks.org/wp-content/uploads/20240520115654/Event-Sourcing.webp)

![Image](https://media.geeksforgeeks.org/wp-content/uploads/20240828131234/Checkpointing-for-Recovery-in-Distributed-Systems.webp)

* Redis dies → replay from Mongo
* Worker crashes → no partial writes
* UI restarts → resubscribe + replay
* Agent restarts → deterministic resume

---

## 14. Non-Goals

* ❌ UI moderation
* ❌ Turn-taking logic
* ❌ State mutation
* ❌ Orchestration brain
* ❌ Chat-only shortcuts

---

## 15. Success Criteria

* All Savant features use Blackboard
* Zero state divergence
* Full replay of any session
* Reasoning workers stateless
* Hub UI becomes projection-only

---

## 16. Final Law (Locked)

> **Blackboard is the system.
> Everything else is a client.**


