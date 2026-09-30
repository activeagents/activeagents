# Pro pilot onboarding

Public registration, Free access, plan selection, and ordinary Stripe checkout remain open. The pilot program is an additional path. These changes do not invite actual clients, provision production accounts, or change Stripe configuration.

## Operator workflow

1. Apply the migrations, ensure the existing `pro` plan is seeded, and run the app's job worker. Both migrations should complete before serving requests with this version.
2. Configure the app's transactional mail delivery and `MAILER_FROM_ADDRESS` with a verified production sender. Verify delivery with a synthetic address you control before inviting clients. Production URL options must point at the production host.
3. Sign in as an email-verified platform administrator (`User#admin?`), then visit `/admin/pilots`.
4. Prepare a draft with the exact owner email, company/workspace name, reason, and review date. Leave expiration empty for access that continues while a retainer is active. Choose an existing workspace only when its owner email matches; otherwise the draft explicitly means a new client workspace.
5. Review the saved recipient and grant intent, then choose **Send invitation**. Preparing a draft does not send. Delivery runs through the transactional mailer. A queue worker must be running.
6. The recipient opens the link and explicitly accepts. New users set their own password. Existing users authenticate with the matching email; their password is never replaced. The valid invitation proves email control. Acceptance selects the intended workspace and shows provider/first-trace instructions at `/workspace`.
7. Review activation and access in `/admin/pilots`. Extend the review date or explicit expiration using **Save / extend Pro grant**. Revoke the grant separately from revoking an unaccepted invitation.

Links last seven days. Tokens are random, stored only as SHA-256 digests, and appear in filtered query parameters rather than URL paths. GET never consumes an invitation. Resend invalidates the previous token immediately. A delivery version prevents stale jobs from sending an older invitation. Failures expose the error class, not credentials or mail content. Email bodies are redacted from mail instrumentation, and token values are never job arguments.

Invitation delivery has no automatic SMTP retry because a network failure can occur after the provider accepted an email. An admin can explicitly resend with a new link. Successfully delivered access notices are deduplicated by the audit event. Investigate failed or ambiguous delivery in the queue before retrying. A queued invitation can be revoked; prepare a replacement if its worker job has been lost.

## Entitlements and reporting

Resolution is deterministic: an active real billing subscription/trial wins, then an active app-managed Pro grant, then a legacy `fake_processor` grant, then Free. Granting or revoking pilot access does not call Stripe or alter a billing subscription. A review date never charges or expires access. There is no automatic conversion.

`Account#current_plan` supplies effective capabilities, quotas, and retention. `billing_subscription`/`subscribed?` exclude complimentary processors; `paid_subscriber?` additionally excludes trials. `access_source` distinguishes Free, trial, real subscription, app-managed complimentary pilot, and legacy complimentary access. The admin page shows these separately and does not count complimentary list prices as recurring revenue. Its overview shows the latest 100 workspaces/invitations and 50 access events, with first trace/evaluation timestamps from retained data.

One grant row exists per workspace. Authorized service calls lock the workspace and retain grant/update/revoke/expire events with actor and policy snapshots. Repeated identical calls do not append another grant or event. The invitation service calls the grant service inside the same acceptance transaction. Row locks, unique normalized email addresses, the pending-invitation index, and unique membership/grant indexes prevent duplicate acceptance.

## Access ending and retention

On explicit expiration or revocation, a real paid subscription still wins. Otherwise, usage limits fall back to the remaining valid entitlement (normally Free). Account login and the workspace remain available. No callback deletes traces on loss of access.

For 14 days after access ends, retention keeps the Pro 14-day window, so previously retained traces age out normally. After that, the effective plan's retention applies (Free: 3 days). Grant notices and the invitation/workspace screens explain this policy. The hourly `ProAccessExpirationJob` records expiration and queues the transactional notice. Effective access checks the timestamp directly, so a delayed worker cannot prolong an expired grant. Monitor the worker and mail queue; notices cannot be guaranteed while delivery is unavailable.

## Workspace migration

Agents, sandbox sessions, and recordings become account-owned for authorization. Existing rows with only `user_id` are assigned once to that user's former primary workspace (first owned workspace, otherwise first membership). Rows without a resolvable workspace remain inaccessible; they are not exposed globally. Review users with multiple existing workspaces before rollout and move historical records explicitly if the old primary mapping is inappropriate. Creator attribution remains on `user_id`.

Agent slug and observed-agent identity uniqueness are workspace-scoped. The ownership migration is deliberately irreversible because different workspaces can subsequently reuse the same slug. Back up before production migration; rollback requires reconciling those names and tenant ownership, not blindly reintroducing global indexes.

Sessions store the selected workspace, and requests recheck membership. `/workspace` provides the switcher. Agents, provider/API keys, recordings, sandbox streams, telemetry, and evaluations use that workspace. Anonymous recording claims are restricted to the recording created in the same browser session; signup parameters cannot claim someone else's recording.

## Public signup and newsletter consent

Public signup is still `/registration`, followed by email verification and profile/plan selection. Existing pending accounts cannot be logged into merely by resubmitting an email address. Dashboard, provider credentials, billing, and profile mutations require verified email ownership. Checkout is owner-only, serialized per workspace, and reuses an unexpired checkout session. Visiting a success URL does not change entitlement; the existing Pay subscription lifecycle does. Free/trial behavior remains distinct from pilot access.

Newsletter forms use `/newsletter_subscription`. They record consent and send a confirmation link, without creating a User, workspace, session, or Pro grant. Confirmation queues Resend synchronization to `RESEND_NEWSLETTER_AUDIENCE_ID`; configure this separately from the existing dashboard-user audience, along with `RESEND_API_KEY`. Account registration and invitation acceptance no longer implicitly subscribe anyone to marketing. Historical contacts and users are unchanged. Resend broadcasts and unsubscribe handling continue to be operated separately.

## Verification

Run `rails test`, including `test/integration/pilot_invitation_concurrency_test.rb` against real PostgreSQL. Build both JavaScript and CSS before request tests (`yarn build && yarn build:css`). The concurrency test intentionally skips under the local PGlite fallback because its single PostgreSQL backend cannot prove row-lock isolation; CI uses PostgreSQL 16.

Use two synthetic client organizations to check invite acceptance, password creation, Pro access, first trace/evaluation, switching, and cross-workspace denial. Check an uninvited registration through checkout separately. Test emails use Action Mailer's test delivery; billing tests replace Stripe calls and never contact live billing.
