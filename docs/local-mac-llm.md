# Running ActiveAgents on a Mac with a local LLM (Apple silicon)

How to run the dashboard on an M-series Mac (containers or native) with a
small local model doing real generations and **tool calls** — visible in
Traces, Interactions, and Metrics — or with a small hosted model like
Claude Haiku 4.5.

## The one architectural rule

**Run the model natively; containerize the app.** Containers on macOS run
inside a Linux VM with no Metal/GPU passthrough — an LLM inside Docker or
Apple's `container` CLI falls back to CPU and is several times slower.
Ollama installed natively uses the M1 Pro's GPU via Metal automatically.

```
┌───────────── your Mac ─────────────┐
│  Ollama (native, Metal)  :11434    │
│        ▲ host.docker.internal      │
│  ┌─────┴──────────── VM ────────┐  │
│  │  app container   :3000       │  │
│  │  postgres container          │  │
│  └──────────────────────────────┘  │
└────────────────────────────────────┘
```

## 1. Install and start the model host

```sh
brew install ollama
ollama serve &
```

### Which small model? (tool calling is the constraint)

| Model | Pull command | RAM needed | Tool calls | Notes |
|---|---|---|---|---|
| **Qwen 3 8B** (recommended) | `ollama pull qwen3:8b` | ~6 GB | ✅ good | The model the activeagent gem's own Ollama tool-calling integration tests use (`qwen3:latest`). Best starting point. |
| Qwen 3 4B | `ollama pull qwen3:4b` | ~3 GB | ✅ | Faster, still tool-capable — good on 16 GB Macs with lots else running. |
| Llama 3.1 8B | `ollama pull llama3.1:8b` | ~5 GB | ✅ | Solid alternative. |
| gpt-oss 20B | `ollama pull gpt-oss:20b` | ~14 GB | ✅ strong | OpenAI's open-weight model (there's no 12B — the small one is 20B). Great on a 32 GB M1 Pro; tight on 16 GB. |
| Gemma 3 | — | — | ❌ | Ollama's gemma3 template has no tool-role support — tool calls error out. Skip it for this use case. |

### Or a small hosted model: Claude Haiku 4.5

There's no "Haiku 5" — the current small Claude is **Claude Haiku 4.5**
(`claude-haiku-4-5`), $1/$5 per million tokens, full tool-use support. No
local RAM cost, and it's noticeably better at tool calling than any ~8B
local model. Use it by putting your Anthropic API key in **Settings →
Provider API Keys → Anthropic** and setting the agent's provider to
`anthropic` with model `claude-haiku-4-5`.

## 2. Run the app

### Option A — containers via Docker Desktop or OrbStack (easiest)

```sh
docker compose -f docker-compose.dev.yml up
```

That starts Postgres and the app (deps install on first boot; give it a
few minutes). The compose file already points the platform's default
Ollama endpoint at your native Ollama via `host.docker.internal`.

### Option B — Apple's `container` CLI (macOS 26+)

Apple's [container](https://github.com/apple/container) tool runs each
Linux container in its own lightweight VM. There's no compose, so wire the
two containers by IP:

```sh
brew install container && container system start

container run -d --name aa-db \
  -e POSTGRES_USER=activeagents -e POSTGRES_PASSWORD=activeagents \
  postgres:16

container build -t activeagents-dev -f Dockerfile.dev .
DB_IP=$(container inspect aa-db | grep -o '"address":"[0-9.]*' | head -1 | cut -d'"' -f4)
container run -d --name aa-web -p 3000:3000 \
  -e DATABASE_URL="postgres://activeagents:activeagents@${DB_IP}/activeagents_temp_development" \
  -e OLLAMA_HOST="http://192.168.64.1:11434/v1" \
  -v "$(pwd):/app" activeagents-dev
```

`192.168.64.1` is the default vmnet gateway (the host as seen from the
container) — check `container network ls` if yours differs. Also start
Ollama bound to all interfaces so the VM can reach it:
`OLLAMA_HOST=0.0.0.0 ollama serve`.

### Option C — fully native (no containers, fastest feedback)

```sh
brew install postgresql@16 && brew services start postgresql@16
mise install   # or: ruby 3.4.8 via your version manager, plus node
bundle install && npm install
bin/rails db:prepare
npm run build && npm run build:css
bin/rails server
```

Native Ollama is just `http://localhost:11434/v1` — no host-gateway games.

## 3. Wire the model in and test tool calls

1. Open http://localhost:3000, register, then **Settings → Provider API
   Keys**. Configure **Ollama** with the host URL for your setup
   (`http://host.docker.internal:11434/v1` in compose,
   `http://localhost:11434/v1` native). For Haiku 4.5, configure
   **Anthropic** with your API key instead. Credentials are encrypted at
   rest (Active Record Encryption).
2. Create an agent: provider `ollama`, model `qwen3:8b` (or provider
   `anthropic`, model `claude-haiku-4-5`), and enable the **fetch**,
   **search**, **code**, and **memory** tools.
3. Run it with a prompt that forces tools, e.g.:
   > Fetch https://example.com, calculate (2+3)*4.5, and save a memory
   > note about what you found.
4. Watch the results:
   - **Traces** — the run's trace with `tool.fetch_url` / `tool.calculate`
     spans under the root span.
   - **Interactions** — the full message stream, including tool results
     (repeat the same fetch and the second result comes back tagged
     `"cached": true` from the tool cache).
   - **Metrics** — tokens/latency aggregates; **Agents** — the scorecard.
5. Optional, MCP: create a platform API key (**Settings → API Keys**) and
   point any MCP client at `http://localhost:3000/mcp` with
   `Authorization: Bearer aa_…` — your agents appear as callable tools and
   `agent://<slug>` resources.

## Gotchas

- **SSRF guard vs. the provider connection:** the `fetch_url` *tool*
  refuses private/loopback URLs by design. That guard does **not** apply
  to the Ollama provider connection — private host URLs are fine there.
- **First generation is slow:** Ollama loads the model into GPU memory on
  first use (tens of seconds for 8B). Subsequent calls are fast. Keep it
  warm with `ollama run qwen3:8b ""` after pulling.
- **16 GB M1 Pro:** run one 8B model at a time and prefer `qwen3:4b` if
  you're also running browsers/IDEs. `gpt-oss:20b` wants ~14 GB free.
- **Tool-call quality:** small local models sometimes emit malformed tool
  calls; the toolbox returns `{ error: ... }` results so runs degrade
  gracefully instead of crashing. Haiku 4.5 is the reliable option when
  you want consistent tool behavior.
