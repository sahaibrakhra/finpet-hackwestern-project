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


# --------------------------------------------------------------------------- skeleton + regions
def _smooth(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def _median_filter(a: np.ndarray, k: int = 5) -> np.ndarray:
    pad = k // 2
    p = np.pad(a, pad, mode="edge")
    return np.array([np.median(p[i:i + k]) for i in range(len(a))])


class Layout:
    """Measurements of the mesh that both the skeleton and the skin weights are derived from."""

    def __init__(self, v: np.ndarray):
        self.lo, self.hi = v.min(axis=0), v.max(axis=0)
        self.H = float(self.hi[1] - self.lo[1])
        if self.H <= 1e-6:
            raise RigError("mesh has no height")
        H = self.H
        self.cx = float((self.lo[0] + self.hi[0]) / 2)
        self.cz = float((self.lo[2] + self.hi[2]) / 2)
        self.ymin, self.ymax = float(self.lo[1]), float(self.hi[1])
        ax = np.abs(v[:, 0] - self.cx)
        nb = 80
        bins = np.minimum(((v[:, 1] - self.ymin) / H * nb).astype(int), nb - 1)
        self.nb = nb

        # --- crotch: top of the zone, measured up from the feet, where there is an empty gap down the middle
        gap = 0.03 * H
        centre_count = np.bincount(bins[ax < gap], minlength=nb)
        y_c = None
        run = 0
        for b in range(nb):
            if centre_count[b] == 0:
                run = b + 1
            elif run > 0:
                break
        if run >= max(3, int(0.08 * nb)):
            y_c = self.ymin + run / nb * H
        self.legs_confident = y_c is not None   # a real gap between the legs was seen
        self.has_legs = True                    # otherwise assume legs below ~42% height, split down the middle
        self.y_c = y_c if y_c is not None else self.ymin + 0.42 * H
        U = self.ymax - self.y_c  # height of the upper body (torso + head)
        self.U = U

        # --- per-bin half-widths (robust: ignore the top few percent, which is where thin arms live)
        hw = np.zeros(nb)
        for b in range(nb):
            m = bins == b
            hw[b] = np.percentile(ax[m], 90) if m.sum() > 8 else 0.0
        self.hw = _median_filter(hw, 5)
        self.hw_bins = self.hw

        # --- neck: strongest width step above the shoulders (head wider than torso or narrower)
        def bin_of(y):
            return int(np.clip((y - self.ymin) / H * nb, 0, nb - 1))
        b0, b1 = bin_of(self.y_c + 0.30 * U), bin_of(self.ymax - 0.12 * U)
        best, neck_b = 1.0, None
        for b in range(max(b0, 4), min(b1, nb - 5)):
            lo_w = self.hw[b - 4:b].mean()
            hi_w = self.hw[b + 1:b + 5].mean()
            if lo_w > 1e-9:
                r = hi_w / lo_w
                if abs(np.log(r)) > abs(np.log(best)):
                    best, neck_b = r, b
        if neck_b is not None and abs(np.log(best)) > np.log(1.12):
            self.y_neck = self.ymin + (neck_b + 0.5) / nb * H
        else:
            self.y_neck = self.y_c + 0.78 * U
        self.y_neck = float(np.clip(self.y_neck, self.y_c + 0.3 * U, self.ymax - 0.1 * U))
        self.Ut = self.y_neck - self.y_c  # torso height

        # --- torso half-width (used for hip/shoulder placement)
        t0, t1 = bin_of(self.y_c + 0.1 * self.Ut), bin_of(self.y_neck - 0.05 * self.Ut)
        seg = self.hw[t0:max(t1, t0 + 1)]
        self.torso_hw = float(np.clip(np.median(seg) if len(seg) else 0.2 * H, 0.06 * H, 0.45 * H))

        # --- arm candidates: vertices that stick out beyond the robust body width, around shoulder height
        core = self.hw[bins] + 0.02 * H
        band = (v[:, 1] > self.y_c - 0.05 * H) & (v[:, 1] < self.y_neck + 0.25 * (self.ymax - self.y_neck))
        cand = band & (ax > core)
        self.arm_mask = {}
        self.arm_pts = {}
        for side, sign in (("Left", 1), ("Right", -1)):
            m = cand & ((v[:, 0] - self.cx) * sign > 0)
            self.arm_mask[side] = m
            self.arm_pts[side] = v[m] if m.sum() >= max(40, int(0.002 * len(v))) else None

        # T-pose / arms held out: the arms are so wide that they define the per-slice width, so measure
        # them against the waist instead.
        w0 = bin_of(self.y_c + 0.10 * self.Ut)
        w1 = max(bin_of(self.y_c + 0.45 * self.Ut), w0 + 1)
        waist_hw = float(np.median(self.hw[w0:w1])) if w1 > w0 else self.torso_hw
        band_ext = float(ax[band].max()) if band.any() else 0.0
        if waist_hw > 0.02 * H and band_ext > 1.8 * waist_hw:
            band_t = (v[:, 1] > self.y_c + 0.30 * self.Ut) & \
                     (v[:, 1] < self.y_neck + 0.10 * (self.ymax - self.y_neck))
            for side, sign in (("Left", 1), ("Right", -1)):
                m = band_t & (ax > waist_hw * 1.15) & ((v[:, 0] - self.cx) * sign > 0)
                if m.sum() >= max(40, int(0.005 * len(v))):
                    self.arm_mask[side] = m
                    self.arm_pts[side] = v[m]

        # Arms pressed against the body do not protrude, so look for a torso that is much wider than the legs:
        # the extra width at the sides is the arms.
        self.arms_inferred = False
        if self.arm_pts["Left"] is None and self.arm_pts["Right"] is None:
            leg_b0, leg_b1 = bin_of(self.ymin + 0.10 * (self.y_c - self.ymin)), bin_of(self.y_c - 0.05 * H)
            leg_seg = self.hw[leg_b0:max(leg_b1, leg_b0 + 1)]
            leg_hw = float(np.median(leg_seg)) if len(leg_seg) else 0.0
            if leg_hw > 0.02 * H and self.torso_hw > 1.35 * leg_hw:
                cut = leg_hw * 1.08
                band2 = (v[:, 1] > self.y_c + 0.1 * self.Ut) & (v[:, 1] < self.y_neck)
                for side, sign in (("Left", 1), ("Right", -1)):
                    m = band2 & (ax > cut) & ((v[:, 0] - self.cx) * sign > 0)
                    if m.sum() >= max(40, int(0.01 * len(v))):
                        self.arm_mask[side] = m
                        self.arm_pts[side] = v[m]
                        self.arms_inferred = True

        # --- leg centre lines (x of each leg at a few heights), for the hip / knee / ankle joints
        self.leg_x = {}
        Ll = self.y_c - self.ymin
        for side, sign in (("Left", 1), ("Right", -1)):
            xs = []
            for f in (0.9, 0.5, 0.12):  # near hip, knee, ankle
                yy = self.ymin + f * Ll
                m = (np.abs(v[:, 1] - yy) < 0.06 * Ll + 0.01 * H) & ((v[:, 0] - self.cx) * sign > gap * 0.5)
                xs.append(float(v[m, 0].mean() - self.cx) if m.sum() > 5 else sign * max(0.35 * self.torso_hw, 0.04 * H))
            self.leg_x[side] = xs


def fit_skeleton(v: np.ndarray):
    """Return (joints, layout). joints = [(name, parent_index (-1 = root), world_position)]."""
    L = Layout(v)
    H, cx, cz = L.H, L.cx, L.cz

    def P(x, y, z=0.0):
        return np.array([cx + x, y, cz + z], dtype=np.float64)

    yc, yn, ym = L.y_c, L.y_neck, L.ymax
    Ut = L.Ut
    joints: list[tuple[str, int, np.ndarray]] = [
        ("Hips", -1, P(0, yc + 0.15 * Ut)),
        ("Spine", 0, P(0, yc + 0.40 * Ut)),
        ("Chest", 1, P(0, yc + 0.68 * Ut)),
        ("Neck", 2, P(0, yn - 0.05 * Ut)),
        ("Head", 3, P(0, yn)),
        ("HeadTop", 4, P(0, ym)),
    ]
    L.arm_found = {}
    for side, sign in (("Left", 1), ("Right", -1)):
        pts = L.arm_pts[side]
        sh_y = yc + 0.88 * Ut
        if pts is not None:
            L.arm_found[side] = True
            top = pts[:, 1].max()
            sh = P(sign * (np.abs(pts[:, 0] - cx).min() + 0.005 * H), min(top, sh_y + 0.05 * H))
            low = pts[pts[:, 1] <= np.percentile(pts[:, 1], 12)]
            wr = np.array([low[:, 0].mean(), low[:, 1].mean(), cz])
            ext = np.abs(pts[:, 0] - cx).max()
            if ext > 1.6 * L.torso_hw and (top - low[:, 1].mean()) < 0.35 * ext:  # T-pose: arm runs outward
                wr = np.array([cx + sign * ext * 0.97, pts[:, 1].mean(), cz])
        else:
            L.arm_found[side] = False
            sh = P(sign * 0.8 * L.torso_hw, sh_y)
            wr = P(sign * 0.9 * L.torso_hw, sh_y - 0.28 * H)
        el = (sh + wr) / 2
        end = wr + (wr - sh) * 0.15
        base = len(joints)
        joints += [
            (f"{side}UpperArm", 2, sh), (f"{side}LowerArm", base, el),
            (f"{side}Hand", base + 1, wr), (f"{side}HandEnd", base + 2, end),
        ]
    Ll = yc - L.ymin
    for side, sign in (("Left", 1), ("Right", -1)):
        hx, kx, ax_ = L.leg_x[side]
        base = len(joints)
        joints += [
            (f"{side}UpperLeg", 0, P(hx, yc + 0.02 * Ut)),
            (f"{side}LowerLeg", base, P(kx, L.ymin + 0.5 * Ll)),
            (f"{side}Foot", base + 1, P(ax_, L.ymin + 0.12 * Ll)),
            (f"{side}Toe", base + 2, P(ax_, L.ymin + 0.02 * H, 0.06 * H)),
        ]
    return joints, L


# --------------------------------------------------------------------------- skin weights
def _chain(t: np.ndarray, bounds: list[float], blend: float) -> np.ndarray:
    """Soft-partition a 1D coordinate t (increasing toward the *end* of the chain) into len(bounds)+1 parts.

    Part 0 is t < bounds[0]; the last part is t > bounds[-1]. ``blend`` is the width of each transition.
    """
    a = [_smooth((t - b) / blend + 0.5) for b in bounds]  # a_k = "past boundary k"
    parts = [1.0 - a[0]]
    for k in range(1, len(bounds)):
        parts.append(a[k - 1] - a[k])
    parts.append(a[-1])
    return np.stack(parts, axis=1)


def skin_weights(v: np.ndarray, joints, L: Layout, max_influences: int = 4):
    """Rigid, region-based weights: each vertex follows one body part, blending only near the joints."""
    n = len(joints)
    idx = {j[0]: i for i, j in enumerate(joints)}
    pos = {j[0]: j[2] for j in joints}
    H, cx = L.H, L.cx
    N = len(v)
    W = np.zeros((N, n))
    y = v[:, 1]
    bl_t = 0.03 * H   # blend width on the torso
    bl_l = 0.025 * H  # blend width on limbs

    # legs below the crotch (split left/right by x)
    m_leg = 1.0 - _smooth((y - L.y_c) / (2 * bl_t) + 0.5) if L.has_legs else np.zeros(N)
    # torso chain, top to bottom: Head | Chest | Spine | Hips
    b_head = L.y_neck
    b_cs = (pos["Chest"][1] + pos["Spine"][1]) / 2
    b_sh = (pos["Spine"][1] + pos["Hips"][1]) / 2
    tw = _chain(-y, [-b_head, -b_cs, -b_sh], bl_t)
    torso = np.zeros((N, n))
    for col, name in enumerate(("Head", "Chest", "Spine", "Hips")):
        torso[:, idx[name]] = tw[:, col]

    # arms: thin parts sticking out of the body, split along the shoulder -> wrist line
    arm = np.zeros((N, n))
    m_arm = np.zeros(N)
    for side, sign in (("Left", 1), ("Right", -1)):
        if not L.arm_found.get(side):
            continue
        sh, wr = pos[f"{side}UpperArm"], pos[f"{side}Hand"]
        axis = wr - sh
        ln = float(np.linalg.norm(axis))
        if ln < 1e-6:
            continue
        t = ((v - sh) @ axis) / (ln * ln)  # 0 at the shoulder, 1 at the wrist
        cw = _chain(t, [0.5, 0.9], 0.12)   # UpperArm | LowerArm | Hand
        sel = L.arm_mask[side]
        for col, name in enumerate((f"{side}UpperArm", f"{side}LowerArm", f"{side}Hand")):
            arm[sel, idx[name]] = cw[sel, col]
        m_arm[sel] = 1.0

    # legs: split by side, then by height along the leg
    leg = np.zeros((N, n))
    if L.has_legs:
        for side, sign in (("Left", 1), ("Right", -1)):
            side_w = _smooth((sign * (v[:, 0] - cx)) / (0.02 * H) + 0.5)
            kn, an = pos[f"{side}LowerLeg"][1], pos[f"{side}Foot"][1]
            lw = _chain(-y, [-kn, -an], bl_l)  # UpperLeg | LowerLeg | Foot
            for col, name in enumerate((f"{side}UpperLeg", f"{side}LowerLeg", f"{side}Foot")):
                leg[:, idx[name]] += side_w * lw[:, col]

    W = m_leg[:, None] * leg + (1 - m_leg)[:, None] * ((1 - m_arm)[:, None] * torso + m_arm[:, None] * arm)
    k = min(max_influences, n)
    top = np.argpartition(-W, k - 1, axis=1)[:, :k]
    wk = np.take_along_axis(W, top, axis=1)
    s = wk.sum(axis=1, keepdims=True)
    bad = s[:, 0] < 1e-9
    wk[bad] = 0.0
    wk[bad, 0] = 1.0
    top[bad, 0] = idx["Hips"]
    s = wk.sum(axis=1, keepdims=True)
    wk = wk / s
    ji = np.zeros((N, 4), dtype=np.uint16)
    ww = np.zeros((N, 4), dtype=np.float32)
    ji[:, :k] = top
    ww[:, :k] = wk
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



def _read_accessor(gltf, blob, i):
    acc = gltf.accessors[i]
    bv = gltf.bufferViews[acc.bufferView]
    ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc.type]
    dt = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}[acc.componentType]
    isz = np.dtype(dt).itemsize * ncomp
    stride = bv.byteStride or isz
    start = (bv.byteOffset or 0) + (acc.byteOffset or 0)
    raw = np.frombuffer(bytes(blob[start:start + stride * acc.count]), dtype=np.uint8).reshape(acc.count, stride)
    return raw[:, :isz].copy().view(dt).reshape(acc.count, ncomp)


