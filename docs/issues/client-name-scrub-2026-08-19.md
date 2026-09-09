# Client-Name Scrub (2026-08-19)

Client-identifying content (client org, product, tenant, and agent names, an
internal wildcard domain, seeded demo credentials, and a vendor index name) had
leaked into code comments and internal docs in two repos. Policy: no client
names anywhere in our codebases.

## Replacement conventions

| Was | Now |
|---|---|
| client agent `.respond` / `.title` | `Assistant.respond` / `Assistant.title` |
| client self-host example domain | `activeagents.example.com` |
| client app / product name | "the client app" |
| tenant-scoped service name | `client-app` |
| seeded admin login + internal domains | removed |

## Files changed

**activeagent** — branch `chore/remove-client-references`, commit `a7d247b9`
(not pushed):

- `actionagent/app/services/action_agent/agent_registrar.rb` — comments
- `actionagent/frontend/components/dashboard/InteractionsView.jsx` — comments
- `docs/framework/self-hosted-observability.md` — example domains

**activeagents** — edited in working tree on `feat/upgrade-activeagent-1.2`
(uncommitted; kept separate from unrelated WIP on that branch):

- `app/services/agent_registrar.rb`, `app/javascript/components/dashboard/InteractionsView.jsx`, `db/migrate/20260731000001_add_observed_agent_registration.rb` — comments
- `docs/features/observability.md`, `docs/integrations/ruby_llm.md` — example domains, consumer attribution
- `docs/features/rubyllm-telemetry-local-validation.md` — rewritten: client domains, tenant, credentials, vendor index name removed
- `docs/features/rubyllm-telemetry-extraction-plan.md`, `docs/features/agent-auto-registration-and-sandbox-builder.md` — genericized throughout
- `docs/issues/pr-96-local-verification.md` — stale-server note genericized

## Not client content (left alone)

"Sparkles" in logo SVGs, `AgentAvatar.jsx`, `agent-builder-svg.html`, and the
`.sparkle` CSS effect in `dill` retro pages are visual sparkle graphics,
unrelated to any client.

`solid_agent` and `ruby-ffmpeg` had no matches. The dashboard engine's
`routes.rb` was already clean at scan time.

## Caveat

Git *history* in both repos still contains the removed names (and the scrubbed
validation doc's earlier revisions). If history itself must be clean before
open-sourcing anything, that needs a separate rewrite (filter-repo) decision.
