# Privacy policy and terms pages (1.9.4)

- Why now: the Google sign-in consent screen (Branding, completed
  2026-10-22) links to `https://activeagents.ai/privacy` and
  `https://activeagents.ai/terms`, and both returned 404. Google's OAuth
  review reads the privacy page, and so does anyone who clicks through
  from the consent dialog. The footer's two links also pointed at `#`.
- What: `PagesController#privacy` and `#terms`, landing layout, one
  `.lp-legal` style block in `lander.css`, footer links wired, tests in
  `pages_controller_test.rb`.
- Content: written from what the app does (traces with `capture_bodies`
  off by default, Stripe, Resend double opt-in newsletter, Turnstile,
  Google Cloud hosting, Google and GitHub sign-in with disconnect from
  Settings, plan retention). The privacy page carries the Google API
  Services User Data Policy / Limited Use sentence that OAuth
  verification looks for.

## For Justin to confirm

- **Legal entity and governing law.** The pages say "Active Agent" and
  "the laws of the United States and of the state in which Active Agent
  is organized". Replace with the registered entity name and a state once
  decided; nothing else in the app records them.
- **Minimum age** is set to 16 (covers GDPR's ceiling). Change to 13 or
  18 if preferred.
- **Deletion window** is 30 days, **price-change notice** 30 days, **terms
  change notice** 14 days, **inactive free account closure** after a
  year with an email first. All are promises the app does not yet
  automate; they are commitments to operate by hand until it does.
- Have a lawyer read both before the production flips if there is time;
  they are plain-language drafts, not reviewed legal text.
