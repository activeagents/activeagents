# Agent Builder Dashboard Implementation

> **See also:** [features/observability.md](features/observability.md) for the
> observability stack (traces, metrics, interactions, evaluations, telemetry
> ingest) — the platform mounts the `actionagent` dashboard engine in
> multi-tenant mode and persists conversations via solid_agent.

## Overview

The Agent Builder Dashboard provides a visual interface for creating, configuring, and testing AI agents built with ActiveAgent.

It ships as its own gem, **`actionagent`**, whose entry point is
`ActionAgent::Engine`. That gem lives beside the `activeagent` framework gem in
the [activeagents/activeagent](https://github.com/activeagents/activeagent)
repo, under the `actionagent/` directory — one repo, two published gems. It
depends on `activeagent`, railties, activerecord and solid_agent; the last two
are the ones the framework gem deliberately does without, which is the whole
reason for the split.

This app mounts the engine (`mount ActionAgent::Engine => "/dashboard",
as: :dashboard` in `config/routes.rb`) and configures it in
`config/initializers/action_agent.rb`; the models, services, jobs,
controllers and React app below live in the engine.

Path conventions in this document: anything starting `actionagent/` is
relative to a checkout of the gem repo, **not** this one. In the sections that
describe the engine, bare `app/…` and `frontend/…` paths are relative to that
same `actionagent/` directory. Everything else — `config/`, `db/migrate/`,
`app/javascript/` — is this repo's.

## Setup

### Prerequisites

- Ruby 3.2+ (Note: Ruby 3.3+ has compatibility issues with Rails 8.1.2)
- PostgreSQL
- Node.js 18+

### Installation

Both gems come from the same repo, so the `Gemfile` names them twice — the
dashboard entry needs the `glob:` because its gemspec is not at the repo root:

```ruby
gem "activeagent", github: "activeagents/activeagent"
gem "actionagent", github: "activeagents/activeagent",
                   glob: "actionagent/*.gemspec"
```

```bash
# Install dependencies
bundle install
npm install

# Setup database
bin/rails db:create
bin/rails db:migrate

# Start the server
bin/dev
```

`npm install` / `bin/dev` build this app's own assets (landing page, Inertia
pages). The dashboard bundle is not built here — it ships prebuilt in the
`actionagent` gem at `actionagent/app/assets/builds/action_agent.{js,css}`,
which the engine adds to the host app's asset paths.

### Access

Navigate to `http://localhost:3000/dashboard` — the engine's mount point — to
access the Agent Builder.

## Architecture

### Database Models

The models live in the engine under `actionagent/app/models/action_agent/`,
namespaced `ActionAgent::`. Their counterparts under this app's `app/models/`
are one-line aliases (`Agent = ActionAgent::Agent`), so bare constant names
keep resolving in platform code; the models this app owns (`Account`,
`AccountMembership`, `User`, `Plan`, `Session`, `Current`, `TelemetryTrace`)
are still real files here. The tables stay in this app's database and stay
unprefixed — the initializer sets `config.table_name_prefix = ""`, where a
fresh self-hosted install would get `active_agent_*`.

#### Agent (`ActionAgent::Agent`)
The core model representing an AI agent configuration.

| Field | Type | Description |
|-------|------|-------------|
| name | string | Agent display name |
| slug | string | URL-safe identifier |
| description | text | Agent description |
| provider | string | LLM provider (openai, anthropic, ollama, openrouter) |
| model | string | Model identifier |
| instructions | text | System prompt/instructions |
| preset_type | string | Avatar preset type |
| appearance | jsonb | Avatar customization |
| instruction_sets | jsonb | Selected instruction categories |
| tools | jsonb | Enabled tools/MCPs |
| model_config | jsonb | Temperature, max_tokens, etc. |
| status | integer | draft (0), active (1), archived (2), observed (3) |

`observed` agents were discovered from reported telemetry rather than authored
here, so they are read-only until forked.

#### AgentVersion (`ActionAgent::AgentVersion`)
Tracks configuration changes for versioning and rollback.

