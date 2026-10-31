# Pay 12 and stripe-ruby 20 upgrade

Branch `chore/pay-12-stripe-20`. Supersedes the two Dependabot PRs that could
not land alone: #206 (pay 12.3.0, which refuses to boot against stripe 12) and
#166 (stripe 20.0.0, which pay 7.3 refuses). Pay pins the stripe gem's major
version, so the two move together.

## What changed

| Gem | From | To |
|-----|------|----|
| `pay` | 7.3.0 | 12.3.0 (`~> 12.3`) |
| `stripe` | 12.6.0 | 20.1.0 (`~> 20.0`) |

Stripe API version is now whatever stripe-ruby 20 pins (`2026-10-28.endive`
at the time of writing); Pay 12.3 was written against `2026-09-30.endive`.

### Breaking changes that touch this app

* **Pay 8: single table inheritance.** Every Pay row carries a `type`
  (`Pay::Stripe::Customer`, `Pay::FakeProcessor::Subscription`, ...) and
  processor behaviour lives on the subclass. A bare `Pay::Subscription` no
  longer answers `active?`/`paused?`. The app itself only creates Pay rows
  through `set_payment_processor`, `add_payment_processor` and `subscribe`,
  which already set `type`; the two test fixtures that inserted rows directly
  now go through `Pay::Stripe::Customer`.
  `pay_payment_methods.type` is renamed to `payment_method_type`; nothing in
  the app reads it.
* **Pay 10: `object` column.** `pay_customers`, `pay_charges` and
  `pay_subscriptions` gain a jsonb `object` copy of the Stripe object. Charge
  details moved under `stripe_invoice`; the app does not render charges.
* **Pay 11: owner associations renamed** to `pay_charges` and
  `pay_subscriptions`. The app reads `account.pay_customers ... .subscriptions`
  (the `Pay::Customer` association, unchanged), so no code change.
* **Pay 12: Stripe failures are always `Pay::Stripe::Error`.** `checkout` and
  `billing_portal` used to let `Stripe::StripeError` through. The checkout
  action already rescues `Pay::Error`, so it keeps working; the raw error is
  `error.cause`. Duplicate `processor_id`s now raise
  `ActiveRecord::RecordNotUnique` (unique indexes) instead of `RecordInvalid`.
* **stripe-ruby 13+: `StripeClient#execute_request` is gone.**
  `StagingProBilling` and `script/staging_billing_diagnostics.rb` now call
  `raw_request(method, path, params:, opts:)`, which returns a `StripeObject`;
  `to_hash` yields the same symbol-keyed data the old `.first.data` did. The
  idempotency key moves from a literal header to `opts[:idempotency_key]`.
* **stripe-ruby 20: `payment_method_types` removed** from Checkout Session
  creation (now `allowed_payment_method_types`). The app never passed it.

Not applicable: Paddle, Braintree and Lemon Squeezy changes, receipts 3.0,
the SCA confirmation view (not copied into the app), Stripe Connect.

## Migrations

Copied with `bin/rails pay:install:migrations`; `create_pay_tables` was
already installed, so only two were added:

* `20261031204507_add_pay_sti_columns.pay.rb` adds `type` to all five Pay
  tables, renames `pay_payment_methods.type`, and backfills `type` on
  existing customers, charges, subscriptions and payment methods from the
  `processor` column. This is a data migration: it touches every existing
  `pay_customers` row (Stripe and `fake_processor` comps alike) and runs in
  the normal migrate job before the new code serves requests.
* `20261031204508_add_object_to_pay_models.pay.rb` adds the jsonb `object`
  column to customers, charges and subscriptions (nullable, no backfill;
  Pay fills it on the next sync or webhook).

`db/schema.rb` was dumped from a scratch database (`DATABASE_URL`,
`db:create db:schema:load db:migrate`) so the stray dev-only tables stay out.

## Verified locally

* `bin/rails runner 'puts Pay::VERSION; puts Stripe::VERSION'` prints
  `12.3.0` / `20.1.0`.
* `bin/rails test` as CI runs it (fresh database, `PARALLEL_WORKERS=1`, no
  master key): 700 runs, 3170 assertions, 0 failures, 0 errors, 3 skips.
* RuboCop, Brakeman and `zeitwerk:check` clean.

## To verify on staging

1. Deploy with the migrate job and check the two migrations ran; spot-check
   `Pay::Customer.where(type: nil).count` and
   `Pay::Subscription.where(type: nil).count` are both 0.
2. **Checkout**: from a fresh test workspace, start a Pro checkout in Stripe
   test mode, pay with a test card, and confirm the `checkout.session.completed`
   and `customer.subscription.created` webhooks produce an active
   `Pay::Stripe::Subscription` and the workspace reads as Pro.
3. **Customer portal**: open the billing portal from Subscription, change
   nothing, return; then cancel from the portal and confirm the
   `customer.subscription.updated` webhook marks `ends_at`.
4. **Webhook delivery**: in the Stripe dashboard check the staging endpoint
   (`/pay/webhooks/stripe`) is delivering 2xx, and compare its pinned API
   version with the one stripe-ruby 20 uses; Pay re-fetches objects, so an
   older endpoint version is tolerated, but note it for the next release.
5. Run the **staging-billing-diagnostics** workflow; the report should still
   print `key_accounts` and `staging_webhooks` for the environment key, which
   proves `raw_request` works against the real API.
6. Run the staging Pro catalog task (`stripe_setup.rake`) once; it should
   report the existing prices unchanged and make no writes.
