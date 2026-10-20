# Sign in with Google

People can sign up and sign in with Google, and a signed-in user can connect or disconnect Google under **Settings** (`/settings`). The buttons appear only when the environment's Google OAuth client is configured. The flow mirrors [Sign in with GitHub](github-sign-in.md): the same account matching, the same Settings rules, and the same session-bound state.

## How accounts are matched

- An identity is keyed on Google's account id, the `sub` claim (`user_identities.uid`), never on the email, which a person can change. `user_identities.login` stays empty for Google: Google has no username, so Settings names the account by its address.
- A Google account already connected to a user signs that user in, and returns them to the page that asked them to sign in.
- A Google account that is not connected, whose verified email has no account here, creates one: a verified user named from the Google profile (its given and family names, or the full name split in two), a random password they never see (`users.password_set = false`), and an owned workspace. The person continues to profile completion and plan selection, as an email signup does after verifying, and the password there is optional. `users.signup_source` is `google`.
- A Google account that is not connected, whose email already has an account here, is never linked automatically. The person is sent to the password sign-in, then to Settings to connect Google. This holds whether or not that existing account's email is verified.
- A Google account whose email Google reports unverified (`email_verified` false) cannot sign up.
- Settings refuses to connect a Google account that another user has connected, and refuses to disconnect Google while it is the account's only way to sign in: no password chosen and no other provider connected. **Email me a link to set a password** on the same page sends the signed-in user the password-reset email. The same rule now applies to GitHub, so a person with both connected can drop either one.

## What is sent and kept

Each round trip carries a random `state` and a PKCE code verifier, kept in the browser's session for ten minutes. A callback consumes them whether or not the state matches. The authorization asks Google for the `openid email profile` scopes with the verifier's S256 challenge, and the code exchange presents the verifier with the client secret. A Settings connect also records the signed-in user and session that started it, and completes only for them.

The access token from the exchange is used for one `GET https://openidconnect.googleapis.com/v1/userinfo` and then dropped. It is never stored or logged. The `id_token` in the same response is not used: it carries the claims userinfo does, and it arrives straight from Google's token endpoint over TLS in an exchange the client secret authenticates, so a signature check would add nothing. The authorization `code` is filtered from the logs (`config/initializers/filter_parameter_logging.rb`).

## Configuring an environment

1. In the Google Cloud console, under **APIs & Services → Credentials**, create an **OAuth client ID** of type **Web application** for the environment (one per environment, so staging and production have their own secrets):
   - **Authorized redirect URIs**: `https://<host>/auth/google/callback` for every host that serves the app. The callback goes to the host the person started on, because the pending sign-in lives in that host's session cookie, and Google refuses a redirect URI that is not registered exactly. For the hosted site these are `https://activeagents.ai/auth/google/callback`, `https://www.activeagents.ai/auth/google/callback` and `https://staging.activeagents.ai/auth/google/callback`. A development client takes `http://localhost:3000/auth/google/callback`;
   - **Authorized JavaScript origins** can stay empty: the flow is a server-side redirect.
2. Under **OAuth consent screen** (Google Auth Platform → Branding / Audience): user type **External**, and **publish** the app so any Google account can sign in. The three scopes are non-sensitive, so publishing needs no verification review; Google shows the app name and support email on the consent page, and verifying the `activeagents.ai` domain in Search Console lets the branding carry it.
3. Give the app the client ID and secret, through either:
   - Rails credentials: `google_oauth.client_id` and `google_oauth.client_secret`;
   - or the environment: `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`.

### Cloud Run (Terraform)

Terraform declares two Secret Manager secrets per environment, `activeagents-<env>-google-oauth-client-id` and `activeagents-<env>-google-oauth-client-secret`, and maps them to `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` when `enable_google_sign_in` is true. Cloud Run refuses a revision that reads a secret with no version, so:

1. Deploy once so the empty secrets exist. Do not create them by hand first, or the next apply fails with a 409.
2. Add a version to each:
   ```sh
   printf '%s' "$CLIENT_ID" | gcloud secrets versions add activeagents-staging-google-oauth-client-id --data-file=-
   printf '%s' "$CLIENT_SECRET" | gcloud secrets versions add activeagents-staging-google-oauth-client-secret --data-file=-
   ```
3. Set `enable_google_sign_in`'s default to `true` in `terraform/environments/<env>/variables.tf` and deploy. CI applies that file's defaults, so a value set anywhere else is lost on the next deploy.

## Tests

- `test/services/google_sign_in_test.rb`: configuration, the authorization URL and PKCE challenge (RFC 7636's worked example), the exchange and userinfo read, and the failures.
- `test/integration/sign_in_with_google_test.rb`: sign-up, sign-in, the matching rules, state and verifier handling, connect and disconnect from Settings, and the buttons.
