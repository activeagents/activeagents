# Bot blocker live test on activeagents.ai (2026-10-20, 20:06–20:08 UTC)

Asked for by Justin ("is production and staging up to date, can you test
the bot blocker signup") after [#180](https://github.com/activeagents/activeagents/pull/180),
[#185](https://github.com/activeagents/activeagents/pull/185) and
[#187](https://github.com/activeagents/activeagents/pull/187) merged. Feature:
[human-check.md](../features/human-check.md); issue:
[2026-10-19-signup-bot-email-abuse.md](../issues/2026-10-19-signup-bot-email-abuse.md).

## Is each environment up to date?

| | Staging (serves activeagents.ai) | Production |
|---|---|---|
| Running | revision `activeagents-staging-00119-nml`, image `0012887…` = `main` at the time (#188) | revision `activeagents-production-00006-tm5`, image `4a4d088…` from the deploy of **2026-10-06** |
| Deploys | 39478473284 (#187), 39478494798 (#185), 39482028008 (#188), all green | last run 2026-10-06; the workflow is `workflow_dispatch` only |
| Turnstile env | `TURNSTILE_SITE_KEY` set, `TURNSTILE_SECRET_KEY` from `activeagents-staging-turnstile-secret-key` | not applied; its `security.auto.tfvars` flag and the import block for its secret apply at the next production `terraform apply` |
| Cloud Armor | `activeagents-staging-policy` on `activeagents-staging-backend` | no load balancer (the only forwarding rules are staging's at 34.49.49.134), no policy |

So staging is current. Production is three weeks behind and has none of
this, but nothing public reaches it: no domain points at it. It gets the
load balancer, Cloud Armor and the Turnstile flag with
[#181](https://github.com/activeagents/activeagents/pull/181)'s apply
(`docs/infrastructure/production-environment.md`).

## The application layer (with a CSRF token, JSON like the landing forms)

| Request | Result |
|---|---|
| `POST /registration`, honeypot `website` filled | 422 `{"error":"We couldn't confirm you're a person. Please try again."}` |
| `POST /registration`, no Turnstile token | same 422 |
| `POST /registration`, `cf-turnstile-response: not-a-real-token` | same 422 |
| `POST /newsletter_subscription`, no token | same 422 |

A POST without a CSRF token gets Rails's own 422 (`Unprocessable Content`)
before any of this runs. Nothing was created and no mail was sent: the
refusals come from `RequiresHuman`, which runs before the action.

## Cloud Armor

Denies logged by the policy since it went live (18:19 UTC), all `GET`,
all 403 by the address rule (priority 1000):

| Address | Denied requests |
|---|---|
| 31.56.196.42 | 11 |
| 95.182.114.251 | 10 |
| 31.57.107.185 | 7 |
| 95.182.89.76 | 6 |
| 31.59.105.64 | 6 |
| 31.56.204.42 | 6 |

The bot is still probing and gets nothing past the edge.

Rate rule (priority 2000, 20 POSTs a minute to the two form paths, then a
ten-minute ban with 429): a burst of 25 `POST /registration` from this
machine at 20:07:16 UTC answered `422 ×16` then `429 ×9`. Four POSTs from
the application test a minute earlier counted toward the same window, so
the 429s began with the 21st request in the minute, as configured. Five
seconds later `POST /registration` and `POST /newsletter_subscription` were
both 429 while `GET /registration/new` and `GET /` were 200: the ban covers
only the two form POSTs. It lifts after ten minutes (about 20:17 UTC;
a check at that time is noted below).

## Did it stop the bot?

`POST /registration` reaching the app (Cloud Run request log):

| Window | Reaching the app |
|---|---|
| 17:19–18:19 UTC, the hour before the policy | 19 × 302 (created), 2 × 422 |
| after 18:19 UTC | 3 × 302 at 18:19:37, 18:24:37 and 18:24:57 from 31.56.196.42 and 31.56.204.42, while the apply was still attaching the policy; then only this test's 422s |

Resend (account log): five sends between 17:00 and 18:19 UTC, one at
18:24:56 UTC (the last bot-created signup; status `failed`), **none since**.
Turnstile came on at 19:03 UTC on top of that.

## Not tested here

- A real signup through the widget. It creates an account and sends mail, so
  it is Justin's to do, from a network other than this one for the next ten
  minutes.
- The six addresses' own POSTs: they no longer reach the app, by design.

## Follow-ups

- Remove the 338 bot-created users and the six verified-by-scanner ones:
  [2026-10-20-resend-list-cleanup.md](../issues/2026-10-20-resend-list-cleanup.md).
- Production gets the same protection with #181.
- The console warning about the loader's `onload` name:
  [#190](https://github.com/activeagents/activeagents/pull/190) (1.9.3).
