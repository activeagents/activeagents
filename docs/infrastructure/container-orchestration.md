# Container Orchestration for Agent Sessions

## Overview

ActiveAgents supports ephemeral container sessions for running AI agents in isolated environments. This document covers the available orchestration backends.

## Recommended: Incus (Cloud-Agnostic)

```
User Request
    |
    v
+---------------+     +------------------------------------+
| Rails App     |---->| Any Linux Host (VPS/Bare Metal)    |
| (anywhere)    |     |                                    |
+---------------+     |  Incus Container Manager           |
                      |  +--------+ +--------+ +--------+  |
                      |  | sandbox| | sandbox| | sandbox|  |
                      |  |   -1   | |   -2   | |   -3   |  |
                      |  +--------+ +--------+ +--------+  |
                      |                                    |
                      |  - Linux namespaces + cgroups      |
                      |  - AppArmor/Seccomp isolation      |
                      |  - Bridge networking               |
                      |  - REST API                        |
                      +------------------------------------+
```

**Files:**
- `scripts/setup-incus-host.sh` - Host setup script
- `app/services/incus_sandbox_service.rb` - Incus API client
- `app/services/sandbox_orchestrator.rb` - Unified orchestrator

**Pros:**
- Cloud-agnostic: runs on any Linux host
- Self-hosted: full control, no vendor lock-in
- Simple: single binary, REST API
- Fast: ~1s container start time
- Cheap: run on any $5/mo VPS
- Mature: based on LXC/LXD (10+ years)
- Live migration between hosts
- Persistent storage support

**Cons:**
- Requires Linux host management
- Manual scaling (or simple scripts)
- No built-in gVisor (uses namespaces + AppArmor)

---

## Alternative: Cloud Run Jobs (GCP Only)

```
User Request
    |
    v
+---------------+     +------------------------------------+
| Rails App     |---->| Cloud Run Jobs                     |
| (Cloud Run)   |     |                                    |
+---------------+     |  +------+ +------+ +------+        |
                      |  |Job 1 | |Job 2 | |Job 3 | ...    |
                      |  +------+ +------+ +------+        |
                      |                                    |
                      |  - Ephemeral execution             |
                      |  - Auto-scaling                    |
                      |  - Pay per use                     |
                      |  - gVisor isolation                |
                      +------------------------------------+
```

**Files:**
- `terraform/modules/sandbox/` - Infrastructure
- `app/services/cloud_run_service.rb` - Service wrapper
- `app/jobs/sandbox_provision_job.rb` - Background provisioning

**Pros:**
- Serverless - no cluster management
- Fast cold starts (~2s)
- Pay only for execution time
- Built-in gVisor isolation
- Simple API

**Cons:**
- GCP-only (vendor lock-in)
- Less control over scheduling
- No persistent connections between containers
- Limited to 3600s max execution
- No custom networking between sessions

---

## Alternative: Kubernetes (Complex Workloads)

```
User Request
    |
    v
+---------------+     +------------------------------------+
| Rails App     |---->| Kubernetes Cluster                 |
| (anywhere)    |     | (GKE, EKS, k3s, etc.)              |
+---------------+     |                                    |
                      |  Namespace: agent-sandboxes        |
                      |  +------+ +------+ +------+        |
                      |  |Pod 1 | |Pod 2 | |Pod 3 | ...    |
                      |  +------+ +------+ +------+        |
                      |                                    |
                      |  - Full K8s control                |
                      |  - Network policies                |
                      |  - Custom scheduling               |
                      +------------------------------------+
```

**Files:**
- `terraform/modules/gke-sandboxes/main.tf` - GKE cluster (optional)
- `app/services/kubernetes_sandbox_service.rb` - K8s client

**Pros:**
- Industry standard
- Network policies for isolation
- Custom resource limits per agent type
- Pod affinity/anti-affinity rules
- Persistent volumes for session state
- Works with any K8s (GKE, EKS, k3s, k0s)

**Cons:**
- Overkill for simple use cases
- Higher operational overhead
- Slower pod startup (~5-10s)
- More complex networking
- Higher base cost

---

## Comparison Matrix

| Feature                  | Incus          | Cloud Run Jobs | Kubernetes   |
|--------------------------|----------------|----------------|--------------|
| Cloud-agnostic           | Yes            | No (GCP only)  | Yes          |
| Self-hosted              | Yes            | No             | Yes          |
| Startup time             | ~1s            | ~2s            | ~5-10s       |
| Min cost                 | ~$5/mo (VPS)   | $0/mo          | ~$70/mo      |
| Max containers           | Host-limited   | Unlimited      | 500+         |
| Isolation                | namespaces     | gVisor         | gVisor/ns    |
| GPU support              | Yes            | No             | Yes          |
| Network isolation        | iptables       | VPC            | CNI policies |
| Persistent storage       | Yes            | No             | Yes          |
| Live migration           | Yes            | No             | No           |
| API complexity           | Simple REST    | Simple REST    | Complex      |
| Operational overhead     | Low            | None           | High         |

