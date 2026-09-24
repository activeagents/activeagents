# External evaluation reports

An application that runs its agents itself can still evaluate them with
`ActiveAgent::Evals` and read the results here. It replays its scenarios in its
own process, then publishes the finished report to `POST /v1/evaluations` with
`ActiveAgent::Evals::Publisher`. The dashboard stores the report as its own
evaluation rows, so the Evaluations page shows it the way it shows a run the
dashboard executed: the per-model summary, the judge's verdict, the fix items
and the scenario × model matrix.

The dashboard never executes the reporting application's agent.

## Publishing

```ruby
receipt = ActiveAgent::Evals::Publisher.new(
  endpoint: "https://api.activeagents.ai/v1/evaluations",
  api_key: ENV.fetch("ACTIVEAGENTS_API_KEY")
).call(report: report, run_id: report.metadata.fetch("run_id"),
       source: "support-app", agent_name: "SupportBot", suite: "orders")
```

The key is any account key trace ingest accepts: an API key from Settings ->
API Keys, or the account's telemetry key. `/api/v1/evaluations` is the same
endpoint for clients configured with an `/api` prefix. The envelope and its
retry contract are documented with the publisher, in the activeagent repo's
`docs/evals/publication.md`.

| Response | When |
|---|---|
| 201 | The report was stored. The receipt carries `id`, `evaluation_id`, `run_id`, `status: "complete"`, `duplicate: false` and `url`, the run's dashboard page. |
| 200 | The same report was already stored under this `run_id`; the receipt names the stored run, with `duplicate: true`. |
| 409 | A different report is already stored under this `run_id`. |
| 413 | The body is over 2 MiB. |
| 400, 422 | The body is not JSON, or not a valid version-1 report. |
| 401 | No key, or an unknown one. |

## Where a report lands

| Record | Identity |
|---|---|
| Agent | The account owner's observed agent for the envelope's `source` and `agent_name`. It is read-only, like the agents trace ingest observes. |
| Evaluation | That agent's evaluation named for the `suite`, qualified by the report metadata's `scope`, `environment` and `role`, in that order: `orders (eu, support)`. |
| Scenarios | One per reported scenario key, updated to the prompt and group the report ran. Scenarios the report did not run are left alone. |
| Run | One complete run per account and `run_id`, with one scenario result per scenario and model. Each result keeps its `metadata` (`result_id`, `trace_id`, `judge_trace_ids`). |

The run cannot be started again from the dashboard, because its agent runs
elsewhere. Evaluate again from the application and publish the new run.

## Local development

A production image of this app runs locally with plain HTTP when
`RAILS_ASSUME_SSL=false` and `RAILS_FORCE_SSL=false` are set.
`bin/rails platform:bootstrap_account EMAIL=… PASSWORD=… PLAN=enterprise` creates
a login with an account and an API key, comps the account onto a plan so trace
quotas do not interrupt testing, and prints the key as `ACTIVEAGENTS_API_KEY=…`.
It is idempotent.
