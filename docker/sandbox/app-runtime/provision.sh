#!/bin/bash
#
# Provisions the sandbox-app-runtime image, which boots a checkout of a Rails
# app: run as root inside a fresh Ubuntu 24.04 container, with this
# directory's files in SOURCE_DIR (default: the directory this script is in).
# scripts/build-app-runtime-image.sh runs it in an Incus builder container,
# and the app-runtime target of docker/sandbox/Dockerfile in a Docker build.
#
# The image carries:
#   - git, a C toolchain and the headers native gems build against
#   - mise, with the latest Ruby of each RUBY_SERIES and Node DEFAULT_NODE
#     preinstalled; sandbox-app-boot installs any other version a checkout
#     pins when it boots
#   - Yarn and pnpm through corepack, and Bun
#   - PostgreSQL, MySQL, Redis, SQLite and libvips. The servers are installed
#     stopped; sandbox-app-boot starts only those the checkout uses, with
#     the scripts in services/
#   - socat, which forwards the container's :8080 to the app
#   - /usr/local/bin/sandbox-app-boot
#
# Every boot command runs as the unprivileged user `sandbox` (uid 1000),
# which owns /workspace and the mise installs.
set -euo pipefail

SOURCE_DIR=${SOURCE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
SANDBOX_USER=sandbox
SANDBOX_UID=1000
MISE_VERSION=${MISE_VERSION:-v2026.10.1}
read -r -a RUBY_SERIES <<< "${RUBY_SERIES:-3.2 3.3 3.4}"
DEFAULT_NODE=${DEFAULT_NODE:-22}
MISE_DATA_DIR=/opt/mise
SERVICE_DIR=/usr/local/lib/sandbox-app-runtime/services
export DEBIAN_FRONTEND=noninteractive

log() {
  echo "[provision $(date '+%H:%M:%S')] $*"
}

as_sandbox() {
  (cd / && runuser -u "$SANDBOX_USER" -- env HOME="/home/$SANDBOX_USER" MISE_DATA_DIR="$MISE_DATA_DIR" MISE_YES=1 \
    PATH=/usr/local/bin:/usr/bin:/bin LANG=C.UTF-8 "$@")
}

install_packages() {
  log "Installing packages"
  apt-get update
  # libvips is libvips42t64 on Ubuntu 24.04 and libvips42 before it.
  local vips=libvips42t64
  apt-cache show "$vips" >/dev/null 2>&1 || vips=libvips42
  apt-get install -y --no-install-recommends \
    ca-certificates curl git gnupg openssh-client tzdata xz-utils unzip zstd \
    build-essential pkg-config autoconf bison patch \
    libssl-dev libyaml-dev libreadline-dev zlib1g-dev libgmp-dev libncurses-dev libffi-dev libgdbm-dev \
    libdb-dev uuid-dev libjemalloc2 \
    postgresql postgresql-contrib libpq-dev \
    mysql-server default-libmysqlclient-dev \
    redis-server \
    sqlite3 libsqlite3-dev \
    "$vips" \
    socat python3
  apt-get clean
  rm -rf /var/lib/apt/lists/*
}

create_user() {
  log "Creating the $SANDBOX_USER user"
  # Ubuntu's own images may ship a user at the uid the platform runs as.
  local existing
  existing=$(getent passwd "$SANDBOX_UID" | cut -d: -f1 || true)
  if [[ -n $existing && $existing != "$SANDBOX_USER" ]]; then
    userdel -r "$existing" 2>/dev/null || userdel "$existing"
  fi
  id "$SANDBOX_USER" >/dev/null 2>&1 || useradd -m -u "$SANDBOX_UID" -s /bin/bash "$SANDBOX_USER"
  install -d -o "$SANDBOX_USER" -g "$SANDBOX_USER" -m 0755 /workspace "$MISE_DATA_DIR"
}

install_toolchains() {
  log "Installing mise $MISE_VERSION"
  curl -fsSL https://mise.run | MISE_VERSION="$MISE_VERSION" MISE_INSTALL_PATH=/usr/local/bin/mise sh

  for series in "${RUBY_SERIES[@]}"; do
    log "Installing Ruby $series"
    as_sandbox mise install "ruby@$series"
  done
  log "Installing Node $DEFAULT_NODE and Bun"
  as_sandbox mise install "node@$DEFAULT_NODE" bun@latest

  # Exact versions, so a boot resolves the defaults without asking the
  # network what "latest" is.
  local ruby node bun
  ruby=$(as_sandbox mise latest --installed "ruby@${RUBY_SERIES[-1]}")
  node=$(as_sandbox mise latest --installed "node@$DEFAULT_NODE")
  bun=$(as_sandbox mise latest --installed bun)
  install -d /etc/mise
  cat > /etc/mise/config.toml << EOF
# The toolchain a checkout gets when it pins no version of its own.
[tools]
ruby = "$ruby"
node = "$node"
bun = "$bun"
EOF
  local node_bin
  node_bin="$(as_sandbox mise where "node@$node")/bin"
  # corepack runs on node, which nothing has put on the PATH yet.
  as_sandbox env PATH="$node_bin:/usr/local/bin:/usr/bin:/bin" corepack enable
}

configure_postgresql() {
  log "Configuring PostgreSQL"
  local version conf
  version=$(find /etc/postgresql -mindepth 1 -maxdepth 1 -printf '%f\n' | sort -V | tail -1)
  conf=/etc/postgresql/$version/main
  # The sandbox's own server, reachable only from inside the container.
  cat > "$conf/pg_hba.conf" << 'EOF'
local all all trust
host  all all 127.0.0.1/32 trust
host  all all ::1/128 trust
EOF
  sed -i "s/^#\?listen_addresses.*/listen_addresses = 'localhost'/" "$conf/postgresql.conf"
  echo manual > "$conf/start.conf"

  "$SERVICE_DIR/start-postgresql"
  runuser -u postgres -- psql -v ON_ERROR_STOP=1 -qc \
    "DO \$\$ BEGIN CREATE ROLE $SANDBOX_USER LOGIN SUPERUSER; EXCEPTION WHEN duplicate_object THEN NULL; END \$\$;"
  pg_ctlcluster "$version" main stop
}

configure_mysql() {
  log "Configuring MySQL"
  "$SERVICE_DIR/start-mysql"
  # Passwordless, as development database.yml files expect: the server
  # listens only inside the container.
  mysql -uroot << EOF
CREATE USER IF NOT EXISTS '$SANDBOX_USER'@'localhost' IDENTIFIED BY '';
CREATE USER IF NOT EXISTS '$SANDBOX_USER'@'127.0.0.1' IDENTIFIED BY '';
GRANT ALL PRIVILEGES ON *.* TO '$SANDBOX_USER'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO '$SANDBOX_USER'@'127.0.0.1' WITH GRANT OPTION;
ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '';
FLUSH PRIVILEGES;
EOF
  mysqladmin -uroot shutdown
}

disable_autostart() {
  # Started by sandbox-app-boot for the checkouts that use them, so an idle
  # container does not hold their memory.
  if command -v systemctl >/dev/null 2>&1; then
    systemctl disable postgresql mysql redis-server >/dev/null 2>&1 || true
  fi
}

install_boot() {
  log "Installing sandbox-app-boot"
  install -d "$SERVICE_DIR"
  install -m 0755 "$SOURCE_DIR"/services/start-* "$SERVICE_DIR/"
  install -m 0755 "$SOURCE_DIR/sandbox-app-boot" /usr/local/bin/sandbox-app-boot
}

main() {
  install_packages
  create_user
  install_boot
  install_toolchains
  configure_postgresql
  configure_mysql
  disable_autostart
  log "Done"
}

main "$@"
