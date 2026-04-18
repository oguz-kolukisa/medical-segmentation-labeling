#!/usr/bin/env bash
# One-shot installer for NVIDIA GPU support in Docker (Linux or WSL2 Ubuntu).
# Installs nvidia-container-toolkit, registers the nvidia runtime, restarts
# Docker, and runs a smoke test. Idempotent — rerun is safe.
#
# Prereqs (you need these BEFORE running this script):
#   - NVIDIA Windows driver installed, so `nvidia-smi` works in WSL
#     (or NVIDIA driver on bare-metal Linux).
#   - `sudo` access (apt + runtime config require root).
set -euo pipefail

log()  { printf '\033[1;34m[kuzey-gpu]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[kuzey-gpu]\033[0m %s\n' "$*" >&2; exit 1; }

require_driver() {
  command -v nvidia-smi >/dev/null || die "nvidia-smi not found. Install the NVIDIA Windows/Linux driver first."
  nvidia-smi -L >/dev/null 2>&1 || die "nvidia-smi can't see a GPU. Fix the driver before running this."
}

add_apt_repo() {
  local keyring=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  [[ -f "$keyring" ]] && { log "NVIDIA apt keyring already present."; return; }
  log "Adding NVIDIA container-toolkit apt repo…"
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | sudo gpg --dearmor -o "$keyring"
  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed "s#deb #deb [signed-by=$keyring] #" \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
}

install_toolkit() {
  if dpkg -s nvidia-container-toolkit >/dev/null 2>&1; then
    log "nvidia-container-toolkit already installed."
    return
  fi
  log "Installing nvidia-container-toolkit…"
  sudo apt-get update -qq
  sudo apt-get install -y nvidia-container-toolkit
}

configure_docker_runtime() {
  log "Registering nvidia runtime with Docker…"
  sudo nvidia-ctk runtime configure --runtime=docker
}

restart_docker() {
  log "Restarting Docker…"
  if command -v systemctl >/dev/null && systemctl is-system-running >/dev/null 2>&1; then
    sudo systemctl restart docker
  else
    # WSL2 without systemd uses the older service command.
    sudo service docker restart
  fi
}

smoke_test() {
  log "Smoke-testing Docker GPU access (pulls a small CUDA image first time)…"
  if docker run --rm --gpus all nvidia/cuda:12.4.1-runtime-ubuntu22.04 nvidia-smi -L 2>&1; then
    log "Success — Docker can now see your GPU."
  else
    die "Smoke test failed. Run 'docker info 2>&1 | grep -i runtime' and check the NVIDIA runtime is listed."
  fi
}

next_steps() {
  cat <<'EOF'

Next: rerun the main launcher with GPU enabled.

  sed -i 's/^DEVICE=.*/DEVICE=cuda/' .env
  rm -f .kuzey-state/medsam2-deployed
  docker rm -f nuclio-nuclio-kuzey-medsam2-interactor-cpu 2>/dev/null
  docker rm -f nuclio-nuclio-kuzey-medsam2-interactor-gpu 2>/dev/null
  docker exec nuclio-local-storage-reader \
    sh -c 'rm -f /etc/nuclio/store/functions/nuclio/kuzey-medsam2-interactor-*.json'
  ./start.sh

EOF
}

main() {
  require_driver
  add_apt_repo
  install_toolkit
  configure_docker_runtime
  restart_docker
  smoke_test
  next_steps
}

main "$@"
