# ActiveAgents

The platform behind [activeagents.ai](https://activeagents.ai). It mounts the
Active Agent dashboard, the `actionagent` engine, in multi-tenant mode and adds
what a hosted product needs: accounts and workspaces, plans and billing, trace
and evaluation ingest keyed per account, and cloud sandboxes.

## Three ways to run the dashboard

| | How | Suits |
| --- | --- | --- |
| **Hosted** | Sign up at [activeagents.ai](https://activeagents.ai) and point telemetry at your API key | Teams that want traces, metrics and evaluations without running anything |
| **Standalone container** | Run a tagged release of this app with Docker Compose, below | Teams that want the whole platform inside their own environment |
| **Engine in your app** | `bundle add actionagent` and mount it ([guide](https://docs.activeagents.ai/framework/self-hosted-observability)) | Developers who want the dashboard side-loaded into their own Rails app |

All three are the same engine and speak the same wire format, so an app moves
between them by changing its telemetry endpoint.

## Run a tagged release

Every release of this repository is a container image,
`ghcr.io/activeagents/activeagents`, for linux/amd64 and linux/arm64. Its tag
names the agent gems inside:

| Tag | What it runs |
| --- | --- |
| `1.8.1` | activeagent and actionagent 1.8.1 |
| `1.8.1.1` | a platform-only release on those same gems |
| `1.8` | the newest release on the 1.8 gems |
| `latest` | the newest release |

Pin a full version anywhere it matters. Each
[GitHub release](https://github.com/activeagents/activeagents/releases)
carries a `compose.yml` that runs that version with its own Postgres:

```sh
curl -fsSLO https://github.com/activeagents/activeagents/releases/latest/download/compose.yml
echo "SECRET_KEY_BASE=$(openssl rand -hex 64)"   >> .env
echo "POSTGRES_PASSWORD=$(openssl rand -hex 24)" >> .env
docker compose up -d

# Your login, its workspace and an API key, on the unmetered plan. Prints the key.
docker compose exec web bin/rails platform:bootstrap_account \
  EMAIL=you@example.com PASSWORD=change-me PLAN=enterprise CONFIRM=yes
```

Then open http://localhost:3000/dashboard and sign in. The first boot creates
the four databases (primary, cache, queue, cable) and seeds the plans.

### Configuration

Everything goes in the `.env` file beside `compose.yml`.

| Variable | Default | Purpose |
| --- | --- | --- |
| `SECRET_KEY_BASE` | required | Signs sessions and encrypts stored provider keys and tokens. Back it up: a new one makes those unreadable. |
| `POSTGRES_PASSWORD` | required | The bundled Postgres. |
| `ACTIVEAGENTS_VERSION` | the release's version | Which image tag to run. |
| `PORT` | `3000` | The host port. |
| `RAILS_ASSUME_SSL`, `RAILS_FORCE_SSL` | `false` | Set both to `true` behind a proxy that terminates TLS. |
| `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `OPENROUTER_API_KEY`, `OLLAMA_HOST` | unset | Platform-wide provider credentials for running agents. Each workspace can also set its own under Settings. |
| `RESEND_API_KEY`, `MAILER_FROM_ADDRESS` | unset | Email through Resend. Without a key, anything that sends mail fails, which is why the bootstrap task creates a verified login. |

### Sending traces and evaluation reports

Point each application's telemetry at the container, with the key the
bootstrap task printed:

```yaml
# config/active_agent.yml
production:
  telemetry:
    enabled: true
    endpoint: https://agents.example.com/v1/traces
    api_key: <%= ENV["ACTIVEAGENTS_API_KEY"] %>
```

Evaluation reports go to `/v1/evaluations` with the same key. Off
localhost, serve the container over TLS: `ActiveAgent::Evals::Publisher`
refuses plain HTTP anywhere but loopback.

### Upgrading

Set `ACTIVEAGENTS_VERSION` to the new release, then:

```sh
docker compose pull && docker compose up -d
```

The container migrates its databases as it boots. Read the release notes
first: they link the gem release whose changes it carries.

### What a container leaves out

Billing, the plans page and checkout need Stripe keys and do nothing without
them. Cloud sandboxes need the Google Cloud or Incus backends this
deployment configures for activeagents.ai. The root URL serves the
activeagents.ai landing page, and the dashboard lives at `/dashboard`.

## Development

```sh
bin/setup      # gems, JavaScript packages and the development database
bin/dev        # the app on http://localhost:3000
bin/rails test
```

`docker-compose.dev.yml` runs the app and Postgres in containers with a
model served from the host; see `docs/local-mac-llm.md`.

## Releasing

Releases follow the agent gems: when activeagent publishes, a pull request
here moves the pins, and the tag that follows it publishes the image, the
GitHub release and the production deploy. See
[docs/releasing.md](docs/releasing.md).
