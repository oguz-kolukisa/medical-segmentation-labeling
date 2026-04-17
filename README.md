# Kuzey — medical video labeling, one command

A desktop app for clinicians and domain experts to label videos for
segmentation, with a state-of-the-art medical-domain AI assistant
(**MedSAM2**) doing the heavy lifting.

> Click once on a lesion in the first frame. Kuzey draws the mask, then
> follows it across the rest of the video. You correct where needed.

Built on [CVAT](https://github.com/cvat-ai/cvat) (MIT) and
[MedSAM2](https://github.com/bowang-lab/MedSAM2) (Apache-2.0).

---

## Quickstart (3 steps)

1. Install **Docker Desktop** (macOS/Windows) or **Docker Engine** (Linux).
2. Open a terminal in this folder and run:
   ```bash
   ./start.sh
   ```
3. Your browser opens at **http://localhost:8080**. Log in with the default
   credentials printed in the terminal (`clinician` / `clinician`). Change
   them in `.env` before first start if you want something different.

First run takes 5–15 minutes while model weights download (~1 GB) and
containers build. Later starts take under 30 seconds.

## Daily use

| | |
|---|---|
| Start the app | `./start.sh` |
| Stop the app | `./stop.sh` |
| Something is stuck | `./stop.sh && ./start.sh` |

Your annotations and videos persist in Docker volumes between sessions —
stopping the app doesn't lose work.

## How to label a video

1. **Log in** with the admin user you created.
2. **Upload a video** via *Projects → New project → New task*. Pick the
   default "kuzey-medical-default" label set, or define your own.
3. On the first frame, click the **AI Tools** icon (magic-wand) and pick
   **MedSAM2** as the interactor. Click once on the structure you want.
4. A mask appears. Refine with a second positive click, or a right-click
   for a negative point.
5. Switch to **Tracking** mode and let MedSAM2 propagate the mask through
   the video. Scrub and correct on frames where it drifts.
6. **Export** from the task menu: COCO, CVAT XML, Datumaro, per-frame PNGs,
   etc. — pick whatever your pipeline needs.

## Hardware

- **NVIDIA GPU:** detected automatically. Labeling is near-real-time.
- **CPU only:** works out of the box with the Tiny MedSAM2 checkpoint.
  Expect ~30 s per AI click on a laptop CPU. Still much faster than
  drawing masks by hand.

## Customizing

| Want to… | Edit… |
|---|---|
| Change the UI port | `.env` → `CVAT_HOST_PORT` |
| Force CPU / GPU | `.env` → `DEVICE=cpu` or `cuda` |
| Use a different MedSAM2 variant | `.env` → `MEDSAM2_VARIANT` |
| Change default labels | `config/labels/medical-default.json` |

## Troubleshooting

**"Docker not found"** — install Docker Desktop and restart your terminal.
**"Port 8080 in use"** — set `CVAT_HOST_PORT=9090` (or anything free) in `.env`.
**Mask takes forever on CPU** — that's expected. Try a GPU machine, or
shorter clips.
**Something else** — `docker compose logs --tail 200` for details, then
`./stop.sh && ./start.sh`.

## Layout of this repo

```
start.sh / stop.sh    ← what the expert runs
docker-compose.override.yml  ← thin layer on top of upstream CVAT
serverless/medsam2/   ← the AI assistant (Nuclio function)
scripts/              ← helpers called by start.sh
config/labels/        ← default label schemas
models/               ← downloaded weights (gitignored)
tests/                ← smoke + unit tests
```

## Licenses

- Kuzey glue code — MIT
- CVAT — MIT
- MedSAM2 — Apache-2.0
- Model weights may have separate licenses; see MedSAM2's repo for details.
