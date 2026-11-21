"""Local, CPU-only heuristic auto-rigger.

Takes any static GLB of an upright, front-facing (+Z) character (Y up) and writes a new
GLB that has a humanoid skeleton, per-vertex skin weights and a looping "idle" clip.

How it works (crude on purpose, no ML, no GPU):
  1. Measure the mesh (height, torso width, arm span) and place a Mixamo-style skeleton.
  2. Skin each vertex to its nearest bone segments (inverse-distance weights, max 4).
  3. Write skeleton + skin + a small idle animation with pygltflib.
Works best for roughly humanoid characters. Odd shapes will deform oddly.
"""
from __future__ import annotations

import logging
import math
from pathlib import Path

import numpy as np

log = logging.getLogger("avatar3d.rigging")

IDLE_PERIOD_S = 4.0


class RigError(Exception):
    pass


# --------------------------------------------------------------------------- skeleton
def _slice_halfwidth(v: np.ndarray, y0: float, y1: float, cx: float) -> float:
    m = (v[:, 1] >= y0) & (v[:, 1] <= y1)
    if not m.any():
        return 0.0
    return float(np.abs(v[m, 0] - cx).max())


def fit_skeleton(v: np.ndarray) -> list[tuple[str, int, np.ndarray]]:
    """Return [(name, parent_index (-1 = root), world_position)] fitted to vertices v (N,3)."""
    lo, hi = v.min(axis=0), v.max(axis=0)
    H = float(hi[1] - lo[1])
    if H <= 1e-6:
        raise RigError("mesh has no height")
    cx = float((lo[0] + hi[0]) / 2)
    cz = float((lo[2] + hi[2]) / 2)

    def y(f: float) -> float:
        return float(lo[1] + f * H)

    torso = float(np.clip(_slice_halfwidth(v, y(.45), y(.55), cx), .08 * H, .30 * H))
    wmax = max(_slice_halfwidth(v, y(.55), y(.80), cx), torso)
    t_pose = wmax > 1.6 * torso

    def P(x: float, f: float, z: float = 0.0) -> np.ndarray:
        return np.array([cx + x, y(f), cz + z], dtype=np.float64)

    hip_x = max(.35 * torso, .04 * H)
    joints: list[tuple[str, int, np.ndarray]] = [
        ("Hips", -1, P(0, .50)),
        ("Spine", 0, P(0, .58)),
        ("Chest", 1, P(0, .68)),
        ("Neck", 2, P(0, .80)),
        ("Head", 3, P(0, .86)),
        ("HeadTop", 4, P(0, 1.0)),
    ]
    # glTF faces +Z, so the character's left is +X.
    for side, sign in (("Left", 1), ("Right", -1)):
        sh = P(sign * .8 * min(torso, wmax), .76)
        if t_pose:
            wr = P(sign * .95 * wmax, .70)
            el = P(sign * (.8 * min(torso, wmax) + .95 * wmax) / 2, .73)
            end = P(sign * wmax, .69)
        else:
            el, wr = P(sign * .9 * wmax, .60), P(sign * .9 * wmax, .46)
            end = P(sign * .9 * wmax, .41)
        base = len(joints)
        joints += [
            (f"{side}UpperArm", 2, sh), (f"{side}LowerArm", base, el),
            (f"{side}Hand", base + 1, wr), (f"{side}HandEnd", base + 2, end),
        ]
    for side, sign in (("Left", 1), ("Right", -1)):
        base = len(joints)
        joints += [
            (f"{side}UpperLeg", 0, P(sign * hip_x, .50)), (f"{side}LowerLeg", base, P(sign * hip_x, .27)),
            (f"{side}Foot", base + 1, P(sign * hip_x, .06)), (f"{side}Toe", base + 2, P(sign * hip_x, .0, .08 * H)),
        ]
    return joints


# --------------------------------------------------------------------------- skin weights
def _seg_dist(p: np.ndarray, a: np.ndarray, b: np.ndarray) -> np.ndarray:
    ab = b - a
    t = np.clip(((p - a) @ ab) / max(float(ab @ ab), 1e-12), 0.0, 1.0)
    return np.linalg.norm(p - (a + t[:, None] * ab), axis=1)


