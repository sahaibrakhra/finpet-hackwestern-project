"""FinPet backend: turns an uploaded photo into a full-body cartoon avatar with Gemini.

The Gemini API key lives only in backend/.env - the iOS app never sees it.

Run:  uvicorn main:app --host 0.0.0.0 --port 8000   (from the backend/ directory)
"""
import io
import logging
import os
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import Response
from PIL import Image, ImageOps, UnidentifiedImageError

load_dotenv(Path(__file__).parent / ".env")

log = logging.getLogger("finpet")

MAX_UPLOAD_BYTES = 10 * 1024 * 1024
MAX_INPUT_SIDE = 1024
MAX_OUTPUT_SIDE = 768
ALLOWED_FORMATS = {"JPEG", "PNG", "WEBP", "HEIC", "HEIF"}

PROMPT = (
    "Create a full-body cartoon avatar of the subject in this photo. "
    "Show the entire body from head to toe, standing in a relaxed neutral front-facing pose, "
    "with both feet visible and nothing cropped. "
    "Preserve the subject's recognizable features: face, hairstyle or fur, skin tone, "
    "colors and clothing or accessories (or a faithful cartoon version of the creature or object "
    "if it is not a person). "
    "Cute, friendly, clean flat illustration style with a thick dark outline. "
    "Centered, plain solid white background, no shadows, no props, no text."
)

app = FastAPI(title="FinPet backend")


def _model() -> str:
    return os.getenv("GEMINI_MODEL", "gemini-3.1-flash-image").strip() or "gemini-3.1-flash-image"


def _normalize(data: bytes) -> bytes:
    """Validate the upload, fix EXIF rotation, cap size, return JPEG bytes."""
    try:
        img = Image.open(io.BytesIO(data))
        fmt = img.format
        img.load()
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError):
        raise HTTPException(400, "That file isn't a readable image.")
    if fmt not in ALLOWED_FORMATS:
        raise HTTPException(400, f"Unsupported image type {fmt}. Use JPG, PNG or WebP.")
    img = ImageOps.exif_transpose(img).convert("RGB")
    img.thumbnail((MAX_INPUT_SIDE, MAX_INPUT_SIDE), Image.LANCZOS)
    out = io.BytesIO()
    img.save(out, "JPEG", quality=90)
    return out.getvalue()


def _generate(photo_jpeg: bytes) -> bytes:
    """Send the photo to Gemini and return the generated avatar as PNG bytes."""
    from google import genai
    from google.genai import errors, types

    key = os.getenv("GEMINI_API_KEY", "").strip()
    if not key:
        raise HTTPException(503, "Server is missing GEMINI_API_KEY. Set it in backend/.env.")

    client = genai.Client(api_key=key)
    try:
        resp = client.models.generate_content(
            model=_model(),
            contents=[types.Part.from_bytes(data=photo_jpeg, mime_type="image/jpeg"), PROMPT],
            config=types.GenerateContentConfig(response_modalities=["TEXT", "IMAGE"]),
        )
    except errors.APIError as e:
        log.warning("Gemini API error %s: %s", e.code, e.message)
        if e.code == 429:
            raise HTTPException(429, "Gemini quota or rate limit reached. Try again shortly.")
        raise HTTPException(502, f"Gemini error {e.code}: {e.message}")
    except Exception as e:  # noqa: BLE001
        log.exception("Gemini call failed")
        raise HTTPException(502, f"Could not reach Gemini: {e}")

    note = ""
    for cand in resp.candidates or []:
        for part in (cand.content.parts if cand.content else None) or []:
            if getattr(part, "text", None):
                note += part.text
            inline = getattr(part, "inline_data", None)
            if inline and inline.data:
                img = Image.open(io.BytesIO(inline.data)).convert("RGBA")
                img.thumbnail((MAX_OUTPUT_SIDE, MAX_OUTPUT_SIDE), Image.LANCZOS)
                out = io.BytesIO()
                img.save(out, "PNG")
                return out.getvalue()
    raise HTTPException(502, f"Gemini did not return an image. {note}".strip())


@app.get("/health")
def health() -> dict:
    return {"ok": True, "model": _model(), "key_configured": bool(os.getenv("GEMINI_API_KEY", "").strip())}


@app.post("/api/avatar")
def create_avatar(photo: UploadFile = File(...)) -> Response:
    """multipart field `photo` (jpg/png/webp, max 10 MB) -> image/png full-body avatar."""
    data = photo.file.read(MAX_UPLOAD_BYTES + 1)
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(413, "Photo is larger than 10 MB.")
    avatar = _generate(_normalize(data))
    return Response(content=avatar, media_type="image/png")
