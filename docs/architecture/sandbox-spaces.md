# Sandbox Spaces Architecture

Sandbox spaces provide ephemeral, isolated execution environments for free-tier users to run sample agents. Each sandbox is a containerized instance of the ActiveAgents application running in sandbox mode.

## Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Active Agents Platform                            │
│  ┌────────────────┐    ┌─────────────────┐    ┌──────────────────┐  │
│  │   React UI     │───▶│   Rails API     │───▶│   Cloud Run      │  │
│  │  (Dashboard)   │    │  (Main App)     │    │   (Sandbox)      │  │
│  └────────────────┘    └─────────────────┘    └──────────────────┘  │
│                               │                       │              │
│                               ▼                       ▼              │
│                     ┌─────────────────┐      ┌──────────────────┐   │
│                     │   Cloud SQL     │      │   Cloud Logging  │   │
│                     │   (PostgreSQL)  │      │   (Observability)│   │
│                     └─────────────────┘      └──────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

## Key Design Decisions

### 1. Same Image, Different Mode

Sandbox containers run the **same ActiveAgents application image** but with `RAILS_ENV=sandbox`. This approach:

- Eliminates the need to maintain separate sandbox codebases
- Ensures feature parity with the main platform
- Simplifies deployment and updates
- Reduces container image proliferation

### 2. SQLite for Isolation

Sandbox containers use SQLite instead of PostgreSQL:

- Complete data isolation between sandbox instances
- No network dependency on shared database
- Ephemeral by design - data is lost when container terminates
- Faster startup time

### 3. Cloud Run Jobs

Sandboxes are provisioned as Cloud Run Jobs (not Services):

- Automatic scaling to zero when idle
- Built-in timeout enforcement
- Cost-effective for ephemeral workloads
- No persistent endpoints to maintain

## Components

### Models

#### `SandboxSession` (app/models/sandbox_session.rb)
Tracks sandbox sessions in the main application database:
- Session ID, status, type
- Run count and token usage
- Cloud Run job references
- User association (optional for anonymous)

#### `SandboxRun` (app/models/sandbox_run.rb)
Tracks individual task executions within a sandbox container:
- Only exists in sandbox SQLite database
- Contains task, result, screenshots
- Used for the sandbox's own run history

### Controllers

#### `Api::SandboxesController` (app/controllers/api/sandboxes_controller.rb)
Main API for creating and managing sandbox sessions:
- POST /api/sandboxes - Create new sandbox
- GET /api/sandboxes/:id - Get sandbox status
- POST /api/sandboxes/:id/run - Execute a task
- DELETE /api/sandboxes/:id - Terminate sandbox

#### `Api::Sandbox::RunsController` (app/controllers/api/sandbox/runs_controller.rb)
Sandbox-internal API (only available in sandbox mode):
- GET /api/sandbox/status - Container status
- POST /api/sandbox/run - Execute task locally
- GET /api/sandbox/runs - Run history

#### `Admin::SpacesController` (app/controllers/admin/spaces_controller.rb)
Admin interface for managing all sandbox spaces:
- List all sandbox sessions
- View Cloud Run container details
- Terminate running containers
- View container logs

### Services

#### `CloudRunService` (app/services/cloud_run_service.rb)
Handles all Cloud Run API interactions:
- Create sandbox jobs
- Query job status
- Fetch container logs
- Terminate jobs

### Jobs

#### `SandboxProvisionJob` (app/jobs/sandbox_provision_job.rb)
Background job to provision new sandbox containers:
- Creates Cloud Run job with sandbox config
- Updates SandboxSession with container URL
- Broadcasts status via ActionCable

#### `SandboxRunJob` (app/jobs/sandbox_run_job.rb)
Executes tasks in provisioned sandboxes:
- Calls sandbox container API
- Records results back to SandboxSession

#### `SandboxCleanupJob` (app/jobs/sandbox_cleanup_job.rb)
Cleans up expired sandbox resources:
- Terminates Cloud Run jobs
- Updates session status

## Free Tier Limits

| Limit | Value |
|-------|-------|
| Max Runs per Session | 10 |
| Task Timeout | 300 seconds |
| Session Duration | 15 minutes |
| Max Tokens | 50,000 |

## Environment Configuration

### Sandbox Container Environment Variables

```bash
RAILS_ENV=sandbox
SANDBOX_MODE=true
SANDBOX_SESSION_ID=<uuid>
SANDBOX_OWNER_ID=<user_id>  # Optional for anonymous
SANDBOX_MAX_RUNS=10
SANDBOX_TIMEOUT=300
SANDBOX_MAX_TOKENS=50000
SANDBOX_IDLE_TIMEOUT=900
ANTHROPIC_API_KEY=<from_secret>
```

### Main Application Environment

```bash
GOOGLE_CLOUD_PROJECT=activeagents-prod
CLOUD_RUN_REGION=us-central1
SANDBOX_IMAGE=gcr.io/activeagents-prod/activeagents:sandbox
```

## Building the Sandbox Image

```bash
# Build sandbox variant
docker build -f Dockerfile.sandbox -t activeagents:sandbox .

# Tag for Artifact Registry
docker tag activeagents:sandbox \
  us-central1-docker.pkg.dev/activeagents-prod/activeagents/sandbox:latest

# Push to registry
docker push us-central1-docker.pkg.dev/activeagents-prod/activeagents/sandbox:latest
```

## Admin Interface

Accessible at `/admin/spaces` for admin users:

- **Index view**: Lists all sandbox sessions with status, user, runs, tokens
- **Show view**: Detailed view of a single sandbox with:
  - Session details
  - Cloud Run container info (CPU, memory, status)
  - Run history
  - Container logs
- **Terminate action**: Force-stops running containers

## Security Considerations

1. **Network isolation**: Sandboxes can only access the internet, not internal GCP resources
2. **Resource limits**: CPU and memory capped at Cloud Run config level
3. **Token limits**: API token usage tracked and enforced
4. **Idle timeout**: Containers auto-terminate after 15 minutes of inactivity
5. **gVisor**: Cloud Run uses gVisor for kernel-level sandboxing
6. **No persistent state**: SQLite database is ephemeral

## Observability

### Cloud Logging

All sandbox containers log to Cloud Logging with structured JSON:
- Request logs
- Agent execution logs
- Error traces

Filter: `resource.type="cloud_run_job" AND resource.labels.job_name="sandbox-*"`

### Metrics

Key metrics tracked:
- `sandbox_sessions_created` - Total sessions created
- `sandbox_runs_executed` - Total tasks executed
- `sandbox_tokens_used` - Token consumption
- `sandbox_duration_ms` - Task execution time

### Alerts

Recommended alerts:
- High error rate on sandbox executions
- Unusual token consumption patterns
- Long-running containers (stuck jobs)

## Future Enhancements

1. **Custom tool support**: Allow users to configure MCP servers
2. **File uploads**: Support uploading files to sandbox
3. **Persistent sandboxes**: Paid tier with longer-lived containers
4. **Team spaces**: Shared sandboxes for collaboration
5. **Snapshots**: Save and restore sandbox state
