repo: activeagents/activeagents
branch: main

## Last sync
date: 2026-07-31T17:56:19Z

### Updated in this project
- Added `ContextMeter` — context-window state (messages / tool results / instructions / tool + MCP schemas / memory) modeled on `AgentContext` + `AgentGeneration` token fields.
- Renamed the per-agent "Sessions" tab to **Interactions**, matching `Api::InteractionsController` (a context is one agent's interaction stream).
- Added "Reload into instance" — replay an interaction against alternate model / instructions / tools / MCP variants for human or judge review.
- Traces now show context state per call, plus `finish_reason` and cached/thinking token counts.

## Screen map
| Screen | Built from |
| --- | --- |
| Agent detail → Interactions | `app/controllers/api/interactions_controller.rb`, `app/models/agent_context.rb`, `app/models/agent_generation.rb` |
| Agent detail → Traces | `app/models/agent_generation.rb` (trace_id, finish_reason, cached/reasoning tokens) |
| Agent detail → Tools | `config/active_agent.yml` |
| ContextMeter component | `app/javascript/components/dashboard/BenchmarkView.jsx` (CONTEXT_WINDOWS, system_prompt_tokens / tool_schema_tokens) |

## Not yet recreated
Session Replay, Benchmarks, Sandbox spaces.
