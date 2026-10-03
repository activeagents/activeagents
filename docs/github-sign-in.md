# Sign in with GitHub

People can sign up and sign in with GitHub, and a signed-in user can connect or disconnect GitHub under **Settings** (`/settings`). The buttons appear only when the environment's GitHub App credentials are configured.

## How accounts are matched

- An identity is keyed on GitHub's numeric user id (`user_identities.uid`), never on the login or email, which the person can change.
- A GitHub account already connected to a user signs that user in, and returns them to the page that asked them to sign in.
- A GitHub account that is not connected, whose verified primary email has no account here, creates one: a verified user named from the GitHub profile, a random password they never see (`users.password_set = false`), and an owned workspace. The person continues to profile completion and plan selection, as an email signup does after verifying, and the password there is optional.
- A GitHub account that is not connected, whose email already has an account here, is never linked automatically. The person is sent to the password sign-in, then to Settings to connect GitHub. This holds whether or not that existing account's email is verified.
- A GitHub account with no verified primary email cannot sign up.
- Settings refuses to connect a GitHub account that another user has connected, and refuses to disconnect GitHub while it is the account's only way to sign in (no password chosen). **Email me a link to set a password** on the same page sends the password-reset email.

The user access token from GitHub is used for `GET /user` and `GET /user/emails` during the callback and then dropped. It is never stored or logged.

Each round trip carries a random `state` kept in the browser's session for ten minutes. A callback consumes it whether or not it matches. A Settings connect also records the signed-in user and session that started it, and completes only for them.

## Configuring an environment

1. In the environment's GitHub App settings:
   - add `https://<host>/auth/github/callback` to **Callback URL**;
   - under **Permissions → Account permissions**, set **Email addresses** to read-only;
   - generate a client secret.
2. Give the app the App's client ID and secret, through either:
   - Rails credentials: `github_app.client_id` and `github_app.client_secret`;
   - or the environment: `GITHUB_APP_CLIENT_ID` and `GITHUB_APP_CLIENT_SECRET`.

### Cloud Run (Terraform)

Terraform declares two Secret Manager secrets per environment, `activeagents-<env>-github-app-client-id` and `activeagents-<env>-github-app-client-secret`, and maps them to `GITHUB_APP_CLIENT_ID` / `GITHUB_APP_CLIENT_SECRET` when `enable_github_sign_in` is true. Cloud Run refuses a revision that reads a secret with no version, so:

1. Deploy once so the empty secrets exist. Do not create them by hand first, or the next apply fails with a 409.
2. Add a version to each:
   ```sh
   printf '%s' "$CLIENT_ID" | gcloud secrets versions add activeagents-staging-github-app-client-id --data-file=-
   printf '%s' "$CLIENT_SECRET" | gcloud secrets versions add activeagents-staging-github-app-client-secret --data-file=-
   ```
3. Set `enable_github_sign_in`'s default to `true` in `terraform/environments/<env>/variables.tf` and deploy. CI applies that file's defaults, so a value set anywhere else is lost on the next deploy.
