# Public signup protection for production. See docs/features/human-check.md
# before changing a value. One Turnstile widget covers every hostname, so
# the same site key and secret as staging go here.

# Cloud Armor needs a load balancer in this environment; production gets
# one with infra/production-full-stack. Turn on together with it, and copy
# blocked_source_ranges from staging's security.auto.tfvars.
# enable_security_policy = true
# blocked_source_ranges  = []

# Cloudflare Turnstile on the signup and newsletter forms. Turn on only
# after activeagents-production-turnstile-secret-key has a version (the
# secret exists once production has applied the Terraform that declares it):
#   gcloud secrets versions add activeagents-production-turnstile-secret-key --data-file=- --project=active-agents-platform
enable_turnstile   = true
turnstile_site_key = "0x4AAAAAAFeC_UHGKXcKCgNn"
