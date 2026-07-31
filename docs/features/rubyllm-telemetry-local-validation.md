# RubyLLM Telemetry — Local Cross-Repo Validation (2026-07-30)

Validated the branch pair end-to-end on OrbStack local dev:

- **activeagents** `claude/rubyllm-telemetry-recording-rogzp9` (main + `docs/integrations/ruby_llm.md`), run from the `~/GitHub/activeagents-telemetry` worktree via `docker compose -f docker-compose.dev.yml up` → https://activeagents.orb.local (needs `RAILS_DEVELOPMENT_HOSTS: .orb.local` in the compose env).
- **sparkle** `claude/rubyllm-telemetry-recording-rogzp9` — vendored `lib/active_agents/ruby_llm_telemetry.rb` + `config/initializers/ruby_llm.rb`, opt-in via `ACTIVEAGENTS_API_KEY`, endpoint override via `ACTIVEAGENTS_TELEMETRY_ENDPOINT=http://localhost:3000/v1/traces`.

## Result: PASS

Clara admin chat (Sparkle CMS UI, client `christus`) driven in the browser on
`claude-haiku-4-5-20251001` (Anthropic test key; Ollama ruled out — laptop RAM).
Traces arrived in the dashboard under **Justin.Bowen's Workspace** (account 3,
its own `telemetry_api_key` as Bearer):

| Trace | Spans | Tokens in/out | Duration | Status |
|---|---|---|---|---|
| `Clara.respond` | root + llm.generate + 7 tool spans (meilisearch_query ×4, meilisearch_health, healthcheck, check_async_invocation) | 42,470 / 1,180 | 22.16s | OK |
| `Clara.title` | root + llm.generate | 431 / 10 | 1.30s | OK |

