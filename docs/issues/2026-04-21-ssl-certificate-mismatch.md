# SSL Certificate Mismatch - activeagents.ai

**Date:** 2026-04-21
**Status:** Fix Ready for Apply
**Severity:** Production Outage

## Symptom

Visiting `https://activeagents.ai` shows SSL error:
```
NET::ERR_CERT_COMMON_NAME_INVALID
```

Browser reports: "Your connection is not private"

## Root Cause

The SSL certificate was only configured for `staging.activeagents.ai`, but DNS was pointing the apex domain (`activeagents.ai`) to the same load balancer.

**Configuration mismatch:**
- `dns.tfvars`: `enable_apex_domain = true` (points apex to LB IP)
- `staging/main.tf`: `lb_domain = "staging.activeagents.ai"` (SSL cert domain)

When users visit `https://activeagents.ai`, the load balancer serves the SSL cert for `staging.activeagents.ai` - causing the certificate/domain mismatch error.

## Fix

Updated Terraform configuration to support multiple domains in the SSL certificate:

1. **modules/load-balancer/variables.tf** - Added `additional_domains` variable
2. **modules/load-balancer/main.tf** - Updated SSL cert to include additional domains
3. **terraform/variables.tf** - Added `lb_additional_domains` to root module
4. **terraform/main.tf** - Pass additional_domains to load balancer module
5. **environments/staging/variables.tf** - Added `lb_additional_domains` variable
6. **environments/staging/main.tf** - Auto-include apex domain when `enable_apex_domain = true`

Now when `enable_apex_domain = true`, the SSL certificate includes both:
- `staging.activeagents.ai`
- `activeagents.ai`

## Apply Instructions

```bash
# 1. Navigate to staging environment
cd terraform/environments/staging

# 2. Initialize (if needed)
terraform init

# 3. Plan the changes
terraform plan -var-file=dns.tfvars -var="image=<current-image>" -var="project_id=activeagent-pro"

# 4. Apply (this will recreate the SSL certificate)
terraform apply -var-file=dns.tfvars -var="image=<current-image>" -var="project_id=activeagent-pro"
```

**Note:** Google-managed SSL certificates take 15-60 minutes to provision. The site will remain inaccessible until the new cert is active.

## Verification

After applying, verify:
1. `gcloud compute ssl-certificates describe activeagents-staging-cert --global` shows both domains
2. `curl -I https://activeagents.ai` returns 200 (may take time for cert propagation)
3. Browser shows valid certificate for both domains

## Future Considerations

- Consider separate production environment with dedicated load balancer and SSL cert
- Production should have its own Terraform workspace (`environments/production/`)
- SSL cert for production: `activeagents.ai` and `www.activeagents.ai`