| Field | Type | Description |
|-------|------|-------------|
| agent_id | reference | Parent agent |
| version_number | integer | Sequential version |
| change_summary | string | Description of changes |
| configuration_snapshot | jsonb | Full config at this version |

#### AgentRun (`ActionAgent::AgentRun`)
Records each agent execution for debugging and analytics.

| Field | Type | Description |
|-------|------|-------------|
| agent_id | reference | Parent agent |
| input_prompt | text | User input |
| output | text | Agent response |
| status | integer | pending/running/complete/failed/cancelled |
| duration_ms | integer | Execution time |
| input_tokens | integer | Tokens consumed |
| output_tokens | integer | Tokens generated |
| error_message | text | Error details if failed |
| trace_id | string | Unique execution trace |

### API Endpoints

The dashboard's JSON API is defined by the engine
(`actionagent/config/routes.rb`) and served under the mount, so
every path below sits at `/dashboard/api/...` on this platform. A self-hosted
install mounting the engine elsewhere gets the same paths under its own mount.

#### Agents

| Method | Path | Description |
|--------|------|-------------|
| GET | /dashboard/api/agents | List all agents |
| POST | /dashboard/api/agents | Create new agent |
| GET | /dashboard/api/agents/:id | Get agent details |
| PATCH | /dashboard/api/agents/:id | Update agent |
| DELETE | /dashboard/api/agents/:id | Delete agent |
| GET | /dashboard/api/agents/:id/versions | Get version history |
| POST | /dashboard/api/agents/:id/restore | Restore a version |
| GET | /dashboard/api/agents/:id/runs | Get execution history |
| POST | /dashboard/api/agents/:id/execute | Queue async execution |
| POST | /dashboard/api/agents/:id/test | Sync test execution |
| POST | /dashboard/api/agents/:id/duplicate | Clone agent |
| GET | /dashboard/api/agents/:id/export | Export agent config/code |
| GET | /dashboard/api/agents/:id/analytics | Per-agent analytics |
| GET | /dashboard/api/agents/presets | Get available presets |

#### Runs

| Method | Path | Description |
|--------|------|-------------|
| GET | /dashboard/api/runs | List all runs |
| GET | /dashboard/api/runs/:id | Get run details |
| POST | /dashboard/api/runs/:id/cancel | Cancel running execution |

#### Observability

| Method | Path | Description |
|--------|------|-------------|
| GET | /dashboard/api/traces | Telemetry traces (account-scoped) |
| GET | /dashboard/api/metrics | 24h metrics, per-agent stats, cost estimates |
| GET | /dashboard/api/interactions | Conversation streams (solid_agent) |
| GET/POST | /dashboard/api/evaluations | Evaluations + runs |
| POST | /v1/traces | Telemetry ingest (Bearer telemetry_api_key) |

