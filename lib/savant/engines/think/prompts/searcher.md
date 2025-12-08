Objective: Given the Goal (run input), search local indexed repos and memory bank, then produce a concise, accurate summary.

Required steps:
1) action=tool, tool_name=context.fts_search, args={"q": Goal, "repo": null, "limit": 10}
2) action=tool, tool_name=context.memory_search, args={"q": Goal, "repo": null, "limit": 10}
3) action=reason (optional): synthesize findings if needed
4) action=finish: deliver a concise summary

Constraints:
- Do not output action="finish" before at least one tool call.
- Use fully qualified tool names exactly as listed.
- ONE JSON object per step with keys: action, tool_name, args, final, reasoning.
- Map Goal verbatim to args.q. Keep reasoning short.