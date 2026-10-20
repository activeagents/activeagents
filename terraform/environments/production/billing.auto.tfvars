# Live-mode Pro prices in the Stripe account (acct_1SyJzXE3QRGeeIHk), found or
# created by bin/stripe-live-setup on 2026-10-20. Terraform passes them to
# the app as STRIPE_PRO_MONTHLY_PRICE_ID / STRIPE_PRO_ANNUAL_PRICE_ID and
# `db:seed` copies them onto the Pro plan row. Checkout refuses the Pro
# plan while the plan row has no price IDs.
stripe_pro_monthly_price_id = "price_1USlerE3QRGeeIHk0M6BStYF"
stripe_pro_annual_price_id  = "price_1USlerE3QRGeeIHkhOElxc2K"
