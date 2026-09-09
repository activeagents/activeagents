# Fresh checkout + latest-gem upgrade test — 2026-09-09

## Scope
Fresh clones of `activeagents/activeagents`, `activeagents/activeagent`,
`activeagents/solid_agent` at `main`, then ran the Rails app against the
latest gem code.

Location: `~/GitHub/activeagents-fresh/`

## Repo notes
- **`actionagent` is not a separate repo.** It lives at `activeagent/actionagent/`
  inside the framework repo, published from its own gemspec. A clone of
  `activeagent` brings it along; depending on it needs a `glob:`:
  ```ruby
  gem "actionagent", github: "activeagents/activeagent", branch: "main",
      glob: "actionagent/*.gemspec"
  ```

| Repo | HEAD | Version |
|---|---|---|
| activeagent | `1ab417d` | 1.4.0 |
| actionagent (nested) | `1ab417d` | 1.3.0 |
| solid_agent | `bb53afc` | 0.2.0 |
| activeagents | `96696df` | Rails 8.2.0.alpha |

## Findings

### 1. `Gemfile.lock` pins stale git revisions (biggest gotcha)
A plain `bundle install` on a fresh clone resolved **activeagent 1.0.3** and
**solid_agent 0.1.1** — the lockfile's recorded revisions, not `main`. Testing
"the latest version" requires an explicit:
```
bundle update activeagent solid_agent
```

### 2. Boot failure: `uninitialized constant ActiveAgent::Dashboard`
In 1.4.0 the in-gem dashboard is **gone**, replaced by the standalone
`actionagent` engine. `config/initializers/active_agent_dashboard.rb` still
calls `ActiveAgent::Dashboard.configure`.

**Fix:** add the `actionagent` gem. It ships a compatibility shim
(`ActionAgent::Compatibility`) that aliases the old constant and warns once,
so the existing initializer keeps working. Boot succeeded after adding it.

### 3. Root cause of 35 test errors: table-name prefix mismatch
Symptom was a misleading cascade of
`PG::InFailedSqlTransaction: current transaction is aborted`
pointing at `TelemetryTrace#dedupe_token_totals!`.

The real error was upstream and **swallowed**:
```
[AgentRegistrar] ActiveRecord::StatementInvalid:
  PG::UndefinedTable: relation "active_agent_agents" does not exist
```
`ActionAgent::AgentRegistrar.call` has a blanket `rescue StandardError` so it
"never raises" — but on PostgreSQL the failed query has already poisoned the
transaction, so every later statement in the test dies with a confusing error.

The engine defaults `ActionAgent.table_name_prefix` to `active_agent_`, while
this app's dashboard tables are **unprefixed** (`agents`, `agent_runs`, ...).
The one exception is the traces table, created as
`active_agent_telemetry_traces`.

**Fix** (in the initializer):
```ruby
ActionAgent.table_name_prefix = ""
Rails.application.config.to_prepare do
  ActionAgent::TelemetryTrace.table_name = "active_agent_telemetry_traces"
end
```
The `to_prepare` is required — naming the model at initializer time loads
Active Record at boot, which the gem split deliberately avoids.

### 4. `Span#span_type` reader removed
`ActiveAgent::Telemetry::Span` is now a subclass of the shared
`ActiveAgents::Telemetry::Span`. The **constructor still accepts `span_type:`**
(so app code is unaffected), but the reader is now `type` and returns a
String rather than a Symbol. Only a test read it.

### 5. Pre-existing test bug (not a gem regression)
`agent_toolbox_test.rb` asserted error results are never cached via
`keys.grep(/1.0/)` — an unescaped `.` that matched `110` inside the SHA of the
*successful* `2+2` cache key. It passed before only by luck of a different
hash. Rewritten to compare key sets before/after.

## Result
```
391 runs, 1247 assertions, 0 failures, 0 errors, 0 skips
```
(passing on both Ruby 4.0.1 and 4.0.6)
- App boots on activeagent 1.4.0 / actionagent 1.3.0 / solid_agent 0.2.0
- Dashboard renders (footer confirms v1.4.0)
- Authenticated APIs 200 with real data: agents, metrics, analytics,
  interactions, runs
- Live trace ingest `POST /v1/traces` → 202; trace persisted with correctly
  deduped tokens (40/20, not double-counted) and `AgentRegistrar` created an
  `observed` agent — the feature that was silently failing before the fix

### 6. Ruby upgraded to 4.0.6 (current stable)
The repo pinned three different Rubies: `.ruby-version` 3.4.8, `mise.toml`
4.0.1, `Dockerfile` 3.4.8 — so local dev, CI (which reads `.ruby-version`)
and the container image did not agree.

All three now pin **4.0.6**, the current stable release (4.0.0 is the only
4.x with preview builds; 4.0.6 is final). `ruby:4.0.6-slim` exists on Docker
Hub. Verified: bundle installs, 391 tests pass, Puma boots and serves on
4.0.6, and live trace ingest persists with correct token dedup.

## Changes made in the fresh checkout
- `Gemfile` — added `actionagent`
- `Gemfile.lock` — updated to latest `main` for all three gems
- `config/initializers/active_agent_dashboard.rb` — table prefix config
- `test/services/agent_execution_service_test.rb` — `span_type` → `type`
- `test/services/agent_toolbox_test.rb` — fixed the regex-luck cache assertion
- `.ruby-version`, `mise.toml`, `Dockerfile` — Ruby 4.0.6

`yarn.lock` was deliberately reverted: `npm install` on macOS swapped the
Linux esbuild/parcel binaries for darwin ones, which would break CI and the
Docker build.

## Suggested upstream follow-ups
1. `AgentRegistrar`'s blanket rescue should wrap the DB work in a savepoint
   (or check `table_exists?`) so a swallowed error can't poison the caller's
   transaction on PostgreSQL. This turned a clear "table missing" into 35
   unrelated failures.
2. The `activeagents` app initializer should drop the
   `ActiveAgent::Dashboard` name and the now-redundant `dedupe_token_totals!`
   workaround (gem 1.4 dedupes natively — the comment already anticipated this).
