# Lander signup + consulting capture review — 2026-08-27

Branch: `feat/upgrade-activeagent-1.2`

Review of the activeagents.ai lander to confirm Resend is collecting signups and
that the consulting CTAs actually capture leads.

## What was already working

The landing-page signup path is live and verified end to end against production:

```
POST https://activeagents.ai/registration  (with CSRF token + session cookie)
  -> 200 {"success":true,"redirect_url":"/pending_verification"}
```

Chain: `_signup.html.erb` -> `RegistrationsController#create_from_landing_page`
-> creates User + Account -> `send_verification_email!` -> `SyncUserToResendJob`
-> `Resend::Contacts.create` -> sets `synced_to_resend`.

Terraform injects `RESEND_API_KEY` / `RESEND_AUDIENCE_ID` as Cloud Run secret env
vars (`terraform/main.tf:205-206`). Transactional mail goes over the Resend SMTP
relay (`config/environments/production.rb:62-73`).

Note: bare `curl` against `/registration` returns 422. That is CSRF correctly
rejecting a token-less request, not a bug — real browsers work.

## Issues found and fixed

### 1. SPF/DKIM did not authorize Resend for the apex domain (deliverability risk)

Production DNS authorized only Google:

```
activeagents.ai TXT -> "v=spf1 include:dc-aa8e722993._spfm.activeagents.ai ~all"
  resolves to        -> "v=spf1 include:_spf.google.com ~all"
resend._domainkey.activeagents.ai -> EMPTY (no DKIM)
```

Staging had the full set of Resend records; production had none. Every
verification email sent through the Resend relay was unauthenticated for this
domain — with `p=none` DMARC it would not hard-bounce, but mailbox providers
would spam-folder it, so signups never verify.

Fixed in `terraform/environments/staging/dns.tfvars` (that workspace owns the
apex zone; there is no production dns.tfvars). Added, mirroring the working
staging setup:

- TXT `send` -> `v=spf1 include:amazonses.com ~all`
- MX  `send` -> `10 feedback-smtp.us-east-1.amazonses.com.`
- TXT `resend._domainkey.send` -> **placeholder, still needs the real key**

The records are scoped to the `send.` subdomain so the apex SPF (Google
Workspace) is untouched and the 10-lookup SPF limit is not at risk.

**BLOCKED — action required:** the DKIM key is generated per-domain by Resend and
cannot be invented. Add `activeagents.ai` in the Resend dashboard
(Domains -> Add Domain), then replace `REPLACE_WITH_RESEND_DKIM_KEY` in
dns.tfvars with the `p=...` value it shows, and apply. Registering the apex
domain means `MAILER_FROM_ADDRESS` can stay `hello@activeagents.ai`.

### 2. Stimulus signup controller was never registered (real bug)

`app/javascript/controllers/index.js` did not register `signup_controller.js`,
though `_signup.html.erb` declared `data-controller="signup"` with
`data: { turbo: false }`. The JS never ran, so the form did a full-page POST
instead of the intended inline AJAX flow. Registered both `signup` and the new
`contact` controller.

### 3. Response targets were outside controller scope

The `#signup-response` / `#contact-response` divs sit as siblings of their forms,
so `data-*-target="response"` was out of scope, `hasResponseTarget` was false,
and success messages were silently dropped. Moved `data-controller` onto the
wrapping `*-form-container` (submit events still bubble up from the form) and
added an explicit `form` target for `reset()`.

### 4. Newsletter section was dead code

`_newsletter.html.erb` was rendered nowhere — despite having full CSS
(`landing/base.css:4219-4315`) and the hero replay demo scripting a
"scroll to newsletter" beat. It also duplicated the signup logic in an inline
`<script>`. Wired into `home.html.erb` and rewritten to reuse the signup
controller. It now opts out of the redirect (`data-signup-redirect-value="false"`)
so a subscriber stays on the page instead of being pushed into account
verification, and it tags `signup_source = "newsletter"`.

### 5. Consulting CTAs were mailto-only (no lead capture)

Every advisory/workshop/dev inquiry depended on the prospect's mail client
opening, with no record of who clicked. Replaced with a real capture form:

- `Lead` model + `20260827120000_create_leads.rb` migration
- `LeadsController#create` (JSON + HTML)
- `LeadMailer` — internal notification routed per service type, with `reply_to`
  set to the lead, plus a confirmation to the lead
- `SyncLeadToResendJob` — adds the lead to the Resend audience
- `_contact.html.erb` + `contact_controller.js` + matching CSS

Service cards now link to `#contact-advisory` / `#contact-workshop` /
`#contact-development`, and the enterprise "Contact Sales" CTAs to
`#contact-enterprise`; the controller preselects the matching option and scrolls
to the form. `mailto:consulting@activeagents.ai` is kept as a visible fallback.

Notification routing: workshop -> workshops@, advisory -> consulting@,
development -> dev@, enterprise -> sales@, general -> hello@. Override with
`LEADS_NOTIFICATION_ADDRESS`.

### 6. Privacy / Terms were dead links

Both were `href="#"`. Added `/privacy` and `/terms` with real content covering
telemetry handling, retention, subprocessors (GCP/Stripe/Resend), and the
consulting engagement terms. **These are drafts and want a legal review.**

### 7. No test coverage on the conversion path

Added 46 tests: Lead model, LeadsController, RegistrationsController (signup +
Resend sync + source attribution + duplicate handling), both Resend sync jobs,
LeadMailer routing, and lander/legal page rendering.

Both sync jobs gained a `contacts_client` class attribute as an injection seam —
Minitest 6 dropped `minitest/mock` from the default bundle, so the tests use a
small fake rather than adding a mocking dependency.

## Verification

- Full suite: **332 runs, 1041 assertions, 0 failures, 0 errors**
- RuboCop clean on all new/changed Ruby
- Browser-verified on a local server: contact form submits without reload and
  shows the inline success message; the lead persists with the service type
  carried from the anchor; newsletter subscribes without redirecting; anchor
  preselection works; mobile (390px) stacks with no horizontal overflow

## Still outstanding

1. **Add activeagents.ai to Resend and fill in the DKIM key**, then apply the
   Terraform DNS change. Until then production email stays unauthenticated.
   This is the highest-impact remaining item.
2. **Confirm the contact mailboxes actually receive.** MX (Google Workspace) is
   live, but port 25 is blocked from the dev machine so delivery could not be
   proven. Send a test to workshops@, consulting@, dev@, sales@, and hello@ —
   any unconfigured alias means inquiries bounce silently.
3. **Verify the GCP secrets hold real values.** `gcloud` needed reauth during
   this review, so `resend-api-key` / `resend-audience-id` were not inspected.
4. **Legal review** of the privacy/terms drafts.
5. Consider adding `privacy@` and `legal@` aliases — both are referenced by the
   new legal pages.
