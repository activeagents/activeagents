# The production environment, and moving activeagents.ai to it

Status 2026-10-20 (late evening): **production runs 1.9.2; Resend's root
domain is verified; live Stripe is the last item before the cutover.**
Production revision `activeagents-production-00008-wtr` (21:21 UTC) is the
`f4c65fb` build, the one staging runs since #192; a runner on the migrate
job printed activeagent 1.9.2 and actionagent 1.9.2. Getting there found
that a plain re-dispatch of the deploy was a no-op (#196 fixes it,
`docs/issues/2026-10-20-production-deploy-staging-tag-noop.md`). Resend
verified `activeagents.ai` at about 21:55 UTC, roughly forty minutes after
the records went live (DKIM and the tracking CNAME within minutes, the
`send` SPF MX and TXT last; re-triggering the check resets every record
to pending, so waiting is the right move). The admin login exists and the
data decision is final (production starts empty, see "Moving the data").
Remaining: the live Stripe key, webhook secret and Pro price IDs, then the
DNS switch.

Status 2026-10-20 (evening): **production is up, not cut over.** #181
merged (`193700a`) with Justin's go; its first deploy (run 39491306303)
stopped at a 409 because the serverless NEG and the backend service
already existed with no state entry, so #193 adopted both with import
blocks; the second deploy (run 39492120223) applied cleanly (2 imported,
4 added, 2 changed) and ran the migrations. `lb_ip_address` is
**34.120.184.132**; `curl --resolve activeagents.ai:443:34.120.184.132
https://activeagents.ai/up` and the same for `api.activeagents.ai` answer
200, and port 80 redirects to HTTPS. Its smoke test reported 404 from the
load balancer two minutes after the forwarding rule was created and passed
on re-run; the check now retries. The plans are seeded (`db:seed` through
the migrate job, execution `activeagents-production-migrate-4zdlt`).
Found on the way: the production Stripe key is a test-mode placeholder,
so live billing is not set up; Resend's root domain `activeagents.ai` was
added to the account and waits for its records in staging's `dns.tfvars`.
The database is empty and there is no admin. The domain still resolves to
staging (34.49.49.134).

Status 2026-10-20: the Terraform in this branch gives production its own
external HTTPS load balancer and the settings it was missing. The domain
still resolves to staging until the cutover below is made, which is a
one-line change in staging's DNS file. Justin's decision (2026-10-20): the
production stack deploys together with the 1.9.2 platform release
(`docs/releases/1.9.2-rc.md`, host bump `chore/activeagent-1.9.2`).

## How the two environments relate

```
                       activeagents.ai zone (Cloud DNS, in STAGING's state)
                       ┌───────────────────────────────────────────────┐
  staging.activeagents.ai ──A──▶ 34.49.49.134  activeagents-staging-ip   │
  activeagents.ai ─────A──▶ public_lb_ip, or the staging IP while unset │
  www ─────────────CNAME─▶ activeagents.ai                               │
  api.activeagents.ai ─A──▶ same as the apex                             │
  activeagent.dev zone, activeagent.pro zone ─A─▶ same as the apex       │
                       └───────────────────────────────────────────────┘
                                   │                        │
                 activeagents-staging LB          activeagents-production LB
                 (certs: all-domains + extras)    (serves the SAME certificates)
                                   │                        │
                 Cloud Run activeagents-staging   Cloud Run activeagents-production
                 Cloud SQL activeagents-staging   Cloud SQL activeagents-production
                 (what activeagents.ai serves      (what it serves after the
                  today)                            cutover)
```

- **Why the domain served staging.** The zone was created from the staging
  environment during the move off Framer, with `enable_apex_domain = true`
  pointing the apex at staging's load balancer. The production Cloud Run
  service, database and secrets existed, but no load balancer and no route
  from the domain. Everything the site has done since (signups, the
  Combinaut pilot work, Stripe test billing) is in the staging database.
- **One zone, one owner.** The Cloud DNS zone has a fixed name
  (`activeagents-zone`), so only one environment's state can hold it.
  Rather than moving the zone between states, staging's records carry the
  public hostnames and a single variable, `public_lb_ip`, says which load
  balancer they point at. Production has `enable_dns = false`.
