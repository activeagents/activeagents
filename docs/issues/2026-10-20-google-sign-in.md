# Sign in with Google (issue #183, milestone 1.9.3)

- Issue: https://github.com/activeagents/activeagents/issues/183
- Milestone: 1.9.3
- Branch: `feat/google-sign-in` (from `main` at 60e456e, after PR #180)
- Companion: #184 (turn on Sign in with GitHub for staging and production: operations only)

## What was built

A Google OpenID Connect sign-in that mirrors the GitHub one from PR #154, so the two share their rules and their shape:

| Piece | File |
| --- | --- |
| Service: authorize URL with PKCE, code exchange, userinfo read | `app/services/google_sign_in.rb` |
| Pending round trip in the session (state, verifier, intent, user, session, expiry) | `app/controllers/concerns/google_authorization.rb` |
| Sign-in, sign-up and connect callback | `app/controllers/google_sessions_controller.rb` |
| Settings connect and disconnect | `app/controllers/google_identities_controller.rb` |
| Provider `google`, `User#google_identity`, `User#signs_in_without?` | `app/models/user_identity.rb`, `app/models/user.rb` |
| Buttons on sign-in and sign-up, one divider for any number of providers | `app/views/sessions/_providers.html.erb` (replaces `github_sessions/_button`) |
| Settings section and the "only way to sign in" wording for one or both providers | `app/views/settings/show.html.erb` |
| Routes `auth/google`, `auth/google/callback`, `settings/google` | `config/routes.rb` |
| Terraform: `enable_google_sign_in`, secrets `google-oauth-client-id` / `-client-secret`, both environments, three test runs touched | `terraform/` |
| Docs | `docs/google-sign-in.md`, `docs/infrastructure/gcp-cicd-setup.md` |

Design choices:

- **userinfo instead of id_token verification.** The id_token from the token endpoint carries the same claims, and arrives over TLS in a client-secret-authenticated exchange. Reading userinfo with the access token keeps the service the same shape as `GithubSignIn` (exchange, one authenticated read, drop the token) and avoids a JWKS fetch and a JWT dependency.
- **PKCE** on top of the state: a 64-character verifier per round trip, S256 challenge in the authorization, verifier in the exchange.
- **Disconnect rule generalized.** A provider can be disconnected when the person has a password or another provider; before, GitHub's disconnect looked only at the password. Settings' wording covers one or both providers.
- **Google identities keep `login` empty.** Google has no username; Settings shows the account's address.

## Status log

- 2026-10-20 19:50 UTC: code, tests and Terraform written. Draft PR #186 opened; CI green (scan, lint, boot, test, Terraform checks). `bin/rails test` on the four sign-in files (Google and GitHub, service and integration): 63 runs, 643 assertions, 0 failures. `terraform test`: 27 passed. Validate passes for staging, production and sandbox-staging.

## Before it is on

Operations, per `docs/google-sign-in.md`: register the OAuth client per environment with the callback URIs, publish the consent screen, deploy once for the empty secrets, add the secret versions, flip `enable_google_sign_in` in the environment's `variables.tf`.
