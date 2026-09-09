# External evaluation reports

Applications can evaluate their own agents and publish a completed `ActiveAgent::Evals::Report#to_h` to the dashboard. The dashboard stores the report, displays scenario/model grades and answers, and links response/judge traces. Importing a report never executes the application's agent or calls a model.

## HTTP contract, version 1

`POST /v1/evaluations` (`/api/v1/evaluations` is an alias) accepts JSON and a Bearer credential. Both Settings-generated API keys and the account's legacy telemetry key are supported. Revoked or missing credentials return 401.

```json
{
  "version": 1,
  "run_id": "stable-run-uuid",
  "source": "example-app",
  "agent_name": "SupportBot",
  "suite": "greetings",
  "report": {
    "models": {"small": {"provider": "openai", "model": "small"}},
    "metadata": {"scope": "workspace-a"},
    "results": [{
      "scenario_key": "hello",
      "group": "greetings",
      "prompt": "Say hello",
      "label": "small",
      "provider": "openai",
      "model": "small",
      "status": "passed",
      "score": 0.9,
      "scores": {"quality": 0.9},
      "answer": "Hello!",
      "input_tokens": 10,
      "output_tokens": 5,
      "duration_ms": 100,
      "metadata": {
        "result_id": "stable-result-id",
        "trace_id": "response-trace-id",
        "judge_trace_ids": ["score-trace-id"]
      }
    }]
  }
}
```

Use the same `run_id` and payload when retrying. A first import returns 201; an identical retry returns 200 with the same database IDs and `duplicate: true`. Object-key order does not affect identity. A different payload for an existing account/run ID returns 409 and never overwrites the saved report.

```json
{"evaluation_id": 4, "id": 8, "run_id": "stable-run-uuid", "status": "complete", "duplicate": false,
 "url": "/dashboard/evaluations?evaluation=4&run=8"}
```

`complete` means the report was imported, not that every scenario passed. Each result retains its `passed`, `failed`, or `errored` status. Missing scores remain unscored, including when computing averages.

The report keeps the core's existing flat result format, including fault, recommendation, diagnosis, tool calls, cost and metadata. Per-result trace references use `metadata.trace_id` and `metadata.judge_trace_ids`; judge requests without a single scenario, such as a comparison verdict, use `report.metadata.judge_trace_ids`. These references are optional so offline reports can still be imported. A report does not create the traces: publish them separately with the same account credential.

## Isolation and validation

- Maximum request size: 2 MiB; oversized requests return 413. Reports contain 1–1,000 results and 1–50 model labels.
- Required envelope identifiers (`run_id`, `source`, `suite`) are 1–200 ASCII letters, numbers, `_`, `.`, `:`, `/` or `-`. Agent names are 2–100 characters.
- Each result requires a scenario key, model label, model, provider and valid status. Scenario-key/model-label pairs and supplied result IDs must be unique within a report. Labels must exist in `report.models`.
- Scores are finite numbers from 0 to 1 or null. Timing/token/cost values are finite, nonnegative numbers. Content fields are limited to 100,000 characters, object keys to 200 characters, nesting to 20 levels, and judge references to 100 IDs per list. Trace IDs accept ASCII letters, numbers, `_` and `-` (up to 128 characters); external URLs are not accepted as trace IDs.
- Malformed JSON returns 400; invalid shape/content returns 422 without creating an agent, evaluation or run.
- Run IDs are unique per authenticated account, enforced by a database index and an account transaction lock. Source, agent, suite and report-context keys (`scope`, `environment`, `publishing_domain`, `role`) group histories separately. `scope` is the generic application-defined context identifier.
- Imports are visible only in their account, including when one person owns multiple accounts. The payload cannot select a different owner/account or attach to another person's agent.

## Dashboard behavior

Imported definitions appear in Evaluations and on their observed agent's evaluation page. Expanding an import loads its recent run history; direct run links also retrieve runs older than that page. The report shows per-model pass counts, average score, token totals, latency, scenario details, answers, errors, recommendations and full context. Content is rendered as text, not HTML. Trace links are constructed locally and trace reads remain account-scoped.

Selecting a linked trace shows links back to its imported evaluation runs in both themes. Reports can arrive before or after telemetry because links resolve by trace ID on read. An unknown or foreign-account trace remains inaccessible.

Observed agents retain their exact reported class names. They cannot execute, update or restore through the agent API; an explicit duplicate creates an authored draft. Imported evaluations cannot run again from the dashboard: rerun the source application and publish a new run ID. Existing dashboard-authored evaluations continue to score generations as before.

## Validation

Request tests cover authentication, revoked keys, retries/conflicts, account and context isolation, shape/size bounds, grade and output persistence, compact index/detail serialization, observed-agent execution guards, explicit forks and bidirectional trace references. Existing evaluation and trace tests run alongside them. `node --test test/javascript/external_evaluation_report_test.mjs` renders the real report component and checks totals, grades, trace links, unscored output and HTML/URL escaping.

Database migration: `20260909202622_add_external_evaluation_reports.rb`, generated from the current UTC timestamp. Deploy the migration before starting the updated app. Existing rows receive nullable import fields and retain their original behavior.
