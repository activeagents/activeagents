# External evaluation report ingestion

Status: implemented; regression validation recorded in the branch milestone.

Applications reporting telemetry could not publish scenario evaluation reports into the hosted dashboard. Sharing an evaluation scoring library did not persist external results or connect them to traces. The dashboard's existing evaluation command executes platform agents and cannot reproduce an external application's authorization, data or tools.

The fix imports immutable versioned reports under account/run identity, preserves scenario grades and output, and exposes report/trace links in both directions. Observed agents remain read-only until explicitly forked. The generic protocol is documented in [external evaluation reports](../features/external-evaluation-reports.md).

Acceptance criteria: authenticated import; one run per retry key; conflicting retry rejected; no account/context mixing; no agent execution on import; per-result output and score retained; safe text rendering; response/judge trace links; existing authored evaluations unchanged.