---

## Recommended Architecture

### For Most Use Cases

**Use Incus** - simple, cheap, cloud-agnostic, full control.

Deploy on any Linux VPS:
- DigitalOcean, Linode, Hetzner, Vultr (~$5-20/mo)
- Self-hosted bare metal
- Any cloud VM (AWS EC2, GCP GCE, Azure VM)

### For Serverless (GCP Only)

**Use Cloud Run Jobs** when you:
- Are already on GCP
- Want zero operational overhead
- Have bursty, unpredictable workloads
- Don't need persistent storage

### For Complex Workloads

**Use Kubernetes** when you need:
- GPU workloads at scale
- Complex multi-container pods
- Enterprise compliance requirements
- Existing K8s infrastructure

---

## Quick Start with Incus

### 1. Setup Host

```bash
# On any Ubuntu/Debian server
curl -fsSL https://your-domain.com/scripts/setup-incus-host.sh | sudo bash

# Or manually:
apt install incus
incus admin init
```

### 2. Configure Rails App

```bash
# Environment variables
export SANDBOX_BACKEND=incus
export INCUS_HOST=https://your-server:8443
export INCUS_PROJECT=agent-sandboxes
```

### 3. Use the Orchestrator

```ruby
# app/jobs/sandbox_provision_job.rb
orchestrator = SandboxOrchestrator.new
result = orchestrator.create_sandbox(sandbox_session)
# => { sandbox_id: "sandbox-abc123", url: "http://10.100.0.42:8080", ... }
```

---

## Implementation Checklist

### To Enable Incus Sandboxes:

1. **Provision Host**
   ```bash
   # Any Linux VPS works (DigitalOcean, Linode, Hetzner, etc.)
   ssh root@your-server
   ./scripts/setup-incus-host.sh
   ```

2. **Dependencies** (optional, for remote access)
   ```ruby
   # Gemfile
   gem "faraday", "~> 2.0"
   ```

3. **Configuration**
   ```bash
   # .env or environment
   SANDBOX_BACKEND=incus
   INCUS_HOST=https://sandbox-host.example.com:8443
   INCUS_PROJECT=agent-sandboxes
   # For remote access with TLS:
   INCUS_CERT_PATH=/path/to/client.crt
   INCUS_KEY_PATH=/path/to/client.key
   ```

4. **Test Connection**
   ```ruby
   # rails console
   orchestrator = SandboxOrchestrator.new
   orchestrator.healthy?
   # => true
   ```

### To Use Cloud Run (GCP):

```bash
SANDBOX_BACKEND=cloud_run
GOOGLE_CLOUD_PROJECT=your-project
```

### To Use Kubernetes:

```bash
SANDBOX_BACKEND=kubernetes
KUBECONFIG=/path/to/kubeconfig
```

---

## Code Sessions (coding agents)

Sandboxes above run the *user's agent*. Code Sessions run a *coding agent*
(Claude Code, Codex, Copilot, ...) against the user's repository, inside a
code-on-incus container on the same Incus host. The host setup script installs
`coi` for this; the operator runbook is
[code-agent-sessions.md](code-agent-sessions.md).

---

## Security Considerations

### Incus Provides:
- Linux namespace isolation (pid, net, mnt, uts, ipc)
- cgroups resource limits
- AppArmor/SELinux profiles
- Seccomp syscall filtering
- UID/GID mapping (isolated)
- Non-root container execution

### Cloud Run Provides:
- gVisor kernel isolation
- Automatic security updates
- VPC network isolation
- IAM-based access control

### Kubernetes Provides:
- Pod Security Standards
- Network policies
- gVisor (optional)
- RBAC access control
- Workload Identity

---

## Cost Estimation

### Incus (Self-Hosted)
- DigitalOcean Droplet: $5-20/month
- Hetzner VPS: $4-10/month
- Any VPS with 2+ cores, 4GB+ RAM
- **Unlimited sessions (host-limited)**

### Cloud Run Jobs
- $0.00002400 per vCPU-second
- $0.00000250 per GiB-second
- **1000 sessions/day @ 5min avg = ~$50/month**

### Kubernetes
- Managed K8s control plane: ~$70/month
- Worker nodes: $25-100/month each
- **1000 sessions/day @ 5min avg = ~$150-250/month**

---

## Files Reference

```
app/services/
  sandbox_orchestrator.rb      # Unified orchestrator (backend-agnostic)
  incus_sandbox_service.rb     # Incus backend
  kubernetes_sandbox_service.rb # Kubernetes backend
  cloud_run_service.rb         # Cloud Run backend

scripts/
  setup-incus-host.sh          # One-command Incus host setup

terraform/modules/
  gke-sandboxes/               # GKE cluster (optional)
  sandbox/                     # Cloud Run Jobs (optional)
```
