# Complimentary Pro pilot for the pilot client workspace on activeagents.ai

Date: 2026-10-20 · Environment: production (https://activeagents.ai) · Status: in progress, waiting for the admin sign-in

## Ask

Justin (2026-10-20): "let's setup a free pilot pro plan for pilot-client in the
hosted activeagents.ai", with grant source `retainer_pilot`.

## How Pro pilots work (already built, [pro-pilots.md](../pro-pilots.md))

- A platform admin (`users.admin = true`, email verified) uses `/admin/pilots`.
- For an existing workspace: the "Grant complimentary Pro" form under the
  workspace (source, start, review date, optional expiration, reason) calls
  `ProAccess.grant!`, which writes one `pro_access_grants` row per workspace
  plus an audit event, and queues a transactional notice to the owner.
- For a client without a workspace: "Prepare invitation" saves a draft
  (workspace name, owner email, review date, optional expiration, reason);
  "Send invitation" emails a seven-day link; accepting creates the workspace
  with the grant.
- `Account#current_plan` resolves a real Stripe subscription first, then an
  active grant (→ Pro), then legacy complimentary, then Free. Grants never
  create a Stripe subscription; the review date neither charges nor expires.

## Production state checked before starting

- Last production deploy (2026-10-06, run of `deploy-production.yml`) rolled
  out image `4a4d088d`, main at 2026-10-05, which contains the pilot feature
  (#142, `5de3eac`) and its migration `20260930000000_add_pilot_onboarding`.
- One-off commands on production run through the migrate job, whose command
  is `./bin/rails` with the job's args (`db:migrate:primary` by default):
  `gcloud run jobs execute activeagents-production-migrate --region=us-central1 --args=... --wait`.
  That is the fallback if the signed-in user is not an admin (there is no
  rake task that promotes a user; a `runner` one-liner would do it).

## Grant values

| Field | Value |
|---|---|
| Workspace | the pilot client (existing workspace if its owner email matches; otherwise an invitation) |
| Source | `retainer_pilot` (confirmed by Justin) |
| Start | now |
| Review date | 2027-01-20 (90 days) |
| Expiration | none |
| Reason | the pilot client's own client work on the hosted dashboard during the pilot period |

## Log

- 2026-10-20: opened https://activeagents.ai/admin/pilots in Chrome; it
  redirected to sign-in. The sign-in is Justin's to do (credentials are never
  entered by the assistant on a hosted site).
- 2026-10-20: no admin login existed, so Justin created one himself with a
  one-off `rails runner` through the production migrate job (execution
  `activeagents-production-migrate-6dgg8`, started 16:18 UTC): user
  `justin@activeagents.ai`, admin, email verified, profile completed, a random
  password nobody knows (to be set through "Forgot your password?"), and an
  "ActiveAgents" workspace it owns. The deployed image (main at 2026-10-05)
  predates `save_with_workspace` and `assign_random_password`, so the
  one-liner used `User.create!` plus `Account.create!` and the membership.
  `gcloud auth login` was needed first (expired tokens). The first execution
  (`…-6dgg8`) failed before touching the database: the command used `@` as
  gcloud's argument delimiter and the email address contains one, so the
  Ruby arrived truncated. The second (`…-hwrpv`, 16:3x UTC) printed
  `user 1 admin=true verified=true account=1`.
- 2026-10-20, correction: per [2026-10-19-signup-bot-email-abuse.md](2026-10-19-signup-bot-email-abuse.md),
  `activeagents.ai` resolves to the **staging** load balancer (34.49.49.134,
  forwarding rules `activeagents-staging-http/https`), and the
  `activeagents-production` service has never served real traffic. So the
  admin user above went into the unused production database; the site at
  activeagents.ai runs `activeagents-staging` (latest main) against the
  staging database. That database already has a `justin@activeagents.ai`
  user: a "Reset your password" email went out at 16:11 UTC, before the
  production user existed. Resend shows both reset emails (16:11 and
  16:28 UTC) **delivered**; Gmail filed them as spam.
- Why the mail lands in spam: the only verified Resend domain is
  `staging.activeagents.ai` (DKIM set, `send.` SPF/MX set), so every message
  the site sends, reset links and pilot invitations included, comes from
  `noreply@staging.activeagents.ai`; the org DMARC is `p=none`; and since
  2026-10-17 a subscription-bombing bot has made the site send hundreds of
  unsolicited "Verify your email" messages (184 today by 16:30 UTC against
  the Resend plan's 100/day, two copies per address), drawing spam
  complaints that sink the sender's reputation at Gmail. Fix the bot and the
  sender domain before sending pilot invitations from this site.
- 2026-10-20 (later): the bot block and human check are host PR
  [#180](https://github.com/activeagents/activeagents/pull/180)
  ([human-check.md](../features/human-check.md)); the reputation repair plan
  is [2026-10-20-email-sender-reputation.md](2026-10-20-email-sender-reputation.md).
  Until the sender domain moves to `activeagents.ai`, send the pilot client
  invitation by hand from Justin's Workspace mailbox, or warn the recipient
  to look in spam. Still needed before the invitation: the pilot client owner's
  email address, and a check that the signed-in `justin@activeagents.ai` is
  an admin on `/admin/pilots`.
- 2026-10-20, 16:40–16:55 UTC (Chrome session + one-off jobs): `dig activeagents.ai`
  → 34.49.49.134 = forwarding rules `activeagents-staging-http/https`, so the
  live site is still `activeagents-staging` (revision `…-00115-5f7`, image of
  main `dc8af1a`) and its database. Everything below is in that database,
  which is the one the pilot client will sign into. The admin user created in the
  production database this morning is unused.
- Read-only query through `activeagents-staging-migrate` (`./bin/rails runner`,
  `--args='^~^runner~…'` because the Ruby contains commas and `@`): no admin
  user, no the pilot client workspace, no pilot invitations. `justin@activeagents.ai`
  is user 10 (verified, owns "Justin's Workspace"); `jusbowen@gmail.com` is
  user 7 (verified); no GitHub identities exist, so "Sign in with GitHub" would
  refuse both addresses until GitHub is connected from Settings.
- Promoted users 10 (`justin@activeagents.ai`, execution `…-v7cwx`) and 7
  (`jusbowen@gmail.com`, execution `…-dr8rm`) to `admin = true`. Revert with `User.where(id: [7, 10]).update_all(admin: false)`.
- In Chrome, https://activeagents.ai/admin/pilots redirected to the home page
  (not signed in). The sign-in itself is Justin's to do at
  https://activeagents.ai/session/new; a password reset request goes out from
  `noreply@staging.activeagents.ai` and Gmail has been filing those as spam.
- Invitation links cannot be recovered from the database (only a SHA-256
  digest is stored). If the pilot client's copy lands in spam, the delivered email,
  link included, is retrievable from Resend's sent log, or the admin page can
  "Resend with new link".
- The live service runs with `APP_HOST=staging.activeagents.ai` and
  `MAILER_FROM_ADDRESS="Active Agent <noreply@staging.activeagents.ai>"`
  (Terraform `terraform/environments/staging/variables.tf`, `app_host` and
  `mailer_from_address`). `staging.activeagents.ai` resolves to the same
  load balancer, so an invitation link works, but the pilot client would receive a
  link and a sender that both say "staging". Decide before sending whether to
  set `app_host = "activeagents.ai"` (links) and a verified `activeagents.ai`
  sender (needs the Resend domain) in the Terraform files, then deploy.
- 2026-10-20, later: Justin decided to build the production environment
  properly instead (branch `infra/production-full-stack`,
  [2026-10-20-production-full-stack.md](2026-10-20-production-full-stack.md))
  and deploy it with the 1.9.2 release. If the pilot is granted on the
  current (staging) database first, the `pro_access_grants` row and its
  events copy over with the data at the cutover; if the invitation path is
  used, send it after the cutover so the link points at activeagents.ai and
  the mail comes from the verified root domain.
- 2026-10-24, staging rehearsal (Chrome with Justin): staging user 376
  (`jusbowen@gmail.com`, GitHub identity) promoted to admin with a
  `rails runner` on `activeagents-staging-migrate`; signed in with GitHub;
  `/admin/pilots` draft "the pilot client" for `justin@client.example`,
  source `retainer_pilot`, review 2027-01-22, no expiration; "Send
  invitation" queued and Resend delivered it at 18:04 UTC (invitation 1,
  `delivery_state` sent, link valid to 2026-10-31). Gmail filed it as
  spam (staging sender, see
  [2026-10-20-email-sender-reputation.md](2026-10-20-email-sender-reputation.md)).
  Acceptance by Justin pending. The real invitation goes out from
  production, where `justin@activeagents.ai` (user 1) is the admin and
  mail leaves as `hello@activeagents.ai` with links on `activeagents.ai`.
