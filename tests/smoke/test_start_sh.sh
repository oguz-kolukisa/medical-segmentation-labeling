#!/usr/bin/env bash
# End-to-end smoke: start the stack in CI mode, wait for health, tear down.
# Runs locally or on a self-hosted runner. Not suitable for GitHub's hosted
# runners (no docker-in-docker, no GPU, and the weight download is ~1 GB).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

cleanup() { ./stop.sh || true; }
trap cleanup EXIT

./start.sh --ci

# start.sh already waits for /api/server/about; reassert for belt-and-braces.
curl -fsS "http://localhost:${CVAT_HOST_PORT:-8080}/api/server/about" | grep -q '"version"'
echo "[smoke] CVAT is up and responding."
