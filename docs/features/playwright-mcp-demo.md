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

## File Structure

```
examples/playwright_mcp/
├── README.md                 # Main documentation
├── demo_agent.rb             # Ruby agent example
└── sandbox/
    ├── Dockerfile            # Cloud Run sandbox container
    ├── Gemfile               # Ruby dependencies
    └── server.rb             # Sinatra server for sandbox

app/
├── models/
│   └── sandbox_session.rb    # Session management model
├── controllers/api/
│   └── sandboxes_controller.rb  # REST API for sandboxes
├── jobs/
│   ├── sandbox_provision_job.rb # Cloud Run provisioning
│   ├── sandbox_run_job.rb       # Task execution
│   └── sandbox_cleanup_job.rb   # Resource cleanup
├── channels/
│   └── sandbox_channel.rb    # Real-time updates
└── javascript/components/dashboard/
    └── SandboxRunner.jsx     # React frontend

terraform/modules/sandbox/    # Cloud Run infrastructure
```

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

A new template was added to `AgentTemplate.seed_defaults!`:

| Field | Value |
|-------|-------|
| Name | PlaywrightMCP Demo |
| Slug | playwright-mcp-demo |
| Category | automation |
| Provider | anthropic |
| Model | claude-sonnet-4-20250514 |
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

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/sandboxes` | List sandbox types and sample tasks |
| POST | `/api/sandboxes` | Create new sandbox session |
| GET | `/api/sandboxes/:session_id` | Get session status and runs |
| POST | `/api/sandboxes/:session_id/run` | Execute a task |
| DELETE | `/api/sandboxes/:session_id` | End session |

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
- `app/models/sandbox_session.rb` - Session management
- `app/controllers/api/sandboxes_controller.rb` - REST API
- `app/jobs/sandbox_*.rb` - Background job handlers
- `app/javascript/components/dashboard/SandboxRunner.jsx` - React UI
- `terraform/modules/sandbox/` - Infrastructure as code
