# DNS Setup for activeagents.ai

## Overview

This guide explains how to configure DNS for activeagents.ai using Google Cloud DNS managed via Terraform, with GoDaddy as the domain registrar.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│    GoDaddy      │────▶│  Cloud DNS      │────▶│  Load Balancer  │
│  (Registrar)    │     │  (DNS Hosting)  │     │  (GCP)          │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

- **GoDaddy**: Domain registrar only - points nameservers to Cloud DNS
- **Cloud DNS**: Hosts all DNS records, managed via Terraform
- **Load Balancer**: Serves traffic for staging.activeagents.ai (and later production)

## Current Configuration

| Domain | Purpose | Target |
|--------|---------|--------|
| `staging.activeagents.ai` | Staging environment | GCP Load Balancer IP |
| `activeagents.ai` | Production (Framer for now) | Framer CNAME (manual) |

## Step 1: Update GoDaddy Nameservers

After Terraform deploys, you'll get Cloud DNS nameservers. Update them in GoDaddy:

1. Log in to [GoDaddy](https://www.godaddy.com)
2. Go to **My Products** → **Domains** → **activeagents.ai**
3. Click **DNS** → **Nameservers** → **Change**
4. Select **Enter my own nameservers (advanced)**
5. Enter the Cloud DNS nameservers from Terraform output:
   ```
   ns-cloud-a1.googledomains.com
   ns-cloud-a2.googledomains.com
   ns-cloud-a3.googledomains.com
   ns-cloud-a4.googledomains.com
   ```
6. Save changes

**Note**: DNS propagation takes 24-48 hours globally.

## Step 2: Verify DNS Propagation

Check if DNS has propagated:

```bash
# Check nameservers
dig NS activeagents.ai

# Check staging A record
dig A staging.activeagents.ai

# Check from Google's DNS
dig @8.8.8.8 staging.activeagents.ai
```

## Step 3: Preserve Existing Records

Before changing nameservers, copy your existing DNS records from GoDaddy to Cloud DNS:

### Email (MX Records)

If using Google Workspace:
```hcl
mx_records = [
  "1 ASPMX.L.GOOGLE.COM.",
  "5 ALT1.ASPMX.L.GOOGLE.COM.",
  "5 ALT2.ASPMX.L.GOOGLE.COM.",
  "10 ALT3.ASPMX.L.GOOGLE.COM.",
  "10 ALT4.ASPMX.L.GOOGLE.COM.",
]
```

### SPF, DKIM, Domain Verification (TXT Records)

```hcl
txt_records = [
  "\"v=spf1 include:_spf.google.com ~all\"",
  # Add your DKIM records here
]
```

## Step 4: Keep Framer for Main Domain

Until you're ready to migrate the main site to GCP:

1. **Option A** (Recommended): Keep a Framer-specific A record
   - Ask Framer for their static IP address
   - Add it to Cloud DNS as an A record for `activeagents.ai`

2. **Option B**: Use GoDaddy's CNAME flattening
   - Some registrars support CNAME at apex via ALIAS records
   - Cloud DNS doesn't support this natively

## Terraform Outputs

After deployment, get the nameservers:

```bash
cd terraform/environments/staging
terraform output dns_name_servers
```

## SSL Certificate

When using a custom domain with the load balancer:
- Google automatically provisions a managed SSL certificate
- Certificate provisioning takes 15-30 minutes after DNS propagates
- HTTPS will work at `https://staging.activeagents.ai`

## Troubleshooting

### SSL Certificate Not Working

1. Verify DNS has propagated: `dig A staging.activeagents.ai`
2. Check certificate status in GCP Console → Load Balancing → Certificates
3. Certificates require DNS to be resolving for 15-30 minutes

### 403 Forbidden

The org policy blocks public Cloud Run access. Users must authenticate or use IAP.
See [Load Balancer documentation](./load-balancer.md) for details.

### DNS Not Propagating

1. Verify nameservers are updated in GoDaddy
2. Use `dig +trace activeagents.ai` to see where resolution fails
3. Wait 24-48 hours for global propagation

## Future Production Migration

When ready to move production to GCP:

1. Set `production_ip` in Terraform to the production load balancer IP
2. The apex domain `activeagents.ai` will point to GCP
3. WWW subdomain will CNAME to apex
