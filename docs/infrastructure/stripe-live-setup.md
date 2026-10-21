# Live Stripe billing for production: `bin/stripe-live-setup`

Runbook context: [production-environment.md](production-environment.md),
"Before the cutover". Staging's test-mode counterpart is
`StagingProBilling` (`docs/staging-billing.md`), which runs inside the app
against the staging database. Production's setup runs from an operator's
terminal instead, because it also has to write a secret, and the only thing
it cannot do through the API is obtain the live key.

## What it does

```
bin/stripe-live-setup                          # do it
bin/stripe-live-setup --dry-run                # report, change nothing
bin/stripe-live-setup --account acct_…         # the account the live key must belong to
bin/stripe-live-setup --env staging            # staging: key check and test-mode webhook only
bin/stripe-live-setup --replace-webhook        # recreate the endpoint so its secret can be stored
```

With `--env staging` the catalog steps are skipped (`StagingProBilling`
owns staging's test-mode product and prices) and only the key check and the
webhook endpoint for `https://staging.activeagents.ai/pay/webhooks/stripe`
run, with the signing secret stored in
`activeagents-staging-stripe-webhook-secret`. `--replace-webhook` deletes
the endpoint(s) at the URL and creates one anew: the only way to get a
signing secret into Secret Manager for an endpoint that already exists.

1. Reads the live secret key from `activeagents-production-stripe-api-key`
   in Secret Manager (never printed) and refuses anything that is not a
   live-mode key (`sk_live_`/`rk_live_`), is not reported as `livemode` by
   `/v1/balance`, or belongs to another Stripe account than expected. The
   expected account is `--account`, else staging's deployed
   `STRIPE_EXPECTED_ACCOUNT_ID` (empty as of 2026-10-20, hence the flag).
2. Finds or creates the Pro product `activeagents_pro` and its two prices,
   $99/month and $995/year, by lookup key
   (`activeagents_pro_monthly_usd_9900_v1`, `activeagents_pro_annual_usd_99500_v1`),
   with the same shape checks as `StagingProBilling`. A rerun creates
   nothing; duplicates it cannot choose between stop it.
3. Finds or creates the webhook endpoint for
   `https://activeagents.ai/pay/webhooks/stripe` with every event Pay 7.3
   handles, and on creation pipes the endpoint's signing secret into a new
   version of `activeagents-production-stripe-webhook-secret`. Stripe
   returns that secret once, so an existing endpoint keeps its secret (the
   script adds missing events to it and says so).
4. Writes `terraform/environments/production/billing.auto.tfvars` with the
   two price IDs on `chore/stripe-live-prices`, cut from `origin/main` in a
   temporary worktree, pushes it and opens a pull request. If `origin/main`
   already has the same IDs, nothing is committed.

Only IDs are printed: account, product, prices, endpoint, pull request.

## Operator steps

```bash
# 1. the live key, from the Stripe dashboard, into Secret Manager (silent prompt)
read -s V; printf '%s' "$V" | gcloud secrets versions add activeagents-production-stripe-api-key --data-file=- --project=active-agents-platform; unset V
# 2. everything else
bin/stripe-live-setup --account acct_…
```

Then merge the pull request, run **Deploy to Production**, and run
`db:seed` through the migrate job so the Pro plan row gets the IDs:

```bash
gcloud run jobs execute activeagents-production-migrate --region=us-central1 --project=active-agents-platform --wait --args=db:seed
```

`db:seed` only writes `stripe_*` plan attributes that are present, so it
never blanks IDs on a later run without the variables.

## 2026-10-20 run

Justin ran it at about 22:35 UTC with `--account acct_1SyJzXE3QRGeeIHk`
(the account behind the test key in `config/credentials.yml.enc`,
"Artificially Incorporated"). Created in live mode: product
`activeagents_pro`, prices `price_1USlerE3QRGeeIHk0M6BStYF` (monthly) and
`price_1USlerE3QRGeeIHkhOElxc2K` (annual), endpoint
`we_1USlerE3QRGeeIHkD4L9Ugp4`; the webhook secret got version 2; pull
request [#198](https://github.com/activeagents/activeagents/pull/198). The
run ended with a harmless traceback from the temp-dir cleanup, fixed in the
same change that added this document.

Webhook deliveries fail until the DNS cutover, because `activeagents.ai`
still reaches staging, whose signing secret differs. There is nothing to
deliver yet and Stripe retries for three days; after the cutover the
endpoint's attempts in the dashboard should turn green.

## Found on the way, and staging

Both Stripe API keys that were in Secret Manager before this,
`activeagents-staging-stripe-api-key` version 1 and
`activeagents-production-stripe-api-key` version 1 (2026-03-27), answered
HTTP 401 from Stripe: invalid. Staging's checkout had therefore been
broken. Production's version 1 was the placeholder the runbook already
named.

Justin's call ("staging should just use the existing test mode API key"):
at 22:40 UTC the test key from `config/credentials.yml.enc` (same account,
valid) became version 2 of `activeagents-staging-stripe-api-key`, and
`bin/stripe-live-setup --env staging` created the test-mode endpoint
`we_1USljJE3QRGeeIHkHH3tXeWP` for
`https://staging.activeagents.ai/pay/webhooks/stripe` (none existed),
storing its signing secret as version 2 of
`activeagents-staging-stripe-webhook-secret`. Staging revision
`activeagents-staging-00127-xmt` (the deploy of #199) picked both up.

The test-mode Pro prices followed through the existing path: the deploy's
`billing` job runs `stripe:setup_pro` (`StagingProBilling`) only when the
repository variable `STRIPE_STAGING_ACCOUNT_ID` is set, and it was empty.
With it set to `acct_1SyJzXE3QRGeeIHk`, the first dispatched run
(39512188611, 23:01 UTC) stopped on "Multiple Pro products exist; configure
explicit price IDs": the test account has three active `ActiveAgent.PRO`
products with `plan_slug=pro`. The newest one's $99/$995 pair (product
`prod_UEckyKSdq4SlCp`, 2026-03-29) went into the repository variables
`STRIPE_PRO_MONTHLY_PRICE_ID` = `price_1TG9UtE3QRGeeIHkX5Nmjyox` and
`STRIPE_PRO_ANNUAL_PRICE_ID` = `price_1TG9UtE3QRGeeIHknLLzEkg2`, and the
second run (39513972279, 23:26 UTC) passed: `StagingProBilling` validated
them and wrote them onto staging's Pro plan row (14-day trial). Staging
checkout works in test mode again.

## Events: 18 of 19

Pay 7.3 subscribes to `payment_method.card_automatically_updated`, an event
type Stripe no longer has; Stripe silently drops it from `enabled_events`,
so both endpoints came back with 18 events. The script's list no longer
includes it, otherwise every rerun would "add" it again.

## Incident 2026-10-20: the live key was echoed into the operator session

At 23:05 UTC, while checking the endpoint's events from the operator
session, a command fed the live key and a Python script into the same
stdin (`gcloud secrets versions access … | python3 - <<'PY'`); Python's
syntax error echoed the first stdin line, the key, into the session's
transcript. The key is therefore treated as compromised. Nothing else was
exposed: the webhook signing secrets and the staging key were not in that
command.

Remediation, in order, all done by 2026-10-21:

1. Justin rolled the live secret key in the Stripe dashboard (live mode,
   Developers → API keys, roll with immediate expiry) at about 23:45 UTC
   on 2026-10-20. Stripe has no API for this. Rolling does not affect
   endpoints or their signing secrets; the exposed value answered
   `401 Expired API Key` minutes later.
2. Versions 2 and 3 of `activeagents-production-stripe-api-key` were
   disabled the same night (`gcloud secrets versions disable`), so
   nothing can resolve to the exposed value.
3. The new key became version 4 on 2026-10-21 at 19:30 UTC, added by
   Justin from his own terminal
   (`read -s V; printf '%s' "$V" | gcloud secrets versions add … --data-file=-`).
   The file-based probe reported `sk_live_… HTTP 200 livemode=True
   account=acct_1SyJ…`.
4. **Deploy to Production** was dispatched at 19:32 UTC (run 39662460277)
   and rolled revision `activeagents-production-00010-26m` (build
   `e151cd5`, main after #200), which started with version 4; a runner on
   the migrate job then confirmed Pay reports `livemode=true` for the same
   account, printing only the key's prefix (details below).

The in-production check was execution `activeagents-production-migrate-6h8pb`
(19:40 UTC, a `runner` through the migrate job, whose template the deploy
had just updated); it printed `STRIPE_CHECK prefix=sk_live_ livemode=true
account=acct_1SyJzXE3QRGeeIHk webhook_secret_prefix=whsec_`. The secret
versions now read: 4 enabled (current), 3 and 2 disabled (exposed and
expired), 1 enabled (the 2026-03-27 placeholder, invalid; harmless because
`latest` resolves to 4).

Rule going forward, now in the operator's notes as well: a piped secret is
only ever consumed by a script *file* (`python3 -I probe.py`), never by an
interpreter reading its program from stdin, and probes print prefixes and
booleans only.