- **Shared certificates.** A Google-managed certificate renews while every
  domain on it resolves to a load balancer that serves it, and one
  certificate can be attached to two HTTPS proxies. Production's proxy
  therefore serves `activeagents-all-domains-cert` (apex, www, staging) and
  staging's per-domain certificates for `api.activeagents.ai` and
  `activeagent.dev` (`terraform/environments/production/load_balancer.auto.tfvars`).
  The hostnames can move with no certificate provisioning gap, and after the
  move both proxies keep renewing: the apex resolves to production (which
  serves the cert), staging.activeagents.ai resolves to staging (which does
  too). The `activeagent.pro` certificates are left out; they failed
  permanently because the registrar never delegated the domain.

## What the branch changes

| Where | Change |
|---|---|
| `terraform/modules/load-balancer` | `additional_existing_ssl_cert_names`: certificates read by name and served alongside the proxy's own; `ssl_certificate_names` output |
| `terraform/main.tf`, `variables.tf`, `outputs.tf` | `public_lb_ip` (the switch; apex, api and alias-domain records follow it, the staging record never does); `lb_additional_existing_ssl_cert_names`; `stripe_pro_price_ids` for environments other than staging; `public_lb_ip` and `lb_ssl_certificate_names` outputs |
| `terraform/environments/production` | Load balancer (committed `load_balancer.auto.tfvars`), `app_host = activeagents.ai`, `mailer_from_address`, 2Gi memory, CI invoker and logging access, authorized domain, live Pro price IDs (`billing.auto.tfvars`, to be added), outputs `lb_ip_address`, `production_url`, `lb_ssl_certificate_names` |
| `terraform/environments/staging` | `public_lb_ip` variable, passed through; a commented line in `dns.tfvars` to set at the cutover |
| `terraform/tests/feature_infra.tftest.hcl` | The switch, the shared certificates, the price IDs |
| `.github/workflows/deploy-production.yml` | Outputs the load balancer IP and domain; a "Public hostname" step that checks the load balancer answers for the domain before the cutover and that the domain answers from production after it |

A production plan against the live state (2026-10-20, current image):
26 to add, 3 to change, 0 to destroy. The additions are the load balancer
(address, NEG, backend, URL maps, proxies, forwarding rules), the recordings
bucket and signer, the seven secrets main added since the last production
apply (empty, behind flags), the CI invoker/logging bindings and two APIs.
The changes are the service and migrate job (memory 1Gi → 2Gi,
`INCUS_APP_RUNTIME_ENABLED=false`, the From name) and registry labels.
A staging plan of the DNS, alias and load balancer modules with the switch
unset: no changes.

## Bring production up (before the cutover; nothing public changes)

1. Merge this branch. `terraform.yml` validates every environment and runs
   the root tests on the PR.
2. Run **Deploy to Production** (`deploy-production.yml`, workflow_dispatch).
   With no `image_tag` it deploys the build the `staging` tag points at,
   resolved to that build's commit tag so Terraform sees a new image string
   and Cloud Run rolls a new revision (applying the literal `staging` tag
   was a no-op on a repeat dispatch, see
   `docs/issues/2026-10-20-production-deploy-staging-tag-noop.md`);
   `image_tag=<commit sha>` pins one main build, and a published release
   deploys the release tag. The deploy applies Terraform, runs
   `activeagents-production-migrate`, health-checks the Cloud Run URL and
   then the load balancer by IP:
   `curl --resolve activeagents.ai:443:<lb_ip> https://activeagents.ai/up`.
3. Note `lb_ip_address` from the job summary (or
   `terraform output -raw lb_ip_address` in `terraform/environments/production`).
   It is a reserved static address and never changes.
4. Seed the plans and create the admin login, through the migrate job
   (`gcloud run jobs execute activeagents-production-migrate --region=us-central1 --args=db:seed --wait`;
   the job's command is `./bin/rails`, so `--args` are rails arguments; use
   `^~^` as the delimiter when a value contains a comma or `@`).

Local plans: `GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token)`
with `-var project_id=… -var image=…` works until the recordings bucket
exists; after that a plan needs `storage.buckets.get` on it, which the
bucket's authoritative policy grants only to the app and the signer. Plan
in CI or with a role that has it.

## Before the cutover: what production still needs

