# Production: missing Resend audience + 1Gi OOM — 2026-08-27

Found while verifying that the activeagents.ai lander actually collects signups
into Resend. Both issues predate the lander work.

## 1. Production was never syncing signups to Resend

`SyncUserToResendJob` starts with:

```ruby
audience_id = ENV["RESEND_AUDIENCE_ID"]
raise "RESEND_AUDIENCE_ID environment variable not set" if audience_id.blank?
```

The deployed production Cloud Run service had **no `RESEND_AUDIENCE_ID`**, and the
backing secret `activeagents-production-resend-audience-id` **did not exist** —
only the staging equivalent had ever been created.

Effect: every signup on activeagents.ai created the User and sent the
verification email (`RESEND_API_KEY` was present), but the job then raised and
the contact never reached the Resend audience. Email delivery worked; audience
collection did not.

Scope check: `User.where(synced_to_resend: false).count` in production shows how
many signups were affected.

### Fix applied

```
gcloud secrets create activeagents-production-resend-audience-id \
  --replication-policy=automatic \
  --labels=secret_name=resend-audience-id,environment=production
# value: d294369d-a1e5-4a18-8818-9b79a86a4a68  ("Users" audience)

gcloud run services update activeagents-production --region=us-central1 \
  --update-secrets=RESEND_AUDIENCE_ID=activeagents-production-resend-audience-id:latest \
  --update-env-vars=MAILER_FROM_ADDRESS='ActiveAgent <hello@activeagents.ai>'
```

The audience ID was confirmed against the Resend API using the production key —
it is the "Users" audience. The account also has "Newsletter"
(`e47ac620-c823-4712-b0fd-f576d8ce132e`) and "General"
(`1a1e9a75-42d4-49a6-b4d0-a2e604637a89`) if per-source routing is wanted later;
the code records `signup_source`, so segmentation can also be done inside Resend.

`MAILER_FROM_ADDRESS` was also unset in production (it fell back to the
`hello@activeagents.ai` default in `config/environments/production.rb:73`, so it
was benign) — set explicitly for parity with staging.

## 2. Production ran at 1Gi and could not boot

The first update attempt failed:

```
ERROR: The user-provided container ran out of memory.
Memory limit of 1024 MiB exceeded with 1229 MiB used
```

The app boots fully — Puma listening, Solid Queue supervisor/worker/dispatcher
started — then is OOM-killed. Rails + Puma + Solid Queue in one container
(`SOLID_QUEUE_IN_PUMA=true`) peaks around 1.2GB. Staging has always run 2Gi;
production was declared at 1Gi in `terraform/environments/production/main.tf`.

This was a **latent production risk, not caused by the env var change**: the
serving revision was healthy only because it was already running. Any restart,
cold start, or scale-up would have hit the same ceiling.

No outage occurred — Cloud Run kept 100% of traffic on the healthy revision
`activeagents-production-00003-pt9` and the failed revision never received
traffic. activeagents.ai returned 200 throughout.

### Fix applied

Raised the service to 2Gi and set `memory = "2Gi"` in
`terraform/environments/production/main.tf` with a comment explaining why, so a
later apply does not silently revert it.

## 3. Config drift between Terraform and the deployed service

`terraform/main.tf` already declared `resend-audience-id` (line 155),
`RESEND_AUDIENCE_ID` (line 205), and `MAILER_FROM_ADDRESS` (line 197) — yet none
were present on the deployed service, which was also missing `SKIP_DB_PREPARE`.
Production was evidently deployed through a path that did not apply this
Terraform.

**Worth following up:** reconcile the deployed production service with
`terraform/environments/production/`, ideally with a `terraform plan` against
production state to see the full extent of the drift. Note that the apex DNS zone
is managed from the *staging* workspace (`terraform/environments/staging/dns.tfvars`);
there is no production dns.tfvars.

## Verification

- Serving revision and traffic split checked before and after
- `curl https://activeagents.ai/` returned 200 throughout
- Audience ID validated against `GET https://api.resend.com/audiences`
