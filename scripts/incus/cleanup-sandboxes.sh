#!/bin/bash
#
# Removes the sandbox containers whose time is up. Installed on an Incus host
# as /usr/local/bin/cleanup-sandboxes.sh and run from cron every five minutes
# (scripts/setup-incus-host.sh, scripts/build-app-runtime-image.sh and the
# Terraform incus-host module install it).
#
# A container labelled user.expires_at (an ISO 8601 time IncusSandboxService
# copies from its session) is removed once that time has passed. One without
# the label is removed MAX_AGE seconds after its user.created_at, and one with
# neither label is left alone.
set -uo pipefail

PROJECT="${INCUS_PROJECT:-agent-sandboxes}"
MAX_AGE="${MAX_AGE:-900}"

now=$(date +%s)
containers=$(incus list --project "$PROJECT" --format csv -c n 2>/dev/null | grep '^sandbox-') || exit 0

for container in $containers; do
  expires=$(incus config get "$container" user.expires_at --project "$PROJECT" 2>/dev/null)
  if [[ -n $expires ]]; then
    deadline=$(date -d "$expires" +%s 2>/dev/null) || {
      logger "cleanup-sandboxes: $container has an unreadable user.expires_at ($expires); left alone"
      continue
    }
  else
    created=$(incus config get "$container" user.created_at --project "$PROJECT" 2>/dev/null)
    [[ -n $created ]] || continue
    created_at=$(date -d "$created" +%s 2>/dev/null) || continue
    deadline=$((created_at + MAX_AGE))
  fi

  if (( now > deadline )); then
    incus delete --force "$container" --project "$PROJECT" 2>/dev/null &&
      logger "cleanup-sandboxes: removed $container (expired $(date -u -d "@$deadline" '+%Y-%m-%dT%H:%M:%SZ'))"
  fi
done
