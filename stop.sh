#!/usr/bin/env bash
# Stop the stack. Does not delete data or weights.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$ROOT/.env" ]] && { set -a; . "$ROOT/.env"; set +a; }

compose_files() {
  printf -- '-f %s -f %s -f %s' \
    "$ROOT/.cvat/docker-compose.yml" \
    "$ROOT/.cvat/components/serverless/docker-compose.serverless.yml" \
    "$ROOT/docker-compose.override.yml"
}

# shellcheck disable=SC2046
docker compose $(compose_files) down
echo "[kuzey] Stopped. Data preserved in docker volumes; weights in ./models."
