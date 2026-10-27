# The production GitHub App (https://github.com/apps/activeagents-production), which
# gives checkout sandboxes repository access through installations. See
# docs/infrastructure/gcp-cicd-setup.md before changing a flag: Cloud Run
# refuses a revision whose secrets have no version, so enable_github_app
# needs activeagents-production-github-app-private-key and -webhook-secret first.
github_app_id     = "5444042"
github_app_slug   = "activeagents-production"
enable_github_app = true
