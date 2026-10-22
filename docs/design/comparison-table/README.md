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

## In the product

`product/` holds shots of the actionagent dashboard after the pattern landed
(`ComparisonTable`, `ValuePill` and `MetricStrip` in
`actionagent/frontend/components/dashboard/`), captured from the real
components in a Playwright harness against seeded example data, not a
booted app. The figures are synthetic.

| File | Shows |
| --- | --- |
| `01-scenario-suite.png` | Scenario run: pass pills in every result cell, two-line COST / TIME headers, the model comparison table under it |
| `02-scenario-suite-dark.png` | Same, dark theme |
| `03-scenario-expanded.png` | A scenario opened: each model's result card leads with a SCORE · TIME · TOKENS · COST strip |
| `04-leaderboard.png` | Evaluations page model leaderboard, rates as pills on the pass thresholds |
| `05-leaderboard-dark.png` | Same, dark theme |
| `06-metrics.png` | Metrics overview: each golden-signal tile's change vs the previous window is a ranked pill |
| `07-metrics-dark.png` | Same, dark theme |
| `08-home-top-agents.png` | Home overview: Top Agents as a sortable comparison table |
| `09-models-panel-phone.png` | The model comparison at 400px: rows stack to labelled pills |
