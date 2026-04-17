#!/usr/bin/env bash
# Fetch MedSAM2 + SAM2.1 Hiera checkpoints into ./models. Idempotent + resumable.
set -euo pipefail

VARIANT="${1:-tiny}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/models"
mkdir -p "$DEST/medsam2" "$DEST/sam2"

# MedSAM2 checkpoint filenames by variant (matches bowang-lab/MedSAM2 release).
case "$VARIANT" in
  tiny)      MEDSAM2_FILE="MedSAM2_2411.pt" ;;
  latest|*)  MEDSAM2_FILE="MedSAM2_latest.pt" ;;
esac

MEDSAM2_URL="https://huggingface.co/wanglab/MedSAM2/resolve/main/${MEDSAM2_FILE}"
SAM2_FILE="sam2.1_hiera_tiny.pt"
SAM2_URL="https://dl.fbaipublicfiles.com/segment_anything_2/092824/${SAM2_FILE}"

fetch() {
  local url="$1" out="$2"
  [[ -s "$out" ]] && { echo "[kuzey] $(basename "$out") present, skipping."; return; }
  echo "[kuzey] Downloading $(basename "$out")…"
  curl -fL --retry 3 -C - -o "$out" "$url"
}

fetch "$MEDSAM2_URL" "$DEST/medsam2/$MEDSAM2_FILE"
fetch "$SAM2_URL"    "$DEST/sam2/$SAM2_FILE"

# Pointer file read by the Nuclio function handler.
cat > "$DEST/active.json" <<EOF
{"medsam2_checkpoint": "medsam2/$MEDSAM2_FILE", "sam2_backbone": "sam2/$SAM2_FILE", "variant": "$VARIANT"}
EOF
echo "[kuzey] Weights ready under $DEST."
