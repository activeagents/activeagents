# Milestone: external evaluation reports

- Implemented the version-1 report endpoint, authenticated by account API key.
- Added account/run uniqueness, canonical-payload retry detection and immutable-conflict responses.
- Added report detail rendering, historical run selection, safe text output, model totals and trace links in both directions.
- Preserved observed agent identity and prohibited remote execution or direct conversion to authored state; explicit forks remain supported.
- Added request/serialization and static React rendering tests using generic synthetic examples.
- Migrated a dedicated local test database using the current UTC migration timestamp; existing application databases were not changed.

Validation: 85 Rails tests, 311 assertions, zero failures/errors/skips across the import, evaluations, agents and traces APIs plus evaluation model/service regressions. Two static React rendering tests passed. RuboCop checked 11 changed Ruby files with zero offenses. The complete JavaScript entry-point build passed. A focused independent review found and verified fixes for dark-theme backlinks, observed-agent execution, and malformed boolean metadata.

The tests used the tracked lockfile unchanged. JavaScript build tooling regenerated a lockfile as a side effect; that change was reverted. Logs and build artifacts remain in gitignored `tmp/` and `app/assets/builds/`.

Run the Rails tests with an isolated `DATABASE_URL`, `RAILS_ENV=test`, `PARALLEL_WORKERS=1`, `SKIP_JS_BUILD=1` and `SKIP_CSS_BUILD=1`:

```sh
bundle exec rails test test/controllers/api/v1/evaluations_controller_test.rb test/controllers/api/evaluations_controller_test.rb test/controllers/api/agents_controller_test.rb test/controllers/api/traces_controller_test.rb test/controllers/api/v1/traces_controller_test.rb test/models/evaluation_run_test.rb test/services/evaluation_runner_service_test.rb
node --test test/javascript/external_evaluation_report_test.mjs
```
