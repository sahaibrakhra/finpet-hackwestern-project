"""sprite2d provider: turn the (background-removed) photo into a flat, textured 2D puppet mesh.

Nothing leaves this machine and no GPU is needed. The cut-out is cropped to its subject, covered with a
regular grid of quads (cells that contain no subject are dropped), and exported as a GLB with the photo as
its base-colour texture. The rest of the pipeline then rigs it exactly like a 3D model (skeleton, region
weights, idle/wave/dance clips) and the viewer shows it unlit and front-on, so it reads as a 2D character.
"""
from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Optional

import numpy as np
from PIL import Image

from .base import Provider, ProviderError, ProgressCb

log = logging.getLogger("avatar3d.sprite2d")


class Sprite2DProvider(Provider):
    name = "sprite2d"
    third_party = False

    def __init__(self) -> None:
        self.rows = int(os.getenv("SPRITE_ROWS", "110"))       # grid cells along the character's height
        self.max_tex = int(os.getenv("SPRITE_TEXTURE_SIZE", "1024"))

    def generate(self, image_path: Path, on_progress: Optional[ProgressCb] = None) -> Path:
        say = on_progress or (lambda _m: None)
        import trimesh
        from trimesh.visual import TextureVisuals
        from trimesh.visual.material import PBRMaterial

        say("Building the 2D puppet from your photo...")
        try:
            img = Image.open(image_path).convert("RGBA")
        except Exception as e:  # noqa: BLE001
            raise ProviderError(f"Could not open the photo: {e}") from e

        alpha = np.asarray(img)[..., 3]
        ys, xs = np.nonzero(alpha > 16)
        if len(xs) < 100:  # no usable cut-out (e.g. background removal was off): use the whole image, opaque
            img.putalpha(255)
            alpha = np.asarray(img)[..., 3]
            x0, y0, x1, y1 = 0, 0, img.width - 1, img.height - 1
        else:
            x0, x1, y0, y1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
        pad = max(2, int(0.01 * max(x1 - x0, y1 - y0)))
        x0, y0 = max(0, x0 - pad), max(0, y0 - pad)
        x1, y1 = min(img.width - 1, x1 + pad), min(img.height - 1, y1 + pad)
        crop = img.crop((x0, y0, x1 + 1, y1 + 1))
        if max(crop.size) > self.max_tex:
            crop.thumbnail((self.max_tex, self.max_tex), Image.LANCZOS)
        w, h = crop.size
        a = np.asarray(crop)[..., 3] > 16

        rows = max(24, self.rows)
        cell = h / rows
        cols = max(4, int(round(w / cell)))
        # a cell is kept when any subject pixel falls inside it
        cell_keep = np.zeros((rows, cols), dtype=bool)
        for r in range(rows):
            ya, yb = int(r * h / rows), max(int(r * h / rows) + 1, int((r + 1) * h / rows))
            for c in range(cols):
                xa, xb = int(c * w / cols), max(int(c * w / cols) + 1, int((c + 1) * w / cols))
                cell_keep[r, c] = a[ya:yb, xa:xb].any()
        if cell_keep.sum() < 8:
            raise ProviderError("The cut-out is empty, so there is nothing to build a 2D avatar from.")

        # world size: 1 unit tall, width follows the photo's aspect ratio; y is up, front faces +Z
        height = 1.0
        width = w / h
        gx = np.linspace(-width / 2, width / 2, cols + 1)
        gy = np.linspace(height, 0.0, rows + 1)          # row 0 is the top of the picture
        vid = -np.ones((rows + 1, cols + 1), dtype=np.int64)
        faces = []
        for r in range(rows):
            for c in range(cols):
                if not cell_keep[r, c]:
                    continue
                corners = [(r, c), (r, c + 1), (r + 1, c), (r + 1, c + 1)]
                for rc in corners:
                    if vid[rc] < 0:
                        vid[rc] = 0  # mark used; real ids assigned below
        used = np.argwhere(vid >= 0)
        for i, (r, c) in enumerate(used):
            vid[r, c] = i
        verts = np.array([[gx[c], gy[r], 0.0] for r, c in used], dtype=np.float64)
        uv = np.array([[c / cols, 1.0 - r / rows] for r, c in used], dtype=np.float64)  # v is up in trimesh
        for r in range(rows):
            for c in range(cols):
                if not cell_keep[r, c]:
                    continue
                a_, b_, c_, d_ = vid[r, c], vid[r, c + 1], vid[r + 1, c], vid[r + 1, c + 1]
                faces.append([a_, c_, b_])  # counter-clockwise seen from +Z
                faces.append([b_, c_, d_])
        faces = np.array(faces, dtype=np.int64)

        mat = PBRMaterial(baseColorTexture=crop, baseColorFactor=[255, 255, 255, 255], metallicFactor=0.0,
                          roughnessFactor=1.0, alphaMode="MASK", alphaCutoff=0.5, doubleSided=True)
        mesh = trimesh.Trimesh(vertices=verts, faces=faces, process=False)
        mesh.visual = TextureVisuals(uv=uv, material=mat)
        out = image_path.with_name(f"{image_path.stem}_2d.glb")
        trimesh.Scene([mesh]).export(str(out), file_type="glb")
        log.info("sprite2d: %dx%d texture, %d vertices, %d faces", w, h, len(verts), len(faces))
        say("2D puppet built.")
        return out
