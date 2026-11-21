"""FinPet backend: photo -> full-body cartoon avatar, avatar -> short animation clips, all via Gemini.

The Gemini key lives only in backend/.env - the iOS app never sees it.

Run:  uvicorn main:app --host 0.0.0.0 --port 8000   (from the backend/ directory)
"""
import base64
import io
import logging
import os
import time
from pathlib import Path

import httpx
from dotenv import load_dotenv
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from PIL import Image, ImageOps, UnidentifiedImageError

import media

load_dotenv(Path(__file__).parent / ".env")

log = logging.getLogger("finpet")

MAX_UPLOAD_BYTES = 10 * 1024 * 1024
MAX_INPUT_SIDE = 1024
ALLOWED_FORMATS = {"JPEG", "PNG", "WEBP", "HEIC", "HEIF"}

AVATAR_PROMPT = (
    "Create a full-body cartoon avatar of the subject in this photo. "
    "Show the entire body from head to toe, standing in a relaxed neutral front-facing pose, "
    "with both feet visible and nothing cropped. Portrait composition. "
    "Preserve the subject's recognizable features: face, hairstyle or fur, skin tone, "
    "colors and clothing or accessories (or a faithful cartoon version of the creature or object "
    "if it is not a person). "
    "Cute, friendly, clean flat illustration style with a thick dark outline. "
    "Centered, on a plain, perfectly flat, single-color background (one soft pastel color that "
    "complements the character and does not appear anywhere on the character), "
    "no gradient, no shadows, no ground, no props, no text."
)

ANIMATION_BASE = (
    "Animate this exact cartoon character, keeping its design, proportions and colors identical. "
    "Fixed static camera, no zoom, no cuts. The background must stay the exact same flat single "
    "color for the whole clip, with no ground, floor, shadow, particles or text. "
    "The whole character stays fully in frame. "
)
ANIMATIONS = {
    "idle": "The character stands and idles: gentle breathing, a soft sway, a slow blink, relaxed arms.",
    "wave": "The character cheerfully waves one hand hello with a happy smile, the rest of the body relaxed.",
    "dance": "The character does a short, fun, energetic dance with simple repeated moves.",
    "cry": (
        "The character is sitting on the ground, hugging its knees, looking super sad and crying "
        "with tears, shoulders shaking slightly. Start from the standing pose and sit down quickly."
    ),
}

app = FastAPI(title="FinPet backend")


def _env(name: str, default: str) -> str:
    return os.getenv(name, "").strip() or default


def _image_model() -> str:
    return _env("GEMINI_MODEL", "gemini-3.1-flash-image")


def _video_model() -> str:
    return _env("VIDEO_MODEL", "gemini-omni-1.2-flash")


def _client(*, api_version: str | None = None):
    from google import genai

    key = os.getenv("GEMINI_API_KEY", "").strip()
    if not key:
        raise HTTPException(503, "Server is missing GEMINI_API_KEY. Set it in backend/.env.")
    if api_version is not None:
        return genai.Client(api_key=key, http_options={"api_version": api_version})
    return genai.Client(api_key=key)


def _normalize(data: bytes) -> bytes:
    """Validate the upload, fix EXIF rotation, cap size, return JPEG bytes."""
    try:
        img = Image.open(io.BytesIO(data))
        fmt = img.format
        img.load()
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError):
        raise HTTPException(400, "That file is not a readable image.")
    if fmt not in ALLOWED_FORMATS:
        raise HTTPException(400, f"Unsupported image type {fmt}. Use JPG, PNG or WebP.")
    img = ImageOps.exif_transpose(img).convert("RGB")
    img.thumbnail((MAX_INPUT_SIDE, MAX_INPUT_SIDE), Image.LANCZOS)
    out = io.BytesIO()
    img.save(out, "JPEG", quality=90)
    return out.getvalue()


def _gemini_error(e: Exception) -> HTTPException:
    from google.genai import errors

    if isinstance(e, errors.APIError):
        log.warning("Gemini API error %s: %s", e.code, e.message)
        if e.code == 429:
            return HTTPException(429, "Gemini quota or rate limit reached. Try again shortly.")
        return HTTPException(502, f"Gemini error {e.code}: {e.message}")
    log.exception("Gemini call failed")
    return HTTPException(502, f"Could not reach Gemini: {e}")


def _generate_avatar_image(photo_jpeg: bytes) -> Image.Image:
    """Photo -> Gemini image model -> the generated avatar (still on its flat background)."""
    from google.genai import types

    client = _client()
    try:
        resp = client.models.generate_content(
            model=_image_model(),
            contents=[types.Part.from_bytes(data=photo_jpeg, mime_type="image/jpeg"), AVATAR_PROMPT],
            config=types.GenerateContentConfig(response_modalities=["TEXT", "IMAGE"]),
        )
    except HTTPException:
        raise
    except Exception as e:  # noqa: BLE001
        raise _gemini_error(e)

    note = ""
    for cand in resp.candidates or []:
        for part in (cand.content.parts if cand.content else None) or []:
            if getattr(part, "text", None):
                note += part.text
            inline = getattr(part, "inline_data", None)
            if inline and inline.data:
                return Image.open(io.BytesIO(inline.data)).convert("RGB")
    raise HTTPException(502, f"Gemini did not return an image. {note}".strip())


