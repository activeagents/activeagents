# Human check on the public forms, and Cloud Armor in front of them

Date: 2026-10-20 · Branch: `fix/bot-signups` · PR: [#180](https://github.com/activeagents/activeagents/pull/180), merged 2026-10-20 18:12 UTC as `60e456ea`, staging deploy run 39472670052 green · Turnstile on since 2026-10-20 19:03 UTC via [#187](https://github.com/activeagents/activeagents/pull/187) (deploy run 39478473284) · Issue: [2026-10-19-signup-bot-email-abuse.md](../issues/2026-10-19-signup-bot-email-abuse.md)

From 2026-10-17 a subscription-bombing bot POSTed `/registration` on
activeagents.ai (served by staging) a few hundred times a day from six
addresses, and every POST made the app send a "Verify your email" message to
someone who never asked for one. The per-IP `rate_limit` (10 per 10 minutes)
let six rotating addresses through at about 360 an hour. Resend's daily cap
filled with bot mail, recipients reported it as spam, and the sending domain's
reputation at Gmail went with it (see
[2026-10-20-email-sender-reputation.md](../issues/2026-10-20-email-sender-reputation.md)).

This change puts three layers in front of the signup and newsletter forms.
Each works on its own; together they stop this bot and the next one.

## 1. Cloud Armor on the load balancer (Terraform)

`terraform/modules/load-balancer` gains a `google_compute_security_policy`
attached to the backend service when `enable_security_policy` is on:

| Priority | Rule | Effect |
|---|---|---|
| 1000… | `blocked_source_ranges` (ten per rule) | 403 for every request from those addresses |
| 2000 | `request.method == 'POST'` to `/registration` or `/newsletter_subscription` | more than `signup_rate_limit.count` (20) in `interval_sec` (60) from one address bans it for `ban_duration_sec` (600) with 429 |
| default | everything else | allowed, as before |

Staging turns it on in the committed
`terraform/environments/staging/security.auto.tfvars`, with the six bot
addresses. Production's `security.auto.tfvars` has the same lines
commented; its Cloud Armor waits for the production load balancer
(`infra/production-full-stack`, host #181). The rule needs no secret, so it
took effect at the staging deploy's `terraform apply` after the merge:
since 2026-10-20 18:19 UTC the policy `activeagents-staging-policy` is
attached to `activeagents-staging-backend` with the six addresses in its
deny rule and the rate rule at 20 POSTs a minute, checked with
`gcloud compute security-policies describe`; the public pages still answer
200 and an empty `POST /registration` gets the app's 422. Cloud Armor's
standard tier bills per policy, per rule and per million requests; at this
traffic that is a few dollars a month.

Remove an address from the list once it has been quiet for a month; the
rate rule stays.

## 2. Honeypot (always on)

`HumanCheckHelper#human_check_fields` renders a text field named `website`
inside each protected form, positioned off screen, out of the tab order and
hidden from assistive tech. People never fill it; form fillers do. A filled
field is refused with 422 and nothing is created or sent. It needs no
configuration, so it protects every deployment, including local ones.

## 3. Cloudflare Turnstile (on when its keys are set)

`HumanCheck.enabled?` is true when `TURNSTILE_SITE_KEY` and
`TURNSTILE_SECRET_KEY` are both present. Then:

- the layouts load `https://challenges.cloudflare.com/turnstile/v0/api.js`
  (explicit render, no `onload` callback name) and the helper renders a
  widget container in each form, which the `turnstile` Stimulus controller
  renders as soon as `window.turnstile` exists, or on the loader script
  element's `load` event when the controller connects first; it resets
  the widget after a refused submission and removes it on disconnect, so
  it survives Turbo navigations;
- the widget writes its token into a hidden `cf-turnstile-response` field;
  the `signup` and `newsletter` controllers copy it (and the honeypot) into
  their JSON bodies through `app/javascript/controllers/human_check.js`;
- `RequiresHuman#require_human!` (a `before_action` on both `create` actions)
  calls `HumanCheck.check`, which POSTs the token to Cloudflare's
  `siteverify` with the client address, five-second timeouts, and **fails
  closed**: a missing token, a rejected token, a timeout or a non-200 reply
  all refuse the submission with 422.

Without the keys, Turnstile is off, nothing third-party loads, and only the
honeypot applies.

Live since 2026-10-20 19:03 UTC on activeagents.ai (served by staging):
Justin ran `bin/turnstile-keys` at 18:49 UTC, #187 merged at 18:58 UTC and
deploy run 39478473284 applied it. Checked at 19:08 UTC: the registration
page serves the loader and the site key with the honeypot still present,
and in a headless Chromium the widget rendered its "Success!" state and
wrote a 730-character token into `cf-turnstile-response` without a
challenge (screenshot in the gitignored
`tmp/screenshots/2026-10-20-turnstile-live/01-registration-new.png`).
Cloudflare's own iframe logs CSP and WebGPU noise to the console; that is
theirs. One warning was ours: api.js was loaded with
`onload=onloadTurnstileCallback`, a global the controller only defined when
it connected, which an async loader usually beat. Harmless, since the
controller then found `window.turnstile` and rendered anyway; fixed for
1.9.3 on `fix/turnstile-onload` by dropping the parameter and waiting on
the script element's `load` event instead.

The refusal has the same shape as the actions' own errors: JSON
`{ "error": "We couldn't confirm you're a person. Please try again." }` for
the landing page forms, the full registration form re-rendered with the
message, and a redirect back with a flash for a plain POST.

## 4. Verification resend cooldown

`RegistrationsController#create_from_landing_page` used to resend the
verification email every time an unverified address was posted again; the
bot replayed addresses and recipients got several copies within minutes. It
now resends at most once per `VERIFICATION_RESEND_INTERVAL` (10 minutes) and
still answers "Verification email resent" so a person who did ask twice sees
the same screen.

## Turning Turnstile on (operator)

One widget serves every hostname, so one site key and one secret go to
both environments. The site key is public (it is rendered into every
form) and is committed; the secret only ever goes into Secret Manager.

1. In the Cloudflare dashboard, Turnstile → Add widget: hostnames
   `activeagents.ai`, `www.activeagents.ai`, `staging.activeagents.ai`,
   `activeagent.dev`, `activeagent.pro`, and `localhost` for development;
   widget mode **Managed** (invisible unless a challenge is needed; the
   forms render it with `appearance: interaction-only`, the full
   registration form with `always`). Copy the site key and the secret key.
2. Run `bin/turnstile-keys` ([#185](https://github.com/activeagents/activeagents/pull/185)) from your own terminal, not through a chat
   session, so the secret stays out of transcripts and shell history. It
   asks for two pastes, the site key first and the secret second (not
   echoed), checks both look like Turnstile keys, and then:
   - adds the secret as a new version of each environment's
     `activeagents-<env>-turnstile-secret-key`. Staging's secret exists
     since the deploy of #180. Production's does not exist until
     production applies the Terraform that declares it, so the script
     creates it with the labels the `secret-manager` module sets and adds
     an `import` block to `terraform/environments/production/imports.tf`,
     the pattern already used there for the Resend secrets, so the next
     production apply adopts it instead of failing with a 409;
   - sets `enable_turnstile = true` and the site key in both
     `security.auto.tfvars`, commits that (plus the import block) on
     `chore/turnstile-keys` cut from `origin/main` in a temporary worktree,
     pushes, and opens the pull request.

   `bin/turnstile-keys --dry-run` prints the plan and the diff and stores,
   creates, commits and pushes nothing. If staging's secret is missing
   while a staging deploy is still running, the script stops and asks for
   a re-run after the deploy, because that apply creates the secret.
3. Merge the pull request. The staging deploy applies it; production
   picks it up at its next deploy. The root output `turnstile_site_key`
   refuses the flag without a site key.
4. Check: `https://activeagents.ai/registration/new` shows the widget;
   a POST without a token to `/registration` gets 422; a real signup goes
   through. Cloudflare's Turnstile analytics show solves and failures.

By hand instead of the script: add the versions from your terminal

```sh
read -s TURNSTILE_SECRET
for env in staging production; do
  printf '%s' "$TURNSTILE_SECRET" | gcloud secrets versions add "activeagents-$env-turnstile-secret-key" --data-file=- --project=active-agents-platform
done
unset TURNSTILE_SECRET
```

(a missing secret first needs `gcloud secrets create <name>
--replication-policy=automatic` and an import block like production's
`imports.tf`), then set `enable_turnstile = true` and
`turnstile_site_key = "<site key>"` in each environment's
`security.auto.tfvars` and commit.

Local development: export the two variables (Cloudflare's test keys
`1x00000000000000000000AA` / `1x0000000000000000000000000000000AA` always
pass) or leave them unset for honeypot-only. Any other deployment of this
app turns the check on the same way: set `TURNSTILE_SITE_KEY` and
`TURNSTILE_SECRET_KEY` in its environment.

## Tests

`test/integration/human_check_test.rb`: honeypot refusals on all three
paths (JSON signup, full form, newsletter); Turnstile off needs no token;
Turnstile on refuses a missing token, accepts a token Cloudflare accepts
(request body checked), refuses a rejected token, a timeout and a 502; the
full form posts its token; the registration page renders the honeypot
always and the widget and loader only when on, never the secret; every
landing page form carries the honeypot; the resend cooldown.

`terraform/tests/feature_infra.tftest.hcl`: the flags pass their variables
and nothing new by default; `enable_turnstile` needs a site key;
`blocked_source_ranges` must be CIDRs; the load-balancer module creates no
policy by default and, when on, chunks the ranges ten per rule, writes the
rate rule's expression and attaches the policy.

## Not in this change

- Cleaning up the bot-created users (including the ones link scanners
  marked verified) and the Resend contacts they produced.
- `POST /resend_verification` (signed-in users only) has no cooldown; the
  bot never reached it.
- The password reset form, Sign in with GitHub and the pilot invitation
  acceptance are untouched.
- The sender domain and DMARC work in
  [2026-10-20-email-sender-reputation.md](../issues/2026-10-20-email-sender-reputation.md).
