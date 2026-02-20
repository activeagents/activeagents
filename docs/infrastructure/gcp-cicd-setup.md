# GCP CI/CD Infrastructure Setup

This document describes how to set up the CI/CD pipeline for deploying ActiveAgents to Google Cloud Platform.

## Architecture Overview

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   GitHub Push   │────▶│  GitHub Actions  │────▶│   Cloud Run     │
│   (main branch) │     │  (Build & Deploy)│     │   (Staging)     │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                                                          │
┌─────────────────┐     ┌──────────────────┐             │
│  GitHub Release │────▶│  GitHub Actions  │─────────────┘
│   (tag v*.*.*)  │     │  (Prod Deploy)   │
└─────────────────┘     └──────────────────┘
                                │
                                ▼
                        ┌─────────────────┐
                        │   Cloud Run     │
                        │  (Production)   │
                        └─────────────────┘
```

## Components

### Infrastructure (Terraform)
- **Cloud Run**: Serverless container hosting
- **Cloud SQL**: Managed PostgreSQL database
- **VPC**: Private networking for secure database access
- **Secret Manager**: Secure storage for credentials
- **Artifact Registry**: Docker image storage
- **Sandbox Infrastructure**: Dynamic execution environments for agents

### CI/CD Pipelines (GitHub Actions)
- **CI**: Security scanning (Brakeman) + linting (RuboCop)
- **Staging Deploy**: Automatic on push to `main`
- **Production Deploy**: Manual or on release tag

## Prerequisites

1. **GCP Project**: Create a new GCP project or use existing
2. **Billing**: Enable billing on the GCP project
3. **GitHub Repository**: Access to repository settings

## Setup Steps

### 1. Create GCP Service Account for GitHub Actions

```bash
# Set your project ID
export PROJECT_ID="your-project-id"

# Create service account
gcloud iam service-accounts create github-actions \
  --display-name="GitHub Actions" \
  --project=$PROJECT_ID

# Grant required roles
ROLES=(
  "roles/run.admin"
  "roles/iam.serviceAccountUser"
  "roles/storage.admin"
  "roles/artifactregistry.admin"
  "roles/secretmanager.admin"
  "roles/cloudsql.admin"
  "roles/compute.networkAdmin"
  "roles/vpcaccess.admin"
)

for ROLE in "${ROLES[@]}"; do
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:github-actions@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="$ROLE"
done
```

### 2. Set Up Workload Identity Federation (Recommended)

This allows GitHub Actions to authenticate without storing service account keys.

```bash
# Create workload identity pool
gcloud iam workload-identity-pools create "github" \
  --project=$PROJECT_ID \
  --location="global" \
  --display-name="GitHub Actions"

# Create provider
gcloud iam workload-identity-pools providers create-oidc "github-actions" \
  --project=$PROJECT_ID \
  --location="global" \
  --workload-identity-pool="github" \
  --display-name="GitHub Actions" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# Get the full provider name
export WORKLOAD_IDENTITY_PROVIDER=$(gcloud iam workload-identity-pools providers describe github-actions \
  --project=$PROJECT_ID \
  --location="global" \
  --workload-identity-pool="github" \
  --format="value(name)")

# Allow GitHub Actions to impersonate service account
# Replace OWNER/REPO with your GitHub repository
gcloud iam service-accounts add-iam-policy-binding \
  "github-actions@$PROJECT_ID.iam.gserviceaccount.com" \
  --project=$PROJECT_ID \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${WORKLOAD_IDENTITY_PROVIDER}/attribute.repository/OWNER/REPO"
```

### 3. Create Terraform State Bucket

```bash
# Create bucket for Terraform state
gsutil mb -p $PROJECT_ID -l us-central1 gs://activeagents-terraform-state

# Enable versioning
gsutil versioning set on gs://activeagents-terraform-state
```

### 4. Configure GitHub Secrets

Go to your GitHub repository → Settings → Secrets and variables → Actions

Add these secrets:

| Secret Name | Value |
|-------------|-------|
| `GCP_PROJECT_ID` | Your GCP project ID |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Output from step 2 |
| `GCP_SERVICE_ACCOUNT` | `github-actions@PROJECT_ID.iam.gserviceaccount.com` |
| `RAILS_MASTER_KEY` | Contents of `config/master.key` |

### 5. Configure GitHub Environments

Create two environments in GitHub:

1. **staging**
   - No protection rules required
   - Deploys automatically on push to main

2. **production**
   - Add required reviewers
   - Add deployment branch rule: only `main`

### 6. Initialize Infrastructure

```bash
# Initialize staging
cd terraform/environments/staging
terraform init
terraform plan -var="project_id=$PROJECT_ID" -var="image=gcr.io/cloudrun/hello"
terraform apply -var="project_id=$PROJECT_ID" -var="image=gcr.io/cloudrun/hello"

