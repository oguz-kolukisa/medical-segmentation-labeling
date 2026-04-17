"""Thin wrapper around MedSAM2's image predictor.

Hides the MedSAM2 API from the Nuclio entry point so `main.py` stays focused on
transport concerns (decode, dispatch, encode). We use `SAM2ImagePredictor` for
the CVAT interactor contract (single-frame input with point/box prompts).
"""
from __future__ import annotations

import io
import json
import os
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

# MedSAM2 ships its SAM2-derived code under the `sam2` package name.
from sam2.build_sam import build_sam2  # type: ignore
from sam2.sam2_image_predictor import SAM2ImagePredictor  # type: ignore


MODELS_DIR = Path(os.environ.get("KUZEY_MODELS_DIR", "/opt/nuclio/models"))


@dataclass(frozen=True)
class WeightsConfig:
    medsam2_checkpoint: Path

    @classmethod
    def load(cls) -> "WeightsConfig":
        active = json.loads((MODELS_DIR / "active.json").read_text())
        return cls(medsam2_checkpoint=MODELS_DIR / active["medsam2_checkpoint"])


class MedSAM2Model:
    """Single-frame predictor wired to MedSAM2's tiny-512 checkpoint."""

    def __init__(self, device: str) -> None:
        weights = WeightsConfig.load()
        # MedSAM2 ships its tiny-at-512 architecture config at
        # sam2/configs/sam2.1_hiera_t512.yaml. Hydra's search root is pkg://sam2.
        sam_model = build_sam2(
            config_file="configs/sam2.1_hiera_t512.yaml",
            ckpt_path=str(weights.medsam2_checkpoint),
            device=device,
        )
        self._predictor = SAM2ImagePredictor(sam_model)

    def segment_frame(
        self,
        image: np.ndarray,
        pos_points: list[tuple[int, int]],
        neg_points: list[tuple[int, int]],
        box: list[int] | None,
    ) -> np.ndarray:
        """Return a binary mask for the prompt on a single RGB frame."""
        self._predictor.set_image(image)
        point_coords, point_labels = _build_point_prompts(pos_points, neg_points)
        masks, scores, _ = self._predictor.predict(
            point_coords=point_coords,
            point_labels=point_labels,
            box=np.array(box, dtype=np.float32) if box else None,
            multimask_output=True,
        )
        best = int(np.argmax(scores))
        return masks[best].astype(np.uint8)


def _build_point_prompts(
    pos_points: list[tuple[int, int]],
    neg_points: list[tuple[int, int]],
) -> tuple[np.ndarray | None, np.ndarray | None]:
    if not pos_points and not neg_points:
        return None, None
    coords = np.array(list(pos_points) + list(neg_points), dtype=np.float32)
    labels = np.array([1] * len(pos_points) + [0] * len(neg_points), dtype=np.int32)
    return coords, labels


def load_image(image_bytes: bytes) -> np.ndarray:
    return np.asarray(Image.open(io.BytesIO(image_bytes)).convert("RGB"))
