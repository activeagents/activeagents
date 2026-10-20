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
`activeagents-staging-stripe-webhook-secret`. Staging picks both up at its
next deploy, which creates a new revision; the test-mode Pro prices are
still `StagingProBilling`'s to set (`stripe:setup_pro`, the deploy's
`billing` job).
