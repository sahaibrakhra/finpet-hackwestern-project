"""Mock provider: a static humanoid mannequin built from capsules and spheres."""
from __future__ import annotations

import logging
import os
import time
from pathlib import Path
from typing import Optional

import numpy as np
import trimesh
from PIL import Image

from .base import Provider, ProgressCb

log = logging.getLogger("avatar3d.mock")


def _avg_color(image_path: Path) -> tuple[int, int, int]:
    """Average colour of the visible pixels; used to tint the shirt so uploads differ."""
    try:
        im = Image.open(image_path).convert("RGBA").resize((32, 32))
        a = np.asarray(im, dtype=np.float32)
        mask = a[..., 3] > 128
        px = a[mask][:, :3] if mask.any() else a.reshape(-1, 4)[:, :3]
        r, g, b = px.mean(axis=0)
        return int(r), int(g), int(b)
    except Exception:  # noqa: BLE001
        return 70, 120, 200


def _colored(mesh: trimesh.Trimesh, rgb) -> trimesh.Trimesh:
    mesh.visual.vertex_colors = np.tile(np.array([*rgb, 255], dtype=np.uint8), (len(mesh.vertices), 1))
    return mesh


def _limb(p0, p1, radius, rgb) -> trimesh.Trimesh:
    """Capsule whose end caps sit at p0 and p1."""
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    d = p1 - p0
    length = float(np.linalg.norm(d))
    cap = trimesh.creation.capsule(height=max(length - 2 * radius, 1e-3), radius=radius, count=[16, 16])
    # capsule is built along +Z centred at origin; rotate Z -> d
    rot = trimesh.geometry.align_vectors([0, 0, 1], d / length)
    cap.apply_transform(rot)
    cap.apply_translation((p0 + p1) / 2)
    return _colored(cap, rgb)


def _sphere(center, radius, rgb) -> trimesh.Trimesh:
    s = trimesh.creation.icosphere(subdivisions=3, radius=radius)
    s.apply_translation(center)
    return _colored(s, rgb)


def build_mannequin(shirt_rgb=(70, 120, 200)) -> trimesh.Scene:
    """Y-up, ~1.8 m tall, facing +Z, feet on y=0."""
    skin = (226, 190, 160)
    pants = (55, 60, 80)
    shoe = (40, 40, 40)
    parts = []
    # Legs
    for sx in (-1, 1):
        x = 0.1 * sx
        parts.append(_limb([x, 0.09, 0.0], [x, 0.50, 0.0], 0.075, pants))        # shin
        parts.append(_limb([x, 0.50, 0.0], [x, 0.92, 0.0], 0.09, pants))         # thigh
        parts.append(_sphere([x, 0.50, 0.0], 0.08, pants))                       # knee
        parts.append(_limb([x, 0.05, 0.0], [x, 0.05, 0.14], 0.05, shoe))         # foot
    # Pelvis, torso
    parts.append(_limb([-0.1, 0.95, 0], [0.1, 0.95, 0], 0.11, pants))
    parts.append(_limb([0, 1.0, 0], [0, 1.4, 0], 0.16, shirt_rgb))
    # Shoulders, arms
    for sx in (-1, 1):
        sh = [0.21 * sx, 1.42, 0]
        parts.append(_sphere(sh, 0.065, shirt_rgb))
        parts.append(_limb(sh, [0.27 * sx, 1.15, 0.0], 0.05, shirt_rgb))         # upper arm
        parts.append(_limb([0.27 * sx, 1.15, 0.0], [0.30 * sx, 0.90, 0.04], 0.042, skin))  # forearm
        parts.append(_sphere([0.30 * sx, 0.87, 0.04], 0.05, skin))               # hand
    # Neck, head
    parts.append(_limb([0, 1.45, 0], [0, 1.55, 0], 0.05, skin))
    head = trimesh.creation.icosphere(subdivisions=3, radius=0.115)
    head.apply_scale([0.92, 1.12, 1.0])
    head.apply_translation([0, 1.67, 0])
    parts.append(_colored(head, skin))

    scene = trimesh.Scene()
    for i, m in enumerate(parts):
        scene.add_geometry(m, node_name=f"part_{i}", geom_name=f"part_{i}")
    return scene


class MockProvider(Provider):
    name = "mock"
    third_party = False

    def generate(self, image_path: Path, on_progress: Optional[ProgressCb] = None) -> Path:
        delay = float(os.getenv("MOCK_DELAY_S", "4"))
        if on_progress:
            on_progress("Building mannequin mesh (mock provider)...")
        time.sleep(delay)
        scene = build_mannequin(_avg_color(image_path))
        out = image_path.with_name(f"{image_path.stem}_mock.glb")
        scene.export(str(out), file_type="glb")
        log.info("mock mesh written: %s", out)
        return out
