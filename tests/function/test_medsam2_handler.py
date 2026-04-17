"""Unit test for the Nuclio handler transport layer.

We don't load MedSAM2 here — that requires GPU + 1 GB of weights. We stub the
model to verify dispatch, decode, and response encoding.
"""
from __future__ import annotations

import base64
import io
import json
import sys
import types
from pathlib import Path

import numpy as np
import pytest
from PIL import Image


NUCLIO_DIR = Path(__file__).resolve().parents[2] / "serverless" / "medsam2" / "nuclio"


@pytest.fixture()
def main_module(monkeypatch):
    """Import main.py with sam2 stubbed out."""
    sys.path.insert(0, str(NUCLIO_DIR))
    # Stub the sam2 import chain so model_handler loads without MedSAM2 installed.
    fake_sam2 = types.ModuleType("sam2")
    fake_build = types.ModuleType("sam2.build_sam")
    fake_build.build_sam2_video_predictor = lambda **kw: None  # type: ignore[attr-defined]
    monkeypatch.setitem(sys.modules, "sam2", fake_sam2)
    monkeypatch.setitem(sys.modules, "sam2.build_sam", fake_build)
    monkeypatch.setenv("KUZEY_HANDLER_KIND", "interactor")
    monkeypatch.setenv("KUZEY_DEVICE", "cpu")
    import importlib
    if "main" in sys.modules: del sys.modules["main"]
    if "model_handler" in sys.modules: del sys.modules["model_handler"]
    return importlib.import_module("main")


class _FakeModel:
    def segment_frame(self, image, pos_points, neg_points, box):
        h, w, _ = image.shape
        mask = np.zeros((h, w), dtype=np.uint8)
        for x, y in pos_points:
            mask[max(0, y - 2): y + 3, max(0, x - 2): x + 3] = 1
        return mask

    def propagate(self, image, prev_mask, state_id):
        return prev_mask


class _FakeContext:
    def __init__(self, kind: str):
        self.user_data = types.SimpleNamespace(model=_FakeModel(), kind=kind)
        self.logger = types.SimpleNamespace(info=lambda *_a, **_k: None)

    def Response(self, body, headers, status_code):
        return types.SimpleNamespace(body=body, headers=headers, status_code=status_code)


def _encoded_image(size: int = 32) -> str:
    buf = io.BytesIO()
    Image.new("RGB", (size, size), color=(0, 0, 0)).save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode()


def test_interactor_returns_mask_near_click(main_module):
    ctx = _FakeContext(kind="interactor")
    event = types.SimpleNamespace(body=json.dumps({
        "image": _encoded_image(),
        "pos_points": [[10, 10]],
        "neg_points": [],
        "obj_bbox": None,
    }))
    resp = main_module.handler(ctx, event)
    mask = np.array(json.loads(resp.body)["mask"], dtype=np.uint8)
    assert resp.status_code == 200
    assert mask[10, 10] == 1
    assert mask.sum() > 0


def test_tracker_propagates_previous_mask(main_module, monkeypatch):
    monkeypatch.setenv("KUZEY_HANDLER_KIND", "tracker")
    ctx = _FakeContext(kind="tracker")
    prev = np.zeros((32, 32), dtype=np.uint8); prev[5:15, 5:15] = 1
    event = types.SimpleNamespace(body=json.dumps({
        "image": _encoded_image(),
        "shape": prev.tolist(),
        "job": "42",
        "track_id": "7",
    }))
    resp = main_module.handler(ctx, event)
    out = np.array(json.loads(resp.body)["mask"], dtype=np.uint8)
    assert out.shape == prev.shape
    assert out.sum() == prev.sum()
