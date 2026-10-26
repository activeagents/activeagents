# Uncapped agent runs for complimentary Pro pilots

Status: built 2026-10-26 on `feat/pilot-uncapped-runs` · Environment: all (host app, `Account` model)

## Ask

Justin (2026-10-26): "maybe we uncap the run limit for the pilots since
they're paying me for the evals work anyway. That way we get a better
understanding of the realistic usage for a pro team plan or our pricing in
general."

## What changed

- `Account#effective_agent_runs_limit` returns `-1` (unlimited) when
  `access_source` is `complimentary_pilot`, i.e. an active `pro_access_grant`
  with no real billing subscription. `Account#pilot_runs_uncapped?` names the
  condition.
- Everything downstream already understood `-1` because Enterprise uses it:
  `can_run_agent?` is always true, `agent_runs_remaining` is infinite,
  `usage_stats[:runs_limit]` is `-1`, and the engine's `quota_checker` in
  `config/initializers/action_agent.rb` never returns a denial for `:execution`.
  `usage_recorder` still increments `agent_runs_this_period`, so the usage
  numbers keep accumulating; that is the point.
- Not uncapped: the trace quota (`effective_trace_limit`, Pro's 25,000 per
  period) and retention (Pro's 14 days). Both are cheap to raise later if a
  pilot hits them; raising them was not asked for.
- `/admin/pilots` now prints "Runs this period: N of unlimited (pilot)" and
  "Traces this period: N of 25000" under each workspace, so the realistic
  usage the pilots are meant to reveal is visible without a console.

## Precedence (unchanged order, new consequence)

| Access source | Run cap |
|---|---|
| Real Stripe subscription or trial | the plan's cap (Pro 10,000; Enterprise unlimited) |
| Complimentary pilot grant, active | **unlimited** |
| Legacy `fake_processor` complimentary | the plan's cap |
| Free | 25 |

A paying pilot that later subscribes to Pro drops back to 10,000; if that is
not wanted when the time comes, the grant can stay and the check can prefer
it, but today a real subscription deliberately wins.

## Tests

`test/services/pro_access_test.rb`: "pilot grants uncap agent runs while a
paid plan keeps its cap" (over the Pro cap: refused on Free, allowed with the
grant, refused again with a paid subscription, refused on Free after
revocation) plus the limit assertions in the existing grant test.

## Log

- 2026-10-26: built, tests green locally (7 runs, 45 assertions), PR opened.
