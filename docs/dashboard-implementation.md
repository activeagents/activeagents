# Agent Builder Dashboard Implementation

> **See also:** [features/observability.md](features/observability.md) for the
> observability stack (traces, metrics, interactions, evaluations, telemetry
> ingest) — the platform runs the activeagent gem's dashboard/telemetry
> engine in multi-tenant mode and persists conversations via solid_agent.

## Overview

The Agent Builder Dashboard provides a visual interface for creating, configuring, and testing AI agents built with ActiveAgent.

## Setup

### Prerequisites

- Ruby 3.2+ (Note: Ruby 3.3+ has compatibility issues with Rails 8.1.2)
- PostgreSQL
- Node.js 18+

### Installation

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

### Access

Navigate to `http://localhost:3000/dashboard` to access the Agent Builder.

## Architecture

### Database Models

#### Agent (`app/models/agent.rb`)
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
| status | integer | draft (0), active (1), archived (2) |

#### AgentVersion (`app/models/agent_version.rb`)
Tracks configuration changes for versioning and rollback.

| Field | Type | Description |
|-------|------|-------------|
| agent_id | reference | Parent agent |
| version_number | integer | Sequential version |
| change_summary | string | Description of changes |
| configuration_snapshot | jsonb | Full config at this version |

#### AgentRun (`app/models/agent_run.rb`)
Records each agent execution for debugging and analytics.

| Field | Type | Description |
|-------|------|-------------|
| agent_id | reference | Parent agent |
| input_prompt | text | User input |
| output | text | Agent response |
| status | integer | pending/running/complete/failed |
| duration_ms | integer | Execution time |
| input_tokens | integer | Tokens consumed |
| output_tokens | integer | Tokens generated |
| error_message | text | Error details if failed |
| trace_id | string | Unique execution trace |

### API Endpoints

#### Agents

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/agents | List all agents |
| POST | /api/agents | Create new agent |
| GET | /api/agents/:id | Get agent details |
| PATCH | /api/agents/:id | Update agent |
| DELETE | /api/agents/:id | Delete agent |
| GET | /api/agents/:id/versions | Get version history |
| POST | /api/agents/:id/restore | Restore a version |
| GET | /api/agents/:id/runs | Get execution history |
| POST | /api/agents/:id/execute | Queue async execution |
| POST | /api/agents/:id/test | Sync test execution |
| POST | /api/agents/:id/duplicate | Clone agent |
| GET | /api/agents/:id/export | Export agent config/code |
| GET | /api/agents/presets | Get available presets |

#### Runs

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/runs | List all runs |
| GET | /api/runs/:id | Get run details |
| POST | /api/runs/:id/cancel | Cancel running execution |

#### Observability

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/traces | Telemetry traces (account-scoped) |
| GET | /api/metrics | 24h metrics, per-agent stats, cost estimates |
| GET | /api/interactions | Conversation streams (solid_agent) |
| GET/POST | /api/evaluations | Evaluations + runs |
| POST | /v1/traces | Telemetry ingest (Bearer telemetry_api_key) |

### React Components

#### Dashboard (`app/javascript/pages/Dashboard.jsx`)
Main application component with routing and state management.

**Props:**
- `user` - Current user info
- `initialAgents` - Pre-loaded agent list
- `meta` - Configuration metadata (providers, tools, etc.)

#### Sidebar (`app/javascript/components/dashboard/Sidebar.jsx`)
Navigation sidebar with agent count and resource links.

#### Header (`app/javascript/components/dashboard/Header.jsx`)
Context-aware header showing current view and agent info.

#### AgentList (`app/javascript/components/dashboard/AgentList.jsx`)
Grid view of all agents with search and filtering.

**Features:**
- Search by name/description
- Filter by provider and status
- Avatar preview with hover effects
- Quick actions (duplicate, delete)

#### AgentBuilder (`app/javascript/components/dashboard/AgentBuilder.jsx`)
Step-by-step wizard for creating new agents.

**Steps:**
1. **Basics** - Name, description, provider, model, temperature
2. **Appearance** - Avatar preset and customization
3. **Capabilities** - Instructions, tools, MCPs
4. **Review** - Final configuration preview

#### AgentEditor (`app/javascript/components/dashboard/AgentEditor.jsx`)
Full editor for existing agents with tabbed interface.

**Tabs:**
- **Configuration** - Basic settings
- **Instructions** - System prompt editor
- **Tools** - Tool selection grid
- **Versions** - Version history with restore
- **Code** - Generated Ruby code preview

#### AgentRunner (`app/javascript/components/dashboard/AgentRunner.jsx`)
Interactive testing interface for agents.

**Features:**
- Prompt input with keyboard shortcuts
- Real-time output display
- Token usage tracking
- Execution history
- Example prompts

### Background Jobs

#### AgentExecutionJob (`app/jobs/agent_execution_job.rb`)
Async agent execution via SolidQueue.

**Features:**
- Executes through AgentExecutionService: real provider generation when
  credentials are configured (config/active_agent.yml), the gem's mock
  provider otherwise — either way the full ActiveAgent pipeline runs
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
4. Or use `/api/agents/:id/export` for full config

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

### Adding New Providers

1. Update `PROVIDER_MODELS` in `AgentBuilder.jsx` and `AgentEditor.jsx`
2. Add provider constant to `Agent::PROVIDERS`
3. Configure in `config/active_agent.yml`

### Adding New Tools

1. Add to `Agent::AVAILABLE_TOOLS`
2. Add icon mapping in component `getToolIcon()` functions
3. Implement tool in ActiveAgent

### Adding New Presets

1. Add to `AGENT_PRESETS` in `AgentAvatar.jsx`
2. Add to `Agent::PRESET_TYPES`
3. Configure appearance defaults in API controller

## File Structure

```
activeagents/
├── app/
│   ├── controllers/
│   │   ├── api/
│   │   │   ├── base_controller.rb
│   │   │   ├── agents_controller.rb
│   │   │   └── agent_runs_controller.rb
│   │   └── dashboard_controller.rb
│   ├── jobs/
│   │   └── agent_execution_job.rb
│   ├── models/
│   │   ├── agent.rb
│   │   ├── agent_version.rb
│   │   └── agent_run.rb
│   └── javascript/
│       ├── pages/
│       │   └── Dashboard.jsx
│       └── components/
│           ├── AgentAvatar.jsx
│           └── dashboard/
│               ├── index.js
│               ├── Sidebar.jsx
│               ├── Header.jsx
│               ├── AgentList.jsx
│               ├── AgentBuilder.jsx
│               ├── AgentEditor.jsx
│               └── AgentRunner.jsx
├── db/
│   └── migrate/
│       ├── 20260216000001_create_agents.rb
│       ├── 20260216000002_create_agent_versions.rb
│       └── 20260216000003_create_agent_runs.rb
└── config/
    └── routes.rb (updated with API routes)
```