| Need | Why | Where |
|---|---|---|
| Resend verifies `activeagents.ai` | Production sends as `hello@activeagents.ai`; Resend refuses an unverified From domain, so no verification, reset or invitation mail would leave | Step 2 of `docs/issues/2026-10-20-email-sender-reputation.md`: add the domain in Resend, put its `resend._domainkey` TXT and `send` SPF/MX records in staging's `dns.tfvars` (the zone owner), deploy staging, verify in Resend |
| Live Stripe | `activeagents-production-stripe-api-key` and `-webhook-secret` have a version each, but checked on 2026-10-20 the key is a test-mode placeholder (`sk_test_…`, rejected by Stripe), so both need the live account's values, plus a live webhook endpoint for `https://activeagents.ai/pay/webhooks/stripe` | Stripe dashboard; `gcloud secrets versions add <secret> --data-file=-` from Justin's terminal |
| Live Pro prices | Checkout refuses the Pro plan without `stripe_monthly_price_id`/`stripe_annual_price_id` on the Plan row; `db:seed` fills them from `STRIPE_PRO_*_PRICE_ID` | Create the $99/month and $995/year prices in live mode, commit them in `terraform/environments/production/billing.auto.tfvars` (`stripe_pro_monthly_price_id`, `stripe_pro_annual_price_id`), deploy, run `db:seed` |
| Data | Decided 2026-10-20: **production starts empty**, nothing is copied from staging. People register again after the cutover; the Combinaut pilot grant is re-made on production (`/admin/pilots`) | See "Moving the data" |
| An admin | `/admin/pilots` needs `users.admin = true` and a verified email | Done: `justin@activeagents.ai` (admin, verified) and the "ActiveAgents" account were created on production with a one-off `runner` on 2026-10-20 |
| GitHub sign-in (optional) | Staging never turned it on (`enable_github_sign_in` is off there too), so nothing is lost at the cutover | `docs/infrastructure/gcp-cicd-setup.md` when wanted |
| Sandboxes | Production has no Incus host; Cloud Run sandboxes use the root defaults (1 vCPU, 512Mi). The Claude Code checkout features that staging tests against sandbox-staging are off | Later: a `sandbox-production` environment like `terraform/environments/sandbox-staging` |

### Moving the data

Not done, by decision (Justin, 2026-10-20): production starts with an empty
database. Only the plans (`db:seed`) and the admin login above exist on it.
The reasons a copy was never attractive still hold and are why the decision
is final rather than deferred: staging's encrypted columns are bound to
staging's keys, and its Stripe objects are test-mode ones that do not exist
in the live account. People re-register after the cutover, the Combinaut
pilot grant is re-made on production, and staging's bot-created users
(`docs/issues/2026-10-19-signup-bot-email-abuse.md`) never reach it.

## The cutover

1. In `terraform/environments/staging/dns.tfvars`, set
   `public_lb_ip = "<lb_ip_address of production>"` (the commented line).
2. Open a PR with just that change; merge it. `deploy-staging.yml` applies
   it: the apex, api and alias-domain A records change to production's IP
   (TTL 300 seconds); www follows as a CNAME; `staging.activeagents.ai`
   stays on staging.
3. Check: `dig +short activeagents.ai @8.8.8.8` returns production's IP;
   `curl -sI https://activeagents.ai/up` is 200; sign in; a password reset
   email arrives from `hello@activeagents.ai` with a link to
   `https://activeagents.ai/...`.
4. Run **Deploy to Production** once more. Its "Public hostname" step now
   requires `https://activeagents.ai/up` to answer from production.

**Rollback:** comment `public_lb_ip` out again and deploy staging. The
records return to staging's IP within the TTL; the certificates were never
touched.

### Phase 2: production's own certificates

After the cutover the hostnames resolve to production, so it can issue its
own per-domain certificates:

1. In `load_balancer.auto.tfvars` set
   `lb_extra_managed_domains = ["api.activeagents.ai", "activeagent.dev", "www.activeagent.dev"]`
   and deploy. Each certificate provisions in 15–60 minutes
   (`gcloud compute ssl-certificates list`).
2. When all are ACTIVE, empty `lb_additional_existing_ssl_cert_names` and
   deploy again.
3. In staging's `dns.tfvars`, remove the same domains from
   `lb_extra_managed_domains`; their staging certificates would stop
   renewing anyway, since the domains no longer resolve to staging.

`activeagents-all-domains-cert` stays shared: it is the apex certificate
for both environments' purposes and renews as long as each of its domains
resolves to one of the two proxies.

## After the cutover

- `deploy-staging.yml` keeps deploying every push to `main` to
  `staging.activeagents.ai`, now a real staging site with its own data.
- `deploy-production.yml` runs on a published GitHub release, or by hand
  with an image tag. Production no longer moves on every merge.
- One-off commands: `activeagents-production-migrate`, as above.
- Update the memory note and `docs/issues/2026-10-20-combinaut-pro-pilot.md`:
  the pilot is granted on whichever database serves the domain.
