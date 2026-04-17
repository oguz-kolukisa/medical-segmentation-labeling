"""Nuclio entry point for the MedSAM2 interactor function.

Kept deliberately thin — transport only; ML lives in `model_handler.py`.
CVAT's v2 interactor contract: request carries `image` (base64), optional
`pos_points`/`neg_points`/`obj_bbox`; response is `{"mask": [[0/1, ...]]}`.
"""
from __future__ import annotations

import base64
import json
import os

import numpy as np

from model_handler import MedSAM2Model, load_image


def init_context(context) -> None:
    device = os.environ.get("KUZEY_DEVICE", "cpu")
    context.logger.info(f"Loading MedSAM2 on {device}…")
    context.user_data.model = MedSAM2Model(device=device)
    context.logger.info("MedSAM2 ready")


def handler(context, event):
    # CVAT passes event.body already parsed as a dict.
    payload = event.body
    image = load_image(base64.b64decode(payload["image"]))
    mask = context.user_data.model.segment_frame(
        image=image,
        pos_points=payload.get("pos_points", []),
        neg_points=payload.get("neg_points", []),
        box=payload.get("obj_bbox"),
    )
    return context.Response(
        body=json.dumps({"mask": _encode_mask(mask)}),
        content_type="application/json",
        status_code=200,
    )


def _encode_mask(mask: np.ndarray) -> list[list[int]]:
    # CVAT accepts a 2D list of 0/1 pixels for mask responses.
    return mask.astype(int).tolist()
