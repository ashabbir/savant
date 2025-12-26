# Agent State Machine - PRD

**Status:** Draft
**Version:** 1.0
**Date:** 2025-12-20
**Owner:** Engineering Team

---

## 1. Overview

### Problem Statement

Agents currently execute reasoning loops without understanding what "phase" they're in (searching for info, analyzing results, making decisions, etc.). This leads to:
- Repeated tool calls (same search twice)
- Circular reasoning (loop between two actions)
- Lack of progress detection
- Inability to exit gracefully when stuck
- Wasted tokens and time

### Solution

Implement a **State Machine** that tracks agent execution phases and enforces transitions, allowing agents to:
- Know what phase they're in
- Detect when stuck in a state
- Automatically suggest exit strategies
- Learn efficient state transitions
- Make smarter tool-selection decisions based on state

### Success Criteria

- [ ] Agent tracks state (Searching → Analyzing → Deciding → Finishing)
- [ ] State transitions are logged and auditable
- [ ] Stuck detection works (same state for N consecutive steps)
- [ ] Agent receives state context in reasoning payload
- [ ] Exit strategies are suggested when stuck
- [ ] No regression in successful agent completions

---

## 2. Core Concepts

### 2.1 State Definitions

```
┌─────────────┐
│    INIT     │  Agent initialized, no actions taken
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  SEARCHING  │  Using context.fts_search to gather information
└──────┬──────┘
       │
       ├──────────┐
       │          │ (loop detection)
       ▼          ▼
┌─────────────┐  ┌──────────────┐
│ ANALYZING   │  │ STUCK_SEARCH │
└──────┬──────┘  └──────────────┘
       │              │
       │              ▼
       │         ┌──────────────┐
       │         │   FINISHING  │ (exit with best guess)
       │         └──────────────┘
       │
       ├─────────────┐
       │             │
       ▼             ▼
┌─────────────┐  ┌──────────────┐
│  DECIDING   │  │ STUCK_ANALYZE│
└──────┬──────┘  └──────────────┘
       │              │
       │              ▼
       │         ┌──────────────┐
       │         │   FINISHING  │
       │         └──────────────┘
       │
       ▼
┌─────────────┐
│  FINISHING  │  Complete and return result
└─────────────┘
```

### 2.2 State Characteristics

| State | Actions Allowed | Next States | Timeout | Stuck After |
|-------|-----------------|-------------|---------|-------------|
| **INIT** | None | SEARCHING, DECIDING, FINISHING | - | - |
| **SEARCHING** | context.fts_search | ANALYZING, STUCK_SEARCH, FINISHING | 60s | 3 identical calls |
| **ANALYZING** | None (wait for LLM) | DECIDING, STUCK_ANALYZE, FINISHING | 30s | - |
| **DECIDING** | Any tool or finish | SEARCHING, FINISHING, STUCK_DECIDE | 45s | 3 failed decisions |
| **STUCK_SEARCH** | finish (with summary) | FINISHING | 10s | - |
| **STUCK_ANALYZE** | finish (with summary) | FINISHING | 10s | - |
| **STUCK_DECIDE** | finish (with summary) | FINISHING | 10s | - |
| **FINISHING** | None | - | 5s | - |

### 2.3 Transitions

**Valid Transitions:**
```ruby
INIT → SEARCHING, DECIDING, FINISHING
SEARCHING → ANALYZING, STUCK_SEARCH, FINISHING
ANALYZING → DECIDING, STUCK_ANALYZE, FINISHING
DECIDING → SEARCHING, FINISHING, STUCK_DECIDE
STUCK_* → FINISHING
FINISHING → (end)
```

**Invalid Transitions (rejected):**
- SEARCHING → DECIDING (must ANALYZE first)
- ANALYZING → SEARCHING (must DECIDE first)
- Any state → INIT (no reset)

---

## 3. Architecture

### 3.1 State Machine Component

**Location:** `lib/savant/agent/state_machine.rb`

