# DNS records migrated from GoDaddy
# These records will be created in Cloud DNS

# LIVE MIGRATION: Point apex domain to Cloud Run load balancer
# Set to true to switch activeagents.ai from Framer to Cloud Run
enable_apex_domain = true

# Use existing SSL certificate (already provisioned and active)
# This avoids the 15-60 min provisioning delay when creating new certs
# Certificate covers: activeagents.ai, www.activeagents.ai, staging.activeagents.ai
lb_existing_ssl_cert_name = "activeagents-all-domains-cert"

# Framer website A records (apex domain) - IGNORED when enable_apex_domain = true
# Updated 2026-02-24 - IPs from Framer custom domain settings
framer_ips = [
  "31.43.160.6",
  "31.43.161.6"
]

# Framer www CNAME
framer_www_cname = "sites.framer.app"

# Google Workspace MX records
mx_records = [
  "1 aspmx.l.google.com.",
  "5 alt1.aspmx.l.google.com.",
  "5 alt2.aspmx.l.google.com.",
  "10 alt3.aspmx.l.google.com.",
  "10 alt4.aspmx.l.google.com."
]

# TXT records at apex domain
txt_records = [
  "\"v=spf1 include:dc-aa8e722993._spfm.activeagents.ai ~all\"",
  "\"google-site-verification=fvyFSc0J2yyHZk4r2HLwNga4k4DeSJ_weFce2xRs44g\""
]

# DMARC record
dmarc_record = "v=DMARC1; p=none;"

# Additional TXT records for subdomains
additional_txt_records = [
  {
    name  = "dc-aa8e722993._spfm"
    value = "v=spf1 include:_spf.google.com ~all"
  },
  {
    name  = "_github-pages-challenge-activeagents"
    value = "f0c8a02a4d095acfbfe0da71cf06e0"
  },
  # Loops dev.activeagents.ai SPF record
  {
    name  = "envelope.dev"
    value = "v=spf1 include:amazonses.com ~all"
  },
  # Resend staging.activeagents.ai DKIM record
  {
    name  = "resend._domainkey.staging"
    value = "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDT7fHYBUcxVla5UpvXOCKE1U22N9grlPPARgyBzT6+/it88nEzKoILoTCKKhAi0TmCnVuzYjVwm6r8LNC4xqogXyXWAJM4lySHl8TWrB7Z6OUH8tevNiePzRbIu4pGxWxOAFpnJLjmJ+E9n8vxBku6b04buqaO0RJwYQQpYobfOQIDAQAB"
  },
  # Resend staging.activeagents.ai SPF record
  {
    name  = "send.staging"
    value = "v=spf1 include:amazonses.com ~all"
  }
]

# Docs subdomain - GitHub Pages for activeagent gem documentation
docs_cname = "activeagents.github.io"

# Subdomain MX records for email sending
subdomain_mx_records = [
  # Loops dev.activeagents.ai
  {
    name   = "envelope.dev"
    values = ["10 feedback-smtp.us-east-1.amazonses.com."]
  },
  # Resend staging.activeagents.ai
  {
    name   = "send.staging"
    values = ["10 feedback-smtp.us-east-1.amazonses.com."]
  }
]

# Loops dev.activeagents.ai DKIM CNAME records
additional_cname_records = [
  {
    name  = "337kwbrgejhaugxhexvz4yglsl3giymj._domainkey.dev"
    value = "337kwbrgejhaugxhexvz4yglsl3giymj.dkim.amazonses.com"
  },
  {
    name  = "k5y5v4li5eujjkoibotfcdy4ofhb2sst._domainkey.dev"
    value = "k5y5v4li5eujjkoibotfcdy4ofhb2sst.dkim.amazonses.com"
  },
  {
    name  = "dn5ndiapkeqyfssjzcxnrnm2nszh32gm._domainkey.dev"
    value = "dn5ndiapkeqyfssjzcxnrnm2nszh32gm.dkim.amazonses.com"
  }
]
