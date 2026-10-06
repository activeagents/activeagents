#!/usr/bin/env bash
#
# Tests scripts/check-incus-host-iam.sh against copies of terraform/ with a
# forbidden grant added in each place it could appear.
#
#   bash scripts/test/check_incus_host_iam_test.sh

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECK="$REPO/scripts/check-incus-host-iam.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

failures=0

fresh_copy() {
  rm -rf "$WORK/terraform"
  mkdir -p "$WORK/terraform"
  (cd "$REPO/terraform" && find . -name '*.tf' -not -path '*/.terraform/*' -print0 | xargs -0 tar -cf - | tar -xf - -C "$WORK/terraform")
}

expect() {
  local outcome=$1 description=$2
  "$CHECK" "$WORK/terraform" > "$WORK/output" 2>&1
  local status=$?
  if [[ $outcome == pass && $status -ne 0 ]] || [[ $outcome == fail && $status -eq 0 ]]; then
    echo "  FAIL [$description]: expected the check to $outcome"
    cat "$WORK/output"
    failures=$((failures + 1))
  fi
}

fresh_copy
expect pass "current tree"

fresh_copy
cat >> "$WORK/terraform/modules/incus-host/main.tf" <<'EOF'

resource "google_project_iam_member" "incus_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${local.host_member}"
}
EOF
expect fail "another project grant inside the module"

fresh_copy
cat >> "$WORK/terraform/environments/sandbox-staging/main.tf" <<'EOF'

resource "google_project_iam_member" "incus_objects" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${module.incus_host.service_account_email}"
}
EOF
expect fail "a project grant to the module's account from a root"

fresh_copy
cat >> "$WORK/terraform/main.tf" <<'EOF'

resource "google_project_iam_binding" "secret_readers" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  members = [
    "serviceAccount:incus-host-staging@example-project.iam.gserviceaccount.com",
  ]
}
EOF
expect fail "an authoritative binding naming the host account"

fresh_copy
cat >> "$WORK/terraform/main.tf" <<'EOF'

resource "google_project_iam_member" "app_reads_logs" {
  project = var.project_id
  role    = "roles/logging.viewer"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}
EOF
expect pass "a project grant to another account"

if [[ $failures -gt 0 ]]; then
  echo "$failures case(s) failed"
  exit 1
fi
echo "check-incus-host-iam: all cases passed"
