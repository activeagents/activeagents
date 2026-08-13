# PlaywrightMCP Demo for Free Users

This document describes the PlaywrightMCP demo feature that allows free users to run sample browser automation agents in shared ephemeral containers on Active Agents GCP infrastructure.

## Overview

The PlaywrightMCP demo provides:
- A free browser automation agent accessible to all users (no account required)
- Runs in GCP Cloud Run ephemeral containers (similar to Hugging Face Spaces)
- Demonstrates Active Agents capabilities without requiring infrastructure setup
- Uses Claude AI with Playwright MCP for browser automation

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Active Agents Platform (GCP)                      │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                     Rails Application                         │   │
│  │  ┌─────────────┐    ┌──────────────┐    ┌────────────────┐   │   │
│  │  │  React UI   │───▶│  Sandboxes   │───▶│ SandboxSession │   │   │
│  │  │ (Dashboard) │    │  Controller  │    │    Model       │   │   │
│  │  └─────────────┘    └──────────────┘    └────────────────┘   │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                              │                                       │
│                              ▼                                       │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                   Cloud Run Sandbox                           │   │
│  │  ┌──────────────┐    ┌──────────────┐    ┌────────────────┐  │   │
│  │  │ PlaywrightMCP│───▶│    Claude    │───▶│   Chromium     │  │   │
│  │  │    Agent     │    │     API      │    │   Browser      │  │   │
│  │  └──────────────┘    └──────────────┘    └────────────────┘  │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

The React UI, the sandboxes controller and the `SandboxSession` model all come
from the activeagent gem's dashboard engine, which this app mounts at
`/dashboard`. The Cloud Run infrastructure underneath is the platform's, and is
registered with the engine as a sandbox backend
(`config.sandbox_backends` in `config/initializers/active_agent_dashboard.rb`).

## File Structure

```
examples/playwright_mcp/
├── README.md                 # Main documentation
├── demo_agent.rb             # Ruby agent example
└── sandbox/
    ├── Dockerfile            # Cloud Run sandbox container
    ├── Gemfile               # Ruby dependencies
    └── server.rb             # Sinatra server for sandbox

# activeagent gem — the dashboard engine this app mounts
lib/active_agent/dashboard/
├── app/models/active_agent/dashboard/
│   └── sandbox_session.rb           # Session management model
├── app/controllers/active_agent/dashboard/api/
│   └── sandboxes_controller.rb      # JSON API for sandboxes
├── app/services/active_agent/dashboard/
│   └── sandbox_orchestrator.rb      # Dispatches to the registered backend
├── app/jobs/active_agent/dashboard/
│   ├── sandbox_provision_job.rb     # Provisioning
│   ├── sandbox_run_job.rb           # Task execution
│   └── sandbox_cleanup_job.rb       # Resource cleanup
└── frontend/components/dashboard/
    └── SandboxRunner.jsx            # React frontend

# this app — the hosted infrastructure the engine dispatches to
app/
├── channels/
│   └── sandbox_channel.rb           # Real-time updates
└── services/
    ├── cloud_run_service.rb         # registered via config.sandbox_backends
    ├── incus_sandbox_service.rb
    └── kubernetes_sandbox_service.rb

terraform/modules/sandbox/           # Cloud Run infrastructure
```

The app also keeps one-line aliases (`app/models/sandbox_session.rb` reads
`SandboxSession = ActiveAgent::Dashboard::SandboxSession`, and likewise for the
jobs) so bare constant names still resolve here.

## Free Tier Limits

| Limit | Value |
|-------|-------|
| Max Runs | 10 per session |
| Timeout | 300s per task |
| Session Duration | 15 minutes |
| Max Tokens | 50,000 per session |

## Deployment

### Infrastructure
The sandbox infrastructure is managed via Terraform in `terraform/modules/sandbox/`:
- Cloud Run Jobs for isolated execution
- Cloud Tasks for job scheduling
- Pub/Sub for event handling
- Artifact Registry for container images

### Building the Sandbox Container
```bash
# Build the PlaywrightMCP sandbox image
cd examples/playwright_mcp/sandbox
docker build -t activeagents-sandbox-playwright .

# Push to Artifact Registry
docker tag activeagents-sandbox-playwright \
  us-central1-docker.pkg.dev/active-agents-platform/activeagents-sandboxes/activeagents-sandbox-playwright:latest
docker push us-central1-docker.pkg.dev/active-agents-platform/activeagents-sandboxes/activeagents-sandbox-playwright:latest
```