```ruby
module Savant
  module Agent
    class StateMachine
      # Attributes
      attr_reader :current_state
      attr_reader :state_history     # [{ state, step_num, tool_name, timestamp }]
      attr_reader :state_duration_ms # Time in current state

      # Initialize
      def initialize(initial_state: :init)
        @current_state = initial_state
        @state_history = []
        @step_count = 0
        @state_entry_time = Time.now
      end

      # Query current state
      def in_state?(name)
        current_state == name.to_sym
      end

      def allowed_actions
        # Return tools allowed in current state
      end

      def next_states
        # Return valid next states
      end

      # Detect if stuck
      def stuck?
        # Same state for N consecutive steps
        # Or: same tool called N times in a row
      end

      def suggest_exit
        # Return: "You've searched 3 times without finding new results. Try: finish with what you found."
      end

      # Transition to new state
      def transition_to(new_state, reason: nil)
        # Validate transition
        # Record history
        # Update entry time
        # Return: { ok: true } or { ok: false, error: "invalid transition" }
      end

      # Update state duration
      def tick
        # Called after each agent step
        # Increments step count in current state
      end

      # For logging/debugging
      def to_h
        {
          current_state: current_state,
          duration_ms: state_duration_ms,
          history: state_history,
          stuck: stuck?,
          suggested_exit: suggest_exit
        }
      end
    end
  end
end
```

### 3.2 Integration Points

**1. Agent::Runtime initialization (lib/savant/agent/runtime.rb)**
```ruby
def initialize(...)
  @state_machine = Savant::Agent::StateMachine.new
end
```

**2. Reasoning loop (lib/savant/agent/runtime.rb, run method)**
```ruby
loop do
  # Get current state context
  state_info = @state_machine.to_h

  # Check if stuck
  if @state_machine.stuck?
    # Auto-suggest exit or force transition to STUCK_* state
  end

  # Call reasoning API with state context
  payload = build_agent_payload
  payload[:agent_state] = state_info  # Add state to payload

  # Get intent from reasoning
  intent = reasoning_client.agent_intent(payload)

  # Determine next state based on tool choice
  next_state = infer_state_from_tool(intent.tool_name)

  # Attempt transition
  result = @state_machine.transition_to(next_state, reason: intent.tool_name)

  # If transition invalid, suggest alternatives or force finish
  if !result[:ok]
    # Handle invalid transition
  end

  # Execute action
  # Record in state history
  @state_machine.tick
end
```

**3. Reasoning API receives state context (reasoning/api.py)**
```python
class AgentIntentRequest(BaseModel):
    ...
    agent_state: Optional[Dict[str, Any]] = None  # New field

def agent_intent(req):
    state_info = req.agent_state or {}

    # Reasoning can factor in current state
    # E.g., if in SEARCHING and stuck, suggest finishing
```

---

## 4. Detailed Behavior

### 4.1 State Detection Logic

**Infer state from tool choice:**
```ruby
def infer_state_from_tool(tool_name)
  case tool_name
  when 'context.fts_search'
    :searching
  when 'context.memory_search'
    :searching
  when nil  # Finishing
    :finishing
  else
    # Custom tools in DECIDING state
    :deciding
  end
end
```

### 4.2 Stuck Detection

**Criteria for "stuck":**
```ruby
def stuck?
  # Rule 1: Same tool called 3+ times consecutively
  last_3_tools = state_history.last(3).map { |h| h[:tool_name] }
  return true if last_3_tools.uniq.length == 1 && last_3_tools.length == 3

  # Rule 2: Same state for 5+ steps
  steps_in_state = state_history.select { |h| h[:state] == current_state }.length
  return true if steps_in_state >= 5

  # Rule 3: State timeout exceeded
  return true if state_duration_ms > timeout_for_state(current_state)

  false
end
```

### 4.3 Exit Strategies

When stuck, suggest:

