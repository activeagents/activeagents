# DNS records migrated from GoDaddy
# These records will be created in Cloud DNS

# Framer website A records (apex domain)
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
  }
]
