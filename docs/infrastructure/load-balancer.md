# External Load Balancer for Cloud Run

## Overview

Both environments use an external HTTPS Load Balancer to provide public access to their Cloud Run service. This bypasses GCP organization policy restrictions that block `allUsers` and `allAuthenticatedUsers` IAM bindings on Cloud Run. Staging's answers for `staging.activeagents.ai`; production's is the one `activeagents.ai` moves to (see [production-environment.md](production-environment.md)).

## Architecture

```
┌─────────────┐    ┌─────────────────┐    ┌─────────────────────┐
│   Internet  │───▶│ Cloud Load      │───▶│ Serverless NEG      │
│             │    │ Balancer        │    │ (Cloud Run Service) │
└─────────────┘    └─────────────────┘    └─────────────────────┘
                          │
                   ┌──────┴──────┐
                   │  Cloud CDN  │
                   │ (Caching)   │
                   └─────────────┘
```

## Components

### 1. Serverless Network Endpoint Group (NEG)
Points to the Cloud Run service, allowing the load balancer to route traffic.

### 2. Backend Service
- Protocol: HTTP
- Load balancing scheme: EXTERNAL_MANAGED
- Cloud CDN enabled with caching policy
- Logging enabled at 100% sample rate

### 3. URL Map
Routes all traffic to the backend service.

### 4. SSL Certificate (optional)
- Managed SSL certificate when a custom domain is configured
- Without a domain, HTTP-only access is available via IP address

### 5. HTTP/HTTPS Proxies and Forwarding Rules
- HTTPS forwarding when domain is configured
- HTTP forwarding for IP-based access
- HTTP to HTTPS redirect when domain is present

## Configuration

### Terraform Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_load_balancer` | Enable external load balancer | `false` |
| `lb_domain` | Custom domain for SSL certificate | `null` |
| `lb_existing_ssl_cert_name` | Serve a certificate that already exists instead of issuing one | `null` |
| `lb_additional_existing_ssl_cert_names` | Further existing certificates the proxy also serves (shared with the other environment's load balancer, so a hostname can move with no provisioning gap) | `[]` |
| `lb_extra_managed_domains` | Domains that each get their own managed certificate | `[]` |
| `enable_cdn` | Enable Cloud CDN caching | `true` |

A Google-managed certificate keeps renewing while every domain on it resolves to a load balancer that serves it, and the same certificate can be attached to more than one HTTPS proxy. That is what lets production serve `activeagents-all-domains-cert` and staging's per-domain certificates during and after the cutover.

### Staging Environment

The staging environment has `enable_load_balancer = true` by default:

```hcl
# terraform/environments/staging/variables.tf
variable "enable_load_balancer" {
  type    = bool
  default = true
}
```

## Access URLs

### Without Custom Domain
- Public URL: `http://<LOAD_BALANCER_IP>`
- Cloud Run URL: `https://activeagents-staging-xxxx-uc.a.run.app` (requires auth)

### With Custom Domain
- Public URL: `https://staging.activeagents.ai`
- HTTP automatically redirects to HTTPS

## Outputs

| Output | Description |
|--------|-------------|
| `lb_ip_address` | Static IP address of the load balancer |
| `lb_url` | Full URL (http or https based on domain config) |
| `public_url` | Best URL for public access |

## Cloud CDN Configuration

When enabled, Cloud CDN caches static assets:

- Cache mode: `CACHE_ALL_STATIC`
- Default TTL: 1 hour (3600s)
- Max TTL: 24 hours (86400s)
- Client TTL: 1 hour
- Serve stale while revalidating: 24 hours
- Negative caching enabled

## Security Notes

1. **HTTP Access**: Without a domain, traffic is HTTP-only. Use a custom domain for production.
2. **Cloud Run IAM**: The Cloud Run service itself still has IAM restrictions. The load balancer's serverless NEG bypasses this for incoming traffic.
3. **WAF**: Consider adding Cloud Armor for DDoS protection and WAF capabilities.

## Adding a Custom Domain

1. Update staging variables:
   ```hcl
   lb_domain = "staging.activeagents.ai"
   ```

2. Create DNS record pointing to the load balancer IP:
   ```
   staging.activeagents.ai. A <lb_ip_address>
   ```

3. Wait for SSL certificate provisioning (can take 15-30 minutes)
