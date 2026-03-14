#!/bin/bash
#
# Setup script for Incus sandbox host
#
# This script configures a Linux server to run agent sandbox containers
# using Incus. Works on Ubuntu 22.04+, Debian 12+, or any distro with
# Incus packages available.
#
# Usage:
#   curl -fsSL https://your-domain.com/setup-incus-host.sh | sudo bash
#   or
#   sudo ./setup-incus-host.sh
#
# After setup:
#   - Incus will be running with a "agent-sandboxes" project
#   - A restricted sandbox profile will be created
#   - Remote access will be configured (optional)
#
set -euo pipefail

# Configuration
INCUS_PROJECT="agent-sandboxes"
STORAGE_POOL="default"
NETWORK_NAME="incusbr0"
SANDBOX_PROFILE="sandbox-restricted"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
  log "ERROR: $*" >&2
  exit 1
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
  fi
}

detect_distro() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    DISTRO=$ID
    VERSION=$VERSION_ID
  else
    error "Cannot detect distribution"
  fi
  log "Detected: $DISTRO $VERSION"
}

install_incus() {
  log "Installing Incus..."

  case $DISTRO in
    ubuntu|debian)
      # Add Zabbly repository (recommended for latest Incus)
      if [[ ! -f /etc/apt/sources.list.d/zabbly-incus-stable.list ]]; then
        curl -fsSL https://pkgs.zabbly.com/key.asc | gpg --dearmor -o /etc/apt/keyrings/zabbly.gpg

        cat > /etc/apt/sources.list.d/zabbly-incus-stable.list << EOF
deb [signed-by=/etc/apt/keyrings/zabbly.gpg] https://pkgs.zabbly.com/incus/stable $(lsb_release -cs) main
EOF
      fi

      apt-get update
      apt-get install -y incus incus-tools
      ;;

    fedora|rhel|centos|rocky|alma)
      dnf copr enable -y ganto/incus
      dnf install -y incus
      ;;

    arch|manjaro)
      pacman -Sy --noconfirm incus
      ;;

    *)
      error "Unsupported distribution: $DISTRO"
      ;;
  esac

  log "Incus installed successfully"
}

configure_incus() {
  log "Configuring Incus..."

  # Enable and start Incus
  systemctl enable --now incus

  # Check if already initialized
  if incus storage list 2>/dev/null | grep -q "$STORAGE_POOL"; then
    log "Incus already initialized, skipping..."
    return
  fi

  # Initialize with preseed
  cat << EOF | incus admin init --preseed
config:
  core.https_address: "[::]:8443"
  images.auto_update_interval: 6

networks:
  - name: ${NETWORK_NAME}
    type: bridge
    config:
      ipv4.address: 10.100.0.1/24
      ipv4.nat: "true"
      ipv4.dhcp.ranges: 10.100.0.10-10.100.0.254
      ipv6.address: none

storage_pools:
  - name: ${STORAGE_POOL}
    driver: dir
    config:
      source: /var/lib/incus/storage-pools/default

profiles:
  - name: default
    config: {}
    devices:
      eth0:
        name: eth0
        network: ${NETWORK_NAME}
        type: nic
      root:
        path: /
        pool: ${STORAGE_POOL}
        type: disk
        size: 10GB

projects: []
EOF

  log "Incus configured successfully"
}

create_sandbox_project() {
  log "Creating sandbox project..."

  if incus project list | grep -q "$INCUS_PROJECT"; then
    log "Project $INCUS_PROJECT already exists"
    return
  fi

  incus project create "$INCUS_PROJECT" \
    -c features.images=true \
    -c features.profiles=true

  log "Project $INCUS_PROJECT created"
}

create_sandbox_profile() {
  log "Creating sandbox security profile..."

  # Switch to sandbox project
  incus project switch "$INCUS_PROJECT"

  if incus profile list | grep -q "$SANDBOX_PROFILE"; then
    log "Profile $SANDBOX_PROFILE already exists"
    incus project switch default
    return
  fi

  incus profile create "$SANDBOX_PROFILE"

  # Configure security restrictions
  incus profile set "$SANDBOX_PROFILE" security.nesting=false
  incus profile set "$SANDBOX_PROFILE" security.privileged=false
  incus profile set "$SANDBOX_PROFILE" security.idmap.isolated=true

  # Resource limits
  incus profile set "$SANDBOX_PROFILE" limits.cpu=2
  incus profile set "$SANDBOX_PROFILE" limits.memory=2GB
  incus profile set "$SANDBOX_PROFILE" limits.processes=500

  # Network device
  incus profile device add "$SANDBOX_PROFILE" eth0 nic network="$NETWORK_NAME" name=eth0

  # Root disk
  incus profile device add "$SANDBOX_PROFILE" root disk pool="$STORAGE_POOL" path=/ size=10GB

  incus project switch default

  log "Profile $SANDBOX_PROFILE created"
}

