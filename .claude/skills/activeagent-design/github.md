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
The dashboard now ships as its own gem, `actionagent`, a mountable engine
living beside the `activeagent` framework gem in
github.com/activeagents/activeagent. Paths marked *(gem)* are relative to
`actionagent/` in that repo; unmarked paths are this repo's. This repo
keeps one-line alias files (`app/models/agent_context.rb` reads
`AgentContext = ActionAgent::AgentContext`).

| Screen | Built from |
| --- | --- |
| Agent detail → Interactions | *(gem)* `app/controllers/action_agent/api/interactions_controller.rb`, `app/models/action_agent/agent_context.rb`, `.../agent_generation.rb` |
| Agent detail → Traces | *(gem)* `app/models/action_agent/agent_generation.rb` (trace_id, finish_reason, cached/reasoning tokens) |
| Agent detail → Tools | `config/active_agent.yml` |
| ContextMeter component | *(gem)* `frontend/components/dashboard/ContextMeter.jsx` (`contextWindowFor`, `estimateTokens`) |

## Not yet recreated
Session Replay, Benchmarks, Sandbox spaces.
