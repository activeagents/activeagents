# PR #96 — Local verification (analytics API key encryption)

**Branch:** `claude/analytics-api-key-encryption-9kwpsc`
**Date:** 2026-07-29
**Setup:** OrbStack (Docker compose: Postgres + Rails) + native Ollama with `qwen3:8b`

## What was verified end to end

1. **Signup → email verification → onboarding** — verification link pulled from
   dev logs; free plan onboarding completes to the dashboard.
2. **Platform API keys (encrypted, show-once)** — created key `local-dev`.
   - Token shown exactly once in the UI; list view shows only `aa_RLBA…D4P8`.
   - DB stores ActiveRecord Encryption ciphertext in `api_keys.token`
     (`{"p": …, "h": {"iv", "at"}}`) with only `token_prefix` in clear.
   - `POST /mcp` with the bearer token → `200` JSON-RPC response; a bogus
     token → `401`.
3. **Provider keys (per-account, encrypted)** — configured Ollama host
   `http://host.docker.internal:11434/v1` in Settings → API Keys.
   - `provider_keys.credential` is ciphertext at rest; UI decrypts for display.
4. **Agent run against local LLM** — created "Local Qwen Assistant"
   (ollama / qwen3:8b, Memory tool enabled) and ran a prompt.
   - Run completed in 30.4s (cold model load) with a correct answer.
   - `agent_runs` recorded duration + 359 input / 406 output tokens;
     2 rows landed in `active_agent_telemetry_traces`.
   - Scorecard stats (Runs 30d / Success / Avg time / Eval) render on the
     agent card.

5. **Tool calling (AgentToolbox)** — prompted the agent to compute
   `(1234 * 5678) - 99` and store the result.
   - qwen chained `calculate` → `save_memory` in one run (40.8s); answer
     7006553 is correct.
   - `agent_memory_entries` row created (category `fact`), bound to the
     Agent record via `agent_memories` (shared across runs).
   - Tool round-trips persisted as `tool` messages in `agent_messages`
     (Interactions), and two `type: "tool"` spans landed on the trace.
6. **MCP end to end** — the agent appears in `tools/list` as
   `run_local-qwen-assistant`; `tools/call` over curl (Bearer API key)
   executed real runs and a `recall_memory` prompt returned the number
   stored by the earlier UI run: cross-run memory over MCP works.
   `resources/read agent://local-qwen-assistant` returns the live
   scorecard JSON (stats + memory summary).

Screenshots: `tmp/playwright/01–07*.png` (gitignored).

## Bug found and fixed in this checkout

**Ollama/OpenAI provider crashes: missing `openai` gem.**
First agent run failed in 321ms with
`Failed to load provider ollama: The 'openai' gem is required for OllamaProvider`.
The activeagent gem's `GEM_LOADERS` requires `openai ~> 0.34` for the
Ollama/OpenAI providers, but the app Gemfile only had `anthropic`. The e2e
specs mock the provider, so CI never hits this.

*Fix applied:* added `gem "openai", "~> 0.34"` to the Gemfile (resolved to
0.73.0). **This should be committed into PR #96.**

## Local-dev changes made (also candidates for the PR)

- `docker-compose.dev.yml`: added OrbStack labels
  (`dev.orbstack.domains: activeagents.orb.local`, `dev.orbstack.http-port: 3000`)
  so the app is served at **https://activeagents.orb.local** via OrbStack's
  built-in HTTPS routing — no Caddy needed, no localhost port collisions.
  Labels are a no-op on other Docker engines.
- `config/environments/development.rb`: allowed host `activeagents.orb.local`.

## Open issues (not fixed)

1. **Ollama model dropdown is hardcoded** (llama3 / mistral / codellama /
   mixtral) in the New Agent wizard and edit page. It doesn't list locally
   pulled models (e.g. `qwen3:8b`) and `llama3` isn't even a valid local tag
   here. Workaround used: set `agents.model` directly in the DB. Suggest
   querying the configured Ollama host's `/v1/models`, or a free-text model
   field.
2. **Transient blank page after onboarding redirect** — one-off Inertia error
   (`Cannot read properties of null (reading 'component')`) on the
   complete-profile → dashboard transition; a reload fixed it and it did not
   reproduce.
3. **`yarn.lock` churn from the container** — the dev container's JS install
   rewrites the bind-mounted `yarn.lock` (+27/−17 lines) on first boot.
   Review before committing.
4. **Tool names missing from telemetry** — tool spans record
   `tool.name: "unknown"` (and MCP responses report `tool_calls: ["unknown"]`).
   The span is created before the tool call's name is resolved from the
   provider payload. Metrics' per-tool counts will be useless until fixed.
5. **Tool metadata missing from Interactions** — `agent_messages` rows for
   tool results leave `tool_name`/`tool_arguments` empty; only the JSON
   result string is stored. Made it hard to debug the recall issue below.
6. **Small-model prompt sensitivity (not a bug)** — qwen3:8b called
   `recall_memory` with an invented `category: "calculation"` filter and got
   0 rows, then claimed no memory existed. Worth defaulting recall to
   unfiltered in the tool description, or having the executor retry without
   the filter when a category yields nothing.

## Environment notes

- A stale Puma server from another local app (running since 7/13) was occupying
  port 3000 and answering with an https redirect; it was killed. Restart it with
  `bin/dev` in that app's checkout if needed.
- Pre-checkout WIP from `feature/agent-builder-hero` is stashed:
  `WIP on feature/agent-builder-hero before PR-96 checkout`.