```ruby
def suggest_exit
  case current_state
  when :searching
    "You've searched 3 times for similar information. Try: finish with the results you found."
  when :analyzing
    "Analysis is taking too long. You have enough information. Try: finish with your summary."
  when :deciding
    "Decision loop detected. Commit to an action or finish."
  else
    "No progress made. Use 'finish' with the best answer you have."
  end
end
```

**Implementation in runtime:**
```ruby
if @state_machine.stuck?
  exit_suggestion = @state_machine.suggest_exit

  # Option 1: Log warning but continue (soft guidance)
  @logger.warn("Agent stuck: #{exit_suggestion}")

  # Option 2: Force transition (hard limit)
  @state_machine.transition_to(:stuck_current_state)
  # Next loop will suggest finishing

  # Option 3: Auto-finish (most aggressive)
  return finish_with_summary("Reached stuck state. Summary: #{current_best_answer}")
end
```

---

## 5. Data Structures

### 5.1 State History Entry

```ruby
{
  step_num: 1,
  state: :searching,
  tool_name: 'context.fts_search',
  tool_args: { query: 'Savant Framework' },
  result: { content: [...], score: 0.95 },
  duration_ms: 2340,
  timestamp: '2025-12-20T23:41:02.213Z'
}
```

### 5.2 Agent Payload Enrichment

```json
{
  "session_id": "...",
  "persona": {...},
  "goal_text": "...",
  "agent_state": {
    "current_state": "searching",
    "duration_ms": 2340,
    "history": [...],
    "stuck": false,
    "suggested_exit": null
  },
  "llm": {...}
}
```

---

## 6. Implementation Plan

### Phase 1: Core State Machine (Week 1)
- [ ] Create `StateMachine` class
- [ ] Implement state definitions and transitions
- [ ] Add stuck detection logic
- [ ] Write unit tests (100% coverage)

### Phase 2: Runtime Integration (Week 1-2)
- [ ] Add `@state_machine` to `Agent::Runtime`
- [ ] Integrate state tracking in reasoning loop
- [ ] Update `build_agent_payload` to include state
- [ ] Add state-based decision making
- [ ] Test with Math Agent and Searcher agent

### Phase 3: Reasoning API Integration (Week 2)
- [ ] Update `AgentIntentRequest` model
- [ ] Pass `agent_state` to reasoning function
- [ ] Implement state-aware prompting
- [ ] Test reasoning with state context

### Phase 4: Logging & Observability (Week 2-3)
- [ ] Log state transitions to MongoDB
- [ ] Add state metrics (time per state, transition frequency)
- [ ] Create state history visualization endpoint
- [ ] Add diagnostics page showing agent state flow

### Phase 5: Refinement & Learning (Week 3-4)
- [ ] Collect data on state transitions
- [ ] Identify patterns in stuck vs. successful agents
- [ ] Optimize timeouts per state
- [ ] Train reasoning model on state context
- [ ] Document best practices

---

## 7. Testing Strategy

### Unit Tests
```ruby
# spec/savant/agent/state_machine_spec.rb
describe Savant::Agent::StateMachine do
  describe '#transition_to' do
    it 'allows valid transitions'
    it 'rejects invalid transitions'
    it 'records state history'
  end

  describe '#stuck?' do
    it 'detects repeated tool calls'
    it 'detects timeout exceeded'
    it 'detects state loops'
  end

  describe '#suggest_exit' do
    it 'returns helpful suggestion when stuck'
  end
end
```

### Integration Tests
```ruby
# Test with real agents
- Math Agent (should stay in DECIDING state)
- Searcher Agent (should cycle SEARCHING → ANALYZING → DECIDING)
- Edge cases:
  - Agent that keeps searching for non-existent thing
  - Agent in infinite tool loop
  - Agent that finishes too early
```

### Manual Testing
```
Scenario 1: Normal execution
- Init → Searching → Analyzing → Deciding → Finishing ✓

Scenario 2: Stuck in search
- Init → Searching → Searching → Searching (stuck detected) → Finishing ✓

Scenario 3: Quick decision
- Init → Deciding → Finishing ✓
```

