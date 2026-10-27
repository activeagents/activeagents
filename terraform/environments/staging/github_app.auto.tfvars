# The staging GitHub App (https://github.com/apps/activeagents-staging), which
# gives checkout sandboxes repository access through installations. See
# docs/infrastructure/gcp-cicd-setup.md before changing a flag: Cloud Run
# refuses a revision whose secrets have no version, so enable_github_app
# needs activeagents-staging-github-app-private-key and -webhook-secret first.
github_app_id     = "5435204"
github_app_slug   = "activeagents-staging"
enable_github_app = true
