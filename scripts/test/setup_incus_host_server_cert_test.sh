#!/usr/bin/env bash
#
# Tests configure_server_cert and publish_server_cert in
# scripts/setup-incus-host.sh with systemctl, incus, hostname and gcloud
# replaced by stubs, against real openssl, so it runs without Incus or root.
#
#   bash scripts/test/setup_incus_host_server_cert_test.sh

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

# A certificate shaped like the one Incus generates for its server: the host
# name and the loopback addresses, nothing else.
generated_cert() {
  rm -rf "$WORK/var" && mkdir -p "$WORK/var"
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:secp384r1 -nodes -days 1 \
    -subj "/O=Linux Containers/CN=root@incus-host-staging" \
    -addext "subjectAltName=DNS:incus-host-staging,IP:127.0.0.1,IP:::1" \
    -keyout "$WORK/var/server.key" -out "$WORK/var/server.crt" 2>/dev/null
}

# Runs the named functions in a subshell against the stubs. Calls land in
# $WORK/calls and output in $WORK/output.
run_steps() {
  : > "$WORK/calls"
  # The stubs are called by the sourced script, not here.
  # shellcheck disable=SC2329
  (
    # shellcheck source=SCRIPTDIR/../setup-incus-host.sh
    source "$SCRIPT"
    INCUS_VAR_DIR="$WORK/var"
    INCUS_SERVER_CERT_SECRET="${STUB_SECRET:-}"
    INCUS_SECRET_PROJECT="${STUB_PROJECT:-}"

    systemctl() { echo "systemctl $*" >> "$WORK/calls"; }
    incus() { echo "incus $*" >> "$WORK/calls"; }
    hostname() { echo incus-host-staging; }
    gcloud() { echo "gcloud $*" >> "$WORK/calls"; }

    for step in "$@"; do
      eval "$step"
    done
  ) > "$WORK/output" 2>&1
}

current="generated certificate gains the address"
generated_cert
original=$(openssl x509 -in "$WORK/var/server.crt" -noout -fingerprint -sha256)
run_steps 'configure_server_cert 10.10.0.2'
status=$?
[[ $status -eq 0 ]] || fail "exited $status: $(cat "$WORK/output")"
openssl x509 -in "$WORK/var/server.crt" -noout -checkip 10.10.0.2 | grep -q " does match" ||
  fail "server.crt does not name 10.10.0.2"
openssl x509 -in "$WORK/var/server.crt" -noout -ext subjectAltName > "$WORK/san"
assert_contains "$WORK/san" "DNS:incus-host-staging"
assert_contains "$WORK/san" "IP Address:127.0.0.1"
[[ "$(openssl x509 -in "$WORK/var/server.crt.generated" -noout -fingerprint -sha256)" == "$original" ]] ||
  fail "the generated certificate was not kept as server.crt.generated"
[[ "$(stat -c %a "$WORK/var/server.key")" == 600 ]] || fail "server.key is not 0600"
[[ "$(openssl x509 -in "$WORK/var/server.crt" -noout -pubkey)" == "$(openssl pkey -in "$WORK/var/server.key" -pubout)" ]] ||
  fail "server.crt and server.key do not match"
assert_contains "$WORK/calls" "systemctl restart incus"
assert_contains "$WORK/calls" "incus admin waitready --timeout=60"

current="a certificate that names the address stays"
replaced=$(openssl x509 -in "$WORK/var/server.crt" -noout -fingerprint -sha256)
run_steps 'configure_server_cert 10.10.0.2'
[[ "$(openssl x509 -in "$WORK/var/server.crt" -noout -fingerprint -sha256)" == "$replaced" ]] ||
  fail "server.crt changed although it already named the address"
assert_not_contains "$WORK/calls" "systemctl restart incus"

current="a second address replaces it but keeps the first backup"
run_steps 'configure_server_cert 10.10.0.3'
openssl x509 -in "$WORK/var/server.crt" -noout -checkip 10.10.0.3 | grep -q " does match" ||
  fail "server.crt does not name 10.10.0.3"
[[ "$(openssl x509 -in "$WORK/var/server.crt.generated" -noout -fingerprint -sha256)" == "$original" ]] ||
  fail "server.crt.generated no longer holds the certificate Incus generated"

current="refuses an address that is not IPv4"
generated_cert
run_steps 'configure_server_cert incus-host-staging'
[[ $? -ne 0 ]] || fail "accepted a host name"
assert_contains "$WORK/output" "Not an IPv4 address"
assert_not_contains "$WORK/calls" "systemctl restart incus"

current="refuses to run before Incus made a certificate"
rm -f "$WORK/var/server.crt"
run_steps 'configure_server_cert 10.10.0.2'
[[ $? -ne 0 ]] || fail "ran without server.crt"
assert_contains "$WORK/output" "initialize Incus first"

current="publishes nothing without a secret"
generated_cert
run_steps publish_server_cert
assert_not_contains "$WORK/calls" "gcloud"
assert_contains "$WORK/output" "INCUS_SERVER_CERT_SECRET is not set"

current="publishes server.crt to the secret"
STUB_SECRET=incus-server-cert-staging STUB_PROJECT=activeagents-staging run_steps publish_server_cert
assert_contains "$WORK/calls" "gcloud secrets versions add incus-server-cert-staging --project=activeagents-staging --data-file=$WORK/var/server.crt"

if [[ $failures -gt 0 ]]; then
  echo "setup-incus-host server certificate: $failures failure(s)"
  exit 1
fi

echo "setup-incus-host server certificate: all cases passed"
