#!/usr/bin/env bash
# Clean + redeploy in one go, with full output captured to a file so the
# user can paste it when things fail. Separate from start.sh because this
# one skips the CVAT bring-up — assumes the stack is already healthy.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="/tmp/kuzey-redeploy.log"

echo "[kuzey-redeploy] Cleaning stale function state…"
"$ROOT/scripts/clean.sh"

echo "[kuzey-redeploy] Running deploy-function (output → $LOG)…"
"$ROOT/scripts/bootstrap.sh" deploy-function 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}

echo
echo "==================================================================="
if [[ $rc -eq 0 ]]; then
  echo "[kuzey-redeploy] Deploy succeeded."
else
  echo "[kuzey-redeploy] Deploy FAILED (exit $rc). Full log: $LOG"
  echo
  echo "--- last 30 lines ---"
  tail -30 "$LOG"
fi
echo "==================================================================="

echo
echo "[kuzey-redeploy] Current function state:"
"$ROOT/.kuzey-state/bin/nuctl" get function --platform local 2>&1 || echo "(nuctl not available)"

echo
echo "[kuzey-redeploy] Current function containers:"
docker ps -a --filter name=nuclio-nuclio-kuzey-medsam2 \
  --format '  {{.Names}}  {{.Status}}' 2>&1 || echo "(none)"

echo
if [[ $rc -eq 0 ]]; then
  echo "Next: hard-reload CVAT in your browser (Ctrl+Shift+R) and try MedSAM2 again."
else
  echo "Next: paste the full log at $LOG so we can fix the underlying error."
fi

exit "$rc"
