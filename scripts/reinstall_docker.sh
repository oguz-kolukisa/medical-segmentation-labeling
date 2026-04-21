#!/usr/bin/env bash
# Clean reinstall of Docker CE + Compose v2 on Ubuntu, following
# https://docs.docker.com/engine/install/ubuntu/ and the post-install
# "Manage Docker as a non-root user" step.
#
# DESTRUCTIVE: removes existing Docker packages and wipes /var/lib/docker
# (all containers, images, volumes, networks). Idempotent — rerun is safe.
#
# Usage:  sudo ./scripts/reinstall_docker.sh [--yes]
set -euo pipefail

ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help) echo "usage: sudo ./scripts/reinstall_docker.sh [--yes]"; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

log()  { printf '\033[1;34m[docker-reinstall]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[docker-reinstall]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[docker-reinstall]\033[0m %s\n' "$*" >&2; exit 1; }

require_root() {
  [[ $EUID -eq 0 ]] || die "Must run as root. Try: sudo $0 $*"
}

require_ubuntu() {
  [[ -r /etc/os-release ]] || die "Can't read /etc/os-release."
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || die "This script targets Ubuntu (got ID=${ID:-unknown})."
}

confirm_destruction() {
  (( ASSUME_YES )) && return
  warn "This will delete ALL Docker containers, images, volumes, and networks on this host."
  read -r -p "Type 'yes' to continue: " reply
  [[ "$reply" == "yes" ]] || die "Aborted."
}

stop_docker_services() {
  log "Stopping any running Docker services…"
  systemctl stop docker.socket docker containerd 2>/dev/null || true
}

# Official uninstall list from docs.docker.com/engine/install/ubuntu/
uninstall_conflicting_packages() {
  log "Removing conflicting Docker packages (official list)…"
  local installed
  installed="$(dpkg --get-selections \
    docker.io docker-compose docker-compose-v2 docker-doc \
    podman-docker containerd runc 2>/dev/null \
    | awk '$2=="install"{print $1}' || true)"
  if [[ -z "$installed" ]]; then
    log "No conflicting packages installed."
    return
  fi
  # shellcheck disable=SC2086
  apt-get remove -y $installed
}

purge_previous_docker_ce() {
  log "Purging any previous docker-ce install…"
  apt-get purge -y \
    'docker-ce' 'docker-ce-cli' 'containerd.io' \
    'docker-buildx-plugin' 'docker-compose-plugin' \
    'docker-ce-rootless-extras' 2>/dev/null || true
  apt-get autoremove -y --purge
}

wipe_docker_state() {
  log "Wiping /var/lib/docker, /var/lib/containerd, and config dirs…"
  rm -rf /var/lib/docker /var/lib/containerd
  rm -rf /etc/docker /etc/containerd
}

remove_old_repo_files() {
  log "Removing stale Docker apt sources and keyrings…"
  rm -f /etc/apt/sources.list.d/docker.list
  rm -f /etc/apt/sources.list.d/docker.sources
  rm -f /etc/apt/keyrings/docker.gpg /etc/apt/keyrings/docker.asc
  rm -f /usr/share/keyrings/docker-archive-keyring.gpg
}

install_apt_prereqs() {
  log "Installing apt prerequisites (ca-certificates, curl)…"
  apt-get update
  apt-get install -y ca-certificates curl
}

add_docker_gpg_key() {
  log "Adding Docker's official GPG key…"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
}

write_docker_sources() {
  log "Writing /etc/apt/sources.list.d/docker.sources…"
  . /etc/os-release
  local codename="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
  local arch; arch="$(dpkg --print-architecture)"
  tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${codename}
Components: stable
Architectures: ${arch}
Signed-By: /etc/apt/keyrings/docker.asc
EOF
  apt-get update
}

install_docker_ce() {
  log "Installing docker-ce + compose v2 plugin…"
  apt-get install -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
}

enable_docker_service() {
  log "Enabling and starting Docker…"
  systemctl enable --now docker
}

# Post-install: docs.docker.com/engine/install/linux-postinstall/
add_user_to_docker_group() {
  local target="${SUDO_USER:-}"
  if [[ -z "$target" || "$target" == "root" ]]; then
    warn "Script was not invoked via sudo by a regular user; skipping group add."
    warn "Run manually:  sudo usermod -aG docker <your-user>  &&  newgrp docker"
    return
  fi
  log "Adding user '$target' to docker group…"
  groupadd -f docker
  usermod -aG docker "$target"
  log "User '$target' added. Activate with:  newgrp docker  (or log out/in)."
}

verify_install() {
  log "Verifying install…"
  docker --version
  docker compose version
  docker run --rm hello-world >/dev/null && log "hello-world smoke test passed."
}

main() {
  require_root "$@"
  require_ubuntu
  confirm_destruction
  stop_docker_services
  uninstall_conflicting_packages
  purge_previous_docker_ce
  wipe_docker_state
  remove_old_repo_files
  install_apt_prereqs
  add_docker_gpg_key
  write_docker_sources
  install_docker_ce
  enable_docker_service
  add_user_to_docker_group
  verify_install
  log "Done. Docker + Compose v2 installed cleanly."
}

main "$@"
