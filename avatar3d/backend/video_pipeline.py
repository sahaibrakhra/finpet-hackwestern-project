"""2D video avatar pipeline (PROVIDER=video2d): photo -> sprite -> AI-generated idle / wave / dance clips.

No rig. The sprite (an AI redraw when a Gemini key is set, otherwise the plain cut-out) is placed on a solid green
canvas and used as the first and last frame of each clip, so every clip starts and ends on the same pose and can
loop or chain back into idle. Clips are keyed to transparent WebM and listed in a manifest the viewer reads.

Output (per avatar id):
    storage/models/<id>.json        manifest (served as the avatar's model_url)
    storage/models/<id>_puppet/     sprite.png, frame0.png, idle.webm, wave.webm, dance.webm
The idle clip finishes the job; wave and dance keep generating in the background and appear when ready.
"""
from __future__ import annotations

import io
import json
import logging
import os
import subprocess
import threading
from pathlib import Path
from typing import Optional

import numpy as np
from PIL import Image

import pipeline
from jobs import JobStore
from video_backends import GREEN, VideoBackend, VideoError, get_video_backend

# chroma-key candidates; the one farthest from the sprite's own colours is used as the background
KEYS = {
    "green": ((0, 177, 64), "solid chroma-key green (#00B140)"),
    "blue": ((0, 71, 187), "solid chroma-key blue (#0047BB)"),
    "magenta": ((255, 0, 255), "solid magenta (#FF00FF)"),
}

log = logging.getLogger("avatar3d.video2d")

CLIPS = {
    "idle": dict(
        seconds=4, loop=True,
        prompt=("A flat 2D cartoon character standing still on a {bg} background, doing a subtle idle "
                "animation: gentle breathing, a tiny body sway, maybe a blink. The character returns to exactly the "
                "starting pose at the end so it loops seamlessly. Static camera, no zoom, {bg} background.")),
    "wave": dict(
        seconds=5, loop=False,
        prompt=("A flat 2D cartoon character on a {bg} background raises one hand and waves hello with a "
                "friendly smile, then lowers the hand and returns to exactly the starting pose. Static camera, no "
                "zoom, same art style, {bg} background.")),
    "dance": dict(
        seconds=5, loop=False,
        prompt=("A flat 2D cartoon character on a {bg} background does a fun energetic dance in place: "
                "bouncing, swaying hips, swinging arms to the beat, then settles back into exactly the starting "
                "pose. Static camera, no zoom, same art style, {bg} background.")),
}

SPRITE_PROMPT = (
    "Redraw this character as a clean, full-body 2D sprite for animation: front-facing, neutral standing pose with "
    "arms slightly away from the body, the whole character visible, flat cartoon shading, keeping the character's "
    "identity, proportions and colours exactly. Place it on a perfectly flat solid pure green background "
    "(#00B140) with no shadows, no ground, no text and no other objects.")

_manifest_lock = threading.Lock()


# ------------------------------------------------------------------------------------------ helpers
def sprite_enabled() -> bool:
    return bool(os.getenv("GEMINI_API_KEY", "").strip()) and pipeline.env_bool("SPRITE_AI", True)


def pick_key(sprite: Image.Image) -> str:
    """Choose the key colour farthest from every colour in the sprite, so keying cannot eat the character."""
    a = np.asarray(sprite.convert("RGBA"))
    px = a[a[..., 3] > 200][:, :3].astype(np.float32)
    if len(px) == 0:
        return "green"
    if len(px) > 30000:
        px = px[np.random.default_rng(0).choice(len(px), 30000, replace=False)]
    best, best_d = "green", -1.0
    for name, (rgb, _) in KEYS.items():
        d = float(np.percentile(np.linalg.norm(px - np.array(rgb, dtype=np.float32), axis=1), 1))
        if d > best_d:
            best, best_d = name, d
    return best


