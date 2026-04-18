#!/usr/bin/env bash
# Reset the MedSAM2 Nuclio function to a pristine "ready to redeploy" state.
# Does NOT touch weights, CVAT data, or the prebuilt base images — those are
# expensive to recreate. After running this, `./start.sh` redeploys cleanly.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '\033[1;34m[kuzey-clean]\033[0m %s\n' "$*"; }

remove_deploy_marker() {
  local marker="$ROOT/.kuzey-state/medsam2-deployed"
  [[ -f "$marker" ]] && rm -f "$marker" && log "Removed deploy marker."
}

remove_function_containers() {
  for name in \
      nuclio-nuclio-kuzey-medsam2-interactor-cpu \
      nuclio-nuclio-kuzey-medsam2-interactor-gpu; do
    if docker rm -f "$name" >/dev/null 2>&1; then
      log "Removed container $name."
    fi
  done
}

remove_nuclio_state() {
  # The local-storage volume is only reachable via its reader container. If
  # that container isn't running (because CVAT stack is down), silently skip.
  if ! docker ps --format '{{.Names}}' | grep -q '^nuclio-local-storage-reader$'; then
    log "Nuclio storage-reader not running, skipping state wipe."
    return
  fi
  docker exec nuclio-local-storage-reader \
    sh -c 'rm -f /etc/nuclio/store/functions/nuclio/kuzey-medsam2-interactor-*.json'
  log "Cleared Nuclio function state JSON."
}

main() {
  remove_deploy_marker
  remove_function_containers
  remove_nuclio_state
  log "Clean. Run ./start.sh to redeploy."
}

main "$@"
