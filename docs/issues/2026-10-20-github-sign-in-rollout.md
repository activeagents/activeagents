# Turn on Sign in with GitHub for staging and production (issue #184, milestone 1.9.3)

- Issue: https://github.com/activeagents/activeagents/issues/184
- Code: already in `main` since PR #154 (`docs/github-sign-in.md`). Nothing to build; this is operations.
- State on 2026-10-20: neither environment has `GITHUB_APP_CLIENT_ID`, so the GitHub buttons do not render anywhere. Both environments' `enable_github_sign_in` defaults are `false`, and no `github_app.auto.tfvars` exists.

## Steps (each environment)

1. In the environment's GitHub App (register one if none exists: `docs/infrastructure/gcp-cicd-setup.md`, "GitHub App"), add the callback URL `https://<host>/auth/github/callback` for every host that serves it, set the **Email addresses** account permission to read-only, and generate a client secret.
2. Add a version to each of `activeagents-<env>-github-app-client-id` and `-github-app-client-secret` with `gcloud secrets versions add`. The secrets already exist (Terraform declares them, and both environments have been applied).
3. Set `enable_github_sign_in`'s default to `true` in `terraform/environments/<env>/variables.tf`, commit, and deploy. CI applies that file's defaults; a value set anywhere else is lost on the next deploy.
4. Check: the sign-in and sign-up pages show **Sign in with GitHub**; a connect from Settings round-trips.

Do staging first. Production follows the production cutover (`docs/infrastructure/production-environment.md`), with its own App and callback URLs on `activeagents.ai` and `www.activeagents.ai`.

Sign in with Google (#183, `docs/google-sign-in.md`) turns on the same way with `enable_google_sign_in` and the `google-oauth-client-*` secrets.
