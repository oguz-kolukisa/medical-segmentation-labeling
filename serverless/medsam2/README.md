# MedSAM2 Nuclio function

CVAT-compatible serverless function that exposes MedSAM2
(`bowang-lab/MedSAM2`) to CVAT's interactor UI.

## Files

| File | Purpose |
|------|---------|
| `nuclio/main.py` | Nuclio HTTP handler — decode, dispatch, encode. Transport only. |
| `nuclio/model_handler.py` | Wraps the MedSAM2 video predictor. Holds per-track memory state. |
| `nuclio/function-cpu.yaml` | Nuclio spec, CPU base image. Deployed when `DEVICE=cpu`. |
| `nuclio/function-cuda.yaml` | Nuclio spec, CUDA 12.4 base image. Deployed when `DEVICE=cuda`. |
| `nuclio/requirements.txt` | Pure-python deps installed after the MedSAM2 source install. |

## Rebuild this function only

From the repo root:

```bash
docker exec nuclio nuctl deploy \
  --project-name cvat \
  --path /opt/nuclio/functions/medsam2 \
  --file /opt/nuclio/functions/medsam2/nuclio/function-cpu.yaml \
  --platform local
```

Swap `function-cpu.yaml` → `function-cuda.yaml` for a GPU rebuild.

## What the function returns

Request (from CVAT):
```json
{"image": "<base64>", "pos_points": [[x, y]], "neg_points": [], "obj_bbox": null}
```

Response:
```json
{"mask": [[0, 0, 1, 1, ...], ...]}
```

A 2-D list of 0/1 pixels. CVAT converts it to its own mask representation.

## Tracking state

For the tracker variant (`KUZEY_HANDLER_KIND=tracker`), the handler keys
MedSAM2's memory bank by `(job_id, track_id)` with a 64-entry LRU so a long
session doesn't leak VRAM.
