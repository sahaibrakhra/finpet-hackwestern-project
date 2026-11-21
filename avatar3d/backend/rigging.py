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



PART_KEYS = ("head", "torso", "left_arm", "right_arm", "left_leg", "right_leg")


def parts_to_hints(parts: dict, image_path: Path, allv: np.ndarray) -> dict:
    """Convert user-drawn boxes (normalised 0..1 on the photo) into mesh-space hints for the rig.

    The mesh is mapped to the photo exactly like colorize.py does (front projection of the subject's
    bounding box), so a box on the photo becomes a box in the mesh's x/y plane.
    """
    from PIL import Image

    img = Image.open(image_path).convert("RGBA")
    W, Hh = img.size
    alpha = np.asarray(img)[..., 3]
    ys, xs = np.nonzero(alpha > 16)
    if len(xs) < 50:
        x0, x1, y0, y1 = 0, W - 1, 0, Hh - 1
    else:
        x0, x1, y0, y1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
    w, h = x1 - x0 + 1, y1 - y0 + 1
    lo, hi = allv.min(0), allv.max(0)
    span = np.maximum(hi - lo, 1e-9)
    mesh_aspect, img_aspect = span[0] / span[1], w / h
    fx = img_aspect / mesh_aspect if mesh_aspect > img_aspect else 1.0
    fy = mesh_aspect / img_aspect if mesh_aspect < img_aspect else 1.0

    def to_mesh(nx: float, ny: float):
        u = 0.5 + (((nx * W) - x0) / w - 0.5) * fx
        t = 0.5 + (((ny * Hh) - y0) / h - 0.5) * fy
        return lo[0] + u * span[0], lo[1] + (1 - t) * span[1]

    boxes = {}
    for k in PART_KEYS:
        b = parts.get(k)
        if not b:
            continue
        ax, ay = to_mesh(b[0], b[1])
        bx, by = to_mesh(b[2], b[3])
        boxes[k] = (min(ax, bx), max(ax, bx), min(ay, by), max(ay, by))  # x0, x1, ymin, ymax

    def pair(a, b):
        """Assign left/right by actual position: the box further along +X is the character's left (faces +Z)."""
        got = [(boxes[k][0] + boxes[k][1]) / 2 for k in (a, b) if k in boxes]
        out = {}
        items = [(k, boxes[k]) for k in (a, b) if k in boxes]
        items.sort(key=lambda kv: -(kv[1][0] + kv[1][1]) / 2)
        if len(items) == 2:
            out["Left"], out["Right"] = items[0][1], items[1][1]
        elif len(items) == 1:
            c = (items[0][1][0] + items[0][1][1]) / 2
            out["Left" if c >= (lo[0] + hi[0]) / 2 else "Right"] = items[0][1]
        return out

    hints = {"arm_boxes": pair("left_arm", "right_arm"), "leg_boxes": pair("left_leg", "right_leg"),
             "head_box": boxes.get("head"), "y_c": None, "y_neck": None}
    leg_tops = [b[3] for b in hints["leg_boxes"].values()]
    if "torso" in boxes and leg_tops:
        hints["y_c"] = (boxes["torso"][2] + float(np.mean(leg_tops))) / 2
    elif "torso" in boxes:
        hints["y_c"] = boxes["torso"][2]
    elif leg_tops:
        hints["y_c"] = float(np.mean(leg_tops))
    if "head" in boxes:
        hints["y_neck"] = boxes["head"][2]
    elif "torso" in boxes:
        hints["y_neck"] = boxes["torso"][3]
    return hints


