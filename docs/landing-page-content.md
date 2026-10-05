# Active Agent Landing Page Content

The commercial lander (activeagents.ai / activeagent.pro) is `app/views/pages/home.html.erb`;
it renders one partial per section from `app/views/pages/sections/`. The open-source lander
on activeagent.dev is `home_oss.html.erb`; `PagesController` picks it by host (`?site=oss` or
`?site=commercial` forces a variant). The two share the pipeline and framework sections, the
hero stage (`_stage.html.erb`) and the dashboard mockups (`_dashboard_bento.html.erb`). Styles
for the sections live in `app/assets/stylesheets/landing/lander.css` (namespaced `lp-`), on
top of the theme tokens and primitives in `base.css`.

The product mockups are hand-built HTML in the dashboard's own grammar (JetBrains Mono, the
TUI glyphs `@ -> # = <> [] {} [>]`, span colors, soft status badges), not screenshots. Keep
the numbers in them plausible and consistent with the dashboard: fractions carry their percent
(`14/16 · 88%`), estimated money carries a `~`, and tokens read `↓ in ↑ out`.

Every claim below is drawn from the gem's docs and CHANGELOG (activeagent / actionagent 1.8).
When a feature changes, change the copy here and in the partial.

---

## 1. Header (`layouts/landing/_header.html.erb`)

Logo, then Framework · Dashboard · Platform · Pricing · Docs. GitHub stars, theme toggle,
Sign In, and a Start Free button in the mobile menu. The OSS host shows Dev Console · Gems ·
Platform instead.

## 2. Hero (`_hero.html.erb`)

- Eyebrow: `FRAMEWORK · DASHBOARD · PLATFORM`
- Headline: **Build AI in Rails. / See everything it does.**
- Body: Active Agent is the framework (agents are controllers, prompts are views, tools are
  methods). Action Agent is the dashboard that mounts beside it. Point the same telemetry at
  activeagents.ai for production.
- Above the fold: the account signup form (email field + Start free), posted to
  `registration_path` by the `signup` Stimulus controller, then "Free workspace, no credit card"
  with links to the docs and GitHub.
- Install strip: `bundle add activeagent actionagent` · `rails g action_agent:install && rails db:migrate`
- Trust chips: MIT licensed · Rails 7.2 / 8.0 / 8.1 · Ruby 3.2+ · 10 providers · Telemetry built in
- Stage: `app/agents/support_agent.rb` (generate_with, before_action, delegate_to, schema
  tools, an MCP server, `as(current_user)`) beside the trace it produces (span waterfall,
  tokens, caller, release, context meter).

## 3. How it fits together (`_pipeline.html.erb`)

**Three gems. One wire format.** `activeagent` (framework, MIT) → `local_storage: true` →
`actionagent` (dashboard, MIT) → `endpoint: api.activeagents.ai` → activeagents.ai (platform,
hosted). Footnote for `solid_agent` and `activeagents-telemetry`.

## 4. The framework (`_features.html.erb`, id `framework`)

**Agents are controllers.** Two-column grid of code cards:

1. Agents are controllers — actions, `before_action`, `generate_now` / `generate_later`
2. Action Prompt — `app/views/agents/<name>/instructions.md`, `<action>.md.erb`, `<action>.json`
3. Any provider — OpenAI, Anthropic, Gemini, Bedrock, Azure, Ollama, OpenRouter, Requesty, DeepSeek, RubyLLM
4. Tools from your schema — `ActiveAgent::SchemaTools`, `filterable`, `returns`, `scope_by_policy`
5. MCP servers — remote `url:` and local `command:` servers
6. Delegation — `delegation` contracts, `delegate_to` with a budget
7. Evaluations as tests (wide) — `ActiveAgent::Evals::Runner`, scenarios, models, report

Chips: structured output, streaming, retries, callbacks, `current_user`, releases, embeddings,
mock provider, token usage and cost.

## 5. The dashboard (`_dashboard.html.erb`, id `dashboard`)

**See inside every agent decision.** Install block, then the bento:

