#!/bin/bash
# GCP Infrastructure Setup Script for ActiveAgents
# This script sets up all the required GCP resources for CI/CD

set -e

# Configuration
PROJECT_ID="active-agents-platform"
REGION="us-central1"
GITHUB_REPO="activeagents/activeagents"

echo "🚀 Setting up GCP infrastructure for ActiveAgents"
echo "Project: $PROJECT_ID"
echo "Region: $REGION"
echo ""

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo "❌ gcloud CLI is not installed. Please install it first:"
    echo "   https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Check if logged in
ACCOUNT=$(gcloud config get-value account 2>/dev/null)
if [ -z "$ACCOUNT" ]; then
    echo "❌ Not logged in to gcloud. Running 'gcloud auth login'..."
    gcloud auth login
fi

echo "✅ Logged in as: $ACCOUNT"
echo ""

# Set project
echo "📁 Setting project to $PROJECT_ID..."
gcloud config set project $PROJECT_ID

# Enable required APIs
echo ""
echo "🔌 Enabling required GCP APIs..."
APIS=(
    "run.googleapis.com"
    "sqladmin.googleapis.com"
    "secretmanager.googleapis.com"
    "cloudresourcemanager.googleapis.com"
    "iam.googleapis.com"
    "compute.googleapis.com"
    "vpcaccess.googleapis.com"
    "servicenetworking.googleapis.com"
    "artifactregistry.googleapis.com"
    "cloudtasks.googleapis.com"
    "pubsub.googleapis.com"
    "iamcredentials.googleapis.com"
)

for API in "${APIS[@]}"; do
    echo "  Enabling $API..."
    gcloud services enable $API --quiet
done
echo "✅ APIs enabled"

# Create Terraform state bucket
echo ""
echo "🪣 Creating Terraform state bucket..."
BUCKET_NAME="${PROJECT_ID}-terraform-state"
if gsutil ls -b gs://$BUCKET_NAME &> /dev/null; then
    echo "  Bucket gs://$BUCKET_NAME already exists"
else
    gsutil mb -p $PROJECT_ID -l $REGION gs://$BUCKET_NAME
    gsutil versioning set on gs://$BUCKET_NAME
    echo "  Created gs://$BUCKET_NAME with versioning enabled"
fi
echo "✅ Terraform state bucket ready"

# Create service account for GitHub Actions
echo ""
echo "👤 Creating GitHub Actions service account..."
SA_NAME="github-actions"
SA_EMAIL="$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"

if gcloud iam service-accounts describe $SA_EMAIL &> /dev/null; then
    echo "  Service account $SA_EMAIL already exists"
else
    gcloud iam service-accounts create $SA_NAME \
        --display-name="GitHub Actions" \
        --project=$PROJECT_ID
    echo "  Created service account $SA_EMAIL"
fi

# Grant required roles
echo ""
echo "🔐 Granting IAM roles to service account..."
ROLES=(
    "roles/run.admin"
    "roles/iam.serviceAccountUser"
    "roles/storage.admin"
    "roles/artifactregistry.admin"
    "roles/secretmanager.admin"
    "roles/cloudsql.admin"
    "roles/compute.networkAdmin"
    "roles/vpcaccess.admin"
    "roles/cloudtasks.admin"
    "roles/pubsub.admin"
)

for ROLE in "${ROLES[@]}"; do
    echo "  Granting $ROLE..."
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:$SA_EMAIL" \
        --role="$ROLE" \
        --quiet > /dev/null
done
echo "✅ IAM roles granted"

# Set up Workload Identity Federation
echo ""
echo "🔗 Setting up Workload Identity Federation..."

# Create workload identity pool
POOL_NAME="github"
if gcloud iam workload-identity-pools describe $POOL_NAME --location="global" &> /dev/null; then
    echo "  Workload identity pool '$POOL_NAME' already exists"
else
    gcloud iam workload-identity-pools create $POOL_NAME \
        --project=$PROJECT_ID \
        --location="global" \
        --display-name="GitHub Actions"
    echo "  Created workload identity pool '$POOL_NAME'"
fi

# Create OIDC provider
PROVIDER_NAME="github-actions"
if gcloud iam workload-identity-pools providers describe $PROVIDER_NAME \
    --location="global" \
    --workload-identity-pool=$POOL_NAME &> /dev/null; then
    echo "  Provider '$PROVIDER_NAME' already exists"
else
    gcloud iam workload-identity-pools providers create-oidc $PROVIDER_NAME \
        --project=$PROJECT_ID \
        --location="global" \
        --workload-identity-pool=$POOL_NAME \
        --display-name="GitHub Actions" \
        --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
        --issuer-uri="https://token.actions.githubusercontent.com"
    echo "  Created OIDC provider '$PROVIDER_NAME'"
fi

# Get workload identity provider resource name
WORKLOAD_IDENTITY_PROVIDER=$(gcloud iam workload-identity-pools providers describe $PROVIDER_NAME \
    --project=$PROJECT_ID \
    --location="global" \
    --workload-identity-pool=$POOL_NAME \
    --format="value(name)")

# Allow GitHub to impersonate service account
echo "  Binding GitHub repository to service account..."
gcloud iam service-accounts add-iam-policy-binding $SA_EMAIL \
    --project=$PROJECT_ID \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/${WORKLOAD_IDENTITY_PROVIDER}/attribute.repository/${GITHUB_REPO}" \
    --quiet > /dev/null

echo "✅ Workload Identity Federation configured"

# Update Terraform backend configuration
echo ""
echo "📝 Updating Terraform backend configuration..."

# Update staging backend
cat > terraform/environments/staging/backend.tf << EOF
terraform {
  backend "gcs" {
    bucket = "${BUCKET_NAME}"
    prefix = "staging"
  }
}
EOF

# Update production backend
cat > terraform/environments/production/backend.tf << EOF
terraform {
  backend "gcs" {
    bucket = "${BUCKET_NAME}"
    prefix = "production"
  }
}
EOF

echo "✅ Terraform backends configured"

# Output summary
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "                    🎉 Setup Complete!                          "
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "📋 GitHub Secrets to configure:"
echo ""
echo "   GCP_WORKLOAD_IDENTITY_PROVIDER:"
echo "   $WORKLOAD_IDENTITY_PROVIDER"
echo ""
echo "   GCP_SERVICE_ACCOUNT:"
echo "   $SA_EMAIL"
echo ""
echo "📍 Next steps:"
echo ""
echo "   1. Add the above secrets to GitHub:"
echo "      Repository → Settings → Secrets and variables → Actions"
echo ""
echo "   2. Add RAILS_MASTER_KEY secret (from config/master.key)"
echo ""
echo "   3. Initialize Terraform:"
echo "      cd terraform/environments/staging"
echo "      terraform init"
echo "      terraform plan -var-file=terraform.tfvars.example"
echo ""
echo "   4. Push to main branch to trigger first deployment"
echo ""
echo "═══════════════════════════════════════════════════════════════"
