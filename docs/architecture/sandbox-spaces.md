# Sandbox Spaces Architecture

Sandbox spaces provide ephemeral, isolated execution environments for free-tier users to run sample agents. Each sandbox is a containerized instance of the ActiveAgents application running in sandbox mode.

The sandbox surface — models, API, orchestrator and jobs — lives in the `actionagent` dashboard engine (`ActionAgent`), which this app mounts at `/dashboard` and configures in `config/initializers/action_agent.rb`. What stays here is the infrastructure: the services that talk to Incus, Kubernetes and Cloud Run, and the admin interface over them.

## Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Active Agents Platform                            │
│  ┌────────────────┐    ┌─────────────────┐    ┌──────────────────┐  │
│  │   React UI     │───▶│  Sandboxes API  │───▶│  Sandbox backend │  │
│  │   (engine)     │    │  + Orchestrator │    │  incus / k8s /   │  │
│  │                │    │    (engine)     │    │  cloud_run (app) │  │
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

### 3. Pluggable Backends

`SandboxOrchestrator` dispatches to a backend **registry** rather than a hardcoded switch. The engine ships only `ActionAgent::MockSandboxBackend` (in-memory, so the sandbox surface is exercisable in development and tests without a container runtime); the backends that talk to real infrastructure are registered by the app that operates them — here, in `config/initializers/action_agent.rb`:

```ruby
config.sandbox_backends = {
  "incus" => "IncusSandboxService",
  "kubernetes" => "KubernetesSandboxService",
  "cloud_run" => "CloudRunService"
}
config.sandbox_service = ENV.fetch("SANDBOX_BACKEND", "incus")
```

Dispatch is capability-based. For each verb the orchestrator calls the first method the backend responds to, so a registered class needs no adapter of its own:

| Verb | Candidates, in order |
|---|---|
| create | `create_sandbox`, `create_sandbox_pod`, `create_sandbox_job` |
| status | `status`, `container_status`, `pod_status`, `job_status` |
| terminate | `terminate`, `terminate_pod`, `cancel_job` |
| list | `list_sandboxes`, `list_sandbox_pods`, `list_jobs` |
| cleanup | `cleanup_expired`, `cleanup_expired_pods`, `cleanup_expired_jobs` |

`instance_tier:` is only passed to backends whose create method accepts it, and the orchestrator normalizes the response (`container_name` / `pod_name` / `job_name` → `sandbox_id`, and so on). Choosing a backend: `SandboxOrchestrator.new(backend: "kubernetes")` names one explicitly, and an unregistered name there raises `UnsupportedBackendError`. With no argument it reads `ENV["SANDBOX_BACKEND"]`, then `config.sandbox_service`, and falls back to `mock` if neither names a registered backend.

When the `cloud_run` backend is selected, sandboxes are provisioned as Cloud Run Jobs (not Services):

- Automatic scaling to zero when idle
- Built-in timeout enforcement
- Cost-effective for ephemeral workloads
- No persistent endpoints to maintain

## Components

Everything under `ActionAgent::` lives in the `actionagent` gem, under `actionagent/app/` in the gem repo (github.com/activeagents/activeagent) — not in this one. This app keeps one-line alias files at the old paths (`app/models/sandbox_session.rb` is now `SandboxSession = ActionAgent::SandboxSession`), so bare constant names still resolve here — but the behaviour is in the engine.

### Models

#### `ActionAgent::SandboxSession`
Tracks sandbox sessions in the main application database:
- Session ID, status, type
- Run count and token usage
- Backend container/job references (`cloud_run_url`, `cloud_run_job_id`)
- Owner association (user or account, both optional for anonymous)

#### `ActionAgent::SandboxRun`
Tracks individual task executions within a sandbox container:
- Only written inside the sandbox container, where the database is SQLite
- Contains task, result, screenshots
- Used for the sandbox's own run history

### Controllers

#### `ActionAgent::Api::SandboxesController`
Main API for creating and managing sandbox sessions. Served under the engine mount, so on this platform the paths are prefixed with `/dashboard`:
- GET /dashboard/api/sandboxes - Sandbox types, free-tier limits, templates, sample tasks
- POST /dashboard/api/sandboxes - Create new sandbox
- GET /dashboard/api/sandboxes/:id - Get sandbox status and run history
- POST /dashboard/api/sandboxes/:id/run - Execute a task
- POST /dashboard/api/sandboxes/compare - Run one task across several providers in one sandbox
- DELETE /dashboard/api/sandboxes/:id - Terminate sandbox

Anonymous access is allowed (free tier). Running a task goes through the engine's quota seam, which this app points at the account's plan.

#### `Api::Sandbox::RunsController` (app/controllers/api/sandbox/runs_controller.rb)
Sandbox-internal API (only available in sandbox mode). Owned by this app and still at the root paths:
- GET /api/sandbox/status - Container status
- POST /api/sandbox/runs - Execute task locally
- GET /api/sandbox/runs - Run history

#### `Admin::SpacesController` (app/controllers/admin/spaces_controller.rb)
Admin interface for managing all sandbox spaces. Owned by this app, and calls `CloudRunService` directly rather than going through the orchestrator:
- List all sandbox sessions
- View Cloud Run container details
- Terminate running containers
- View container logs

### Services

#### `ActionAgent::SandboxOrchestrator`
The single entry point the engine's controllers and jobs use — `create_sandbox`, `status`, `terminate`, `list_sandboxes`, `cleanup_expired`, plus `backend_info` and the instance-tier helpers. It owns the backend registry described above and normalizes each backend's response shape.

#### `CloudRunService` (app/services/cloud_run_service.rb)
Handles Cloud Run API interactions. Stays in this app, which is where the Google Cloud SDK dependency belongs:
- Create sandbox jobs
- Query job status
- Fetch container logs
- Terminate jobs

#### `IncusSandboxService` (app/services/incus_sandbox_service.rb) and `KubernetesSandboxService` (app/services/kubernetes_sandbox_service.rb)
The other two backends this app registers — Incus containers on any Linux host (the default, per `SANDBOX_BACKEND`) and Kubernetes pods.

### Jobs

#### `ActionAgent::SandboxProvisionJob`
Background job to provision new sandbox containers:
- Asks `SandboxOrchestrator` for a sandbox from the configured backend
- Updates SandboxSession with container URL
- Broadcasts status via ActionCable
- Simulates provisioning in development and test rather than hitting a backend

#### `ActionAgent::SandboxRunJob`
Executes tasks in provisioned sandboxes:
- Runs the task through ActiveAgent for the requested provider
- Records results back to SandboxSession

#### `ActionAgent::SandboxCleanupJob`
Cleans up expired sandbox resources:
- Deletes the session's Cloud Run job directly, not through the orchestrator — only when `cloud_run_job_id` is set
- Updates session status

## Free Tier Limits

From `ActionAgent::SandboxSession::FREE_TIER_LIMITS`:

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
SANDBOX_BACKEND=cloud_run          # incus (default) | kubernetes | cloud_run

# cloud_run backend
GOOGLE_CLOUD_PROJECT=activeagents-prod
CLOUD_RUN_REGION=us-central1
SANDBOX_IMAGE=gcr.io/activeagents-prod/activeagents:sandbox

# incus backend
INCUS_HOST=unix:///var/lib/incus/unix.socket
INCUS_PROJECT=agent-sandboxes
INCUS_CERT_PATH=                   # for remote Incus over HTTPS
INCUS_KEY_PATH=

# kubernetes backend
KUBECONFIG=~/.kube/config
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
