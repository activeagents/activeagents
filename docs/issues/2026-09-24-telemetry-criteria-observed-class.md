# Telemetry criteria find no traces for an observed agent whose class lacks `Agent`

**Repo:** activeagents/activeagent (actionagent engine). **Status:** noted, not filed.

`EvaluationRunnerService#telemetry_traces` selects traces with
`for_agent(@evaluation.agent.telemetry_agent_class)`, and `Agent#telemetry_agent_class` appends
`Agent` to a class name without it. An observed agent is registered from the trace's own
`agent.class`, so an application reporting `SupportBot` gets an observed `SupportBot.respond`
whose telemetry criteria (`trace_error_rate`, `trace_latency`) look for `SupportBotAgent` and
score no traces.

Likely fix: for an observed agent, select its traces by `agent_id` (ingest sets it through
`AgentRegistrar`) or by the stored `agent_class_name` + `action_name`.
