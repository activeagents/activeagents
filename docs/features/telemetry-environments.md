# Telemetry environments: named keys that tag traces, with a global filter

Date: 2026-10-25 · Status: design, not started

## Ask

Justin (2026-10-25):

- "allow creating named keys for telemetry that tags traces with the
  environment (key name) for filtering dev/staging/prod as well as white
  labels or multiple apps managed by a pro user that is say a consultant
  using the evals for their contract clients"
- "the named telemetry keys should also come with a global filter to only
  view telemetry and evals from that env"
- "looks like we have named keys already from the main settings, but not
  the org settings page"

## What exists

- **Named keys.** `ActionAgent::ApiKey` (`api_keys`: `name`, `token`
  encrypted, `token_prefix`, `account_id`, `user_id`, `last_used_at`),
  created under Settings → API Keys in the dashboard
  (`frontend/components/dashboard/SettingsView.jsx`, `api/api_keys`). The
  Organization view (`OrganizationView.jsx`) has no key section, which is
  the gap Justin noticed: keys are workspace-scoped, so they belong next
  to members and the plan meter as much as under personal settings.
- **Legacy key.** `accounts.telemetry_api_key`, one per workspace, still
  accepted.
- **Ingest.** This app serves `/v1/traces` and `/v1/evaluations` with
  `Api::AccountTokenAuthentication`, which resolves the bearer token to an
  `Account` through `Account.authenticate_api_token` and then forgets which
  key it was. `ProcessTelemetryTracesJob` receives only `account_id`.
- **Environment on traces.** The SDK already sends one:
  `ActiveAgent::Telemetry::Configuration#resolved_environment` (Rails env
  by default) lands in `active_agent_telemetry_traces.environment` and
  `resource_attributes["service.environment"]`; the model has
  `scope :for_environment`. Nothing in the dashboard filters on it, and a
  consultant's three client apps all say "production".
- **Evaluation reports.** `EvaluationReportImport` reads `scope`,
  `environment` and `role` from the payload (`SCOPE_KEYS`), but
  `evaluation_runs` stores no environment column (only
  `external_tenant`, `external_run_id`, `scores`, `selection`).

## Design

### 1. A key names a source

- `api_keys.environment` (string, required, defaults to a slug of `name`
  on create; editable). The key's name is what people read ("Acme
  production", "Globex staging", "Internal dev"); `environment` is the
  stable tag traces carry. Unique per workspace.
- `api_keys` → traces and evaluation runs: `active_agent_telemetry_traces.api_key_id`
  and `evaluation_runs.api_key_id` (nullable, indexed with `account_id`),
  plus `evaluation_runs.environment`.
- Ingest passes the key through: `Account.authenticate_api_token` returns
  the `ApiKey` too (or the account with `Current.api_key`),
  `ProcessTelemetryTracesJob` takes `api_key_id:`, and
  `TelemetryTrace.create_from_payload` / `EvaluationReportImport` set
  `environment` from the key when one is present, falling back to the
  payload's value for the legacy key. The key wins because the SDK's value
  is whatever the client app's `RAILS_ENV` says; the key is what the
  workspace owner issued for a given app and stage.
- Legacy `telemetry_api_key` traffic is tagged with the payload's
  environment as today and shown as "(legacy key)" in the filter.

### 2. White labels and multiple apps

One workspace, one key per (app, stage): a consultant issues "Acme
production", "Acme staging", "Globex production". No new "project"
entity: the key name already names the app, and a Pro workspace is the
billing boundary the pilot program grants. If a client needs to see only
their own data, that is a separate workspace with its own keys, not a
filter.

### 3. Global environment filter

- A header control next to the avatar: "All environments" or one key's
  name (plus "(legacy key)" when such traces exist). The selection is kept
  in the URL (`?env=acme-production`) and in `localStorage` per workspace,
  so a shared link opens on the same slice and a reload keeps it.
- `apiFetch` adds `environment=` to every dashboard request when set, and
  the engine's list and aggregate endpoints scope on it: traces,
  interactions, metrics and analytics (`TelemetryTrace.for_environment`),
  evaluation runs and reports (`evaluation_runs.environment`), the
  interactions inbox and the agent stat cards. Agents themselves are
  definitions and stay listed; their counters follow the filter.
- Settings → API Keys and the Organization view ignore the filter.

### 4. Organization view

Show the workspace's keys there (name, environment tag, prefix, last
used, created by) with create and revoke, reusing the Settings → API Keys
component; keep the Settings copy for personal keys if
`ProviderKey.personal_keys_enabled?` ever applies to API keys, otherwise
make Settings link across.

### 5. Order of work

1. Gem: migration (`api_keys.environment`, `api_key_id` + `environment`
   on traces and evaluation runs), `ApiKey` validation and default,
   ingest plumbing (`api_key:` through the job and the import), model
   scopes. Tests on ingest attribution and on the legacy fallback.
2. Gem: `environment` param on the list/aggregate API controllers, with
   a shared `scoped_to_environment(relation)` helper and tests per
   endpoint.
3. Gem: header filter, `apiFetch` param, URL and `localStorage` sync,
   Organization view key section. Frontend tests on the param plumbing.
4. Host: `Account.authenticate_api_token` returns the key; the ingest
   concern passes it; docs on activeagents.ai for issuing one key per
   app and stage.
5. Release in the gem, bump the host pin, Chrome check on staging with
   two keys and a trace from each.

## Open questions

- Should the filter also narrow the sandbox and code-session lists? They
  are not ingested by key, so probably not; they would need their own
  environment later.
- Rate limits and quotas stay per workspace, not per key.