`POST /v1/traces` stays at the root, routed by this app to
`Api::V1::TracesController` (a subclass of the engine's ingest controller), so
SDKs already configured against it keep working. `POST /mcp` is kept at the
root for the same reason, pointed at the engine's MCP controller — which the
engine also serves under its own mount. The remaining root-level API routes
this app owns are `/api/usage`, `/api/benchmarks`, `/api/v1/*` and
`/api/sandbox/*`.

### React Components

The React sources live at `actionagent/frontend/` in the gem repo. They are
not packaged in the gem itself — only the bundle they build into
(`app/assets/builds/`) ships, so a host app never runs a JavaScript build. The
dashboard no longer runs on Inertia: the engine's `DashboardController` renders
one page and hands initial state over as a JSON `data-props` attribute, which
`frontend/index.jsx` reads before mounting.

#### Dashboard (`actionagent/frontend/pages/Dashboard.jsx`)
Main application component with routing and state management.

**Props:**
- `user` - Current user info
- `account` - Current account, including its telemetry API key
- `initialAgents` - Pre-loaded agent list
- `meta` - Configuration metadata (providers, tools, etc.)
- `subscription` - Billing state for the Organization view; the engine passes
  `null`, since billing belongs to the host app

The same payload also carries `mountPath`, which `index.jsx` publishes on
`window.ACTIVE_AGENT_DASHBOARD` so `utils/dashboardPath.js` and the `fetch`
shim resolve client-side routes and `/api/...` calls against the mount rather
than assuming `/dashboard`.

#### Sidebar (`frontend/components/dashboard/Sidebar.jsx`)
Navigation sidebar with agent count and resource links.

#### Header (`frontend/components/dashboard/Header.jsx`)
Context-aware header showing current view and agent info.

#### AgentList (`frontend/components/dashboard/AgentList.jsx`)
Grid view of all agents with search and filtering.

**Features:**
- Search by name/description
- Filter by provider and status; rank by recency, runs, avg duration, cost
  or tokens (server-side, over the scorecards)
- Scorecard tiles per card: runs, success rate, avg time, eval, tokens, cost
  (no mascot — removed so the metrics carry the space)
- Quick actions (duplicate, delete)

#### AgentBuilder (`frontend/components/dashboard/AgentBuilder.jsx`)
Step-by-step wizard for creating new agents.

**Steps:**
1. **Basics** - Name, description, provider, model, temperature
2. **Appearance** - Avatar preset and customization
3. **Capabilities** - Instructions, tools, MCPs
4. **Review** - Final configuration preview

#### AgentEditor (`frontend/components/dashboard/AgentEditor.jsx`)
Full editor for existing agents with tabbed interface.

**Tabs:**
- **Configuration** - Basic settings
- **Instructions** - System prompt editor
- **Tools** - Tool selection grid
- **Versions** - Version history with restore
- **Code** - Generated Ruby code preview

#### AgentRunner (`frontend/components/dashboard/AgentRunner.jsx`)
Interactive testing interface for agents.

**Features:**
- Prompt input with keyboard shortcuts
- Real-time output display
- Token usage tracking
- Execution history
- Example prompts

### Background Jobs

#### AgentExecutionJob (`ActionAgent::AgentExecutionJob`)
Async agent execution via SolidQueue.

**Features:**
- Executes through AgentExecutionService: real provider generation when
  credentials are configured — the account's own provider key first (resolved
  through `config.provider_credentials_resolver`), else the platform keys in
  config/active_agent.yml; without either the run fails with
  `ProviderNotConfiguredError` rather than falling back to the framework's
  mock provider, which is accepted in the test environment only
- Records a telemetry trace and persists the conversation (solid_agent)
  per run, correlated on trace_id
- Error handling and logging
- ActionCable broadcast for real-time updates

## Usage

### Creating an Agent

1. Click "New Agent" in the sidebar
2. Follow the wizard steps:
   - Enter name and select provider/model
   - Choose avatar preset and customize
   - Configure instructions and tools
   - Review and create

### Testing an Agent

1. Open an agent from the list
2. Click "Run Agent"
3. Enter a prompt
4. Press Cmd+Enter or click Run
5. View output and token usage

### Version Management

1. Open an agent
2. Click "Versions" tab
3. View version history
4. Click "Restore" on any previous version

### Exporting Configuration

1. Open an agent
2. Click "Code" tab
3. Copy the generated Ruby code
4. Or use `/dashboard/api/agents/:id/export` for full config

## Integration with ActiveAgent

The dashboard generates agents that work with the ActiveAgent gem:

```ruby
class MyAgent < ApplicationAgent
  generate_with :openai, model: "gpt-4o-mini", temperature: 0.7

  def perform
    prompt instructions: <<~INSTRUCTIONS
      You are a helpful AI assistant...
    INSTRUCTIONS
  end
end
```

Agents can also be dynamically instantiated:

```ruby
# Load agent config from database
agent_record = Agent.find_by(slug: "my-agent")

# Execute with ActiveAgent
response = DynamicAgent
  .with(config: agent_record.configuration_snapshot)
  .perform
  .generate_now
```

## Customization

These all live in the `actionagent` gem now, so changing them means changing
the engine and releasing it — not this app.

### Adding New Providers

1. Add the model list to `Api::ProviderModelsController` (the source of truth
   the builder fetches) and to `FALLBACK_PROVIDER_MODELS` in
   `frontend/utils/providerModels.js`, which only covers a failed fetch
