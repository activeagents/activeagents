# ActiveAgents Design System

Design system for **Active Agent** (activeagents.ai) — a Rails framework for AI agents plus a hosted observability platform (agent management, monitoring, traces, metrics, evaluations). Business model mirrors PostHog: free MIT gem with a Rails-engine dashboard, plus hosted/self-hosted Pro & Enterprise platform.

## Sources
- GitHub: github.com/activeagents/activeagents (lander, brand assets, the hosted platform)
  - `DESIGN_SPEC.md` — canonical design spec (colors, dark mode, observability UX)
  - `public/landing/css/index.css` — marketing site CSS (OKLCH theme system)
- GitHub: github.com/activeagents/activeagent (the gem — ships the dashboard as a mountable Rails engine the platform mounts)
  - `lib/active_agent/dashboard/frontend/utils/designTokens.js` — dashboard tokens (TUI philosophy)
  - `lib/active_agent/dashboard/frontend/components/dashboard/*.jsx` — product screens
- Industry competitor to position against: mastra.ai. Liked reference: Laravel Nightwatch (lander + product).

## Naming
- **Active Agent** — product brand name (two words, both capitalized). Never "Active Agents" in UI copy.
- **ActiveAgent** — Ruby gem / code references (`class TranslationAgent < ApplicationAgent`)
- **activeagents.ai** — domain. Gems: ActiveAgent (free/MIT), Solid Agent, Active Instrumentation.

## The two surfaces
1. **Product dashboard** (dense, data-first): sidebar nav (Agents / Observability / Workspace), traces, metrics, evaluations, interactions, session replay. Dark & light from day one.
2. **Marketing website** (lander): OKLCH-driven theme (hue 358), max-width 1008px, eyebrow badges, feature cards, pricing tiers.

## CONTENT FUNDAMENTALS
- **Tone**: technical, terse, developer-first with Rails-culture confidence. Short declarative fragments: "Actions, callbacks, views. For agents." / "Prompt templates. Like Action Mailer, but for AI."
- Rails analogies are the core rhetorical device (Action Mailer, controllers, ERB views, conventions).
- Sentence case for body; section eyebrows in ALL CAPS badges ("WHAT'S IN THE BOX", "OBSERVABILITY PLATFORM").
- Headlines: benefit-led, short. "See Inside Every Agent Decision", "AI Agents in Rails. One Framework."
- Data display favors mono type, uppercase micro-labels ("TOTAL REQUESTS"), unit suffixes (`847ms`, `$42.18`, `2.4M`).
- **No emoji in product UI chrome** going forward (legacy code had some); the dashboard token file mandates ASCII/TUI-style glyphs: `->` traces, `#` metrics, `@` agents, `[>]` replay, `[+]` success, `[!]` error.
- Pricing/CTA verbs: "Get Started", "View on GitHub", "Contact Sales", "Subscribe to Pro".

