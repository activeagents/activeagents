#!/usr/bin/env bash
#
# Tests configure_egress_acl in scripts/setup-incus-host.sh with incus, ip and
# curl replaced by stubs, so it runs without Incus or root.
#
#   bash scripts/test/setup_incus_host_egress_acl_test.sh

set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/setup-incus-host.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

failures=0
current=""

fail() {
  echo "  FAIL [$current]: $*"
  failures=$((failures + 1))
}

assert_contains() {
  grep -qF -- "$2" "$1" || fail "expected $(basename "$1") to contain: $2"
}

assert_not_contains() {
  if grep -qF -- "$2" "$1"; then fail "expected $(basename "$1") not to contain: $2"; fi
}

# Runs configure_egress_acl in a subshell against the stubs. Stub state comes
# from the STUB_* variables; calls land in $WORK/calls and the ACL YAML that
# `incus network acl edit` receives lands in $WORK/acl.yaml.
run_configure() {
  : > "$WORK/calls"
  : > "$WORK/acl.yaml"
  # The stubs are called by the sourced script, not here.
  # shellcheck disable=SC2329
  (
    # shellcheck source=SCRIPTDIR/../setup-incus-host.sh
    source "$SCRIPT"

    incus() {
      echo "incus $*" >> "$WORK/calls"
      case "$*" in
        "network get incusbr0 ipv6.address --project default") echo "${STUB_IPV6:-none}" ;;
        "network get incusbr0 security.acls --project default") echo "${STUB_ACLS:-}" ;;
        "network acl show sandbox-egress --project default") [[ "${STUB_ACL_EXISTS:-0}" == 1 ]] ;;
        "network acl edit sandbox-egress --project default") cat > "$WORK/acl.yaml" ;;
      esac
    }

    ip() {
      printf '%s\n' \
        "1: lo    inet 127.0.0.1/8 scope host lo" \
        "2: ens4    inet 10.10.0.5/32 metric 100 brd 10.10.0.5 scope global dynamic ens4" \
        "3: incusbr0    inet 10.100.0.1/24 scope global incusbr0"
    }

    curl() {
      if [[ -n "${STUB_EXTERNAL_IP:-}" ]]; then printf '%s' "$STUB_EXTERNAL_IP"; else return 22; fi
    }

    configure_egress_acl
  ) > "$WORK/output" 2>&1
}

current="fresh host"
STUB_EXTERNAL_IP=34.1.2.3 run_configure
status=$?
[[ $status -eq 0 ]] || fail "exited $status: $(cat "$WORK/output")"
assert_contains "$WORK/calls" "incus network acl create sandbox-egress --project default"
assert_contains "$WORK/acl.yaml" 'destination: "169.254.0.0/16,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"'
assert_contains "$WORK/acl.yaml" 'destination: "10.10.0.5/32,10.100.0.1/32,34.1.2.3/32"'
assert_contains "$WORK/acl.yaml" "action: reject"
assert_contains "$WORK/acl.yaml" "ingress: []"
assert_not_contains "$WORK/acl.yaml" "127.0.0.1"
assert_contains "$WORK/calls" "incus network set incusbr0 --project default security.acls=sandbox-egress security.acls.default.egress.action=allow security.acls.default.ingress.action=allow"

current="no metadata server"
run_configure
status=$?
[[ $status -eq 0 ]] || fail "exited $status: $(cat "$WORK/output")"
assert_contains "$WORK/acl.yaml" 'destination: "10.10.0.5/32,10.100.0.1/32"'

current="run again"
STUB_ACL_EXISTS=1 STUB_ACLS=sandbox-egress run_configure
status=$?
[[ $status -eq 0 ]] || fail "exited $status: $(cat "$WORK/output")"
assert_not_contains "$WORK/calls" "network acl create"
assert_contains "$WORK/calls" "security.acls=sandbox-egress security.acls.default.egress.action=allow"

current="keeps other ACLs"
STUB_ACL_EXISTS=1 STUB_ACLS=operator-acl run_configure
status=$?
[[ $status -eq 0 ]] || fail "exited $status: $(cat "$WORK/output")"
assert_contains "$WORK/calls" "security.acls=operator-acl,sandbox-egress "

current="custom ranges"
SANDBOX_EGRESS_REJECT=169.254.0.0/16,100.64.0.0/10 run_configure
status=$?
[[ $status -eq 0 ]] || fail "exited $status: $(cat "$WORK/output")"
assert_contains "$WORK/acl.yaml" 'destination: "169.254.0.0/16,100.64.0.0/10"'

current="refuses IPv6 on the bridge"
STUB_IPV6=fd42:1::1/64 run_configure
status=$?
[[ $status -ne 0 ]] || fail "expected a non-zero exit"
assert_contains "$WORK/output" "has IPv6"
assert_not_contains "$WORK/calls" "network acl edit"

current="refuses a range that is not IPv4 CIDR"
SANDBOX_EGRESS_REJECT=169.254.0.0/16,metadata.google.internal run_configure
status=$?
[[ $status -ne 0 ]] || fail "expected a non-zero exit"
assert_contains "$WORK/output" "Not an IPv4 CIDR"
assert_not_contains "$WORK/calls" "network acl edit"

if [[ $failures -gt 0 ]]; then
  echo "$failures assertion(s) failed"
  exit 1
fi
echo "setup-incus-host egress ACL: all cases passed"
