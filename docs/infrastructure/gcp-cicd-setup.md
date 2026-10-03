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

## Every setting lives in the tf files

Every environment variable, secret and setting the platform reads is declared in Terraform:

- secrets go in the `module "secrets"` map in `terraform/main.tf` and reach Cloud Run through `local.cloud_run_secret_env_vars`;
- plain values go in `local.cloud_run_env_vars`;
- every input variable is declared in `terraform/variables.tf` and in the environment's `variables.tf`;
- per-environment values go in a committed `*.auto.tfvars` file in `terraform/environments/<env>/`, which Terraform loads without CLI flags. `.gitignore` ignores only `terraform.tfvars`.

Never set anything with `gcloud run services update` or the console: the next `terraform apply` in the deploy workflow removes it. Secret values are the one exception. Terraform manages each secret but not its versions, so values are added with `gcloud secrets versions add`. The rule covers the Incus host too: its ACL and IAM live in `terraform/modules/incus-host` and `scripts/setup-incus-host.sh`, not in hand-run `incus` or `gcloud` commands.

Cloud Run refuses a revision that reads a secret with no version. A new secret is therefore declared first, given a version by hand, and only then passed to the app, behind a flag that defaults to off.

## GitHub App, encryption keys and recordings storage

Terraform creates these in both environments, and none of them reaches the app until its flag is on:

| Secret (`activeagents-<env>-…`) | Variable the app reads | Flag |
| --- | --- | --- |
| `github-app-client-id` | `GITHUB_APP_CLIENT_ID` | `enable_github_sign_in` |
| `github-app-client-secret` | `GITHUB_APP_CLIENT_SECRET` | `enable_github_sign_in` |
| `github-app-private-key` | `GITHUB_APP_PRIVATE_KEY` | `enable_github_app` |
| `github-app-webhook-secret` | `GITHUB_APP_WEBHOOK_SECRET` | `enable_github_app` |
| `active-record-encryption-primary-key` | `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | `enable_active_record_encryption_keys` |
| `active-record-encryption-deterministic-key` | `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | `enable_active_record_encryption_keys` |
| `active-record-encryption-key-derivation-salt` | `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | `enable_active_record_encryption_keys` |

| Plain value | Variable the app reads | Flag |
| --- | --- | --- |
| `github_app_id` (committed) | `GITHUB_APP_ID` | `enable_github_app` |
| `github_app_slug` (committed) | `GITHUB_APP_SLUG` | `enable_github_app` |
| the recordings bucket | `RECORDINGS_BUCKET` | `enable_recordings_storage` |
| the recordings signer | `RECORDINGS_SIGNER_EMAIL` | `enable_recordings_storage` |

The bucket is `<project>-recordings-<env>`, with uniform bucket-level access and public access prevention enforced. The app's service account has `roles/storage.objectAdmin` on that bucket only. The signer (`recordings-signer-<env>`) has `roles/storage.objectViewer` on it, and the app may mint tokens for the signer and nothing else, so it can sign read-only URLs through the IAM Credentials API without a key file. Those two bindings are the bucket's whole IAM policy: Terraform sets it authoritatively, which removes the bindings GCS gives a new bucket for the project's owners, editors and viewers. Project-level roles such as `roles/storage.admin` still reach the bucket, and a binding added by hand is removed by the next apply.

### 1. Register one GitHub App per environment

GitHub's Terraform provider cannot create Apps, so register them at <https://github.com/organizations/activeagents/settings/apps/new> (or the manifest flow). One App serves both repository access through installations and Sign in with GitHub through user authorization.

- **Name**: `ActiveAgents (staging)` for staging, `ActiveAgents` for production.
- **Homepage URL**: the environment's public URL.
- **Callback URL**: the Sign in with GitHub callback, `https://<host>/auth/github/callback`, once for every host that serves the environment.
- **Setup URL**: leave empty until the installation flow ships. Callback and setup URLs can be added later without registering again.
- **Webhook**: generate the secret now so the registration does not change later, and leave **Active** unchecked until a receiver exists:

  ```bash
  WEBHOOK_SECRET=$(openssl rand -hex 32)
  printf %s "$WEBHOOK_SECRET" | pbcopy   # paste into the App's webhook secret field
  ```

- **Repository permissions**: Contents read and write, Pull requests read and write, Metadata read.
- **Account permissions**: Email addresses read (`/user/emails` needs it).
- Nothing else: no Workflows, Administration, Secrets or Actions permission.
- **Where can this GitHub App be installed?** Any account.

After creating it, note the App ID, the client ID and the slug (the last part of `https://github.com/apps/<slug>`), generate a client secret, and generate a private key (a `.pem` download).

### 2. Add the App's secrets