create_sandbox_images() {
  log "Creating sandbox container images..."

  incus project switch "$INCUS_PROJECT"

  # Base image
  if ! incus image list --format csv | grep -q "sandbox-base"; then
    log "Building sandbox-base image..."

    incus launch images:ubuntu/22.04 sandbox-base-builder
    sleep 5

    # Install base packages
    incus exec sandbox-base-builder -- bash -c "
      apt-get update
      apt-get install -y curl wget git python3 python3-pip nodejs npm
      apt-get clean
      rm -rf /var/lib/apt/lists/*

      # Create sandbox user
      useradd -m -s /bin/bash sandbox
      echo 'sandbox ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/sandbox
    "

    incus stop sandbox-base-builder
    incus publish sandbox-base-builder --alias sandbox-base
    incus delete sandbox-base-builder

    log "sandbox-base image created"
  fi

  # Playwright image (for browser automation)
  if ! incus image list --format csv | grep -q "sandbox-playwright"; then
    log "Building sandbox-playwright image..."

    incus launch sandbox-base sandbox-playwright-builder
    sleep 5

    incus exec sandbox-playwright-builder -- bash -c "
      npm install -g playwright
      npx playwright install chromium --with-deps
      npx playwright install-deps
    "

    incus stop sandbox-playwright-builder
    incus publish sandbox-playwright-builder --alias sandbox-playwright
    incus delete sandbox-playwright-builder

    log "sandbox-playwright image created"
  fi

  incus project switch default

  log "Sandbox images ready"
}

setup_firewall() {
  log "Configuring firewall..."

  if command -v ufw &>/dev/null; then
    # Allow Incus API (for remote access)
    ufw allow 8443/tcp comment "Incus API"

    # Allow container traffic
    ufw allow in on "$NETWORK_NAME"
    ufw allow out on "$NETWORK_NAME"
  elif command -v firewall-cmd &>/dev/null; then
    firewall-cmd --permanent --add-port=8443/tcp
    firewall-cmd --permanent --zone=trusted --add-interface="$NETWORK_NAME"
    firewall-cmd --reload
  fi

  log "Firewall configured"
}

setup_remote_access() {
  log "Setting up remote access..."

  # Generate trust password
  TRUST_PASSWORD=$(openssl rand -base64 32)

  incus config set core.trust_password "$TRUST_PASSWORD"

  # Get server fingerprint
  FINGERPRINT=$(incus info | grep "certificate fingerprint" | cut -d: -f2- | tr -d ' ')

  cat << EOF

==========================================================
  Incus Remote Access Configuration
==========================================================

Server Address: $(hostname -I | awk '{print $1}'):8443
Trust Password: $TRUST_PASSWORD
Fingerprint:    $FINGERPRINT

To connect from your Rails app, set these environment variables:

  export INCUS_HOST="https://$(hostname -I | awk '{print $1}'):8443"
  export INCUS_PROJECT="$INCUS_PROJECT"

To add this remote from another machine:

  incus remote add activeagents $(hostname -I | awk '{print $1}')

==========================================================
EOF

  # Save credentials to file
  cat > /root/.incus-credentials << EOF
INCUS_HOST=https://$(hostname -I | awk '{print $1}'):8443
INCUS_PROJECT=$INCUS_PROJECT
INCUS_TRUST_PASSWORD=$TRUST_PASSWORD
EOF
  chmod 600 /root/.incus-credentials

  log "Credentials saved to /root/.incus-credentials"
}

create_cleanup_cron() {
  log "Setting up cleanup cron job..."

  cat > /etc/cron.d/incus-sandbox-cleanup << 'EOF'
# Clean up expired sandbox containers every 5 minutes
*/5 * * * * root /usr/local/bin/cleanup-sandboxes.sh
EOF

  cat > /usr/local/bin/cleanup-sandboxes.sh << 'SCRIPT'
#!/bin/bash
# Cleanup sandbox containers older than 15 minutes

PROJECT="agent-sandboxes"
MAX_AGE=900  # 15 minutes in seconds

incus project switch "$PROJECT" 2>/dev/null || exit 0

for container in $(incus list --format csv -c n 2>/dev/null | grep "^sandbox-"); do
  created=$(incus config get "$container" volatile.base_image_date 2>/dev/null || echo "")
  if [[ -n "$created" ]]; then
    created_ts=$(date -d "$created" +%s 2>/dev/null || echo 0)
    now_ts=$(date +%s)
    age=$((now_ts - created_ts))

    if [[ $age -gt $MAX_AGE ]]; then
      incus stop "$container" --force 2>/dev/null
      incus delete "$container" 2>/dev/null
      logger "Cleaned up expired sandbox: $container (age: ${age}s)"
    fi
  fi
done

incus project switch default 2>/dev/null
SCRIPT

  chmod +x /usr/local/bin/cleanup-sandboxes.sh

  log "Cleanup cron job configured"
}

print_summary() {
  cat << EOF

==========================================================
  Incus Sandbox Host Setup Complete
==========================================================

Project:        $INCUS_PROJECT
Profile:        $SANDBOX_PROFILE
Network:        $NETWORK_NAME (10.100.0.0/24)
Storage:        $STORAGE_POOL

Available Images:
  - sandbox-base       (Ubuntu 22.04 with basic tools)
  - sandbox-playwright (with Chromium for browser automation)

Quick Test:
  incus project switch $INCUS_PROJECT
  incus launch sandbox-base test-sandbox --profile $SANDBOX_PROFILE
  incus exec test-sandbox -- bash
  incus delete test-sandbox --force

Next Steps:
  1. Set SANDBOX_BACKEND=incus in your Rails app
  2. Configure INCUS_HOST with the server address
  3. Copy client certificates for remote access (optional)

Documentation:
  https://linuxcontainers.org/incus/docs/main/

==========================================================
EOF
}

main() {
  log "Starting Incus sandbox host setup..."

  check_root
  detect_distro
  install_incus
  configure_incus
  create_sandbox_project
  create_sandbox_profile
  create_sandbox_images
  setup_firewall
  setup_remote_access
  create_cleanup_cron
  print_summary

  log "Setup complete!"
}

main "$@"