## VISUAL FOUNDATIONS
- **Color**: brand red `#FA343B` (marketing) / `#ef4444` (product UI accent). NEVER rose/indigo/blue for accent. Blue reserved for info. Warm neutral darks — `#0f0f0f`/`#1a1a1a`, never Tailwind gray-900/950 (blue tint).
- **Type**: Inter Variable (body) + JetBrains Mono (all data, stats, labels, code). Marketing scale is large (66px hero); product scale is dense (13px base, 32px mono stats).
- **Dark mode**: first-class on both surfaces. Dark cards are `rgba(255,255,255,0.05)` on `#0f0f0f`; borders `rgba(255,255,255,0.1)`.
- **Cards**: 12px radius (product) / 16px (marketing), 1px border, minimal shadow; hover = ring (`box-shadow 0 0 0 1px border-level-3`) or shadow-lg lift. Featured pricing card: red border + xl shadow.
- **Backgrounds**: flat colors; marketing hero gets a subtle top red gradient wash (`#FA343B14 → transparent`). No textures, no illustrations except the mascot.
- **Mascot**: red pentagon face w/ black hat & sunglasses (`assets/activeagent-hero.svg`). Used at 28px (sidebar) to 200px (hero). Same design everywhere.
- **Motion**: fast utilitarian transitions (0.15–0.2s ease); transform scale(0.98) press on cards; hover raises via shadow; spinners = red border-b circle. No bounces.
- **Hover states**: bg shifts to `--color-hover`; nav active = red tint bg + red text. Press = darker/scale.
- **Borders over shadows** for structure; tables use bottom-border rows only.
- **Density**: compact — 8–12px cell padding, 20px card padding in product; 24px marketing.
- **Buttons**: primary solid red; secondary red-tint bg + red text (marketing) or gray border (product); tertiary gray fill; 12px radius (m), compact 8px.
- **Status badges**: soft tint bg + strong text (green/yellow/red/blue/gray), pill or 4px radius, 11–12px.
- **Trace spans**: color-coded system — root gray, prompt blue, generate purple, LLM red, thinking amber, tool green, response teal.
- **Focus**: 2px red ring on inputs/buttons.
- **Charts**: red gradient bars, thin 2px sparkline polylines (red/green/gray), progress bars for provider breakdowns. Moderate chart usage: a few key charts per screen, tables carry the load.

## ICONOGRAPHY
- **Product**: ASCII/TUI glyph system from `designTokens.js` — rendered in JetBrains Mono. Nav: `@` agents, `+` new, `->` traces, `#` metrics, `=` evaluations, `<>` interactions, `%%` benchmarks, `[>]` replay. Status: `[+]` `[!]` `[?]` `[i]` `[*]`. Plus minimal inline stroke SVGs (Heroicons-style, 1.5–2px stroke) for actions.
- **Marketing**: Font Awesome 6.7.2 (solid) in the legacy lander; prefer the TUI glyphs + stroke SVGs going forward for consistency.
- Unicode box-drawing chars (─ │ ├ └) used for trace trees.
- Logos: `assets/activeagent-logo.svg` (light), `assets/activeagent-logo-dark.svg`, `assets/icon.svg` (favicon mark), `assets/banner-dark.svg`.

## Index
- `styles.css` — global entry (imports tokens/)
- `tokens/` — fonts.css, colors.css, typography.css, spacing.css, base.css
- `assets/` — logos, mascot, banner, favicon, UI placeholder
- `fonts/` — Inter Variable (woff2), JetBrains Mono (ttf)
- `guidelines/` — foundation specimen cards (Design System tab)
- `components/core/` — Button, Input, Select, Checkbox, Switch, Card, Badge, StatusBadge, Tabs, Tag
- `components/data/` — StatCard, DataTable, SpanBar, ScoreBar, MonoLabel, ContextMeter (v2: deferred rows, source groups, sub-limit meters, freshness footer)
- `components/telemetry/` — the telemetry object family: ObjectRow (shared expandable shell) + AgentRow, InteractionRow, TraceRow, EvalRow. Object grammar: `@` agent · `<>` interaction · `->` trace · `=` eval · `#` context; every object = chevron · glyph chip · mono id · title · mono meta · indicators · status badge; nesting via `depth` (interaction event -> trace -> spans). Runtime copy for screens/cards: `ui_kits/dashboard/TelemetryObjects.jsx` (`window.AAKit.Telemetry`)
- `components/feedback/` — Dialog, Toast, Tooltip, Spinner, EmptyState
- `ui_kits/dashboard/` — product app screens (fleet, agent detail, traces, metrics, evals)
- `ui_kits/website/` — marketing lander
- `slides/` — slide templates
- `SKILL.md` — agent skill entrypoint

## Intentional additions
- Standard form/feedback primitives (Dialog, Toast, Tooltip) authored per user request for a full component set; styled strictly from the spec's patterns.
