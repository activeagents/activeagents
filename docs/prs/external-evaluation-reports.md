# Import external evaluation reports with trace correlation

External applications could report traces but could not store their scenario/model evaluation results in the dashboard. Add a versioned Bearer-authenticated report endpoint, immutable account/run storage, historical report rendering and bidirectional response/judge trace links. Imported agents remain observed and read-only until explicitly forked; existing dashboard-authored evaluations retain their execution path.

Retries return the same run; conflicting reuse of a run ID returns 409. Validation bounds request size, result/model counts, scores, context and trace identifiers. The UI renders external output as text and constructs trace URLs locally.

Validation: 85 Rails tests / 311 assertions; two static React rendering tests; Ruby lint; full JavaScript build. Migration required: `20260909202622_add_external_evaluation_reports.rb`. No dependency changes.

PR URL: pending publication after review.