def _quat_to_mat(q) -> np.ndarray:
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def _scale_quat(q: np.ndarray, gain: float) -> np.ndarray:
    """Scale the rotation angle of unit quaternions (N,4) by ``gain`` (0 = rest pose)."""
    w = np.clip(q[:, 3], -1.0, 1.0)
    ang = 2 * np.arccos(w)
    sn = np.sqrt(np.maximum(1 - w * w, 1e-12))
    axis = q[:, :3] / sn[:, None]
    na = ang * gain
    out = np.concatenate([axis * np.sin(na / 2)[:, None], np.cos(na / 2)[:, None]], axis=1)
    out[ang < 1e-9] = [0, 0, 0, 1]
    return out


class _Stretch:
    """CPU linear-blend skinning used to measure how much a clip would stretch / tear the mesh."""

    def __init__(self, joints, prims, H, max_edges=40000, seed=0):
        self.joints = joints
        self.rest = np.array([j[2] for j in joints])
        self.parent = [j[1] for j in joints]
        self.local = np.array([j[2] - (joints[j[1]][2] if j[1] >= 0 else 0) for j in joints])
        self.H = H
        rng = np.random.default_rng(seed)
        self.prims = []
        for pos, ji, ww, idx in prims:
            tri = idx[: len(idx) // 3 * 3].reshape(-1, 3)
            e = np.concatenate([tri[:, [0, 1]], tri[:, [1, 2]], tri[:, [2, 0]]])
            if len(e) > max_edges:
                e = e[rng.choice(len(e), max_edges, replace=False)]
            l0 = np.linalg.norm(pos[e[:, 0]] - pos[e[:, 1]], axis=1)
            self.prims.append((pos, ji.astype(int), ww.astype(np.float64), e, l0))

    def _pose(self, rots: dict, trans: dict):
        n = len(self.joints)
        R = np.zeros((n, 3, 3))
        T = np.zeros((n, 3))
        for i in range(n):
            Rl = _quat_to_mat(rots.get(i, (0, 0, 0, 1.0)))
            loc_t = trans.get(i, self.local[i])
            par = self.parent[i]
            if par < 0:
                R[i], T[i] = Rl, loc_t
            else:
                R[i] = R[par] @ Rl
                T[i] = T[par] + R[par] @ loc_t
        return R, T

    def measure(self, rots: dict, trans: dict) -> float:
        """Worst-case edge length change, as a fraction of body height (99.7th percentile)."""
        R, T = self._pose(rots, trans)
        worst = 0.0
        for pos, ji, ww, e, l0 in self.prims:
            out = np.zeros_like(pos)
            for k in range(4):
                idx = ji[:, k]
                out += ww[:, k:k + 1] * (np.einsum("nij,nj->ni", R[idx], pos - self.rest[idx]) + T[idx])
            l1 = np.linalg.norm(out[e[:, 0]] - out[e[:, 1]], axis=1)
            worst = max(worst, float(np.percentile(np.abs(l1 - l0), 99.7)) / self.H)
        return worst


def _upright(geoms) -> bool:
    """Rotate Z-up (or X-up) exports to Y-up. Returns True if a rotation was applied."""
    import trimesh
    allv = np.concatenate([np.asarray(g.vertices) for g in geoms])
    ext = allv.max(0) - allv.min(0)
    if ext[2] > 1.3 * ext[1] and ext[2] >= ext[0]:      # tallest along Z -> Z-up
        m = trimesh.transformations.rotation_matrix(-math.pi / 2, [1, 0, 0])
    elif ext[0] > 1.3 * ext[1] and ext[0] > ext[2]:      # tallest along X
        m = trimesh.transformations.rotation_matrix(math.pi / 2, [0, 0, 1])
    else:
        return False
    for g in geoms:
        g.apply_transform(m)
    return True


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
    reoriented = _upright(geoms)
    flat = trimesh.Scene(geoms)  # world-space geometry, identity node transforms, textures kept
    gltf = pg.GLTF2().load_from_bytes(flat.export(file_type="glb"))

    allv = np.concatenate([np.asarray(g.vertices, dtype=np.float64) for g in geoms])
    joints, layout = fit_skeleton(allv)

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
    skin_prims = []
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
            ji, ww = skin_weights(pos.astype(np.float64), joints, layout)
            prim.attributes.JOINTS_0 = add_view_accessor(ji, pg.UNSIGNED_SHORT, "VEC4", pg.ARRAY_BUFFER)
            prim.attributes.WEIGHTS_0 = add_view_accessor(ww, pg.FLOAT, "VEC4", pg.ARRAY_BUFFER)
            if prim.indices is not None:
                idx = _read_accessor(gltf, blob, prim.indices).reshape(-1).astype(np.int64)
            else:
                idx = np.arange(acc.count, dtype=np.int64)
            skin_prims.append((pos.astype(np.float64), ji, ww, idx))
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

    # one-shot action clips (wave, dance). They start and end at the rest pose so the viewer can
    # crossfade idle -> clip -> idle without a pop.
    H = float(allv[:, 1].max() - allv[:, 1].min())
    jpos = {j[0]: j[2] for j in joints}

    D = math.radians

    def arm_raise(side: str) -> float:
        """Radians about +Z (negated for the right arm) that raise the arm as high as it can go while
        the hand still clears the body outline (so the motion is visible, not hidden inside a wide head)."""
        sign = 1 if side == "Left" else -1
        sh, wr = jpos[f"{side}UpperArm"], jpos[f"{side}Hand"]
        d = wr - sh
        alpha = math.atan2(d[1], d[0] * sign)           # rest direction of the arm (0 = straight outward)
        up = (math.pi / 2 - alpha) % (2 * math.pi)      # rotation that points it straight up
        out = (0.0 - alpha) % (2 * math.pi)             # rotation that points it straight outward
        if out > math.pi:
            out = 0.0
        ln = float(np.linalg.norm(d[:2]))
        for theta in np.linspace(max(min(up - D(15), out + D(55)), out), out, 24):
            ang = alpha + theta
            hx = (sh[0] - layout.cx) * sign + ln * math.cos(ang)
            hy = sh[1] + ln * math.sin(ang)
            b = int(np.clip((hy - layout.ymin) / layout.H * layout.nb, 0, layout.nb - 1))
            if hx > layout.hw[b] + 0.015 * H:
                return float(theta)
        return float(out)

    def smooth(x: float) -> float:
        x = min(max(x, 0.0), 1.0)
        return x * x * (3 - 2 * x)

    def envelope(t: float, dur: float, ramp: float = 0.5) -> float:
        return smooth(t / ramp) * smooth((dur - t) / ramp)

    stretch = _Stretch(joints, skin_prims, H)
    clip_gain: dict[str, float] = {}
    MAX_STRETCH = 0.03  # edges may change by at most 3% of body height before a clip is toned down

    def add_clip(name: str, dur: float, rot_fn, trans_fn=None, fps: int = 30) -> None:
        ts = np.arange(0, int(round(dur * fps)) + 1, dtype=np.float64) / fps
        raw_q = {}
        for jn, fn in rot_fn.items():
            q = np.array([fn(float(t)) for t in ts], dtype=np.float64)
            raw_q[jn] = q / np.linalg.norm(q, axis=1, keepdims=True)
        raw_t = {jn: np.array([fn(float(t)) for t in ts], dtype=np.float64) for jn, fn in (trans_fn or {}).items()}
        rest_t = {jn: jpos[jn] for jn in raw_t}  # translated joints here are root-level (world == local)
        jidx = {jn: names[jn] - base_idx for jn in list(raw_q) + list(raw_t)}
        frames = list(range(0, len(ts), max(1, fps // 2)))

        def worst(gain: float) -> float:
            w = 0.0
            for f in frames:
                rots = {jidx[jn]: tuple(_scale_quat(q[f:f + 1], gain)[0]) for jn, q in raw_q.items()}
                trans = {jidx[jn]: rest_t[jn] + (t[f] - rest_t[jn]) * gain for jn, t in raw_t.items()}
                w = max(w, stretch.measure(rots, trans))
            return w

        gain = 0.2
        for g in (1.0, 0.8, 0.6, 0.45, 0.3):
            if worst(g) <= MAX_STRETCH:
                gain = g
                break
        clip_gain[name] = gain
        if gain < 1.0:
            log.info("clip %s toned down to %.0f%% to avoid stretching the mesh", name, gain * 100)

        t_acc_c = add_view_accessor(ts.astype(np.float32), pg.FLOAT, "SCALAR", minmax=True)
        clip = pg.Animation(name=name, samplers=[], channels=[])
        for jn, q in raw_q.items():
            qg = _scale_quat(q, gain) if gain < 1.0 else q
            o = add_view_accessor(qg.astype(np.float32), pg.FLOAT, "VEC4")
            clip.samplers.append(pg.AnimationSampler(input=t_acc_c, output=o, interpolation="LINEAR"))
            clip.channels.append(pg.AnimationChannel(
                sampler=len(clip.samplers) - 1, target=pg.AnimationChannelTarget(node=names[jn], path="rotation")))
        for jn, t in raw_t.items():
            tg = rest_t[jn] + (t - rest_t[jn]) * gain
            o = add_view_accessor(tg.astype(np.float32), pg.FLOAT, "VEC3")
            clip.samplers.append(pg.AnimationSampler(input=t_acc_c, output=o, interpolation="LINEAR"))
            clip.channels.append(pg.AnimationChannel(
                sampler=len(clip.samplers) - 1, target=pg.AnimationChannelTarget(node=names[jn], path="translation")))
        gltf.animations.append(clip)

    def rot(*parts):
        """Compose [(axis, angle_rad), ...] into one quaternion."""
        qq = np.array([0, 0, 0, 1.0])
        for axis, ang in parts:
            qq = _qmul(qq, _axis_quat(axis, ang))
        return qq

    X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)
    TAU = 2 * math.pi
    sgn = {"Left": 1, "Right": -1}

    # WAVE (5 s). Uses whichever arm was found in the mesh. With no arms (blob / animal / object) it becomes a
    # greeting: a bow plus a head tilt, so the button still does something sensible.
    WD = 5.0
    arms = [sd for sd in ("Left", "Right") if layout.arm_found.get(sd)]
    wave_side = arms[0] if arms else None
    if wave_side:
        ws = sgn[wave_side]
        up = arm_raise(wave_side)
        wave_chan = {
            f"{wave_side}UpperArm": lambda t: rot((Z, ws * up * envelope(t, WD, 0.7))),
            f"{wave_side}LowerArm": lambda t: rot((Z, ws * D(28) * math.sin(TAU * 0.9 * t) * envelope(t, WD, 1.0))),
            "Spine": lambda t: rot((Z, -ws * D(3) * envelope(t, WD, 0.8)),
                                   (Y, D(5) * math.sin(TAU * 0.45 * t) * envelope(t, WD, 0.8))),
            "Head": lambda t: rot((Z, ws * D(6) * envelope(t, WD, 0.8)), (Y, -ws * D(6) * envelope(t, WD, 0.8))),
        }
    else:
        wave_chan = {
            "Spine": lambda t: rot((X, D(14) * math.sin(math.pi * min(t / WD, 1.0)) ** 2)),
            "Head": lambda t: rot((Z, D(10) * math.sin(TAU * 0.6 * t) * envelope(t, WD, 0.8)),
                                  (X, D(6) * envelope(t, WD, 0.8))),
        }
    add_clip("wave", WD, wave_chan)

    # DANCE (5 s, 4 beats of 1.25 s): bounce, hip/shoulder twist, arms pumping up and out, head nod.
    DD, BEAT = 5.0, 1.25
    def beat(t):  # 0..1 phase within the beat
        return (t / BEAT) % 1.0
    def d_env(t):
        return envelope(t, DD, 0.4)
    def d_arm(side):
        s = sgn[side]
        raise_ = arm_raise(side)
        def f(t):
            e = d_env(t)
            pump = 0.5 + 0.5 * math.sin(TAU * t / (BEAT * 2) - math.pi / 2 + (0 if side == "Left" else math.pi))
            return rot((Z, s * raise_ * (0.30 + 0.45 * pump) * e))
        return f
    def d_elbow(side):
        s = sgn[side]
        def f(t):
            e = d_env(t)
            return rot((X, D(-35) * (0.5 + 0.5 * math.sin(TAU * t / BEAT)) * e), (Z, s * D(10) * e))
        return f
    def d_hips(t):
        e = d_env(t)
        return rot((Z, D(7) * math.sin(TAU * t / (BEAT * 2)) * e), (Y, D(9) * math.sin(TAU * t / (BEAT * 2)) * e))
    def d_spine(t):
        e = d_env(t)
        return rot((Z, D(-5) * math.sin(TAU * t / (BEAT * 2)) * e), (Y, D(-8) * math.sin(TAU * t / (BEAT * 2)) * e))
    def d_head(t):
        e = d_env(t)
        return rot((X, D(7) * math.sin(TAU * t / BEAT) * e), (Z, D(5) * math.sin(TAU * t / (BEAT * 2)) * e))
    def d_leg(side):
        s = 1 if side == "Left" else -1
        def f(t):
            e = d_env(t)
            return rot((X, D(14) * max(0.0, s * math.sin(TAU * t / (BEAT * 2))) * e), (Z, s * D(4) * e))
        return f
    def d_knee(side):
        s = 1 if side == "Left" else -1
        def f(t):
            e = d_env(t)
            return rot((X, D(-14) * max(0.0, s * math.sin(TAU * t / (BEAT * 2))) * e))
        return f
    hips_rest = jpos["Hips"]
    def d_bounce(t):
        e = d_env(t)
        dy = 0.018 * H * (0.5 - 0.5 * math.cos(TAU * t / (BEAT / 2))) * e
        return hips_rest + np.array([0.0, dy, 0.0])
    dance_chan = {"Hips": d_hips, "Spine": d_spine, "Head": d_head}
    for sd in ("Left", "Right"):
        if layout.arm_found.get(sd):
            dance_chan[f"{sd}UpperArm"] = d_arm(sd)
            dance_chan[f"{sd}LowerArm"] = d_elbow(sd)
        if layout.has_legs:
            dance_chan[f"{sd}UpperLeg"] = d_leg(sd)
            dance_chan[f"{sd}LowerLeg"] = d_knee(sd)
    add_clip("dance", DD, dance_chan, {"Hips": d_bounce})

    while len(blob) % 4:
        blob.append(0)
    gltf.set_binary_blob(bytes(blob))
    gltf.buffers[0].byteLength = len(blob)
    gltf.save_binary(str(dst))
    return {"joints": len(joints), "primitives": skinned, "reoriented": reoriented,
            "legs": layout.has_legs, "arms": [sd for sd in ("Left", "Right") if layout.arm_found.get(sd)],
            "clip_gain": clip_gain}
