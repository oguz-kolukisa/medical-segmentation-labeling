#!/usr/bin/env bash
# Dispatch: create-superuser | deploy-function | seed-project.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
set -a; . "$ROOT/.env"; set +a

NUCTL_VERSION="1.13.0"
NUCTL_BIN="$ROOT/.kuzey-state/bin/nuctl"

ensure_nuctl() {
  [[ -x "$NUCTL_BIN" ]] && return
  mkdir -p "$(dirname "$NUCTL_BIN")"
  local os arch url
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) echo "Unsupported arch: $(uname -m)" >&2; exit 1 ;;
  esac
  url="https://github.com/nuclio/nuclio/releases/download/${NUCTL_VERSION}/nuctl-${NUCTL_VERSION}-${os}-${arch}"
  echo "[kuzey] Downloading nuctl ${NUCTL_VERSION}…"
  curl -fL -o "$NUCTL_BIN" "$url"
  chmod +x "$NUCTL_BIN"
}

create_superuser() {
  # Django's createsuperuser --noinput reads DJANGO_SUPERUSER_* env vars.
  # It exits non-zero if the user already exists — we treat that as success.
  echo "[kuzey] Ensuring CVAT superuser '$CVAT_SUPERUSER_USERNAME' exists…"
  docker exec \
    -e DJANGO_SUPERUSER_USERNAME="$CVAT_SUPERUSER_USERNAME" \
    -e DJANGO_SUPERUSER_EMAIL="$CVAT_SUPERUSER_EMAIL" \
    -e DJANGO_SUPERUSER_PASSWORD="$CVAT_SUPERUSER_PASSWORD" \
    cvat_server python3 manage.py createsuperuser --noinput 2>&1 \
    | grep -vE 'that username is already taken|already exists' || true
}

ensure_nuclio_project() {
  # --platform local keeps project state in ~/.nuctl; CVAT-compatible
  # functions live under project "cvat" by convention.
  "$NUCTL_BIN" get project cvat --platform local >/dev/null 2>&1 && return
  echo "[kuzey] Creating Nuclio project 'cvat'…"
  "$NUCTL_BIN" create project cvat --platform local
}

render_function_yaml() {
  # Substitute host-specific paths so the YAML stays portable across checkouts.
  local src="$1"
  local out; out="$(mktemp -t kuzey-function-XXXXXX.yaml)"
  sed "s|__KUZEY_MODELS_HOST__|$ROOT/models|g" "$src" > "$out"
  echo "$out"
}

ensure_base_image() {
  # The nuclio function's baseImage (kuzey-medsam2-base:$DEVICE) is built
  # locally per host — we never push it to a registry, so a fresh checkout
  # has to build it once. Skip if the image is already cached.
  local kind="$DEVICE"
  local image="kuzey-medsam2-base:${kind}"
  local dockerfile="$ROOT/serverless/medsam2/docker/Dockerfile.${kind}"
  if docker image inspect "$image" >/dev/null 2>&1; then
    echo "[kuzey] Base image $image already built, skipping."
    return
  fi
  [[ -f "$dockerfile" ]] || { echo "No Dockerfile for $kind at $dockerfile" >&2; exit 1; }
  echo "[kuzey] Building $image from $(basename "$dockerfile") — first run takes 5–15 min."
  docker build --progress=plain -t "$image" -f "$dockerfile" "$(dirname "$dockerfile")"
}

deploy_function() {
  local kind="$DEVICE"                         # cuda or cpu
  local fn_dir="$ROOT/serverless/medsam2/nuclio"
  local yaml="$fn_dir/function-${kind}.yaml"
  [[ -f "$yaml" ]] || { echo "No Nuclio spec for DEVICE=$kind" >&2; exit 1; }
  ensure_base_image
  ensure_nuctl
  ensure_nuclio_project
  local rendered; rendered="$(render_function_yaml "$yaml")"
  echo "[kuzey] Deploying MedSAM2 Nuclio function ($kind)…"
  # --path/--file use host paths; nuctl runs on the host and talks to the
  # local Docker daemon. main.py sits at the root of $fn_dir so
  # `handler: main:handler` resolves without a package prefix.
  "$NUCTL_BIN" deploy \
    --project-name cvat \
    --path "$fn_dir" \
    --file "$rendered" \
    --platform local
}

seed_project() {
  local api="http://localhost:${CVAT_HOST_PORT}/api"
  local schema="$ROOT/config/labels/medical-default.json"
  echo "[kuzey] Seeding default CVAT project from $(basename "$schema")…"
  # Admin user 'clinician' is created on CVAT first-run via its own superuser flow;
  # here we just POST the project if it doesn't exist. Auth handled interactively
  # by the expert on first login — safer than baking a password into the repo.
  if ! curl -fsS "$api/projects?name=kuzey" | grep -q '"name":"kuzey"'; then
    echo "[kuzey] Log in to CVAT in your browser once, then rerun ./start.sh"
    echo "[kuzey] to auto-create the default project. (CVAT requires an admin"
    echo "[kuzey] user to exist before API writes are allowed.)"
  fi
}

case "${1:-}" in
  create-superuser) create_superuser ;;
  deploy-function)  deploy_function ;;
  seed-project)     seed_project ;;
  *) echo "usage: bootstrap.sh {create-superuser|deploy-function|seed-project}" >&2; exit 2 ;;
esac
