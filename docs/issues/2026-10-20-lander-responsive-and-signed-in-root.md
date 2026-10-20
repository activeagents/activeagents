# The lander on every width, and the root for signed-in people

- Reported 2026-10-20 by Justin with a screenshot of the header: the right-hand
  controls (Discord, GitHub stars, theme toggle) on one row and **Sign In**
  wrapped onto a second, making the bar twice as tall. And: "I'm already
  signed in, but it takes me to the lander; I have to click login to get to
  the dashboard, that should be automatic."
- Branch: `fix/lander-responsive` (from `main` at fd9fc0f).

## What was wrong

Measured with Playwright against the running app (`tmp/screenshots/lander/`,
gitignored):

| Width | Header height | Cause |
| --- | --- | --- |
| 1100–1440px | 112px | brand 162 + menu 509 + actions 329 + padding 28 = 1028px in a bar capped at 1008px; the actions' `flex-wrap: wrap` put Sign In on a second row |
| 1024px and below | 62px | menu folded behind the hamburger (as designed) |
| 480–767px | overflow | the bar kept Discord, stars, theme and Sign In (379px) next to the brand (162px) in a 448px bar |
| 390px | clipped | the evaluations matrix in the dashboard bento was cut off at the pane edge |
| 768–1056px | untidy | the install command box wrapped onto two lines with the separator dangling at the end of the first |

And `pages#home` rendered the lander for everyone.

## What changed

- `base.css`: the bar is `align-items: center` with a 12px gap between its three
  parts; links use 10px side padding and never wrap; the actions live in
  `.nav-actions` (no wrap, no shrink, 8px gap). The desktop bar now needs
  about 970px, inside the 1008px cap, on both landers (the OSS one has
  "Dev Console").
- `tablet.css` (≤1056px): the folded menu's links get 12px vertical padding;
  the install box becomes two rows with no separator.
- `mobile.css` (≤767px, was ≤479px): Discord, the stars and Sign In leave the
  bar (`.nav-wide`) and join the folded menu (`.nav-narrow`): full-width
  Sign In / Start Free, then a centered Discord + stars row.
- `_header.html.erb`: one `github-stars` controller on the bar fills both
  badges (`countTargets`); a signed-in visitor sees **Dashboard** in the bar
  and **Go to your dashboard** in the menu instead of Sign In / Start Free.
- `pages_controller.rb`: a signed-in visitor opening `/` is sent to
  `/dashboard` (or to email verification if not yet verified). `?site=` and
  `?demo_mode` still show the lander, for previewing it.
- `_dashboard_bento.html.erb`: the evaluations matrix scrolls sideways in a
  `.lp-table-wrap` instead of being clipped.

## Checks

- `test/controllers/pages_controller_test.rb`: four new tests (Sign In in bar
  and menu; signed-in redirect; unverified redirect; the lander still
  previewable with the dashboard offered).
- Screenshots after the change at 320–1440px plus the open menu, both landers.