2. Add provider constant to `Agent::PROVIDERS`
3. Configure credentials in `config/active_agent.yml` here, or per-account via
   Settings → Provider API Keys

### Adding New Tools

1. Add to `Agent::AVAILABLE_TOOLS`
2. Add icon mapping in `AgentEditor.jsx`'s `getToolIcon()`
3. Give it a server-side implementation in `AgentToolbox` (`DEFINITIONS` +
   `FUNCTIONS`), or it is ignored during platform execution

### Adding New Presets

1. Add to `AGENT_PRESETS` in `frontend/components/AgentAvatar.jsx`
2. Add to `Agent::PRESET_TYPES`
3. Configure appearance defaults in `Api::AgentsController#presets`

## File Structure

The implementation, in the gem repo (github.com/activeagents/activeagent).
`lib/` there is the `activeagent` framework gem; `actionagent/` is the
dashboard gem, with its own gemspec:

```
activeagent/                       # the repo
├── lib/                           # the activeagent gem — framework only
└── actionagent/                   # the actionagent gem
    ├── actionagent.gemspec
    ├── lib/
    │   ├── action_agent.rb            # the configuration seams
    │   ├── action_agent/engine.rb
    │   ├── action_agent/compatibility.rb  # old ActiveAgent::Dashboard names
    │   ├── actionagent.rb             # gem-name require shim
    │   └── generators/action_agent/install_generator.rb
    ├── config/
    │   └── routes.rb              # the engine's own /api routes + catch-all
    ├── app/
    │   ├── controllers/action_agent/
    │   │   ├── dashboard_controller.rb   # renders the React app
    │   │   ├── traces_controller.rb      # server-rendered <mount>/console/traces
    │   │   └── api/
    │   │       ├── base_controller.rb
    │   │       ├── agents_controller.rb
    │   │       ├── agent_runs_controller.rb
    │   │       └── ...                   # traces, metrics, interactions,
    │   │                                 # evaluations, sandboxes, mcp, ...
    │   ├── jobs/action_agent/
    │   │   └── agent_execution_job.rb
    │   ├── models/action_agent/
    │   │   ├── agent.rb
    │   │   ├── agent_version.rb
    │   │   └── agent_run.rb
    │   ├── services/action_agent/
    │   │   ├── agent_execution_service.rb
    │   │   ├── agent_toolbox.rb
    │   │   └── ...
    │   └── assets/builds/
    │       └── action_agent.{js,css}     # prebuilt, shipped in the gem
    └── frontend/                         # React sources, NOT shipped in the gem
        ├── index.jsx                     # mounts from the data-props payload
        ├── pages/
        │   └── Dashboard.jsx
        └── components/
            ├── AgentAvatar.jsx
            └── dashboard/
                ├── index.js
                ├── Sidebar.jsx
                ├── Header.jsx
                ├── AgentList.jsx
                ├── AgentBuilder.jsx
                ├── AgentEditor.jsx
                └── AgentRunner.jsx
```

What stays here, on the platform (this repo):

```
activeagents/
├── app/
│   └── models/
│       ├── agent.rb               # Agent = ActionAgent::Agent
│       ├── agent_version.rb       # (alias)
│       └── agent_run.rb           # (alias)
├── db/
│   └── migrate/
│       ├── 20260216000001_create_agents.rb
│       ├── 20260216000002_create_agent_versions.rb
│       ├── 20260216000003_create_agent_runs.rb
│       └── 20260812200000_add_owner_columns_for_dashboard_engine.rb
├── Gemfile                        # requires both gems; actionagent uses
│                                  # glob: "actionagent/*.gemspec"
└── config/
    ├── routes.rb                  # mounts the engine at /dashboard
    └── initializers/
        └── action_agent.rb        # tenancy, quotas, credentials, sandboxes
```

The same one-line aliasing covers the moved services, jobs, queries and
serializers (`app/services/agent_execution_service.rb`,
`app/jobs/agent_execution_job.rb`, `app/queries/agent_executions.rb`, the three
serializers). This app's own sandbox backends, benchmark runner and
`app/agents/` classes are still real files alongside them.
