# Savant Engine MVP --- Final Checklist (v0.1.0)

## 1. Boot Sequence

-   [ ] Driver prompt loads\
-   [ ] AMR rules load\
-   [ ] Persona template loads\
-   [ ] Model adapter (Ollama) initializes\
-   [ ] Logging initialized\
-   [ ] Boot errors logged cleanly\
-   [ ] `savant run` loads Driver + AMR + Persona successfully

## 2. MCP Multiplexer (STDIO + SSE)

-   [ ] STDIO MCP support\
-   [ ] SSE MCP support\
-   [ ] Mount 2+ MCP servers\
-   [ ] Auto-discover tools\
-   [ ] Unified tool registry\
-   [ ] Routing logs emitted\
-   [ ] Agent can call tools across all mounted MCPs

## 3. Agent Runtime

-   [ ] Reasoning loop functional\
-   [ ] Tool selection engine working\
-   [ ] Tool execution + result parsing\
-   [ ] Error handling + retry logic\
-   [ ] Session memory (runtime-only)\
-   [ ] Stop/end conditions implemented\
-   [ ] No infinite loops\
-   [ ] Structured logs for reasoning + tool calls

## 4. Git Integration

-   [ ] Repo root detection\
-   [ ] Load repo metadata\
-   [ ] Extract git diffs\
-   [ ] Extract changed lines\
-   [ ] Read file context\
-   [ ] Provide repo context to agents\
-   [ ] Verified across 3 repos

## 5. MR Review Agent

-   [ ] Reads git diff\
-   [ ] Applies AMR rules\
-   [ ] Generates MR summary\
-   [ ] Generates inline comments\
-   [ ] Comments are specific + repo-aware\
-   [ ] `savant review` works on 3 repos\
-   [ ] 100% local execution (Ollama)

## 6. Workflow Engine (YAML)

-   [ ] Load `workflow.yaml`\
-   [ ] Parse steps sequentially\
-   [ ] Pass output between steps\
-   [ ] Support tool calls\
-   [ ] Support agent calls\
-   [ ] Log workflow errors clearly\
-   [ ] At least 1 workflow runs end-to-end\
-   [ ] `savant workflow run` command functional

## 7. Logging Layer

-   [ ] Log agent reasoning\
-   [ ] Log tool calls\
-   [ ] Log MCP routing\
-   [ ] Log Git interactions\
-   [ ] Log errors\
-   [ ] Structured JSON logs\
-   [ ] Logs stored in fixed runtime location

# MVP Exit Criteria

MVP (v0.1.0) is officially **DONE** when:

100% of the checklist is complete\
All commands run in 3 real repos\
Zero crashes\
Consistent, predictable agent behavior
