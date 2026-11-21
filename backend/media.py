"""Image/video helpers: background keying, canvas layout, frame extraction. No network, no Gemini."""
import io
import subprocess
import tempfile
from pathlib import Path

import imageio_ffmpeg
import numpy as np
from PIL import Image
from scipy import ndimage

CANVAS_W, CANVAS_H = 576, 1024  # 9:16 portrait canvas shared by the avatar and every animation frame
KEY_LO, KEY_HI = 18.0, 42.0  # RGB distance: fully background below LO, fully subject above HI


def sample_background(img: Image.Image) -> tuple[int, int, int]:
    """Median color of the four corner patches = the flat background color."""
    a = np.asarray(img.convert("RGB"))
    h, w = a.shape[:2]
    n = max(4, min(h, w) // 40)
    patches = [a[:n, :n], a[:n, -n:], a[-n:, :n], a[-n:, -n:]]
    px = np.concatenate([p.reshape(-1, 3) for p in patches])
    return tuple(int(v) for v in np.median(px, axis=0))


def to_hex(rgb: tuple[int, int, int]) -> str:
    return "#{:02X}{:02X}{:02X}".format(*rgb)


def from_hex(value: str) -> tuple[int, int, int]:
    v = value.strip().lstrip("#")
    if len(v) != 6:
        raise ValueError("background must be #RRGGBB")
    return int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16)


def key_out_background(img: Image.Image, bg: tuple[int, int, int]) -> Image.Image:
    """Make the background transparent. Only background-colored pixels connected to the image border
    are removed, so similar colors inside the character (e.g. white clothes on white) are kept."""
    rgb = np.asarray(img.convert("RGB")).astype(np.float32)
    dist = np.sqrt(((rgb - np.array(bg, dtype=np.float32)) ** 2).sum(axis=2))
    bgish = dist < KEY_HI
    labels, _ = ndimage.label(bgish)
    border = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
    region = np.isin(labels, border[border > 0])
    alpha = np.ones(dist.shape, dtype=np.float32)
    soft = np.clip((dist - KEY_LO) / (KEY_HI - KEY_LO), 0.0, 1.0)
    alpha[region] = soft[region]
    # Remove the background color bleeding into semi-transparent edge pixels.
    edge = region & (alpha > 0.0) & (alpha < 1.0)
    b = np.array(bg, dtype=np.float32)
    a3 = alpha[..., None]
    despilled = np.where(edge[..., None], (rgb - (1.0 - a3) * b) / np.maximum(a3, 1e-3), rgb)
    out = np.dstack([np.clip(despilled, 0, 255), alpha * 255.0]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def layout_on_canvas(rgba: Image.Image) -> Image.Image:
    """Crop to the subject and place it, feet near the bottom, on the shared 9:16 transparent canvas."""
    box = rgba.getchannel("A").point(lambda v: 255 if v > 12 else 0).getbbox()
    if box:
        rgba = rgba.crop(box)
    scale = min(CANVAS_W * 0.82 / rgba.width, CANVAS_H * 0.88 / rgba.height)
    size = (max(1, round(rgba.width * scale)), max(1, round(rgba.height * scale)))
    rgba = rgba.resize(size, Image.LANCZOS)
    canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    canvas.paste(rgba, ((CANVAS_W - size[0]) // 2, CANVAS_H - size[1] - round(CANVAS_H * 0.05)), rgba)
    return canvas


def flatten_on_color(rgba: Image.Image, bg: tuple[int, int, int]) -> Image.Image:
    base = Image.new("RGB", rgba.size, bg)
    base.paste(rgba, mask=rgba.getchannel("A"))
    return base


def png_bytes(img: Image.Image) -> bytes:
    out = io.BytesIO()
    img.save(out, "PNG", optimize=True)
    return out.getvalue()


def video_to_frames(mp4: bytes, bg: tuple[int, int, int], fps: int, max_height: int) -> list[bytes]:
    """Decode the clip at `fps`, key out the background, return transparent PNG frames."""
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "clip.mp4"
        src.write_bytes(mp4)
        pattern = str(Path(tmp) / "f_%03d.png")
        cmd = [ffmpeg, "-v", "error", "-i", str(src), "-vf", f"fps={fps},scale=-2:'min({max_height},ih)'", pattern]
        run = subprocess.run(cmd, capture_output=True, text=True)
        if run.returncode != 0:
            raise RuntimeError(f"ffmpeg failed: {run.stderr.strip()[:300]}")
        frames = sorted(Path(tmp).glob("f_*.png"))
        if not frames:
            raise RuntimeError("ffmpeg produced no frames")
        out = []
        for f in frames:
            with Image.open(f) as im:
                out.append(png_bytes(key_out_background(im, bg)))
        return out