class Layout:
    """Measurements of the mesh that both the skeleton and the skin weights are derived from."""

    def __init__(self, v: np.ndarray, hints: dict | None = None):
        hints = hints or {}
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
        if hints.get("y_c") is not None:  # user-marked body parts win over the guess
            self.y_c = float(np.clip(hints["y_c"], self.ymin + 0.1 * H, self.ymax - 0.2 * H))
            self.legs_confident = True
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
        if hints.get("y_neck") is not None:
            self.y_neck = float(np.clip(hints["y_neck"], self.y_c + 0.2 * (self.ymax - self.y_c), self.ymax - 0.03 * H))
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
        self.arm_from_labels = set()
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
                cut = max(leg_hw * 0.98, 0.45 * self.torso_hw)  # arms are the extra width outside the legs
                band2 = (v[:, 1] > self.y_c + 0.1 * self.Ut) & (v[:, 1] < self.y_neck)
                for side, sign in (("Left", 1), ("Right", -1)):
                    m = band2 & (ax > cut) & ((v[:, 0] - self.cx) * sign > 0)
                    if m.sum() >= max(40, int(0.01 * len(v))):
                        self.arm_mask[side] = m
                        self.arm_pts[side] = v[m]
                        self.arms_inferred = True

        # One arm found but not the other: assume the character is symmetric and mirror the arm's extent.
        for a_side, b_side, sa in (("Left", "Right", 1), ("Right", "Left", -1)):
            if self.arm_pts[a_side] is not None and self.arm_pts[b_side] is None:
                pts_a = self.arm_pts[a_side]
                dd = np.abs(pts_a[:, 0] - self.cx)
                sb = -sa
                m = (((v[:, 0] - self.cx) * sb) >= dd.min()) & (((v[:, 0] - self.cx) * sb) <= dd.max()) \
                    & (v[:, 1] >= pts_a[:, 1].min()) & (v[:, 1] <= pts_a[:, 1].max())
                if m.sum() >= 40:
                    self.arm_mask[b_side] = m
                    self.arm_pts[b_side] = v[m]

        # user-marked arm boxes override whatever was auto-detected
        for side, (bx0, bx1, by0, by1) in hints.get("arm_boxes", {}).items():
            m = (v[:, 0] >= bx0) & (v[:, 0] <= bx1) & (v[:, 1] >= by0) & (v[:, 1] <= by1)
            hb = hints.get("head_box")
            if hb is not None:  # where boxes overlap, the head wins
                m &= ~((v[:, 0] >= hb[0]) & (v[:, 0] <= hb[1]) & (v[:, 1] >= hb[2]) & (v[:, 1] <= hb[3]))
            if m.sum() >= 20:
                # Boxes are loose: keep only vertices close to the arm's own centre line, so neighbouring
                # geometry that merely falls inside the box (ears, hair, a hip) is not dragged along.
                xy = v[m][:, :2]
                c = xy.mean(axis=0)
                axis = np.linalg.svd(xy - c, full_matrices=False)[2][0]
                perp = np.abs((xy - c) @ np.array([-axis[1], axis[0]]))
                keep = perp <= max(2.5 * float(np.percentile(perp, 60)), 0.015 * H)
                idx = np.nonzero(m)[0]
                m2 = np.zeros_like(m)
                m2[idx[keep]] = True
                if m2.sum() >= 20:
                    m = m2
                self.arm_mask[side] = m
                self.arm_pts[side] = v[m]
                self.arm_from_labels.add(side)

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
        self.cx_legs = self.cx
        lb = hints.get("leg_boxes", {})
        for side, (bx0, bx1, _, _) in lb.items():
            c = (bx0 + bx1) / 2 - self.cx
            self.leg_x[side] = [c, c, c]
        if len(lb) == 2:
            self.cx_legs = float(np.mean([(b[0] + b[1]) / 2 for b in lb.values()]))


def fit_skeleton(v: np.ndarray, hints: dict | None = None):
    """Return (joints, layout). joints = [(name, parent_index (-1 = root), world_position)]."""
    L = Layout(v, hints)
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
            if side in L.arm_from_labels:
                # Marked by the user: the box may be loose, so use the arm's own principal direction.
                xy = pts[:, :2]
                c = xy.mean(axis=0)
                axis = np.linalg.svd(xy - c, full_matrices=False)[2][0]
                if abs(axis[0]) >= abs(axis[1]):      # mostly horizontal (held out): point away from the body
                    if axis[0] * sign < 0:
                        axis = -axis
                elif axis[1] > 0:                     # mostly vertical (hanging): point downward
                    axis = -axis
                proj = (xy - c) @ axis
                k = max(5, int(0.1 * len(proj)))
                order = np.argsort(proj)
                near, far = xy[order[:k]].mean(axis=0), xy[order[-k:]].mean(axis=0)
                a = near - axis * 0.02 * H            # put the shoulder slightly inside the body
                sh = np.array([a[0], a[1], cz])
                wr = np.array([far[0], far[1], cz])
                el = (sh + wr) / 2
                end = wr + (wr - sh) * 0.15
                base = len(joints)
                joints += [
                    (f"{side}UpperArm", 2, sh), (f"{side}LowerArm", base, el),
                    (f"{side}Hand", base + 1, wr), (f"{side}HandEnd", base + 2, end),
                ]
                continue
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
            side_w = _smooth((sign * (v[:, 0] - L.cx_legs)) / (0.02 * H) + 0.5)
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



