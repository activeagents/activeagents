# External evaluation reports

An application that runs its agents itself can still evaluate them with
`ActiveAgent::Evals` and read the results here. It replays its scenarios in its
own process, then publishes the finished report to `POST /v1/evaluations` with
`ActiveAgent::Evals::Publisher`. The dashboard stores the report as its own
evaluation rows, so the Evaluations page shows it the way it shows a run the
dashboard executed: the per-model summary, the judge's verdict, the fix items
and the scenario × model matrix.

The dashboard never executes the reporting application's agent.

## Who does what

The collector is the `actionagent` engine's:
`ActionAgent::Api::EvaluationReportsController` validates and answers the
request, and `ActionAgent::EvaluationReportImport` stores the report. Its
statuses, validity rules and storage are documented with the publisher, in the
activeagent repo's `docs/evals/publication.md` ("Self-hosted collector").

This app serves that collector at `/v1/evaluations` through
`Api::V1::EvaluationsController`, a subclass that changes three things:

| Seam | This app |
|---|---|
| Authentication | Any account key trace ingest accepts (`Api::AccountTokenAuthentication`): an API key from Settings -> API Keys, or the account's telemetry key. The engine's own authentication takes only the telemetry key. |
| Metering | A new report is refused with 429 once the account is over its plan's trace quota, through `ActionAgent.quota_checker` (`:evaluation_report`, in `config/initializers/action_agent.rb`). The body is the one `/v1/traces` answers its quota 429 with: `error` and the plan's `limit`. |
| Receipt `url` | The run's report on this app's dashboard, `/dashboard/evaluations?evaluation=:evaluation_id&run=:id`. |

`/api/v1/evaluations` is the same endpoint for clients configured with an `/api`
prefix. The engine also answers at its own mount, `/dashboard/api/evaluation_reports`,
with the same quota but the engine's authentication. Publish to `/v1/evaluations`.

## Publishing

```ruby
receipt = ActiveAgent::Evals::Publisher.new(
  endpoint: "https://api.activeagents.ai/v1/evaluations",
  api_key: ENV.fetch("ACTIVEAGENTS_API_KEY")
).call(report: report, run_id: report.metadata.fetch("run_id"),
       source: "support-app", agent_name: "SupportBot", suite: "orders")
```

| Response | When |
|---|---|
| 201 | The report was stored. The receipt carries `id`, `evaluation_id`, `run_id` (exactly as sent), `status: "complete"`, `duplicate: false` and `url`. |
| 200 | The same report was already stored under this `run_id`; the receipt names the stored run, with `duplicate: true`. A retry is answered before the quota and the rate limit are consulted. |
| 409 | A different report is already stored under this `run_id`. Never retry that report under this `run_id`. |
| 422 | Not a valid version-1 report (the error names the field), or the agent already has an evaluation of that name that no report with this source, suite and scope created: publish under another suite or scope. |
| 403 | Storing it needs an operator first: the account's owner holds as many observed agents as allowed, the agent holds 100 evaluations, or the evaluation would hold more than 2,000 scenarios. |
| 429 | A new report from an account over its plan's trace quota, or past 30 new reports a minute from the account. |
| 413 | The body is over 2 MiB. |
| 415 | The body is not declared `Content-Type: application/json`. |
| 400 | The body is not JSON. |
| 401 | No key, or an unknown one. |

## Where a report lands

| Record | Identity |
|---|---|
| Agent | The account's observed agent for the envelope's `source` and `agent_name`. It belongs to the account's owner (`trace_owner_resolver`), with `account_id` set to the publishing account, and is read-only, like the agents trace ingest observes. |
| Evaluation | That agent's evaluation named for the `suite`, qualified by the report metadata's `scope`, `environment` and `role`, in that order: `orders (eu, support)`. |
| Scenarios | One per reported scenario key, updated to the prompt and group the report ran. Scenarios the report did not run are left alone. |
| Run | One complete run per account and `run_id` (`evaluation_runs.external_tenant` and `external_run_id`), with one scenario result per scenario and model. Each result keeps its `metadata` (`result_id`, `trace_id`, `judge_trace_ids`). |

The run cannot be started again from the dashboard, because its agent runs
elsewhere. Evaluate again from the application and publish the new run.

## Local development

A production image of this app runs locally with plain HTTP when
`RAILS_ASSUME_SSL=false` and `RAILS_FORCE_SSL=false` are set.
`bin/rails platform:bootstrap_account EMAIL=… PASSWORD=… PLAN=enterprise CONFIRM=yes`
creates a login with an account it owns and an API key, comps the account onto a plan so
trace quotas do not interrupt testing, and prints the key as `ACTIVEAGENTS_API_KEY=…`. It is
idempotent. `CONFIRM=yes` is required wherever `RAILS_ENV` is production, which includes a
local run of the production image, and it refuses to comp an account with a paid
subscription.