def _video_bytes(video) -> bytes:
    """Read the clip from an Interactions `video` output (inline base64 or a download URI)."""
    data = getattr(video, "data", None)
    if data:
        if isinstance(data, str):
            return base64.b64decode(data)
        raw = bytes(data)
        return raw if raw[4:8] == b"ftyp" else base64.b64decode(raw)
    uri = getattr(video, "uri", None)
    if uri:
        r = httpx.get(uri, headers={"x-goog-api-key": os.environ["GEMINI_API_KEY"].strip()},
                      follow_redirects=True, timeout=120)
        r.raise_for_status()
        return r.content
    raise HTTPException(502, "Gemini returned a video without any data.")


def _generate_video(still_png: bytes, motion_prompt: str) -> bytes:
    """Image-to-video with the cheapest settings: short duration, 360p, portrait."""
    # Omni video is served by the v1beta Interactions API.
    client = _client(api_version="v1beta")
    duration = int(_env("ANIM_SECONDS", "3"))
    try:
        interaction = client.interactions.create(
            model=_video_model(),
            input=[
                {"type": "text", "text": ANIMATION_BASE + motion_prompt},
                {"type": "image", "data": base64.b64encode(still_png).decode(), "mime_type": "image/png"},
            ],
            response_format={
                "type": "video",
                "duration": f"{duration}s",
                "resolution": _env("ANIM_RESOLUTION", "360p"),
                "aspect_ratio": "9:16",
                "delivery": "inline",
            },
        )
        deadline = time.time() + 360
        while getattr(interaction, "status", "completed") in ("in_progress", "queued", "requires_continuation"):
            if time.time() > deadline:
                raise HTTPException(504, "Animation timed out.")
            time.sleep(3)
            interaction = client.interactions.get(interaction.id)
    except HTTPException:
        raise
    except Exception as e:  # noqa: BLE001
        raise _gemini_error(e)

    status = getattr(interaction, "status", "completed")
    if status != "completed":
        raise HTTPException(502, f"Animation did not complete (status: {status}).")
    video = getattr(interaction, "output_video", None)
    if video is None:
        raise HTTPException(502, "Gemini did not return a video.")
    return _video_bytes(video)


def _b64(data: bytes) -> str:
    return base64.b64encode(data).decode()


@app.get("/health")
def health() -> dict:
    return {
        "ok": True,
        "image_model": _image_model(),
        "video_model": _video_model(),
        "key_configured": bool(os.getenv("GEMINI_API_KEY", "").strip()),
    }


@app.post("/api/avatar")
def create_avatar(photo: UploadFile = File(...)) -> dict:
    """multipart `photo` -> {avatar: base64 transparent PNG (9:16), background: "#RRGGBB"}."""
    data = photo.file.read(MAX_UPLOAD_BYTES + 1)
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(413, "Photo is larger than 10 MB.")
    generated = _generate_avatar_image(_normalize(data))
    bg = media.sample_background(generated)
    avatar = media.layout_on_canvas(media.key_out_background(generated, bg))
    return {"avatar": _b64(media.png_bytes(avatar)), "background": media.to_hex(bg)}


@app.post("/api/animate")
def create_animation(
    kind: str = Form(...),
    background: str = Form(...),
    avatar: UploadFile = File(...),
) -> dict:
    """`avatar` (the transparent PNG from /api/avatar) + its `background` hex + `kind`
    (idle|wave|dance|cry) -> {fps, frames: [base64 transparent PNG, ...]}. One short video call."""
    if kind not in ANIMATIONS:
        raise HTTPException(400, f"kind must be one of {', '.join(ANIMATIONS)}.")
    try:
        bg = media.from_hex(background)
    except ValueError as e:
        raise HTTPException(400, str(e))
    data = avatar.file.read(MAX_UPLOAD_BYTES + 1)
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(413, "Avatar is larger than 10 MB.")
    try:
        rgba = Image.open(io.BytesIO(data)).convert("RGBA")
    except (UnidentifiedImageError, OSError, ValueError):
        raise HTTPException(400, "That avatar is not a readable image.")

    still = media.png_bytes(media.flatten_on_color(rgba, bg))
    mp4 = _generate_video(still, ANIMATIONS[kind])
    fps = int(_env("ANIM_FPS", "10"))
    try:
        frames = media.video_to_frames(mp4, bg, fps=fps, max_height=int(_env("ANIM_FRAME_HEIGHT", "512")))
    except RuntimeError as e:
        raise HTTPException(502, str(e))
    return {"fps": fps, "frames": [_b64(f) for f in frames]}