def chroma_to_alpha(img: Image.Image, tol: float = 70.0, soft: float = 45.0) -> Image.Image:
    """Turn a picture on a flat green background into an RGBA sprite (with simple green de-spill)."""
    rgb = np.asarray(img.convert("RGB")).astype(np.float32)
    dist = np.linalg.norm(rgb - np.array(GREEN, dtype=np.float32), axis=2)
    alpha = np.clip((dist - tol) / soft, 0.0, 1.0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    rgb[..., 1] = np.minimum(g, np.maximum(r, b) + 12.0)  # pull green fringes back toward the neighbours
    out = np.dstack([np.clip(rgb, 0, 255).astype(np.uint8), (alpha * 255).astype(np.uint8)])
    return Image.fromarray(out, "RGBA")


def crop_to_subject(img: Image.Image, pad: float = 0.02) -> Image.Image:
    a = img.getchannel("A").point(lambda v: 255 if v > 16 else 0)
    bb = a.getbbox()
    if not bb:
        raise VideoError("No character was found in the photo after removing the background.")
    p = int(pad * max(img.size))
    return img.crop((max(0, bb[0] - p), max(0, bb[1] - p), min(img.width, bb[2] + p), min(img.height, bb[3] + p)))


def make_first_frame(sprite: Image.Image, key: tuple = GREEN) -> tuple[Image.Image, str]:
    """Place the sprite on a green canvas. Tall characters get a portrait canvas, others landscape."""
    portrait = sprite.height / sprite.width > 1.3
    W, H = (480, 832) if portrait else (832, 480)
    s = min(W * 0.82 / sprite.width, H * 0.90 / sprite.height)
    sp = sprite.resize((max(1, int(sprite.width * s)), max(1, int(sprite.height * s))), Image.LANCZOS)
    canvas = Image.new("RGBA", (W, H), tuple(key) + (255,))
    canvas.alpha_composite(sp, ((W - sp.width) // 2, int(H * 0.95) - sp.height))
    return canvas.convert("RGB"), ("9:16" if portrait else "16:9")


def ffmpeg_exe() -> str:
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception as e:  # noqa: BLE001
        raise VideoError("ffmpeg is not available. Run: pip install -r backend\\requirements.txt") from e


def encode_transparent_webm(src_mp4: Path, dst_webm: Path, key: tuple = GREEN) -> None:
    """Key out the green background and write a VP9 WebM with an alpha channel (plays in Chrome)."""
    sim = os.getenv("CHROMA_SIMILARITY", "0.14")
    blend = os.getenv("CHROMA_BLEND", "0.05")
    vf = f"chromakey=0x{key[0]:02X}{key[1]:02X}{key[2]:02X}:{sim}:{blend},format=yuva420p"
    cmd = [ffmpeg_exe(), "-y", "-loglevel", "error", "-i", str(src_mp4), "-vf", vf, "-an",
           "-c:v", "libvpx-vp9", "-pix_fmt", "yuva420p", "-b:v", "0", "-crf", "34", "-auto-alt-ref", "0",
           "-row-mt", "1", "-deadline", "good", "-cpu-used", "4", str(dst_webm)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0 or not dst_webm.exists():
        raise VideoError(f"Could not encode the clip: {r.stderr.strip()[:200]}")


def write_manifest(models_dir: Path, job_id: str, manifest: dict) -> None:
    with _manifest_lock:
        path = models_dir / f"{job_id}.json"
        tmp = path.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(manifest, indent=1), encoding="utf-8")
        os.replace(tmp, path)


def ai_sprite(cutout_path: Path) -> Image.Image:
    """Ask Gemini to redraw the character as a clean sprite on green; return it keyed to RGBA."""
    from google import genai

    client = genai.Client(api_key=os.environ["GEMINI_API_KEY"].strip())
    model = os.getenv("SPRITE_MODEL") or os.getenv("GEMINI_MODEL", "gemini-2.5-flash-image")
    src = Image.open(cutout_path).convert("RGBA")
    base = Image.new("RGBA", src.size, GREEN + (255,))
    base.alpha_composite(src)
    resp = client.models.generate_content(model=model, contents=[SPRITE_PROMPT, base.convert("RGB")])
    for cand in resp.candidates or []:
        for part in (cand.content.parts if cand.content else []) or []:
            inline = getattr(part, "inline_data", None)
            if inline and inline.data:
                out = chroma_to_alpha(Image.open(io.BytesIO(inline.data)))
                if (np.asarray(out.getchannel("A")) > 16).mean() > 0.02:
                    return out
                raise VideoError("The AI sprite came back empty.")
    raise VideoError("Gemini returned no image for the sprite.")


def _make_clip(backend: VideoBackend, name: str, puppet: Path, frame0: Path, aspect: str, say,
               key_name: str) -> tuple[Path, int]:
    spec = CLIPS[name]
    secs = backend.pick_seconds(spec["seconds"])
    key_rgb, bg_text = KEYS[key_name]
    raw = backend.generate(frame0, frame0, spec["prompt"].format(bg=bg_text), secs, aspect, say, key_rgb)
    webm = puppet / f"{name}.webm"
    say(f"Removing the green background from the {name} clip...")
    encode_transparent_webm(raw, webm, key_rgb)
    Path(raw).unlink(missing_ok=True)
    return webm, secs


# -------------------------------------------------------------------------------------------- main
def run_video_pipeline(store: JobStore, job_id: str, image_path: Path, models_dir: Path,
                       parts: Optional[dict] = None) -> None:
    notes: list[str] = []

    def stage(status: str, message: str) -> None:
        store.update(job_id, status=status, message=" ".join(notes + [message]).strip())

    try:
        backend = get_video_backend()
        puppet = models_dir / f"{job_id}_puppet"
        puppet.mkdir(parents=True, exist_ok=True)

        # 1. cut-out
        current = image_path
        if pipeline.rembg_enabled():
            stage("removing_background", "Removing background...")
            nobg = image_path.with_name(f"{image_path.stem}_nobg.png")
            try:
                pipeline._remove_background(current, nobg)
                current = nobg
            except Exception as e:  # noqa: BLE001
                log.warning("rembg failed: %s", e)
                notes.append("(Background removal failed; using the original photo.)")

        # 2. sprite
        if sprite_enabled():
            stage("stylizing", "Drawing a clean 2D sprite with Gemini...")
            try:
                sprite = ai_sprite(current)
            except Exception as e:  # noqa: BLE001  (never log the key)
                log.warning("AI sprite failed: %s", type(e).__name__)
                notes.append("(AI sprite failed; using the plain cut-out.)")
                sprite = Image.open(current).convert("RGBA")
        else:
            sprite = Image.open(current).convert("RGBA")
        sprite = crop_to_subject(sprite)
        sprite.save(puppet / "sprite.png", "PNG")
        key_name = pick_key(sprite)
        frame_img, aspect = make_first_frame(sprite, KEYS[key_name][0])
        frame0 = puppet / "frame0.png"
        frame_img.save(frame0, "PNG")

        manifest = {
            "type": "video2d", "id": job_id, "backend": backend.name, "aspect": aspect, "key": key_name,
            "size": list(frame_img.size),
            "sprite": f"/api/puppets/{job_id}/sprite.png",
            "clips": {n: {"state": "pending", "loop": CLIPS[n]["loop"]} for n in CLIPS},
        }
        write_manifest(models_dir, job_id, manifest)

        # 3. idle first: it finishes the job
        stage("generating_mesh", f"Generating the idle loop with '{backend.name}'...")
        webm, secs = _make_clip(backend, "idle", puppet, frame0, aspect,
                                lambda m: stage("generating_mesh", m), key_name)
        manifest["clips"]["idle"].update(state="ready", url=f"/api/puppets/{job_id}/idle.webm", seconds=secs)
        write_manifest(models_dir, job_id, manifest)

        stage("finalizing", "Saving...")
        if not store.is_active(job_id):  # timed out meanwhile
            return
        extra = "Wave and dance clips are still generating." if backend.name != "mock" else ""
        store.update(job_id, status="done", message=" ".join(notes + ["Done.", extra]).strip())
        log.info("job %s idle ready; generating wave/dance in the background", job_id)

        threading.Thread(target=_background_clips, args=(backend, job_id, puppet, frame0, aspect, models_dir, manifest, key_name),
                         daemon=True, name=f"clips-{job_id}").start()
    except VideoError as e:
        log.warning("job %s video error: %s", job_id, e)
        store.fail(job_id, str(e))
    except Exception as e:  # noqa: BLE001
        log.exception("job %s failed", job_id)
        store.fail(job_id, f"Unexpected error: {type(e).__name__}: {e}")


def _background_clips(backend: VideoBackend, job_id: str, puppet: Path, frame0: Path, aspect: str,
                      models_dir: Path, manifest: dict, key_name: str) -> None:
    for name in ("wave", "dance"):
        try:
            webm, secs = _make_clip(backend, name, puppet, frame0, aspect, lambda m: None, key_name)
            manifest["clips"][name].update(state="ready", url=f"/api/puppets/{job_id}/{name}.webm", seconds=secs)
        except VideoError as e:
            log.warning("job %s %s clip failed: %s", job_id, name, e)
            manifest["clips"][name].update(state="error", message=str(e))
        except Exception as e:  # noqa: BLE001
            log.exception("job %s %s clip failed", job_id, name)
            manifest["clips"][name].update(state="error", message=f"{type(e).__name__}: {e}")
        if not (models_dir / f"{job_id}.json").exists():  # avatar was deleted meanwhile
            return
        write_manifest(models_dir, job_id, manifest)