def skin_weights(v: np.ndarray, joints, max_influences: int = 4):
    """Return (joint_idx (N,4) uint16, weights (N,4) float32)."""
    n = len(joints)
    pos = np.array([j[2] for j in joints])
    H = float(v[:, 1].max() - v[:, 1].min())
    cx = float((v[:, 0].min() + v[:, 0].max()) / 2)
    cols, owners = [], []
    for i in range(n):
        kids = [k for k in range(n) if joints[k][1] == i]
        if not kids:
            continue
        # bone i runs from joint i to its first child
        d = _seg_dist(v, pos[i], pos[kids[0]])
        name = joints[i][0]
        if name.startswith("Left") or name.startswith("Right"):  # keep the two sides apart
            sign = 1 if name.startswith("Left") else -1
            same = (v[:, 0] - cx) * sign > -0.03 * H
            d = np.where(same, d, d * 4.0 + 0.05 * H)
        cols.append(d)
        owners.append(i)
    D = np.stack(cols, axis=1)  # (N, bones)
    k = min(max_influences, D.shape[1])
    idx = np.argpartition(D, k - 1, axis=1)[:, :k]
    dk = np.take_along_axis(D, idx, axis=1)
    w = 1.0 / (dk + 0.01 * H) ** 4
    w /= w.sum(axis=1, keepdims=True)
    owners_arr = np.array(owners)
    ji = np.zeros((len(v), 4), dtype=np.uint16)
    ww = np.zeros((len(v), 4), dtype=np.float32)
    ji[:, :k] = owners_arr[idx]
    ww[:, :k] = w
    ww /= ww.sum(axis=1, keepdims=True)
    return ji, ww


# --------------------------------------------------------------------------- glTF writing
def _qmul(a, b):
    x1, y1, z1, w1 = a
    x2, y2, z2, w2 = b
    return np.array([w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2, w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
                     w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2, w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2])


def _axis_quat(axis, angle):
    ax = np.asarray(axis, dtype=np.float64)
    ax = ax / np.linalg.norm(ax)
    s = math.sin(angle / 2)
    return np.array([ax[0] * s, ax[1] * s, ax[2] * s, math.cos(angle / 2)])