Dashboard renders: timeline, per-agent/action filters (Clara#respond, Clara#title),
waterfall with tool spans, token totals, cost estimate, provider·model chip
(`anthropic · claude-haiku-4-5-20251001`). Bad key → 401; good key → 202.

## Bug the telemetry found: `meilisearch_query` reported page size as the total

Asked "how many physicians are in the database?", Clara answered **1**. The
Sparkle admin UI said **104**, and so did Meilisearch. The captured tool I/O in
the trace showed why in one line:

```
args:   {"model":"Physician","query":"","database":"sandbox","limit":1}
result: {... "hits_count":1, "hits":[...]}     # no total anywhere
```

`app/lib/mcp/diagnostic/tools/meilisearch_query.rb` returned `hits_count:
hits.size` — the size of the returned *page* — and discarded
`estimatedTotalHits` (104) from the Meilisearch response it already held. Any
agent asking "how many" gets back its own `limit` value, confidently. A silent
wrong answer, not an error: ask with `limit: 20` and it reports 20.

Compare `find_record`, which caps at `FUZZY_LIMIT = 5` but emits a `{truncated:
true, fuzzy_limit: 5}` sentinel — Clara read that correctly and said "at least
5+". The contract works when the tool admits it truncated.

**Fix applied** (uncommitted, sparkle): pass through `total_count`
(`estimatedTotalHits`) and `truncated` alongside `hits_count`, mark all three
`required`, and document `hits_count` as page-limited so the schema can't be
misread. After the fix Clara answers **104 in the database, 104 visible in
provider search** — verified in the UI and in the trace
(`hits_count=1 total_count=104 truncated=true`).

Worth noting for the platform pitch: this is exactly the class of bug telemetry
is *for*. The chat transcript alone looks like a reasoning failure; the tool I/O
capture shows it was a tool-contract failure, and points at the line to change.

### Not a bug: the live-index 404

Clara flags `404 - Index development_christus_kyruus_v9_live_physician not
found` every run. Expected locally — the live database
(`sparkle_christus_live_development`, `config/database.yml:21-23`) does not
exist in this dev setup, so `glint_reindex_now` can only write the sandbox
index. Her report is accurate.

### Still open

Imported physicians have **null `first_name`/`last_name` in the index** (the
sample CSV's name columns aren't reaching the indexed document, though `name`
is populated). Provider search by name would be unusable. Unrelated to
telemetry; worth a separate look.

## Full-flow capture (added during validation)

The waterfall showed *that* tools ran, not what they were asked or what came
back — and nothing of the conversation itself. Three changes closed that:

1. **sparkle** `capture_content:` (was `capture_tool_io:`) — opt-in, off by
   default, gated locally by `ACTIVEAGENTS_CAPTURE_CONTENT`. Records
   `llm.prompt`, `llm.instructions`, `llm.completion` on the llm span and
   `tool.arguments` / `tool.result` on each tool span, truncated at 4KB.
2. **activeagents Traces** — clicking a span expands its attributes, JSON
   pretty-printed. This is what located the counting bug.
3. **activeagents Interactions** — `TraceInteractionSerializer` rebuilds a
   conversation stream from spans, so agents executing *outside* the platform
   appear alongside platform runs. Verified: `Clara.respond`, 14 messages
   (prompt → 6 tool call/result pairs → response), 49.8K tokens, labelled
   REPORTED with service `sparkle-christus`.

### Why Interactions was empty (architectural, worth knowing)

Interactions read `AgentContext` / `AgentMessage` / `AgentGeneration` —
solid_agent persistence written only by agents the *platform* executes. An app
running its own agent and reporting traces never writes those tables. Locally:
9 traces, 0 contexts, "No interactions yet". Traces and Interactions were two
views of the same runs that could never both be populated for an external
customer. The serializer bridges that; the split is worth keeping in mind for
anything else keyed off solid_agent tables.

## Sparkle local run recipe

```sh
# services: mise run dev (docker: mysql/redis/meilisearch/… already up)
CLIENT=christus \
SPARKLE_BASE_DOMAIN=christus.local.sparkle.health \
SPARKLE_AI_CHAT_MODEL=claude-haiku-4-5-20251001 \
OPENAI_API_KEY=unused ANTHROPIC_API_KEY=<test key> \
ACTIVEAGENTS_API_KEY=<account telemetry_api_key> \
ACTIVEAGENTS_TELEMETRY_ENDPOINT=http://localhost:3000/v1/traces \
bin/rails server -p 3001 -b 0.0.0.0
# plus: bin/bundle exec vite dev
```

- Admin UI: http://sandbox-doctors.christus.local.sparkle.health:3001/admin
  (`*.local.sparkle.health` is public wildcard DNS → 127.0.0.1; `/admin` redirects
  to the sandbox host). Login `admin@combinaut.com` / `password1`
  (seeded by `rake sparkle_ai:demo:seed`).
- Clara chat: `/admin/ai/chats`.
- One local-only shim (untracked, delete after testing):
  `sparkle/config/initializers/zz_anthropic_dev_key.rb` wires
  `RubyLLM.config.anthropic_api_key` from env — the branch's initializer only wires
  OpenAI, and `Chat#prepare_for_admin_chat` hard-codes `provider :openai`; the UI
  chat resolves provider from the `SparkleAI::Model` registry row instead, which is
  how Claude runs. For production-shape usage on OpenAI none of this is needed.

## Gotchas hit

- `caddy` container crash-loops (missing `/certs/local.sparkle.health.pem`) — avoided
  TLS entirely by running Rails on :3001 plain http.
- Stale Puma from an earlier run held 127.0.0.1:3001 and shadowed the new server
  (bind precedence) — check `lsof -iTCP:3001` when responses look stale.
- The sparkle checkout got switched to `main` mid-session by something outside the
  session (~16:45 PT); switched back (schema.rb stash/pop). Worth confirming what did it.
- Sparkle branch migrations were pending on the shared `sparkle_christus_development`
  DB; ran `db:migrate` (15 migrations).
- Playwright first-loads time out while Vite cold-compiles — warm pages with curl first.