### Database Migration
```bash
bin/rails db:migrate
```

## Agent Template

A new template was added to `AgentTemplate.seed_defaults!` (the defaults now ship
with the engine, in `ActiveAgent::Dashboard::AgentTemplate`):

| Field | Value |
|-------|-------|
| Name | PlaywrightMCP Demo |
| Slug | playwright-mcp-demo |
| Category | automation |
| Provider | anthropic |
| Model | claude-sonnet-5 |
| Tools | playwright |
| Free Tier | true |
| Featured | true |

### Database Migrations
```ruby
# db/migrate/20260301000001_add_free_tier_and_mcp_servers_to_agent_templates.rb
add_column :agent_templates, :free_tier, :boolean, default: false
add_column :agent_templates, :mcp_servers, :jsonb, default: {}
add_index :agent_templates, :free_tier

# db/migrate/20260301000002_create_sandbox_sessions.rb
# Creates sandbox_sessions table for tracking ephemeral sessions
```

## Usage Examples

### From the Web Interface
1. Go to https://activeagents.ai/dashboard/sandbox
2. Session is created automatically (no account required)
3. Select or enter a task
4. Click "Run" and watch the agent work

### Sample Tasks
- "Take a screenshot of https://example.com"
- "Go to https://news.ycombinator.com and list the top 5 stories"
- "Navigate to Wikipedia and summarize the AI article"
- "Visit https://github.com/trending and list top repositories"

### From Active Agents Dashboard
Users can create an agent from the "PlaywrightMCP Demo" template:
1. Go to Dashboard > Templates
2. Select "PlaywrightMCP Demo"
3. Click "Use Template"
4. Customize as needed

## Security Considerations

- Browser runs in isolated container
- No persistent storage between sessions
- API keys are not stored (client-side only)
- Sessions timeout after 5 minutes of inactivity
- Network access limited to standard web ports

## Future Enhancements

1. **Persistent Results**: Store screenshots/results in cloud storage
2. **Session History**: Allow users to see past runs
3. **Custom MCP Servers**: Support additional MCP tools
4. **Paid Tier**: Longer sessions, more resources
5. **Multiple Browsers**: Firefox, WebKit support

## API Endpoints

Served by the engine under its mount — `/dashboard/api/...` here, `<mount>/api/...`
in a self-hosted install:

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/dashboard/api/sandboxes` | List sandbox types and sample tasks |
| POST | `/dashboard/api/sandboxes` | Create new sandbox session |
| GET | `/dashboard/api/sandboxes/:session_id` | Get session status and runs |
| POST | `/dashboard/api/sandboxes/:session_id/run` | Execute a task |
| DELETE | `/dashboard/api/sandboxes/:session_id` | End session |
| POST | `/dashboard/api/sandboxes/compare` | Run one task across several providers in the same sandbox |

## Real-time Updates

The `SandboxChannel` provides WebSocket updates for:
- Session status changes (provisioning, ready, running, completed)
- Run completion with results
- Error notifications

```javascript
// Subscribe to sandbox updates
const channel = consumer.subscriptions.create(
  { channel: "SandboxChannel", session_id: sessionId },
  {
    received(data) {
      if (data.type === 'run_complete') {
        // Handle completed run
      }
    }
  }
);
```

## Related Files

- `examples/playwright_mcp/demo_agent.rb` - Ruby agent implementation
- `examples/playwright_mcp/sandbox/` - Cloud Run container files
- `config/initializers/active_agent_dashboard.rb` - Registers this platform's sandbox backends with the engine
- `app/channels/sandbox_channel.rb` - Real-time updates
- `app/services/{incus_sandbox_service,kubernetes_sandbox_service,cloud_run_service}.rb` - The backends themselves
- `terraform/modules/sandbox/` - Infrastructure as code

In the activeagent gem, under `lib/active_agent/dashboard/`:

- `app/models/active_agent/dashboard/sandbox_session.rb` - Session management
- `app/controllers/active_agent/dashboard/api/sandboxes_controller.rb` - JSON API
- `app/services/active_agent/dashboard/sandbox_orchestrator.rb` - Backend dispatch
- `app/jobs/active_agent/dashboard/sandbox_*.rb` - Background job handlers
- `frontend/components/dashboard/SandboxRunner.jsx` - React UI
