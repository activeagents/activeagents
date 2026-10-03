#!/usr/bin/env bash
#
# Fails when Terraform could grant the Incus host's service account a role at
# project, folder or organization level anywhere other than
# google_project_iam_member.host_project_roles in terraform/modules/incus-host.
# That resource's precondition refuses every role matching the module's
# forbidden_host_project_roles, so the host can only reach a secret or a
# bucket through a binding on that one secret or bucket.
#
#   scripts/check-incus-host-iam.sh [terraform-dir]

set -euo pipefail

root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/terraform}"

# The awk program is single-quoted on purpose: awk, not the shell, expands it.
# shellcheck disable=SC2016
violations=$(
  find "$root" -name '*.tf' -not -path '*/.terraform/*' -print0 |
    xargs -0 awk '
      FNR == 1 { in_module = (FILENAME ~ /\/modules\/incus-host\/[^\/]+\.tf$/) }

      /^resource "google_(project|folder|organization)_iam_(member|binding|policy)"/ {
        collecting = 1; block = ""; depth = 0; opened = 0
        type = $2; name = $3; start = FNR
      }

      collecting {
        block = block "\n" $0
        opened += gsub(/\{/, "{")
        depth += gsub(/\{/, "{") - gsub(/\}/, "}")
        if (opened && depth <= 0) {
          collecting = 0
          allowed = in_module && type == "\"google_project_iam_member\"" && name == "\"host_project_roles\""
          # Inside the module every broad grant is suspect; elsewhere only one
          # that names the host account.
          if (!allowed && (in_module || block ~ /incus_host|incus-host/)) {
            printf "%s:%d: resource %s %s\n", FILENAME, start, type, name
          }
        }
      }
    '
)

if [[ -n "$violations" ]]; then
  echo "The Incus host service account may only get project-level roles through"
  echo "google_project_iam_member.host_project_roles in terraform/modules/incus-host."
  echo "Grant secret or bucket access on that one resource instead:"
  echo "$violations"
  exit 1
fi

echo "Incus host IAM: no project-, folder- or organization-level grant outside host_project_roles"
