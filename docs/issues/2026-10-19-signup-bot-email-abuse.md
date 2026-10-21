# Signup bot is sending verification emails to people who never signed up (2026-10-19)

Status (2026-10-20): fix in [#180](https://github.com/activeagents/activeagents/pull/180), `fix/bot-signups`, merged 18:12 UTC; Cloud Armor has been
live on staging's load balancer since 18:19 UTC ([human-check.md](../features/human-check.md)). Turnstile
is on since 19:03 UTC (`bin/turnstile-keys` [#185](https://github.com/activeagents/activeagents/pull/185), keys [#187](https://github.com/activeagents/activeagents/pull/187)); the widget passes on the live form. The bot-created users are
cleaned up per [2026-10-20-resend-list-cleanup.md](2026-10-20-resend-list-cleanup.md);
the sender reputation it cost is tracked in
[2026-10-20-email-sender-reputation.md](2026-10-20-email-sender-reputation.md).

Result (20:08 UTC): no signup POST from the bot has reached the app since
18:24:57 UTC and no verification mail has gone out since 18:24:56 UTC; the
six addresses keep probing and get 403 at the edge. Live test of every layer:
[2026-10-20-bot-blocker-live-test.md](../testing/2026-10-20-bot-blocker-live-test.md).
Production has none of this yet (no load balancer, last deployed 2026-10-06);
it comes with #181.

## Summary
activeagents.ai resolves to the **staging** load balancer (34.49.49.134 → `activeagents-staging`).
The `activeagents-production` Cloud Run service is not behind any domain. In 90 days it
logged one request, the deploy smoke test on 2026-10-06.

From 2026-10-17 on, a bot has been POSTing to `/registration` on activeagents.ai, and every
signup it creates sends a verification email through Resend (`noreply@staging.activeagents.ai`).

activeagents.pro and activeagent.dev also point at 34.49.49.134. The `activeagents-staging`
GCP project has neither Cloud Run nor Compute enabled, so nothing runs there. The production
project (if it's a separate one) hasn't been located yet.

## Source of the emails (confirmed)
- I pulled the full send log with the `activeagents-production-resend-api-key` secret. It
  returns the same account-wide log as the staging key, so both keys belong to one Resend
  account.
- The log holds 448 emails (Sep 30 – Oct 19): 447 "Verify your email" and 1 newsletter confirm.
  **Every one was sent from `noreply@staging.activeagents.ai`**, which is the staging
  service's `MAILER_FROM_ADDRESS`. Production sends as `hello@activeagents.ai`, and **no
  email from that address appears**.
- 445 of the 448 sends fall within 2 minutes of a successful (302) `POST /registration`
  on `activeagents-staging`. The other 3 are one on Sep 30 and two on Oct 19, probably resends.
- Conclusion: production never sent these emails. They come from the staging service, which
  is reached through activeagents.ai because the domain's DNS points at the staging LB.

## Did the bots use the product? No.
- The bot IPs made 1,792 requests in 30 days. All of them were the landing page,
  `registration/new`, `POST /registration`, `pending_verification` and `GET session/new`,
  plus probes for newsletter or contact form URLs (`/subscribe`, `/newsletter`,
  `/contact-us`, …), all 404s. That's a subscription-bombing bot hunting for any form that
  will send an email. It **never posted to `/session`**, never verified an account and never
  reached a logged-in page.
- 18 verification links were clicked from other IPs. All were GET-only. The furthest any
  went was `complete_profile` or the home page. Nothing was submitted, and there were no
  dashboard, agent or API requests.
  - Azure (74.179.x, 135.232.x, 72.152.x) and OVH (51.89/54.37/87.98/178.32/46.105) IPs
    clicked within seconds of delivery, often twice. These look like corporate mail
    link scanners (Safe Links and similar), not people.
  - 136.22.x were single clicks that loaded the landing page. Possibly real recipients
    checking what the email was.
  - 172.56.42.159 (T-Mobile iPhone, Sep 30) matches the one pre-attack signup, likely an
    internal test.
- Note: the scanner clicks mark those bot-created users as **verified**, so cleanup must
  include verified users created from the bot IPs, not just unverified ones.

## Evidence (Cloud Run request logs for `activeagents-staging`, last 14 days)
| Metric | Value |
|---|---|
| POST /registration | 681 (Oct 17: 50, Oct 18: 250, Oct 19: 381) |
| Outcome | 513 × 302 (created), 119 × 422, 49 × 429 |
| Source IPs | 6 IPs in the 31.56–31.59.x / 95.182.x ranges did ~670 of them; 82.38.96.x did 7 |
| User agent | One Chrome/12x Windows UA on every request |

The six addresses, by requests since Oct 17 (count / 302 created): 95.182.89.76 (240/163),
31.57.107.185 (229/169), 31.59.105.64 (229/166), 31.56.204.42 (205/148),
95.182.114.251 (196/147), 31.56.196.42 (187/130). 82.38.96.243 and .237 made 7 between
them and are left alone. The bot was still posting on Oct 20 (verification mail to random
Gmail addresses, two copies each, 15:45–16:28 UTC).

The other POSTs in that window are ordinary vulnerability scans (xmlrpc.php, index.php,
graphql, cgi-bin traversal, ignition).

## Resend impact
- At least 100 verification emails on Oct 19 alone, many recipients getting 2–4 copies.
- Spam **complaints** from at least one recipient, several **suppressed** addresses and
  delayed deliveries. The newest sends, from 16:52 UTC on, show `failed`.
- Resend's metrics for Oct 19: 220 sent, 3 complaints (1.36%), 5 bounces, 25 failed; the
  free plan's 100-a-day cap was passed on Oct 18, 19 and 20.
- The recipients look like real people whose addresses the bot is using (subscription
  bombing). These are not real signups, and the complaints hurt the sending domain's reputation.

## Why the current defense isn't enough
`RegistrationsController` has `rate_limit to: 10, within: 10.minutes`, keyed per IP. With
6 rotating IPs that still allows about 360 signups an hour. There's no CAPTCHA or bot check.

## Recommended fixes
1. Immediately: block the abusing IP ranges at Cloud Armor or the LB, or turn off the
   verification mailer for now. → `fix/bot-signups`: Cloud Armor policy in the
   load-balancer module, the six addresses in `environments/staging/security.auto.tfvars`,
   plus a rate-based ban on signup POSTs (20 a minute per address, 10-minute ban).
2. Add Cloudflare Turnstile (or a similar check) plus a honeypot field to the registration form.
   → same branch: honeypot on every form, Turnstile behind `enable_turnstile` once the
   widget exists and the secret has a version.
3. Rate-limit per recipient email, and send at most one verification per address per day.
   → same branch: one resend per address per ten minutes on the landing-page path.
4. Remove the bot-created unverified users. Check Resend's suppression and complaint lists.
   → commands prepared in [2026-10-20-resend-list-cleanup.md](2026-10-20-resend-list-cleanup.md). Resend's suppression list holds one complaint (a Comcast address, Oct 19) and
   one old bounce; Gmail complaints are not reported back.
5. Separately: decide whether activeagents.ai should point at production, and whether
   staging should send real email at all. → open; see the reputation doc.
