#!/usr/bin/env bash
# Collect every piece of state I'd ask for when debugging a "500 Internal
# Server Error" from the MedSAM2 interactor, into one file. Run it, then
# paste the output file contents.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="/tmp/kuzey-diagnose.txt"
NUCTL="$ROOT/.kuzey-state/bin/nuctl"

section() { printf '\n===== %s =====\n' "$1"; }

{
  section "env"
  date
  uname -a
  echo "--- .env ---"
  grep -E '^(DEVICE|CVAT_HOST_PORT|MEDSAM2_VARIANT|CVAT_VERSION)=' "$ROOT/.env" 2>/dev/null || echo "(.env missing)"

  section "docker version / compose"
  docker --version 2>&1
  docker compose version 2>&1
  docker info 2>&1 | grep -iE 'server version|runtime|nvidia|operating system|kernel version' | head -10

  section "running containers"
  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' 2>&1

  section "docker networks"
  docker network ls --format '{{.Name}}' 2>&1 | grep -iE 'cvat|nuclio|medsam' || echo "(no cvat/nuclio networks)"

  section "nuclio functions (nuctl)"
  if [[ -x "$NUCTL" ]]; then
    "$NUCTL" get function --platform local 2>&1
  else
    echo "(nuctl not downloaded yet — $NUCTL missing)"
  fi

  section "nuclio stored function JSON files"
  if docker ps --format '{{.Names}}' | grep -q '^nuclio-local-storage-reader$'; then
    docker exec nuclio-local-storage-reader \
      ls -la /etc/nuclio/store/functions/nuclio/ 2>&1
  else
    echo "(storage reader not running)"
  fi

  section "function container logs (cpu)"
  docker logs nuclio-nuclio-kuzey-medsam2-interactor-cpu --tail 120 2>&1 \
    || echo "(no -cpu container)"

  section "function container logs (gpu)"
  docker logs nuclio-nuclio-kuzey-medsam2-interactor-gpu --tail 120 2>&1 \
    || echo "(no -gpu container)"

  section "function container network attachments"
  for name in nuclio-nuclio-kuzey-medsam2-interactor-cpu nuclio-nuclio-kuzey-medsam2-interactor-gpu; do
    echo "--- $name ---"
    docker inspect "$name" --format '{{json .NetworkSettings.Networks}}' 2>&1 \
      || echo "(not present)"
  done

  section "cvat_server → function reachability test"
  for name in nuclio-nuclio-kuzey-medsam2-interactor-cpu nuclio-nuclio-kuzey-medsam2-interactor-gpu; do
    printf -- '--- GET http://%s:8080/ ---\n' "$name"
    docker exec cvat_server curl -sS -o /dev/null -w "HTTP %{http_code}   time %{time_total}s\n" \
      -m 5 "http://$name:8080/" 2>&1
  done

  section "cvat_server recent 500s and lambda traces"
  docker logs cvat_server --tail 200 2>&1 | grep -iE 'lambda|nuclio|500|traceback|internal server' | tail -40

  section "kuzey base images"
  docker images --format '{{.Repository}}:{{.Tag}} {{.CreatedSince}} {{.Size}}' | grep -iE 'kuzey|cvat\.kuzey' || echo "(none)"

  section "kuzey weights on disk"
  ls -la "$ROOT/models/" 2>&1 | head -10
  ls -la "$ROOT/models/medsam2/" 2>&1 | head -5
  cat "$ROOT/models/active.json" 2>&1

  section "host reachability of function port from cvat_server"
  docker exec cvat_server curl -sS -o /dev/null -w "host.docker.internal → HTTP %{http_code}\n" \
    -m 5 "http://host.docker.internal:32794/" 2>&1 \
    | head -3
} > "$OUT" 2>&1

echo "Diagnostics written to $OUT"
echo "Paste the whole file. First 40 lines:"
head -40 "$OUT"
echo
echo "(...truncated — share the full file)"
