# The production load balancer's certificates. Terraform loads this file on
# every plan, locally and in deploy-production.yml, so these are the values
# that apply (docs/infrastructure/gcp-cicd-setup.md, "Every setting lives in
# the tf files").
#
# Phase 1 (now): serve the certificates staging already holds, so the
# hostnames can move here with no provisioning gap. A Google-managed
# certificate keeps renewing while each of its domains resolves to a load
# balancer that serves it, and the same certificate can be attached to two
# HTTPS proxies. activeagents-all-domains-cert covers activeagents.ai,
# www.activeagents.ai and staging.activeagents.ai; the staging-extra ones
# cover api.activeagents.ai and activeagent.dev. The activeagent.pro
# certificates are left out: they failed permanently because the registrar
# never delegated the domain.
#
# Phase 2 (after the cutover, docs/infrastructure/production-environment.md):
# list api.activeagents.ai and the alias domains in lb_extra_managed_domains,
# wait for those certificates to go ACTIVE, then empty
# lb_additional_existing_ssl_cert_names and drop the same domains from
# staging's lb_extra_managed_domains.

enable_load_balancer      = true
lb_existing_ssl_cert_name = "activeagents-all-domains-cert"

lb_additional_existing_ssl_cert_names = [
  "activeagents-staging-extra-api-activeagents-ai",
  "activeagents-staging-extra-activeagent-dev",
  "activeagents-staging-extra-www-activeagent-dev",
]

lb_extra_managed_domains = []
