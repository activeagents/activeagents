# Telemetry criteria find no traces for an observed agent whose class lacks `Agent`

**Repo:** activeagents/activeagent (actionagent engine). **Status:** fixed in
https://github.com/activeagents/activeagent/pull/481, released in activeagent and actionagent
1.7.0, which this app runs.

`EvaluationRunnerService#telemetry_traces` selects traces with
`for_agent(@evaluation.agent.telemetry_agent_class)`, and `Agent#telemetry_agent_class` appends
`Agent` to a class name without it. An observed agent is registered from the trace's own
`agent.class`, so an application reporting `SupportBot` gets an observed `SupportBot.respond`
whose telemetry criteria (`trace_error_rate`, `trace_latency`) look for `SupportBotAgent` and
score no traces.

The fix gives `Agent` a `#telemetry_traces` scope that reads an observed agent's traces by
`agent_id`, plus unattributed traces matching its `service_name`, `agent_class` and
`agent_action`. Telemetry criteria, the agent's Traces and Tools tabs, and the Metrics page's
deploy markers all use it.