_GROUPS = ("head", "torso", "LA", "RA", "LL", "RL")
_ANCHOR = {"head": "Head", "torso": "Hips", "LA": "LeftUpperArm", "RA": "RightUpperArm",
           "LL": "LeftUpperLeg", "RL": "RightUpperLeg"}


def _joint_group(name: str) -> str:
    left = name.startswith("Left")
    if name in ("Head", "HeadTop", "Neck"):
        return "head"
    if "Arm" in name or "Hand" in name:
        return "LA" if left else "RA"
    if "Leg" in name or "Foot" in name or "Toe" in name:
        return "LL" if left else "RL"
    return "torso"


def _split_sprite_parts(g, joints, ji, ww):
    """Cut a flat sprite mesh into one piece per body part (cut-out puppet), with a one-cell overlap ring.

    On a single continuous surface, triangles that bridge an arm and the torso get stretched into smeared strands
    when the arm rotates. Giving every part its own copy of the boundary triangles (rigidly bound to that part)
    keeps each part intact and hides the seam under the overlap. Returns (trimesh, joint_idx (N,4), weights (N,4)).
    """
    import trimesh
    from trimesh.visual import TextureVisuals

    names = [j[0] for j in joints]
    idx_of = {n: i for i, n in enumerate(names)}
    jgrp = np.array([_GROUPS.index(_joint_group(n)) for n in names])
    v = np.asarray(g.vertices, dtype=np.float64)
    uv = np.asarray(g.visual.uv, dtype=np.float64)
    faces = np.asarray(g.faces, dtype=np.int64)
    ji = ji.astype(np.int64)
    top = ji[np.arange(len(ji)), ww.argmax(axis=1)]
    vgrp = jgrp[top]

    counts = np.zeros((len(faces), len(_GROUPS)))
    for k in range(3):
        np.add.at(counts, (np.arange(len(faces)), vgrp[faces[:, k]]), 1)
    fgrp = counts.argmax(axis=1)

    out_v, out_uv, out_f, out_ji, out_ww = [], [], [], [], []
    base = 0
    for gi, gname in enumerate(_GROUPS):
        own = fgrp == gi
        if not own.any():
            continue
        sel = own.copy()
        if gname != "torso":  # limbs and head carry a one-cell ring of their neighbours' triangles
            touched = np.zeros(len(v), dtype=bool)
            touched[faces[own].ravel()] = True
            sel |= ~own & touched[faces].any(axis=1)
        used = np.unique(faces[sel].ravel())
        remap = -np.ones(len(v), dtype=np.int64)
        remap[used] = np.arange(len(used))
        out_f.append(remap[faces[sel]] + base)
        out_v.append(v[used])
        out_uv.append(uv[used])
        base += len(used)

        j_g = ji[used].copy()
        w_g = ww[used].astype(np.float64).copy()
        in_group = vgrp[used] == gi
        keep = jgrp[j_g] == gi                       # influences that belong to this part's own bones
        w_g = np.where(keep, w_g, 0.0)
        tot = w_g.sum(axis=1)
        ok = in_group & (tot > 1e-6)
        w_g[ok] /= tot[ok][:, None]
        anchor = idx_of[_ANCHOR[gname]]
        # ring vertices (and any with no influence from this part's bones) follow this part's anchor bone rigidly
        rigid = ~ok
        j_g[rigid] = 0
        w_g[rigid] = 0.0
        j_g[rigid, 0] = anchor
        w_g[rigid, 0] = 1.0
        out_ji.append(j_g)
        out_ww.append(w_g)

    mesh = trimesh.Trimesh(vertices=np.concatenate(out_v), faces=np.concatenate(out_f), process=False)
    mesh.visual = TextureVisuals(uv=np.concatenate(out_uv), material=g.visual.material)
    return mesh, np.concatenate(out_ji).astype(np.uint16), np.concatenate(out_ww).astype(np.float32)


