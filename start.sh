#!/usr/bin/env bash
# Kuzey — one-command launcher for the medical video labeling app.
# Reruns are idempotent: checks are cheap, work only happens when missing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$ROOT/.kuzey-state"
CI_MODE=0
for arg in "$@"; do
  case "$arg" in
    --ci) CI_MODE=1 ;;
    -h|--help) echo "usage: ./start.sh [--ci]"; exit 0 ;;
  esac
done

log()  { printf '\033[1;34m[kuzey]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[kuzey]\033[0m %s\n' "$*" >&2; exit 1; }

require_docker() {
  command -v docker >/dev/null || die "Docker not found. Install Docker Desktop or Docker Engine, then rerun."
  docker compose version >/dev/null 2>&1 || die "Docker Compose v2 not found. Update Docker, then rerun."
}

ensure_env_file() {
  [[ -f "$ROOT/.env" ]] && return
  cp "$ROOT/.env.example" "$ROOT/.env"
  local device; device="$("$ROOT/scripts/detect_device.sh")"
  sed -i.bak "s/^DEVICE=.*/DEVICE=$device/" "$ROOT/.env" && rm "$ROOT/.env.bak"
  log "Wrote .env with DEVICE=$device"
}

current_cvat_host() {
  grep -E '^CVAT_HOST=' "$ROOT/.env" | head -n1 | cut -d= -f2- || true
}

write_cvat_host() {
  local host="$1"
  if grep -qE '^CVAT_HOST=' "$ROOT/.env"; then
    sed -i.bak "s|^CVAT_HOST=.*|CVAT_HOST=$host|" "$ROOT/.env" && rm "$ROOT/.env.bak"
  else
    printf 'CVAT_HOST=%s\n' "$host" >> "$ROOT/.env"
  fi
}

ensure_cvat_host() {
  local current; current="$(current_cvat_host)"
  [[ -n "$current" && "$current" != "auto" ]] && return
  local host; host="$("$ROOT/scripts/detect_host.sh")"
  write_cvat_host "$host"
  log "Resolved CVAT_HOST=$host"
}

load_env() { set -a; . "$ROOT/.env"; set +a; }

clone_cvat_if_missing() {
  [[ -d "$ROOT/.cvat/.git" ]] && return
  log "Cloning upstream CVAT ($CVAT_VERSION)…"
  git clone --depth 1 --branch "$CVAT_VERSION" "$CVAT_REPO" "$ROOT/.cvat"
}

download_weights_if_missing() {
  "$ROOT/scripts/download_weights.sh" "$MEDSAM2_VARIANT"
}

compose_files() {
  local base="$ROOT/.cvat/docker-compose.yml"
  local serverless="$ROOT/.cvat/components/serverless/docker-compose.serverless.yml"
  local overlay="$ROOT/docker-compose.override.yml"
  printf -- '-f %s -f %s -f %s' "$base" "$serverless" "$overlay"
}

bring_stack_up() {
  log "Starting CVAT + Nuclio (profile=${DEVICE})…"
  # shellcheck disable=SC2046
  docker compose $(compose_files) --profile "$DEVICE" up -d
}

ensure_superuser_once() {
  local marker="$STATE_DIR/superuser-created"
  mkdir -p "$STATE_DIR"
  [[ -f "$marker" ]] && return
  "$ROOT/scripts/bootstrap.sh" create-superuser
  touch "$marker"
}

deploy_function_once() {
  local marker="$STATE_DIR/medsam2-deployed"
  mkdir -p "$STATE_DIR"
  [[ -f "$marker" ]] && { log "MedSAM2 function already deployed, skipping."; return; }
  "$ROOT/scripts/bootstrap.sh" deploy-function
  touch "$marker"
}

wait_for_cvat() {
  log "Waiting for CVAT to be healthy…"
  # Hit loopback for reliability, but pass the Host header Traefik's router
  # expects — otherwise the request falls through to a 404.
  local url="http://localhost:${CVAT_HOST_PORT}/api/server/about"
  for _ in $(seq 1 120); do
    curl -fsS -H "Host: ${CVAT_HOST}" "$url" >/dev/null 2>&1 && { log "CVAT is up."; return; }
    sleep 2
  done
  die "CVAT did not become healthy in 4 minutes. Check 'docker compose logs'."
}

seed_project_once() {
  local marker="$STATE_DIR/project-seeded"
  [[ -f "$marker" ]] && return
  "$ROOT/scripts/bootstrap.sh" seed-project && touch "$marker"
}

open_ui() {
  (( CI_MODE )) && { log "CI mode — not opening browser."; return; }
  "$ROOT/scripts/open_browser.sh" "http://${CVAT_HOST}:${CVAT_HOST_PORT}"
}

announce_login() {
  log "Ready: http://${CVAT_HOST}:${CVAT_HOST_PORT}"
  log "Log in as: ${CVAT_SUPERUSER_USERNAME} / ${CVAT_SUPERUSER_PASSWORD}"
}

main() {
  require_docker
  ensure_env_file
  ensure_cvat_host
  load_env
  clone_cvat_if_missing
  download_weights_if_missing
  bring_stack_up
  wait_for_cvat
  ensure_superuser_once
  deploy_function_once
  seed_project_once
  open_ui
  announce_login
}

main "$@"
