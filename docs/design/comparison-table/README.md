# Comparison table — design specimen

Reference implementation of the *Ranked Data & Comparison Tables* section
of `DESIGN_SPEC.md`: sortable two-line headers, rank-tinted value pills,
hairline rows, mobile stacking, light and dark themes, lander and dashboard
densities.

`specimen.html` is self-contained vanilla HTML. Open it in a browser, or
point the Playwright harness at it to compare a change. The theme and
density toggles set `data-theme` / `data-density` on `<html>`; the tokens
in its `:root` block mirror `actionagent/frontend/tokens.css`.

The rows are example figures from a seeded evaluation run, not a benchmark.