def rig_glb(src: Path, dst: Path, parts: dict | None = None, image_path: Path | None = None) -> dict:
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
    pre = None  # (joints, layout, hints, joint_idx, weights) when a flat sprite was split into parts
    if len(geoms) == 1 and hasattr(geoms[0].visual, "uv") and geoms[0].visual.uv is not None:
        v0 = np.asarray(geoms[0].vertices, dtype=np.float64)
        if float(np.ptp(v0[:, 2])) < 0.02 * float(np.ptp(v0[:, 1])):
            hints0 = None
            if parts and image_path is not None:
                try:
                    hints0 = parts_to_hints(parts, Path(image_path), v0)
                except Exception as e:  # noqa: BLE001
                    log.warning("could not use body-part labels: %s", e)
            joints0, layout0 = fit_skeleton(v0, hints0)
            ji0, ww0 = skin_weights(v0, joints0, layout0)
            g2, ji2, ww2 = _split_sprite_parts(geoms[0], joints0, ji0, ww0)
            geoms = [g2]
            pre = (joints0, layout0, hints0, ji2, ww2)
    flat = trimesh.Scene(geoms)  # world-space geometry, identity node transforms, textures kept
    gltf = pg.GLTF2().load_from_bytes(flat.export(file_type="glb"))

    # Vertices in the exact order the skinning loop below visits them, so per-vertex masks line up.
    _b0 = gltf.binary_blob() or b""
    allv = np.concatenate([_read_accessor(gltf, _b0, pr.attributes.POSITION).astype(np.float64)
                           for nd in gltf.nodes if nd.mesh is not None
                           for pr in gltf.meshes[nd.mesh].primitives])
    if pre is not None:
        joints, layout, hints = pre[0], pre[1], pre[2]
    else:
        hints = None
        if parts and image_path is not None:
            try:
                hints = parts_to_hints(parts, Path(image_path), allv)
            except Exception as e:  # noqa: BLE001
                log.warning("could not use body-part labels: %s", e)
        joints, layout = fit_skeleton(allv, hints)

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

    ji_all, ww_all = (pre[3], pre[4]) if pre is not None else skin_weights(allv, joints, layout)
    # Flat (2D sprite) meshes have every vertex at the same depth, so a raised arm would z-fight with the torso.
    # Give each body part a small depth offset: arms in front, then head/neck, torso, and legs behind.
    flat = float(allv[:, 2].max() - allv[:, 2].min()) < 0.02 * layout.H
    dz_all = None
    if flat:
        zf = np.zeros(len(joints))
        for i, (jn_, _, _) in enumerate(joints):
            if "Arm" in jn_ or "Hand" in jn_:
                zf[i] = 0.030
            elif jn_ in ("Head", "HeadTop", "Neck"):
                zf[i] = 0.015
            elif "Leg" in jn_ or "Foot" in jn_ or "Toe" in jn_:
                zf[i] = -0.015
        dz_all = (ww_all * zf[ji_all.astype(int)]).sum(axis=1) * layout.H
    offset = 0
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
            ji = ji_all[offset:offset + acc.count]
            ww = ww_all[offset:offset + acc.count]
            if dz_all is not None:
                arr = np.frombuffer(blob, dtype=np.uint8)
                view = arr[start:start + stride * acc.count].reshape(acc.count, stride)
                zc = view[:, 8:12].copy().view(np.float32).reshape(-1) + dz_all[offset:offset + acc.count].astype(np.float32)
                view[:, 8:12] = zc.astype(np.float32).view(np.uint8).reshape(-1, 4)
                if acc.min and acc.max:
                    acc.min[2], acc.max[2] = float(zc.min()), float(zc.max())
                pos = pos.copy()
                pos[:, 2] = zc
                del view, arr  # release the buffer export so the blob can grow later
            offset += acc.count
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
    # edges may change by at most this fraction of body height before a clip is toned down (flat puppets tolerate more)
    MAX_STRETCH = 0.07 if flat else 0.03

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
            "clip_gain": clip_gain, "labels_used": hints is not None, "flat": flat}
