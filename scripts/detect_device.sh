#!/usr/bin/env bash
# Echo "cuda" if an NVIDIA GPU is usable, else "cpu".
set -euo pipefail

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
  echo "cuda"
else
  echo "cpu"
fi
