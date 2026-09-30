# Staging Pro billing

Staging uses test billing only. Production deployment is a separate release/manual workflow.
Do not use complimentary Pro grants to verify subscription checkout.

## Configuration

1. Store the sandbox API key in the existing staging Secret Manager secret, and
   the staging Stripe webhook signing secret in its separate signing-secret slot.
   Never put secret values in GitHub variables, source, workflow output, or logs.
2. Run **Staging billing diagnostics**. Its sanitized report identifies the
   account and verifies `livemode=false` with a Stripe API response. A key prefix
   alone does not prove valid sandbox access. All effective keys should agree.
3. Set the GitHub **staging environment** variable `STRIPE_STAGING_ACCOUNT_ID`
   to that verified account ID. Deployment stops before Terraform if it is absent.
4. Optionally set staging environment variables `STRIPE_PRO_MONTHLY_PRICE_ID`
   and `STRIPE_PRO_ANNUAL_PRICE_ID` to existing matching sandbox prices. Terraform
   passes them to both the web service and maintenance job.

After migrations, staging deployment runs `bin/rails stripe:setup_pro` in the
existing staging Cloud Run job. The task requires the staging database, matching
test keys, the expected account, and an active Pro plan configured for $99/month,
$995/year, and a 14-day trial. It reuses matching prices or creates only missing
Pro catalog objects with stable product/lookup IDs and idempotency keys. It
refuses conflicting or ambiguous configuration. It never creates Enterprise,
Advisory, customers, subscriptions, or access grants.

Price IDs persist on the Plan. Repeated setup reuses them, and seeds preserve them
when price variables are omitted. The old broad `stripe:setup` task stops with
instructions to use the scoped task.

Pay owns Stripe key resolution, with the deployed environment taking precedence
over encrypted credentials. `STRIPE_REQUIRE_TEST_MODE=true` is injected only for
staging; boot fails if the effective key is live or disagrees with Pay.

## End-to-end acceptance

- Reuse the existing verified staging user and workspace; select monthly Pro.
- Confirm Stripe Checkout is in test mode and shows $99/month after a 14-day trial.
- Complete checkout using Stripe's documented test card details.
- Verify an actual test Stripe subscription has status `trialing`, the expected
  price, and a 14-day trial. Verify webhook delivery to
  `https://staging.activeagents.ai/pay/webhooks/stripe` with the matching secret.
- Verify Pay stored that subscription on the original workspace, the app reports
  `access_source=trial` and `current_plan=pro`, and the effective quotas are
  10,000 runs/month, 25,000 traces/month, and 14-day retention. A checkout redirect
  or complimentary grant is not evidence that billing synchronization works.
- Verify annual catalog pricing separately; do not create a second subscription
  on the same workspace just to check its price.

Tax setup is outside this staging trial test; no automatic tax settings are changed.