Run once per environment, with `DEPLOY_ENV=staging` or `DEPLOY_ENV=production`. `read -rs` keeps values out of your shell history.

```bash
DEPLOY_ENV=staging
PROJECT=active-agents-platform

gcloud secrets versions add "activeagents-$DEPLOY_ENV-github-app-private-key" --project=$PROJECT \
  --data-file=path/to/the-app.private-key.pem
rm path/to/the-app.private-key.pem

read -rs CLIENT_ID && printf %s "$CLIENT_ID" |
  gcloud secrets versions add "activeagents-$DEPLOY_ENV-github-app-client-id" --project=$PROJECT --data-file=-
read -rs CLIENT_SECRET && printf %s "$CLIENT_SECRET" |
  gcloud secrets versions add "activeagents-$DEPLOY_ENV-github-app-client-secret" --project=$PROJECT --data-file=-
printf %s "$WEBHOOK_SECRET" |
  gcloud secrets versions add "activeagents-$DEPLOY_ENV-github-app-webhook-secret" --project=$PROJECT --data-file=-

unset CLIENT_ID CLIENT_SECRET WEBHOOK_SECRET
```

### 3. Add the encryption keys

Without these variables, `config/initializers/active_record_encryption.rb` derives each key from `secret_key_base`. The explicit keys must **equal those derived values**. Fresh values from `bin/rails db:encryption:init` would leave every stored provider key, GitHub token and API key unreadable, and `ApiKey.authenticate` would stop finding keys. Once the explicit keys are live, rotating `secret_key_base` no longer touches stored credentials.

Compute each value once per environment from a checkout of the revision that environment runs. The command boots the app in production mode with the environment's master key, so `secret_key_base` comes from the same credentials as on Cloud Run; it needs no database. Boot output goes to stdout, so the value is written to file descriptor 3 and never printed. Boot errors still reach the terminal. All three values are computed before any is added, so a failed boot adds nothing:

```bash
DEPLOY_ENV=staging
PROJECT=active-agents-platform
export RAILS_MASTER_KEY="$(gcloud secrets versions access latest --secret="activeagents-$DEPLOY_ENV-rails-master-key" --project=$PROJECT)"

derive() {
  env -u SECRET_KEY_BASE -u SECRET_KEY_BASE_DUMMY RAILS_ENV=production bin/rails runner \
    'IO.for_fd(3).write(Rails.application.key_generator.generate_key("active_record_encryption.#{ARGV.first}", 32).unpack1("H*"))' \
    "$1" 3>&1 1>/dev/null
}

PRIMARY_KEY=$(derive primary_key)
DETERMINISTIC_KEY=$(derive deterministic_key)
KEY_DERIVATION_SALT=$(derive key_derivation_salt)

if [[ "$PRIMARY_KEY$DETERMINISTIC_KEY$KEY_DERIVATION_SALT" =~ ^[0-9a-f]{192}$ ]]; then
  printf %s "$PRIMARY_KEY" |
    gcloud secrets versions add "activeagents-$DEPLOY_ENV-active-record-encryption-primary-key" --project=$PROJECT --data-file=-
  printf %s "$DETERMINISTIC_KEY" |
    gcloud secrets versions add "activeagents-$DEPLOY_ENV-active-record-encryption-deterministic-key" --project=$PROJECT --data-file=-
  printf %s "$KEY_DERIVATION_SALT" |
    gcloud secrets versions add "activeagents-$DEPLOY_ENV-active-record-encryption-key-derivation-salt" --project=$PROJECT --data-file=-
else
  echo "The app did not produce three keys; nothing was added"
fi

unset PRIMARY_KEY DETERMINISTIC_KEY KEY_DERIVATION_SALT RAILS_MASTER_KEY
```

The explicit keys must be live in both environments before the platform takes an engine release that adds encrypted columns.

### 4. Turn the values on

Commit `terraform/environments/<env>/github_app.auto.tfvars` (staging first, then production) and let the deploy workflow apply it. Turn a flag on only once every secret it reads has a version:

```hcl
# GitHub App and encryption keys for this environment. See
# docs/infrastructure/gcp-cicd-setup.md before changing a flag.
github_app_id                        = "123456"
github_app_slug                      = "activeagents-staging"
enable_github_app                    = true
enable_github_sign_in                = true
enable_active_record_encryption_keys = true
```

`enable_recordings_storage = true` goes in the same file once the app stores recordings on GCS.

### 5. Check

Right after the deploy that turns on `enable_active_record_encryption_keys`:

- an API key created before the deploy still authenticates against `/v1/traces`;
- a provider key saved before the deploy still works from Settings.

If either fails, set the flag back to `false` at once. The app then derives its keys again, but anything encrypted while the wrong keys were live stays unreadable.