def rig_glb(src: Path, dst: Path) -> dict:
    """Rig ``src`` (GLB) into ``dst``. Returns a small info dict. Raises RigError."""
    import pygltflib as pg
    import trimesh

    try:
        scene = trimesh.load(str(src), force="scene")
        raw = pg.GLTF2().load_binary(str(src))
    except Exception as e:  # noqa: BLE001
        raise RigError(f"could not read GLB: {e}") from e
    if raw.skins:
        raise RigError("model already has a skeleton")
    geoms = [g for g in scene.dump(concatenate=False) if hasattr(g, "vertices") and len(g.vertices)]
    if not geoms:
        raise RigError("model has no meshes")
    flat = trimesh.Scene(geoms)  # world-space geometry, identity node transforms, textures kept
    gltf = pg.GLTF2().load_from_bytes(flat.export(file_type="glb"))

    allv = np.concatenate([np.asarray(g.vertices, dtype=np.float64) for g in geoms])
    joints = fit_skeleton(allv)

    blob = bytearray(gltf.binary_blob() or b"")

    def add_view_accessor(arr: np.ndarray, comp: int, typ: str, target=None, minmax=False) -> int:
        while len(blob) % 4:
            blob.append(0)
        data = np.ascontiguousarray(arr).tobytes()
        gltf.bufferViews.append(pg.BufferView(buffer=0, byteOffset=len(blob), byteLength=len(data), target=target))
        blob.extend(data)
        acc = pg.Accessor(bufferView=len(gltf.bufferViews) - 1, componentType=comp, type=typ,
                          count=int(arr.shape[0]))
        if minmax:
            acc.min, acc.max = [float(arr.min())], [float(arr.max())]
        gltf.accessors.append(acc)
        return len(gltf.accessors) - 1

    # joint nodes
    base_idx = len(gltf.nodes)
    for name, parent, p in joints:
        local = p - (joints[parent][2] if parent >= 0 else 0)
        gltf.nodes.append(pg.Node(name=name, translation=[float(x) for x in local]))
    for i, (_, parent, _) in enumerate(joints):
        if parent >= 0:
            pn = gltf.nodes[base_idx + parent]
            pn.children = (pn.children or []) + [base_idx + i]
    gltf.scenes[gltf.scene or 0].nodes.append(base_idx)  # Hips is the only skeleton root

    ibm = np.zeros((len(joints), 4, 4), dtype=np.float32)
    for i, (_, _, p) in enumerate(joints):
        m = np.eye(4)
        m[:3, 3] = -p
        ibm[i] = m.T  # glTF is column-major
    ibm_acc = add_view_accessor(ibm.reshape(-1, 16), pg.FLOAT, "MAT4")
    gltf.skins.append(pg.Skin(name="Armature", joints=list(range(base_idx, base_idx + len(joints))),
                              inverseBindMatrices=ibm_acc, skeleton=base_idx))

    skinned = 0
    for node in gltf.nodes[:base_idx]:
        if node.mesh is None:
            continue
        if node.matrix or node.translation or node.rotation or node.scale:
            raise RigError("unexpected node transform after flattening")
        for prim in gltf.meshes[node.mesh].primitives:
            acc = gltf.accessors[prim.attributes.POSITION]
            bv = gltf.bufferViews[acc.bufferView]
            start = (bv.byteOffset or 0) + (acc.byteOffset or 0)
            stride = bv.byteStride or 12
            chunk = np.frombuffer(bytes(blob[start:start + stride * acc.count]), dtype=np.uint8)
            pos = chunk.reshape(acc.count, stride)[:, :12].copy().view(np.float32).reshape(-1, 3)
            ji, ww = skin_weights(pos.astype(np.float64), joints)
            prim.attributes.JOINTS_0 = add_view_accessor(ji, pg.UNSIGNED_SHORT, "VEC4", pg.ARRAY_BUFFER)
            prim.attributes.WEIGHTS_0 = add_view_accessor(ww, pg.FLOAT, "VEC4", pg.ARRAY_BUFFER)
            skinned += 1
        node.skin = 0
    if not skinned:
        raise RigError("no mesh primitives to skin")

    # looping idle clip: breathing / sway on spine, chest, head and arms
    steps = 16
    times = np.linspace(0, IDLE_PERIOD_S, steps + 1, dtype=np.float32)
    t_acc = add_view_accessor(times, pg.FLOAT, "SCALAR", minmax=True)
    names = {j[0]: base_idx + i for i, j in enumerate(joints)}
    motions = [  # joint, axis, amplitude (deg), phase (rad)
        ("Spine", (1, 0, 0), 1.2, 0.0), ("Chest", (1, 0, 0), 1.5, 0.4), ("Spine", (0, 1, 0), 1.5, 0.0),
        ("Head", (1, 0, 0), 1.5, 0.9), ("Head", (0, 1, 0), 3.0, 1.6),
        ("LeftUpperArm", (0, 0, 1), 2.5, 0.5), ("RightUpperArm", (0, 0, 1), -2.5, 0.5),
        ("Hips", (0, 0, 1), 1.0, 2.0),
    ]
    anim = pg.Animation(name="idle", samplers=[], channels=[])
    by_joint: dict[str, list] = {}
    for jn, axis, amp, ph in motions:
        by_joint.setdefault(jn, []).append((axis, amp, ph))
    for jn, parts in by_joint.items():
        q = []
        for t in times:
            qq = np.array([0, 0, 0, 1.0])
            for axis, amp, ph in parts:
                a = math.radians(amp) * math.sin(2 * math.pi * float(t) / IDLE_PERIOD_S + ph)
                qq = _qmul(qq, _axis_quat(axis, a))
            q.append(qq / np.linalg.norm(qq))
        q[-1] = q[0]
        o_acc = add_view_accessor(np.array(q, dtype=np.float32), pg.FLOAT, "VEC4")
        anim.samplers.append(pg.AnimationSampler(input=t_acc, output=o_acc, interpolation="LINEAR"))
        anim.channels.append(pg.AnimationChannel(
            sampler=len(anim.samplers) - 1, target=pg.AnimationChannelTarget(node=names[jn], path="rotation")))
    gltf.animations.append(anim)

    while len(blob) % 4:
        blob.append(0)
    gltf.set_binary_blob(bytes(blob))
    gltf.buffers[0].byteLength = len(blob)
    gltf.save_binary(str(dst))
    return {"joints": len(joints), "primitives": skinned}
