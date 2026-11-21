"""Photo -> GLB pipeline. run_pipeline() is blocking; main.py runs it in a worker thread."""
from __future__ import annotations

import io
import logging
import os
import shutil
from pathlib import Path

from PIL import Image, ImageOps, UnidentifiedImageError

from jobs import JobStore
from providers import Provider, ProviderError

log = logging.getLogger("avatar3d.pipeline")

MAX_SIDE = 1024
ALLOWED_FORMATS = {"JPEG", "PNG", "WEBP"}

STYLIZE_PROMPT = (
    "Turn the person in this photo into a clean, front-facing, full-body stylized 3D-character "
    "reference image. Neutral standing pose, arms relaxed slightly away from the body, "
    "plain uniform background, soft even lighting, no text, no props."
)


class BadImage(ValueError):
    """The uploaded file is not a usable jpg/png/webp image."""


def env_bool(name: str, default: bool = False) -> bool:
    v = os.getenv(name)
    return default if v is None else v.strip().lower() in {"1", "true", "yes", "on"}


def rembg_enabled() -> bool:
    return env_bool("REMBG", True)


def rig_enabled() -> bool:
    return env_bool("RIG", True)


def stylize_enabled() -> bool:
    return env_bool("STYLIZE", False) and bool(os.getenv("GEMINI_API_KEY", "").strip())


def normalize_photo(data: bytes) -> Image.Image:
    """Validate and normalize: real image, allowed format, EXIF-rotated, RGB(A), max side 1024."""
    try:
        probe = Image.open(io.BytesIO(data))
        fmt = probe.format
        probe.verify()
        img = Image.open(io.BytesIO(data))
        img.load()
    except (UnidentifiedImageError, OSError, SyntaxError, ValueError, Image.DecompressionBombError) as e:
        raise BadImage("That file isn't a readable image. Please upload a JPG, PNG or WebP photo.") from e
    if fmt not in ALLOWED_FORMATS:
        raise BadImage(f"Unsupported image type {fmt}. Please upload a JPG, PNG or WebP photo.")
    img = ImageOps.exif_transpose(img)
    img = img.convert("RGBA" if "A" in img.getbands() else "RGB")
    img.thumbnail((MAX_SIDE, MAX_SIDE), Image.LANCZOS)
    return img


_REMBG_SESSION = None


def _remove_background(src: Path, dst: Path) -> None:
    from rembg import new_session, remove  # heavy import, keep lazy
    global _REMBG_SESSION
    if _REMBG_SESSION is None:
        _REMBG_SESSION = new_session(os.getenv("REMBG_MODEL", "u2net"))
    with Image.open(src) as im:
        out = remove(im, session=_REMBG_SESSION)
    out.save(dst, "PNG")


def _stylize(src: Path, dst: Path) -> None:
    from google import genai  # google-genai
    client = genai.Client(api_key=os.environ["GEMINI_API_KEY"].strip())
    model = os.getenv("GEMINI_MODEL", "gemini-2.5-flash-image")
    with Image.open(src) as im:
        resp = client.models.generate_content(model=model, contents=[STYLIZE_PROMPT, im.convert("RGB")])
    for cand in resp.candidates or []:
        for part in (cand.content.parts if cand.content else []) or []:
            inline = getattr(part, "inline_data", None)
            if inline and inline.data:
                Image.open(io.BytesIO(inline.data)).convert("RGB").save(dst, "PNG")
                return
    raise RuntimeError("Gemini returned no image")


def run_pipeline(store: JobStore, job_id: str, image_path: Path, provider: Provider,
                 models_dir: Path) -> None:
    """Stages 2-5. Stage 1 (validate/normalize) already ran in the upload handler."""
    notes: list[str] = []

    def stage(status: str, message: str) -> None:
        store.update(job_id, status=status, message=" ".join(notes + [message]).strip())

    try:
        current = image_path

        # 2. background removal
        if rembg_enabled():
            stage("removing_background", "Removing background...")
            nobg = image_path.with_name(f"{image_path.stem}_nobg.png")
            try:
                _remove_background(current, nobg)
                current = nobg
            except Exception as e:  # noqa: BLE001
                log.warning("rembg failed: %s", e)
                notes.append("(Background removal failed; using the original photo.)")
        else:
            notes.append("(Background removal disabled.)")

        # 3. optional stylize
        if stylize_enabled():
            stage("stylizing", "Stylizing photo with Gemini...")
            styled = image_path.with_name(f"{image_path.stem}_styled.png")
            try:
                _stylize(current, styled)
                current = styled
            except Exception as e:  # noqa: BLE001  (never log the key)
                log.warning("stylize failed: %s", type(e).__name__)
                notes.append("(Stylize step failed and was skipped.)")

        # 4. mesh
        stage("generating_mesh", f"Generating 3D mesh with '{provider.name}' provider...")
        glb = provider.generate(current, on_progress=lambda m: stage("generating_mesh", m))

        # 4b. local auto-rig (skeleton + skin weights + idle clip)
        if rig_enabled():
            stage("generating_mesh", "Rigging model (skeleton + skin weights)...")
            rigged = glb.with_name(f"{glb.stem}_rigged.glb")
            try:
                import rigging
                info = rigging.rig_glb(glb, rigged)
                glb = rigged
                log.info("job %s rigged: %s", job_id, info)
            except Exception as e:  # noqa: BLE001
                log.warning("rigging failed: %s", e)
                notes.append(f"(Rigging failed: {e}; showing the unrigged model.)")

        # 5. finalize
        stage("finalizing", "Saving model...")
        models_dir.mkdir(parents=True, exist_ok=True)
        final = models_dir / f"{job_id}.glb"
        shutil.move(str(glb), final)
        if not final.exists() or final.stat().st_size < 20:
            raise ProviderError("The provider produced an empty model file.")
        if not store.is_active(job_id):  # timed out meanwhile
            final.unlink(missing_ok=True)
            return
        store.update(job_id, status="done", message=" ".join(notes + ["Done."]).strip())
        log.info("job %s done", job_id)
    except ProviderError as e:
        log.warning("job %s provider error: %s", job_id, e)
        store.fail(job_id, str(e))
    except NotImplementedError as e:
        store.fail(job_id, f"Provider '{provider.name}' is not implemented. {e}")
    except Exception as e:  # noqa: BLE001
        log.exception("job %s failed", job_id)
        store.fail(job_id, f"Unexpected error: {type(e).__name__}: {e}")
