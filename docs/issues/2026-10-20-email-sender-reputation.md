# Repairing the email sender reputation of activeagents.ai

Date: 2026-10-20 · Status: plan; step 1 is in `fix/bot-signups` · Owner: Justin

## What happened

Every message the hosted site sends (verification links, password resets,
pilot invitations, newsletter confirmations) leaves Resend as
`noreply@staging.activeagents.ai`, the only domain verified in the Resend
account. From 2026-10-17 a subscription-bombing bot made the site send
hundreds of unsolicited "Verify your email" messages
([2026-10-19-signup-bot-email-abuse.md](2026-10-19-signup-bot-email-abuse.md)).

Resend's own numbers for October (checked 2026-10-20 16:40 UTC):

| Day | Sent | Complaints | Complaint rate | Bounces |
|---|---|---|---|---|
| Oct 17 | 42 | 0 | 0 | 0 |
| Oct 18 | 192 | 0 | 0 | 0 |
| Oct 19 | 220 | 3 | **1.36%** | 5 |
| Oct 20 (to 16:40) | 188 | 0 | 0 | 2 |
| Month | 642 | 3 | 0.47% | 7 (1.09%) |

Gmail's sender guidelines want the spam rate (what Gmail users mark as
spam, measured in Postmaster Tools) under 0.1% and never over 0.3%. Resend
only sees complaints from providers with feedback loops (Comcast and
similar); Gmail's are invisible here and are the ones that filed Justin's
two password reset emails as spam. Opens and clicks read 0 because
tracking is off, not because nobody opened.

Usage: 193 of the free plan's 100-a-day cap today, 635 of 3,000 a month,
828 of 1,000 contacts. Real onboarding mail competes with bot mail for
that cap.

Authentication today (from `terraform/environments/staging/dns.tfvars`):
`staging.activeagents.ai` has Resend's DKIM and `send.staging` SPF/MX;
`activeagents.ai` has SPF for Google Workspace only, no Resend DKIM, and
`_dmarc.activeagents.ai` is `v=DMARC1; p=none;` with no reporting address.
Mail from the staging subdomain aligns with its own DKIM, so it passes
DMARC, but the reputation it earns is a staging subdomain's.

## Why this hurts onboarding

- A verification link in spam is a signup that never finishes. The pilot
  invitation link (seven-day expiry) is the same message class.
- Over the daily cap, Resend refuses sends; a person's verification email
  is then never queued at all.
- Reputation is per sending domain, judged on the last weeks of traffic.
  It recovers only by sending wanted mail at a steady volume from a
  properly authenticated domain. There is no form to fill in; Postmaster
  Tools shows it moving.

## Plan, in order

### 1. Stop the unwanted mail (this week)

`fix/bot-signups`: Cloud Armor blocks the six bot addresses and rate-bans
signup POSTs; a honeypot on every form; Cloudflare Turnstile once its keys
are set; one verification resend per address per ten minutes
([human-check.md](../features/human-check.md)). Nothing else below helps
while the site still sends mail nobody asked for.

Then clean the list: bot-created users (unverified ones, and the verified
ones that corporate link scanners clicked) should not get any further
mail, and their addresses should not sit in the Resend Users audience.

### 2. Send from the real domain, authenticated (next)

- Add `activeagents.ai` to Resend (region us-east-1, like staging) and put
  its records in `terraform/environments/staging/dns.tfvars`, as the
  staging ones are: `resend._domainkey` TXT (DKIM), `send` SPF TXT and MX.
  Apex SPF stays Google Workspace's; Resend uses the `send` subdomain as
  its return path, so the apex SPF record does not change.
- Choose the From address: `hello@activeagents.ai` is already production's
  default (`MAILER_FROM_ADDRESS` in `terraform/variables.tf`) and a real
  Google Workspace mailbox, so replies land somewhere. Staging's
  `mailer_from_address` variable then moves to it as well, since staging
  is what serves activeagents.ai (a new `mailer.auto.tfvars` or the
  existing default in `environments/staging/variables.tf`).
- Keep transactional and newsletter mail apart: a second verified domain
  such as `news.activeagents.ai` for the newsletter later, so a campaign
  can never drag verification links down with it.
- The staging subdomain keeps its records so an actual staging deployment
  (when the domain moves to production) still sends.

A fresh, aligned sending domain starts with a neutral reputation; the
staging subdomain's complaints stay attached to the staging subdomain.
Gmail also weighs the organisational domain, so the clean-up in step 1
still matters.

### 3. DMARC that reports, then enforces

- `dmarc_record` in `dns.tfvars` → `v=DMARC1; p=none; rua=mailto:dmarc@activeagents.ai; fo=1`
  for two weeks of reports (a Workspace group or a free aggregator such
  as Postmark's DMARC digests), to confirm only Google and Resend send as
  the domain.
- Then `p=quarantine; pct=100`, later `p=reject`. Enforced DMARC is one of
  the signals Gmail weighs for bulk senders and it stops anyone else from
  spending the domain's reputation.

### 4. Register with the receivers and watch

- Google Postmaster Tools: add `activeagents.ai` (the TXT verification can
  go in `txt_records`), then watch Domain reputation, Spam rate and
  Authentication daily. Reputation moves from "Bad"/"Low" to "Medium"/"High"
  over two to four weeks of clean sending; this is the only place Gmail's
  view is visible.
- Microsoft SNDS/JMRP for Outlook addresses, if pilot clients use them.

### 5. Make every message easy to keep

- `List-Unsubscribe` and `List-Unsubscribe-Post` headers on the newsletter
  (Gmail requires one-click unsubscribe for bulk senders; it costs nothing
  on transactional mail either).
- Plain, short transactional templates with the product name in the
  subject and From name, a working reply-to, and no tracking links on
  verification mail (tracking is off in Resend already; keep it off for
  transactional).
- Only send to addresses that asked: double opt-in stays on the
  newsletter, and signups send one verification and stop.

### 6. Volume and warm-up

The site sends tens of messages a day when healthy. That is below any
warm-up schedule; a dedicated IP is wrong at this volume (it would never
build reputation). Stay on Resend's shared pool. Moving off the free plan
(Pro, 50,000 a month, no daily cap) removes the cap that blocks real mail
on a bad day; that is Justin's call.

## Onboarding while it recovers

- Tell invitees to check spam and to drag the message to the inbox
  (that is also a positive signal to Gmail).
- Sign in with GitHub needs no email at all; the flag exists
  (`enable_github_sign_in`) and sidesteps the verification email for
  anyone with a GitHub account.
- For the pilot client pilot and other hand-picked clients: send the
  invitation personally from Justin's Workspace mailbox, whose reputation
  is fine, with the accept link copied from the admin page once the admin
  page shows it (today it only emails it; a small follow-up).
- Resend's cap resets at 23:59 UTC; a blocked bot keeps the day's sends in
  the tens.

## Checks that show it worked

- Postmaster Tools spam rate under 0.1% for 14 days and domain reputation
  at least Medium.
- Resend complaint rate 0 and bounce rate under 1% over a week.
- A test signup from a fresh Gmail address lands in the inbox, with
  `Authentication-Results` showing SPF, DKIM and DMARC pass for
  `activeagents.ai`.

## Log

- 2026-10-20: numbers above collected through the Resend connector;
  plan written; step 1 implemented in `fix/bot-signups`.