The `github_app_install_url` output of the environment shows where an account installs the App.

## Incus host: sandbox egress and IAM

`terraform/modules/incus-host` (used by `terraform/environments/sandbox-staging`, which no workflow applies) keeps code running in a sandbox away from cloud credentials and private networks:

- **Egress ACL.** `scripts/setup-incus-host.sh egress-acl` creates the `sandbox-egress` network ACL and attaches it to `incusbr0`, so it covers every container on the bridge whichever profile created it. It rejects `169.254.0.0/16` (which holds the metadata server behind `metadata.google.internal`), `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` and every address of the host. Incus accepts DNS and DHCP to the host ahead of any ACL rule, and replies to connections the host opens, so both keep working. Everything else, including the public internet, is allowed. The ranges are the module's `sandbox_egress_reject_ranges`. IPv6 stays off on the bridge, and the script refuses to run if it is on.
- **IAM.** The host's service account holds only `roles/logging.logWriter` and `roles/monitoring.metricWriter` at project level. It may add versions to `incus-client-cert-<env>` and `incus-client-key-<env>`, which Terraform creates, and read nothing. The app's service account (`app_service_account`) may read those two secrets. A precondition on `host_project_roles` accepts only the log, metric and trace writer roles. `scripts/check-incus-host-iam.sh` fails CI on any other project-, folder- or organization-level IAM resource in the module. Outside the module it matches by name: it fails on such a resource only when the resource mentions `incus_host` or `incus-host`.

The VM keeps the startup script it was created with (`metadata_startup_script` is in `ignore_changes`), so a running host that predates the ACL gets it from step 4 below.

### Apply

1. `cd terraform/environments/sandbox-staging && terraform init && terraform plan`. Check that `project_id` is the project the host actually runs in.
2. Look for `incus-client-cert-staging` and `incus-client-key-staging` with `gcloud secrets describe <name> --project=<project_id>`. If both exist, an earlier host or a person created them outside Terraform: run `terraform apply -var adopt_existing_incus_secrets=true` once to import both. If neither exists, run `terraform apply`. If only one exists, delete it, then run `terraform apply`.
3. If `gcloud secrets versions list incus-client-cert-staging --project=<project_id>` lists no version, the running host never published its credentials: the project-level role it held could not create secrets, so its first boot stopped there. Publish the certificate and key it already trusts, which its new `secretVersionAdder` binding allows:

   ```bash
   gcloud compute ssh incus-host-staging --project=<project_id> --zone=<zone> --command='
     sudo gcloud secrets versions add incus-client-cert-staging --project=<project_id> --data-file=/etc/incus/certs/client.crt &&
     sudo gcloud secrets versions add incus-client-key-staging --project=<project_id> --data-file=/etc/incus/certs/client.key'
   ```

4. From the repository root, run the command printed by `terraform -chdir=terraform/environments/sandbox-staging output -raw egress_acl_command`. It streams `scripts/setup-incus-host.sh` to the host over `gcloud compute ssh` and runs its `egress-acl` step. Add `--tunnel-through-iap` if the host takes no direct SSH.

A host built from the module applies the ACL itself, before any container exists.

The ACL lists the host's addresses as they were when it was applied. The host's external IP is ephemeral and changes when the VM is stopped and started, so run step 4 again after that.

### Check from a container

On the host:

```bash
incus launch images:ubuntu/22.04 egress-check --project agent-sandboxes --profile default --profile sandbox-restricted
incus exec egress-check --project agent-sandboxes -- bash -c '
  apt-get update -qq && apt-get install -y -qq git ruby python3 >/dev/null
  probe() { timeout 5 bash -c "</dev/tcp/$1/$2" 2>/dev/null && echo "REACHABLE $1:$2" || echo "rejected  $1:$2"; }
  probe 169.254.169.254 80
  probe metadata.google.internal 80
  probe 10.10.0.1 443
  probe 172.16.0.1 443
  probe 192.168.0.1 443
  probe 10.100.0.1 8443      # the host, on the bridge
  probe 10.100.0.1 22
  git ls-remote https://github.com/rails/rails HEAD && gem fetch rack
'
incus exec egress-check --project agent-sandboxes -- systemd-run --unit=egress-check-http python3 -m http.server 8080
sleep 2
curl -sS -o /dev/null -w '%{http_code}\n' "http://$(incus list egress-check --project agent-sandboxes -c 4 -f csv | cut -d' ' -f1):8080/"
incus delete egress-check --project agent-sandboxes --force
```

Every probe prints `rejected`, `apt-get`, `git ls-remote` and `gem fetch` succeed (so DNS works), and the final `curl` from the host gets `200`. Probe the host's VPC address (`hostname -I` on the host) and its external IP the same way.

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
