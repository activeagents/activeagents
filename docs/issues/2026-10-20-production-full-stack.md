# A real production environment: load balancer, DNS switch, the full Terraform stack

Date: 2026-10-20 · Status: draft PR [#181](https://github.com/activeagents/activeagents/pull/181) (`infra/production-full-stack`), to deploy with the 1.9.2 release · Owner: Justin

## Ask

Justin (2026-10-20): "We need to make our production environment including
load balancers and the terraform full stack", after learning that
activeagents.ai has only ever been served by the staging Cloud Run service
and its database. Later the same day: "Let's deploy this with the new
1.9.2 release once the release is ready to merge. Let me know once ready.
We can improve auth later with Google and GitHub signup."

## Found

- `dig activeagents.ai` → 34.49.49.134 → forwarding rules
  `activeagents-staging-http/https`. `activeagents-production` had a Cloud
  Run service (image `4a4d088d`, main of 2026-10-05), migrate job, regional
  Cloud SQL (`db-custom-2-4096`), VPC, sandbox infrastructure and seven
  secrets with versions, but no load balancer, no static IP, and no way for
  the domain to reach it.
- The Cloud DNS zone `activeagents-zone` and every record, plus the
  `activeagent.dev`/`.pro` alias zones, live in the **staging** Terraform
  state. The dns module's zone name is fixed, so a second environment
  cannot instantiate it.
- Certificates: `activeagents-all-domains-cert` (apex, www, staging) ACTIVE;
  staging's per-domain certificates for `api.activeagents.ai`,
  `activeagent.dev` and `www.activeagent.dev` ACTIVE; both `activeagent.pro`
  certificates PROVISIONING_FAILED_PERMANENTLY (registrar never delegated).
- A production plan of the files on `main` was already 13 to add, 3 to
  change (secrets, recordings bucket, APIs added since the last apply).
- Production runs `RAILS_ENV=production` with
  `MAILER_FROM_ADDRESS="ActiveAgent <hello@activeagents.ai>"` and
  `APP_HOST` unset (defaults to activeagents.ai); staging runs with
  `APP_HOST=staging.activeagents.ai` and `noreply@staging.activeagents.ai`.
- Plans get their Stripe price IDs from `db:seed` reading
  `STRIPE_PRO_MONTHLY_PRICE_ID`/`STRIPE_PRO_ANNUAL_PRICE_ID`; Terraform
  passed those only on staging.
- GitHub sign-in is off in both environments (no `github_app.auto.tfvars`).

## Decided

- Keep the zone where it is; add one switch, `public_lb_ip`, to the
  staging environment. Set it to production's static IP and the apex, api
  and alias-domain records move; `staging.activeagents.ai` never does.
  Unset it to roll back. No state surgery on the live domain.
- Production's load balancer serves the certificates staging already holds
  (the load-balancer module gained `additional_existing_ssl_cert_names`),
  so the hostnames move with no TLS gap. Production issues its own
  per-domain certificates afterwards (phase 2 in the runbook).
- Production gets the settings it lacked: 2Gi memory (staging's), CI
  invoker and logging access, authorized domain, `app_host`,
  `mailer_from_address`, live Pro price IDs through a committed
  `billing.auto.tfvars` once the prices exist.
- The deploy workflow checks the load balancer answers for the domain
  before the cutover and that the domain answers from production after it.
- Deploy with the 1.9.2 release. Google and GitHub sign-up: later.

## Done on the branch

See [docs/infrastructure/production-environment.md](../infrastructure/production-environment.md)
for the file-by-file list, the runbook and the cutover checklist.

Verified locally (2026-10-20):

| Check | Result |
|---|---|
| `terraform validate`, staging / production / sandbox-staging | valid |
| `terraform test` (root, mock providers) | 28 passed, 0 failed (19 before, 9 new) |
| `terraform plan`, production, live state, current image | 26 to add, 3 to change, 0 to destroy; the three shared certificates read by name |
| `terraform plan -refresh=false`, staging, switch unset | DNS, alias and load balancer resources unchanged |
| `terraform fmt -check` on the CI-formatted directories | clean |

Local plans need `GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token)`.
A refreshed staging plan fails for `justin@activeagents.ai` with 403 on
`active-agents-platform-recordings-staging` (the bucket's policy is
deliberately narrow), hence `-refresh=false` for the check.

## Still to do (in order)

1. PR review and merge (Terraform CI validates every environment and runs
   the root tests).
2. Dispatch **Deploy to Production** with the 1.9.2 image once the host
   bump (`chore/activeagent-1.9.2`) is on `main`; note `lb_ip_address`.
3. The pre-cutover checklist in the runbook: Resend verifies
   `activeagents.ai`; live Stripe keys confirmed and the live Pro prices
   committed in `billing.auto.tfvars`; `db:seed`; decide on the data
   (migrate the staging database, with staging's encryption keys, or start
   empty); an admin user.
4. Cutover: `public_lb_ip` in staging's `dns.tfvars`, deploy staging,
   verify, deploy production again.
5. Phase 2 certificates; update `docs/issues/2026-10-20-client-pro-pilot.md`
   and the memory note on where the domain points.

## Log

- 2026-10-20 17:00–18:10 UTC: branch written and verified as above.
- 2026-10-20 18:20 UTC: draft PR #181 opened.
- 2026-10-20 18:40 UTC: CI on #181 green (scan, lint, boot, test, Terraform validate + tests). Host bump PR #182 opened alongside.
