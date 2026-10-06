#!/bin/bash
#
# Builds or rebuilds the sandbox-app-runtime image on an Incus host, the image
# IncusSandboxService boots a checkout from, and installs the reaper that
# keeps a checkout until its session expires. Run it as root from a checkout
# of this repository, on a new host or one that is already serving:
#
#   sudo scripts/build-app-runtime-image.sh
#
# The image is provisioned by docker/sandbox/app-runtime/provision.sh in a
# builder container and published under the alias sandbox-app-runtime, with
# the image property boot_spec_version set to the version of the boot spec
# its sandbox-app-boot runs. IncusSandboxService reports app_runtime_supported
# only while that property matches the version it writes. Containers already
# running keep their own copy; the previous image is deleted once the new one
# holds the alias.
#
# Environment:
#   INCUS_PROJECT  the sandbox project (default agent-sandboxes)
#   BASE_IMAGE     what the builder launches from (default images:ubuntu/24.04)
#   RUBY_SERIES    the Ruby series to preinstall (default "3.2 3.3 3.4")
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT=${INCUS_PROJECT:-agent-sandboxes}
PROFILE=sandbox-restricted
ALIAS=sandbox-app-runtime
BASE_IMAGE=${BASE_IMAGE:-images:ubuntu/24.04}
SOURCE="$ROOT/docker/sandbox/app-runtime"
# Not named sandbox-*: the reapers remove those.
BUILDER="app-runtime-builder-$(date +%s)"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
  log "ERROR: $*" >&2
  exit 1
}

[[ $EUID -eq 0 ]] || error "run this as root"
command -v incus >/dev/null || error "incus is not installed"
incus project show "$PROJECT" >/dev/null 2>&1 || error "the Incus project $PROJECT does not exist; run scripts/setup-incus-host.sh first"

VERSION=$(sed -n 's/^BOOT_SPEC_VERSION = \([0-9][0-9]*\)$/\1/p' "$SOURCE/sandbox-app-boot")
[[ -n $VERSION ]] || error "cannot read BOOT_SPEC_VERSION from $SOURCE/sandbox-app-boot"

install_reaper() {
  log "Installing the sandbox reaper"
  install -m 0755 "$ROOT/scripts/incus/cleanup-sandboxes.sh" /usr/local/bin/cleanup-sandboxes.sh
  echo "*/5 * * * * root INCUS_PROJECT=$PROJECT /usr/local/bin/cleanup-sandboxes.sh" > /etc/cron.d/incus-sandbox-cleanup
}

cleanup_builder() {
  incus delete --force "$BUILDER" --project "$PROJECT" >/dev/null 2>&1 || true
}

build_image() {
  log "Launching $BUILDER from $BASE_IMAGE"
  trap cleanup_builder EXIT
  # The restricted profile, with the host's CPUs: compiling three Rubies is
  # the slow part of the build.
  incus launch "$BASE_IMAGE" "$BUILDER" --project "$PROJECT" --profile "$PROFILE" \
    -c limits.cpu="$(nproc)" -c limits.memory=8GB -c limits.processes=4000

  log "Waiting for the builder's network"
  incus exec "$BUILDER" --project "$PROJECT" -- \
    timeout 120 sh -c 'until getent hosts archive.ubuntu.com >/dev/null; do sleep 2; done'

  incus file push --recursive "$SOURCE" "$BUILDER/tmp/" --project "$PROJECT"
  incus exec "$BUILDER" --project "$PROJECT" -- env SOURCE_DIR=/tmp/app-runtime \
    RUBY_SERIES="${RUBY_SERIES:-3.2 3.3 3.4}" bash /tmp/app-runtime/provision.sh
  incus exec "$BUILDER" --project "$PROJECT" -- rm -rf /tmp/app-runtime

  local previous current
  previous=$(incus image alias list --project "$PROJECT" --format csv | awk -F, -v alias="$ALIAS" '$1 == alias { print $2 }')

  log "Publishing $ALIAS (boot spec version $VERSION)"
  incus stop "$BUILDER" --project "$PROJECT"
  incus publish "$BUILDER" --project "$PROJECT" --alias "$ALIAS" --reuse \
    boot_spec_version="$VERSION" description="Sandbox app runtime (boot spec $VERSION)"

  current=$(incus image alias list --project "$PROJECT" --format csv | awk -F, -v alias="$ALIAS" '$1 == alias { print $2 }')
  if [[ -n $previous && $previous != "$current" ]]; then
    log "Deleting the previous image $previous"
    incus image delete "$previous" --project "$PROJECT" || log "Could not delete $previous; remove it by hand"
  fi
}

install_reaper
build_image
log "$ALIAS is ready: check it with bin/rails incus:preflight"