---

## 8. Success Metrics

| Metric | Target | Current |
|--------|--------|---------|
| Agents finishing in ≤5 steps | 80% | ? |
| No infinite loops detected | 100% | ~70% |
| Avg steps to completion | 3-4 | 5-10 |
| Stuck detection accuracy | 95%+ | - |
| User satisfaction | 4.5+/5 | ? |

---

## 9. Future Enhancements

### 9.1 Reinforcement Learning
- Reward agents for efficient state transitions
- Learn optimal paths through state space
- Adapt timeouts based on agent type

### 9.2 State Visualization
- Real-time state diagram during agent execution
- Historical state flow analysis
- Compare successful vs. failed state paths

### 9.3 Multi-Agent Coordination
- Agents that delegate to other agents change state
- Parallel state machines for concurrent agents
- State synchronization across agents

### 9.4 Dynamic State Definitions
- Allow custom states per agent type
- User-defined state transitions
- Per-domain state machines (code search vs. math vs. writing)

---

## 10. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| State machine is too rigid | Medium | Start with simple states, extend gradually |
| Reasoning API unaware of state | High | Update payload and tests early |
| Performance overhead | Low | State tracking is O(1) per step |
| Existing agents break | High | Feature flag state machine (default: off initially) |
| Stuck detection false positives | Medium | Tune thresholds based on agent types |

---

## 11. Open Questions

1. Should state be per-agent-type or global?
2. How much state context should we pass to reasoning API?
3. Should agents learn custom optimal state transitions?
4. How aggressive should auto-exit be?
5. Should we visualize state flow in the UI?

---

## 12. Appendix

### A. State Machine Diagram (ASCII)

```
        ┌─────────┐
        │  START  │
        └────┬────┘
             │
             ▼
        ┌─────────────┐
        │    INIT     │
        └────┬────────┘
             │
       ┌─────┴─────┬──────────┐
       │           │          │
       ▼           ▼          ▼
   ┌────────┐ ┌────────┐ ┌─────────┐
   │SEARCHING│ │DECIDING│ │FINISHING│
   └────┬───┘ └────┬───┘ └────┬────┘
        │          │          │
        ▼          ▼          ▼
   ┌────────┐ ┌────────┐ ┌─────┐
   │ANALYZING│ │SEARCH' │ │ END │
   └────┬───┘ │ANALYZE'│ └─────┘
        │     │DECIDE' │
        │     └────────┘
        │          ▲
        └──────────┘
```

### B. Example: Math Agent Flow

```
Input: "What is 12 divided by 4?"

Step 1: INIT → DECIDING
  - No search needed, math problem
  - Decide immediately

Step 2: DECIDING (reasoning with Gemini)
  - Gemini: "This is a simple math problem. Answer: 3"
  - Action: finish

Step 3: DECIDING → FINISHING
  - Return: "3"

Timeline: 3 steps, 2 seconds
```

### C. Example: Searcher Agent Flow

```
Input: "Tell me about Savant Framework"

Step 1: INIT → SEARCHING
  - Need information, use search

Step 2: SEARCHING (search #1)
  - Query: "Savant Framework"
  - Results: 7 documents

Step 3: SEARCHING → ANALYZING
  - Process results, summarize

Step 4: ANALYZING → DECIDING
  - Decide: need more specific info

Step 5: DECIDING → SEARCHING
  - Search for: "Savant Framework architecture"

Step 6: SEARCHING (search #2)
  - Results: 4 documents

Step 7: SEARCHING → STUCK_SEARCH (after 3rd search attempt)
  - Suggestion: "You've searched enough. Finish with summary."

Step 8: STUCK_SEARCH → FINISHING
  - Return comprehensive summary

Timeline: 8 steps, 45 seconds
```

---

**Document Version History:**
| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-12-20 | Engineering | Initial draft |