# Initialize production
cd ../production
terraform init
terraform plan -var="project_id=$PROJECT_ID" -var="image=gcr.io/cloudrun/hello"
terraform apply -var="project_id=$PROJECT_ID" -var="image=gcr.io/cloudrun/hello"
```

### 7. Set Secrets in Secret Manager

```bash
# Set Rails master key
echo -n "YOUR_MASTER_KEY" | gcloud secrets versions add activeagents-staging-rails-master-key --data-file=-
echo -n "YOUR_MASTER_KEY" | gcloud secrets versions add activeagents-production-rails-master-key --data-file=-

# Set Stripe keys
echo -n "sk_test_..." | gcloud secrets versions add activeagents-staging-stripe-api-key --data-file=-
echo -n "sk_live_..." | gcloud secrets versions add activeagents-production-stripe-api-key --data-file=-

# Set Stripe webhook secrets
echo -n "whsec_..." | gcloud secrets versions add activeagents-staging-stripe-webhook-secret --data-file=-
echo -n "whsec_..." | gcloud secrets versions add activeagents-production-stripe-webhook-secret --data-file=-
```

## Deployment Workflow

### Staging
1. Push to `main` branch
2. CI runs (security scan + lint)
3. Docker image builds and pushes to Artifact Registry
4. Terraform applies changes
5. Health check runs

### Production
1. Create a GitHub Release (e.g., `v1.0.0`)
2. Workflow verifies staging is healthy
3. Docker image builds with release tag
4. Terraform applies changes
5. Health check runs

## Sandbox Infrastructure

The sandbox module provides infrastructure for running isolated agent execution environments, similar to HuggingFace Spaces or Google Colab.

### Features
- **Cloud Run Jobs**: One-off executions with resource limits
- **Cloud Run Services**: Persistent sandboxes (notebooks/IDEs)
- **Cloud Tasks**: Queue-based scheduling
- **Pub/Sub**: Event processing
- **gVisor isolation**: Secure execution of untrusted code

### Configuration
```hcl
# In terraform.tfvars
sandbox_image            = "your-sandbox-image:latest"
sandbox_cpu              = "2"
sandbox_memory           = "2Gi"
sandbox_timeout_seconds  = 600
max_concurrent_sandboxes = 50
```

### Using Sandboxes from the App

```ruby
# Create a sandbox execution
def execute_in_sandbox(agent_run)
  client = Google::Cloud::Tasks.cloud_tasks

  task = {
    http_request: {
      http_method: :POST,
      url: "https://#{ENV['REGION']}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/#{ENV['PROJECT_ID']}/jobs/sandbox-template-#{ENV['RAILS_ENV']}:run",
      body: { env: { AGENT_RUN_ID: agent_run.id } }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    }
  }

  client.create_task(parent: queue_path, task: task)
end
```

## Monitoring

### Cloud Run Metrics
- Request count
- Request latency
- Container instance count
- CPU/Memory utilization

### Alerts (Recommended)
1. Error rate > 1% for 5 minutes
2. Latency p95 > 2s for 5 minutes
3. Instance count at max for 10 minutes

## Troubleshooting

### Common Issues

**Build fails with "Buildx not found"**
- Ensure Docker Buildx is set up in the workflow

**Terraform state lock**
- Use `terraform force-unlock LOCK_ID`

**Cloud Run health check fails**
- Check `/up` endpoint returns 200
- Verify database connection

**Workload Identity Federation fails**
- Verify repository attribute mapping
- Check service account permissions

## Cost Optimization

### Staging
- `min_instances = 0`: Scale to zero when idle
- `db-f1-micro`: Smallest database tier
- VPC connector: `e2-micro` instances

### Production
- `min_instances = 1`: Keep warm for fast response
- `db-custom-2-4096`: Appropriate for production load
- Consider committed use discounts

## Files Created

```
terraform/
├── main.tf                     # Root module
├── variables.tf                # Input variables
├── outputs.tf                  # Output values
├── modules/
│   ├── cloud-run/              # Cloud Run service
│   ├── cloud-sql/              # PostgreSQL database
│   ├── networking/             # VPC and connectivity
│   ├── secret-manager/         # Secrets
│   └── sandbox/                # Dynamic execution environments
└── environments/
    ├── staging/                # Staging config
    └── production/             # Production config

.github/workflows/
├── ci.yml                      # CI pipeline
├── deploy-staging.yml          # Staging deployment
└── deploy-production.yml       # Production deployment
```
