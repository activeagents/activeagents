# activeagent.dev DNS delegation (2026-09-08)

## Problem

activeagent.dev served GoDaddy's parking lander. The domain was still on
GoDaddy's default nameservers (`ns67/ns68.domaincontrol.com`), which answer
with GoDaddy's parking IPs. Terraform had already created the Cloud DNS zone
(`activeagent-dev-zone`: apex A → 34.49.49.134, www CNAME, CAA), but the
registrar-side NS delegation — the documented second step in
`terraform/modules/domain-alias/main.tf` — was never done.

## Fix applied

Changed the nameservers for activeagent.dev in GoDaddy (Domain Portfolio →
DNS → Nameservers → "I'll use my own nameservers") to the zone's servers:

- ns-cloud-b1.googledomains.com
- ns-cloud-b2.googledomains.com
- ns-cloud-b3.googledomains.com
- ns-cloud-b4.googledomains.com

Verified: the .dev registry now delegates to the four Google nameservers, and
`dig activeagent.dev @8.8.8.8` returns 34.49.49.134 (the platform LB).

## Remaining: TLS certs failed permanently

The per-domain managed certs provisioned while DNS was still parked and are
stuck (`gcloud compute ssl-certificates list`):

- `activeagents-staging-extra-activeagent-dev` — PROVISIONING_FAILED_PERMANENTLY
- `activeagents-staging-extra-www-activeagent-dev` — PROVISIONING_FAILED_PERMANENTLY

Permanently failed certs never retry; they must be deleted and recreated now
that DNS resolves to the LB. Recreating with the same name/domains keeps
terraform state consistent (cert resource ids are name-based). `.dev` is
HSTS-preloaded, so the site is unreachable until a cert is ACTIVE.

```bash
# 1. Detach the two failed certs from the proxy
gcloud compute target-https-proxies update activeagents-staging-https-proxy --global \
  --ssl-certificates=activeagents-all-domains-cert,activeagents-staging-extra-activeagent-pro,activeagents-staging-extra-api-activeagents-ai,activeagents-staging-extra-www-activeagent-pro

# 2. Delete and recreate with identical names/domains
gcloud compute ssl-certificates delete activeagents-staging-extra-activeagent-dev --global -q
gcloud compute ssl-certificates delete activeagents-staging-extra-www-activeagent-dev --global -q
gcloud compute ssl-certificates create activeagents-staging-extra-activeagent-dev --global --domains=activeagent.dev
gcloud compute ssl-certificates create activeagents-staging-extra-www-activeagent-dev --global --domains=www.activeagent.dev

# 3. Re-attach everything
gcloud compute target-https-proxies update activeagents-staging-https-proxy --global \
  --ssl-certificates=activeagents-all-domains-cert,activeagents-staging-extra-activeagent-dev,activeagents-staging-extra-www-activeagent-dev,activeagents-staging-extra-activeagent-pro,activeagents-staging-extra-api-activeagents-ai,activeagents-staging-extra-www-activeagent-pro

# 4. Watch provisioning (15–60 min after DNS is visible)
watch -n 60 'gcloud compute ssl-certificates list --format="table(name,managed.status,managed.domainStatus)"'
```

## Also pending

- **activeagent.pro** is in the same pre-delegation state (its certs are also
  FAILED_NOT_VISIBLE). Same registrar NS change is needed at its registrar,
  pointing at `activeagent-pro-zone`'s nameservers, then the same cert
  delete/recreate dance.
- **DNSSEC**: the Cloud DNS zone has DNSSEC on, but GoDaddy holds no DS
  record, so the delegation is unsigned (works fine, just not validated).
  Optional: add the DS record from
  `gcloud dns managed-zones describe activeagent-dev-zone --format="value(dnssecConfig)"`
  / the zone's registrar setup page in Cloud Console.