- Traces (list with release chips and status)
- Metrics (five golden signals, requests chart with a deploy marker and an incident marker)
- Evaluations (scenario × model matrix, judge's pick, costs, What to fix card)
- Interactions (transcript with a tool call, context meter)
- Run Agent (generative UI blocks, composer)
- MCP server (`<mount>/mcp`: `run_<agent>`, schema tools, `evaluations_run`, `traces_search`)
- Integrations (GitHub connection, checkout sandbox, Claude Code or Codex session, suite re-run, diff)
- Also on the sidebar: Agents, Tools and MCP Services, Session Replay, Ask ActiveAgents

## 6. The platform (`_platform.html.erb`, id `platform`)

**Same engine. Run for you.** The development vs production YAML, then: workspaces and seats,
hosted ingestion (`/v1/traces`, `/v1/evaluations`), evaluation reports from CI, retention and
quotas by plan, your agents as an MCP server, managed sandboxes. Footnote links to the
self-hosted guide.

## 7. Pricing (`_pricing.html.erb`, id `pricing`)

**The gems are free. The platform scales with you.** Plans mirror `db/seeds.rb` and
`Account::USAGE_LIMITS` / `TRACE_LIMITS` / `TRACE_RETENTION`:

| Plan | Price | Seats / workspaces | Traces / mo | Retention | Executions / mo |
|---|---|---|---|---|---|
| Free | $0 | 1 / 1 | 250 | 3 days | 25 |
| Pro Platform | $99 / mo or $995 / yr, 14-day trial | 5 / 1 | 25,000 | 14 days | 10,000 |
| Enterprise | $269 / mo or $2,690 / yr | Unlimited | 500,000+ | 400 days | Unlimited |

The comparison table adds a Self-hosted column and the add-on prices.

## 8. Services (`_services.html.erb`, id `services`)

Workshops ($2,500 half day / $4,500 full day), Advisory (from $3,000 a month), Development
($250 an hour or fixed price). Mailto CTAs.

## 9. FAQ (`_faq.html.erb`)

What is free and what is paid · How do I install it · Which providers · Does MCP work with
every provider · How does the platform get my data · Can I self-host for a team · What do
evaluations test · Does it work with an existing Rails app.

## 10. Signup (`_signup.html.erb`)

Email form posting to `registration_path`. "Free forever · No credit card required".

## 11. Footer (`layouts/landing/_footer.html.erb`)

Documentation · Pricing (or Gems on the OSS host) · Changelog · GitHub · cross-link to the
other site, plus GitHub, Discord, Twitter and Bluesky.

---

## The open-source lander (activeagent.dev, `home_oss.html.erb`)

Header: Framework · Dev Console · Gems · Platform (activeagents.ai) · Docs.

1. **Hero** (`_hero_oss.html.erb`). Eyebrow `OPEN SOURCE · MIT`. "Build AI in Rails. / Agents
   are controllers." Body keeps the phrase "provider-agnostic". Above the fold: the newsletter
   signup (email field + Get release notes), posted to `newsletter_subscription_path` by the
   `newsletter` Stimulus controller, then links to the docs and GitHub. Install strip
   `bundle add activeagent` · `rails generate active_agent:install`. The shared stage follows,
   then a one-line pointer to activeagents.ai.
2. **Pipeline** and **Framework**: shared with the commercial lander.
3. **Dev console** (`_dev_console.html.erb`, id `dev-console`). "See your agents while you
   build": the `actionagent` install block and the shared dashboard mockups, with a footnote on
   mounting it for a team and the self-hosted guide.
4. **Gems** (`_gems_oss.html.erb`, id `gems`). "Free, and free forever." One card per MIT gem:
   `activeagent`, `actionagent`, `solid_agent`, `activeagents-telemetry`, each with its install
   chips and a docs link, then a wide "Need it hosted?" card pointing at the platform. No prices
   on this host: `PagesControllerTest` asserts "Pro Platform" never appears here.
5. **Newsletter** (`_newsletter.html.erb`, id `newsletter`). "Release notes, in your inbox." An
   email field posted to `/newsletter_subscription`: the server stores the consent, sends a
   confirmation email, and `SyncNewsletterToResendJob` adds the contact to the Resend newsletter
   audience once confirmed. No account is created on this host.
6. **FAQ** (`_faq_oss.html.erb`) and **CTA** (`_cta_oss.html.erb`, "Ship your first agent this
   afternoon.").

---

## Retired with this lander

The session-replay hero (the lander inside an iframe with an agent cursor), the flip cards,
the separate "Gems" pricing tier for a PRO gem, and the `_product_preview` mockups are no
longer rendered from `home.html.erb`. Their partials, Stimulus controllers and CSS are still in
the repository; remove them once nothing else needs them.
