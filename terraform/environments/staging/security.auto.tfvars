# Public signup protection for staging, which serves activeagents.ai.
# See docs/features/human-check.md before changing a value.

# Cloud Armor on the load balancer: the addresses below get 403, and an
# address that POSTs to /registration or /newsletter_subscription more than
# 20 times a minute is banned for ten minutes (signup_rate_limit).
enable_security_policy = true

# The subscription-bombing bot of 2026-10-17 onwards
# (docs/issues/2026-10-19-signup-bot-email-abuse.md): six addresses made
# about 670 of the 681 signup POSTs in that window. Remove an entry once it
# has been quiet for a month.
blocked_source_ranges = [
  "95.182.89.76/32",
  "31.57.107.185/32",
  "31.59.105.64/32",
  "31.56.204.42/32",
  "95.182.114.251/32",
  "31.56.196.42/32",
]

# Cloudflare Turnstile on the signup and newsletter forms. Turn on only
# after activeagents-staging-turnstile-secret-key has a version:
#   gcloud secrets versions add activeagents-staging-turnstile-secret-key --data-file=-
# then set the widget's site key here.
enable_turnstile   = true
turnstile_site_key = "0x4AAAAAAFeC_UHGKXcKCgNn"
