# Complimentary Pro pilot for the Combinaut workspace on activeagents.ai

Date: 2026-10-20 · Environment: production (https://activeagents.ai) · Status: invitation sent 2026-10-26, waiting for Chris to accept

## Ask

Justin (2026-10-20): "let's setup a free pilot pro plan for combinaut in the
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
| Workspace | Combinaut (existing workspace if its owner email matches; otherwise an invitation) |
| Source | `retainer_pilot` (confirmed by Justin) |
| Start | now |
| Review date | 2027-01-20 (90 days) |
| Expiration | none |
| Reason | Combinaut's own client work on the hosted dashboard during the pilot period |

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
  Until the sender domain moves to `activeagents.ai`, send the Combinaut
  invitation by hand from Justin's Workspace mailbox, or warn the recipient
  to look in spam. Still needed before the invitation: the Combinaut owner's
  email address, and a check that the signed-in `justin@activeagents.ai` is
  an admin on `/admin/pilots`.
- 2026-10-20, 16:40–16:55 UTC (Chrome session + one-off jobs): `dig activeagents.ai`
  → 34.49.49.134 = forwarding rules `activeagents-staging-http/https`, so the
  live site is still `activeagents-staging` (revision `…-00115-5f7`, image of
  main `dc8af1a`) and its database. Everything below is in that database,
  which is the one Combinaut will sign into. The admin user created in the
  production database this morning is unused.
- Read-only query through `activeagents-staging-migrate` (`./bin/rails runner`,
  `--args='^~^runner~…'` because the Ruby contains commas and `@`): no admin
  user, no Combinaut workspace, no pilot invitations. `justin@activeagents.ai`
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
  digest is stored). If Combinaut's copy lands in spam, the delivered email,
  link included, is retrievable from Resend's sent log, or the admin page can
  "Resend with new link".
- The live service runs with `APP_HOST=staging.activeagents.ai` and
  `MAILER_FROM_ADDRESS="Active Agent <noreply@staging.activeagents.ai>"`
  (Terraform `terraform/environments/staging/variables.tf`, `app_host` and
  `mailer_from_address`). `staging.activeagents.ai` resolves to the same
  load balancer, so an invitation link works, but Combinaut would receive a
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
  `/admin/pilots` draft "Combinaut" for `justin.bowen@combinaut.com`,
  source `retainer_pilot`, review 2027-01-22, no expiration; "Send
  invitation" queued and Resend delivered it at 18:04 UTC (invitation 1,
  `delivery_state` sent, link valid to 2026-10-31). Gmail filed it as
  spam (staging sender, see
  [2026-10-20-email-sender-reputation.md](2026-10-20-email-sender-reputation.md)).
  Acceptance by Justin pending. The real invitation goes out from
  production, where `justin@activeagents.ai` (user 1) is the admin and
  mail leaves as `hello@activeagents.ai` with links on `activeagents.ai`.
- 2026-10-25, rehearsal completed: Justin had signed in with Google as
  `justin.bowen@combinaut.com` first, which created a Free "Justin Bowen's
  Workspace" and redirected to the dashboard after profile completion
  without returning to the invitation (see
  [2026-10-25-pilot-invitation-google-signin.md](2026-10-25-pilot-invitation-google-signin.md)).
  Reopening the invitation link while signed in showed the single accept
  button; accepting at 16:29:38 UTC created the "Combinaut" workspace
  (ActiveAgent.PRO, "Complimentary pilot"), granted by `jusbowen@gmail.com`
  with review 2027-01-22 and no expiration, marked invitation 1 Accepted,
  and Resend delivered "Combinaut: Pro pilot access granted" at 16:29:48 UTC
  (the first message with the HTML part and `Reply-To`). The flow works
  end to end; the production invitation to Chris can go out from
  `/admin/pilots` as `justin@activeagents.ai`, with the note "set a
  password on the invitation page, or sign in first and reopen the link".
- 2026-10-26 (production, activeagents.ai on main `395fc94` with 1.9.4):
  Justin asked for Chrome open on `/admin/pilots` to send chris@combinaut.com
  the invitation himself. The page redirected to `/dashboard`: the signed-in
  user is `jusbowen@gmail.com` (production user 4, verified, not admin). The
  production database still holds the 2026-10-20 admin `justin@activeagents.ai`
  (user 1); 6 users, 6 workspaces, no grants, no pilot invitations. Promoted
  user 4 to `admin = true` through `activeagents-production-migrate`
  (`runner`, execution `…-nj9cz`; read-only listing was `…-wgd9t`). Revert with
  `User.find(4).update!(admin: false)`. `/admin/pilots` then rendered; the
  stale "Access denied" flash from the redirect shows once. The invitation
  itself (recipient, workspace name, review date, reason, Send) is Justin's.
- 2026-10-26: Justin also decided pilots run uncapped, so their real usage
  informs the Pro team plan and pricing: host PR
  [#228](https://github.com/activeagents/activeagents/pull/228),
  [pilot-uncapped-runs.md](../features/pilot-uncapped-runs.md). Until it is
  deployed, a new pilot grant carries the Pro cap of 10,000 runs a period.
- 2026-10-26, 12:58 UTC-7: invitation draft prepared on production from
  `/admin/pilots` (workspace "Combinaut", chris@combinaut.com, review
  2027-01-24, no expiration, reason recorded on the row). Not sent yet; the
  Send button is Justin's. Decision: the Pro cap stays for now (10,000 runs,
  25,000 traces a month); PR #228 parked as a draft for later.
- 2026-10-26, 20:43 UTC: Justin clicked "Send invitation". Resend shows the
  message to chris@combinaut.com **delivered**, from "Active Agent"
  <hello@activeagents.ai> (the verified root domain), subject "Your Combinaut
  Pro workspace invitation", link on activeagents.ai, expiring 2026-11-02.
  The admin row says "Invited by jusbowen@gmail.com": that is the inviting
  user, not the sender. Next: Chris accepts, which creates the Combinaut
  workspace with the Pro grant (source `retainer_pilot`, review 2027-01-24);
  the admin page then shows the workspace under "Workspace access and
  activation". If the mail is not seen, "Resend with new link" on the row.
