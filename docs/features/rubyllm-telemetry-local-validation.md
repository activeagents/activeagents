# RubyLLM Telemetry — Local Cross-Repo Validation (2026-07-30)

Validated the branch pair end-to-end on OrbStack local dev:

- **activeagents** `claude/rubyllm-telemetry-recording-rogzp9` (main + `docs/integrations/ruby_llm.md`), run from the `~/GitHub/activeagents-telemetry` worktree via `docker compose -f docker-compose.dev.yml up` → https://activeagents.orb.local (needs `RAILS_DEVELOPMENT_HOSTS: .orb.local` in the compose env).
- **client app** (external Rails CMS, same branch name) — vendored `lib/active_agents/ruby_llm_telemetry.rb` + `config/initializers/ruby_llm.rb`, opt-in via `ACTIVEAGENTS_API_KEY`, endpoint override via `ACTIVEAGENTS_TELEMETRY_ENDPOINT=http://localhost:3000/v1/traces`.

## Result: PASS

The client app's admin-chat agent (referred to here as `Assistant`) driven in
the browser on `claude-haiku-4-5-20251001` (Anthropic test key; Ollama ruled
out — laptop RAM). Traces arrived in the dashboard under **Justin.Bowen's
Workspace** (account 3, its own `telemetry_api_key` as Bearer):

| Trace | Spans | Tokens in/out | Duration | Status |
|---|---|---|---|---|
| `Assistant.respond` | root + llm.generate + 7 tool spans (meilisearch_query ×4, meilisearch_health, healthcheck, check_async_invocation) | 42,470 / 1,180 | 22.16s | OK |
| `Assistant.title` | root + llm.generate | 431 / 10 | 1.30s | OK |

Dashboard renders: timeline, per-agent/action filters (Assistant#respond,
Assistant#title), waterfall with tool spans, token totals, cost estimate,
provider·model chip (`anthropic · claude-haiku-4-5-20251001`). Bad key → 401;
good key → 202.

## Bug the telemetry found: `meilisearch_query` reported page size as the total

Asked "how many physicians are in the database?", the agent answered **1**. The
client app's admin UI said **104**, and so did Meilisearch. The captured tool
I/O in the trace showed why in one line:

```
args:   {"model":"Physician","query":"","database":"sandbox","limit":1}
result: {... "hits_count":1, "hits":[...]}     # no total anywhere
```

The client app's Meilisearch query tool returned `hits_count: hits.size` — the
size of the returned *page* — and discarded `estimatedTotalHits` (104) from the
Meilisearch response it already held. Any agent asking "how many" gets back its
own `limit` value, confidently. A silent wrong answer, not an error: ask with
`limit: 20` and it reports 20.

Compare its `find_record` tool, which caps at `FUZZY_LIMIT = 5` but emits a
`{truncated: true, fuzzy_limit: 5}` sentinel — the agent read that correctly
and said "at least 5+". The contract works when the tool admits it truncated.

**Fix applied** (uncommitted, client app): pass through `total_count`
(`estimatedTotalHits`) and `truncated` alongside `hits_count`, mark all three
`required`, and document `hits_count` as page-limited so the schema can't be
misread. After the fix the agent answers **104 in the database, 104 visible in
provider search** — verified in the UI and in the trace
(`hits_count=1 total_count=104 truncated=true`).

Worth noting for the platform pitch: this is exactly the class of bug telemetry
is *for*. The chat transcript alone looks like a reasoning failure; the tool I/O
capture shows it was a tool-contract failure, and points at the line to change.

### Not a bug: the live-index 404

The agent flags a `404 - Index … not found` for the live-database search index
every run. Expected locally — the live database does not exist in this dev
setup, so reindexing can only write the sandbox index. The report is accurate.

### Still open

Imported physicians have **null `first_name`/`last_name` in the index** (the
sample CSV's name columns aren't reaching the indexed document, though `name`
is populated). Provider search by name would be unusable. Unrelated to
telemetry; worth a separate look (client-app issue).

## Full-flow capture (added during validation)

The waterfall showed *that* tools ran, not what they were asked or what came
back — and nothing of the conversation itself. Three changes closed that:

1. **client app** `capture_content:` (was `capture_tool_io:`) — opt-in, off by
   default, gated locally by `ACTIVEAGENTS_CAPTURE_CONTENT`. Records
   `llm.prompt`, `llm.instructions`, `llm.completion` on the llm span and
   `tool.arguments` / `tool.result` on each tool span, truncated at 4KB.
2. **activeagents Traces** — clicking a span expands its attributes, JSON
   pretty-printed. This is what located the counting bug.
3. **activeagents Interactions** — `TraceInteractionSerializer` rebuilds a
   conversation stream from spans, so agents executing *outside* the platform
   appear alongside platform runs. Verified: `Assistant.respond`, 14 messages
   (prompt → 6 tool call/result pairs → response), 49.8K tokens, labelled
   REPORTED with the client app's service name.

### Why Interactions was empty (architectural, worth knowing)

Interactions read `AgentContext` / `AgentMessage` / `AgentGeneration` —
solid_agent persistence written only by agents the *platform* executes. An app
running its own agent and reporting traces never writes those tables. Locally:
9 traces, 0 contexts, "No interactions yet". Traces and Interactions were two
views of the same runs that could never both be populated for an external
customer. The serializer bridges that; the split is worth keeping in mind for
anything else keyed off solid_agent tables.

## Client-app local run recipe

Run the client Rails app with its usual local env (tenant, base domain, model
selection) plus the telemetry env:

```sh
# services: mise run dev (docker: mysql/redis/meilisearch/… already up)
OPENAI_API_KEY=unused ANTHROPIC_API_KEY=<test key> \
ACTIVEAGENTS_API_KEY=<account telemetry_api_key> \
ACTIVEAGENTS_TELEMETRY_ENDPOINT=http://localhost:3000/v1/traces \
bin/rails server -p 3001 -b 0.0.0.0
# plus: bin/bundle exec vite dev
```

- Admin UI: the app's admin path on :3001, seeded demo admin login.
- Agent chat: `/admin/ai/chats`.
- One local-only shim (untracked, delete after testing): an initializer wiring
  `RubyLLM.config.anthropic_api_key` from env — the branch's initializer only
  wires OpenAI, and the admin chat hard-codes `provider :openai`; the UI chat
  resolves provider from the app's model registry row instead, which is how
  Claude runs. For production-shape usage on OpenAI none of this is needed.

## Gotchas hit

- The app's `caddy` container crash-loops on a missing local TLS cert — avoided
  TLS entirely by running Rails on :3001 plain http.
- Stale Puma from an earlier run held 127.0.0.1:3001 and shadowed the new server
  (bind precedence) — check `lsof -iTCP:3001` when responses look stale.
- The client-app checkout got switched to `main` mid-session by something outside
  the session (~16:45 PT); switched back (schema.rb stash/pop). Worth confirming what did it.
- Client-app branch migrations were pending on the shared development DB; ran
  `db:migrate` (15 migrations).
- Playwright first-loads time out while Vite cold-compiles — warm pages with curl first.
