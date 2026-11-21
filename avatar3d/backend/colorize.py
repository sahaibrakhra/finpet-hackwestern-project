"""Cheap, local colouring: project the (background-removed) photo onto an untextured mesh.

Front-view orthographic projection: every vertex takes the colour of the photo pixel at the same
relative x/y position inside the subject's bounding box. Vertices facing away from the camera
(normal -Z) get a slightly darker copy of the same colours, so the back is a mirrored guess.
Runs on CPU, no network. Skipped when the mesh already has a texture or vertex colours.
"""
from __future__ import annotations

import logging
from pathlib import Path

import numpy as np
import trimesh
from PIL import Image

log = logging.getLogger("avatar3d.colorize")


class ColorizeError(Exception):
    pass


def _already_coloured(geom) -> bool:
    vis = getattr(geom, "visual", None)
    kind = getattr(vis, "kind", None)
    if kind == "texture":
        return True
    if kind == "vertex":
        vc = np.asarray(vis.vertex_colors)
        return len(vc) > 0 and bool((vc[:, :3].std(axis=0) > 3).any())
    return False


def colorize_glb(src: Path, image_path: Path, dst: Path, back_shade: float = 0.75) -> dict:
    img = Image.open(image_path).convert("RGBA")
    arr = np.asarray(img)
    alpha = arr[..., 3]
    ys, xs = np.nonzero(alpha > 16)
    if len(xs) < 50:  # no usable cut-out: use the whole image
        x0, x1, y0, y1 = 0, arr.shape[1] - 1, 0, arr.shape[0] - 1
    else:
        x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    sub = arr[y0:y1 + 1, x0:x1 + 1]
    h, w = sub.shape[:2]

    scene = trimesh.load(str(src), force="scene")
    geoms = [g for g in scene.dump(concatenate=False) if hasattr(g, "vertices") and len(g.vertices)]
    if not geoms:
        raise ColorizeError("model has no meshes")
    if all(_already_coloured(g) for g in geoms):
        raise ColorizeError("model already has colours/texture")

    allv = np.concatenate([np.asarray(g.vertices) for g in geoms])
    lo, hi = allv.min(axis=0), allv.max(axis=0)
    span = np.maximum(hi - lo, 1e-9)
    # Match the photo's aspect ratio to the mesh's: letterbox the narrower one, centred.
    mesh_aspect, img_aspect = span[0] / span[1], w / h
    for g in geoms:
        v = np.asarray(g.vertices)
        u = (v[:, 0] - lo[0]) / span[0]
        t = 1.0 - (v[:, 1] - lo[1]) / span[1]  # image y grows downward
        if mesh_aspect > img_aspect:   # mesh wider than photo: squeeze u into the middle
            f = img_aspect / mesh_aspect
            u = 0.5 + (u - 0.5) / f
        elif mesh_aspect < img_aspect:  # mesh taller: squeeze t
            f = mesh_aspect / img_aspect
            t = 0.5 + (t - 0.5) / f
        px = np.clip((u * (w - 1)).round().astype(int), 0, w - 1)
        py = np.clip((t * (h - 1)).round().astype(int), 0, h - 1)
        col = sub[py, px].astype(np.float64)
        # Pixels that fall on transparent background: borrow the nearest opaque row colour (mean subject colour).
        opaque = sub[..., 3] > 16
        mean = sub[opaque][:, :3].mean(axis=0) if opaque.any() else np.array([200, 200, 200.0])
        bad = col[:, 3] <= 16
        col[bad, :3] = mean
        normals = np.asarray(g.vertex_normals)
        back = normals[:, 2] < -0.2
        col[back, :3] *= back_shade
        col[:, 3] = 255
        g.visual = trimesh.visual.ColorVisuals(g, vertex_colors=np.clip(col, 0, 255).astype(np.uint8))

    trimesh.Scene(geoms).export(str(dst), file_type="glb")
    return {"meshes": len(geoms), "vertices": int(len(allv))}
