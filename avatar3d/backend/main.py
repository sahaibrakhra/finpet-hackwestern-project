"""FastAPI app: API + static frontend on one port.

Run from avatar3d\\backend:  uvicorn main:app --port 8000
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import shutil
import uuid
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ROOT / ".env")

import pipeline  # noqa: E402  (after load_dotenv so env is populated)
from jobs import JobStore  # noqa: E402
from providers import ProviderError, get_provider  # noqa: E402

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"),
                    format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("avatar3d")

STORAGE = ROOT / "storage"
UPLOADS = STORAGE / "uploads"
MODELS = STORAGE / "models"
FRONTEND = ROOT / "frontend"
for d in (UPLOADS, MODELS):
    d.mkdir(parents=True, exist_ok=True)

MAX_UPLOAD_BYTES = 10 * 1024 * 1024
ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
THIRD_PARTY_WARNING = "Your photo is sent to a third-party public Space."


def _third_party_warning() -> str:
    backend = getattr(getattr(provider, "backend", None), "name", None)
    if backend == "veo":
        return "Your photo is sent to Google (Gemini / Veo) to generate the sprite and video clips."
    return THIRD_PARTY_WARNING

store = JobStore(STORAGE / "jobs.json")
executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="pipeline")

try:
    provider = get_provider()
    provider_error = None
except Exception as e:  # noqa: BLE001  - keep server up, report on upload
    provider, provider_error = None, str(e)
    log.error("Provider init failed: %s", e)


async def _watchdog() -> None:
    while True:
        await asyncio.sleep(15)
        store.expire_stuck()


@asynccontextmanager
async def lifespan(_app: FastAPI):
    task = asyncio.create_task(_watchdog())
    log.info("Provider=%s rembg=%s stylize=%s", provider.name if provider else None,
             pipeline.rembg_enabled(), pipeline.stylize_enabled())
    yield
    task.cancel()
    executor.shutdown(wait=False, cancel_futures=True)


app = FastAPI(title="avatar3d", lifespan=lifespan)


def _model_url(job_id: str) -> str:
    if (MODELS / f"{job_id}.json").exists():  # 2D video avatar
        return f"/api/models/{job_id}.json"
    return f"/api/models/{job_id}.glb"


def _check_id(item_id: str) -> None:
    if not ID_RE.match(item_id):
        raise HTTPException(400, "Invalid id.")


@app.get("/api/config")
def get_config():
    third_party = bool(provider and provider.third_party)
    return {
        "provider": provider.name if provider else os.getenv("PROVIDER", "mock"),
        "third_party": third_party,
        "warning": _third_party_warning() if third_party else None,
        "stylize_enabled": pipeline.stylize_enabled(),
        "rembg_enabled": pipeline.rembg_enabled(),
        "rig_enabled": pipeline.rig_enabled(),
        "parts_labels": True,
        "avatar_style": ("video2d" if provider is not None and provider.name == "video2d"
                         else "2d" if provider is not None and provider.name == "sprite2d" else "3d"),
        "video_backend": getattr(getattr(provider, "backend", None), "name", None),
        "optional_steps": {"rembg": pipeline.rembg_enabled(), "stylize": pipeline.stylize_enabled(), "rig": pipeline.rig_enabled()},
        "max_upload_mb": MAX_UPLOAD_BYTES // (1024 * 1024),
        "provider_error": provider_error,
    }


PART_KEYS = ("head", "torso", "left_arm", "right_arm", "left_leg", "right_leg")


def _parse_parts(raw: str | None) -> dict | None:
    """Optional body-part boxes: {"head": [x0, y0, x1, y1], ...}, normalised 0..1 on the photo."""
    if not raw:
        return None
    try:
        data = json.loads(raw)
        out = {}
        for k, b in data.items():
            if k not in PART_KEYS:
                raise ValueError(k)
            x0, y0, x1, y1 = (float(n) for n in b)
            if not (0 <= x0 < x1 <= 1 and 0 <= y0 < y1 <= 1):
                raise ValueError(k)
            out[k] = [x0, y0, x1, y1]
        return out or None
    except (ValueError, TypeError, AttributeError) as e:
        raise HTTPException(400, "The body-part labels are not valid. Skip that step or redraw the boxes.") from e


@app.post("/api/avatars")
async def create_avatar(photo: UploadFile = File(...), parts: str | None = Form(None)):
    if provider is None:
        raise HTTPException(500, f"Provider is misconfigured: {provider_error}")
    data = await photo.read(MAX_UPLOAD_BYTES + 1)
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(413, "That photo is larger than 10 MB. Please upload a smaller one.")
    if not data:
        raise HTTPException(400, "The uploaded file is empty.")
    try:
        img = await asyncio.to_thread(pipeline.normalize_photo, data)
    except pipeline.BadImage as e:
        raise HTTPException(415, str(e)) from e

    parts_dict = _parse_parts(parts)
    job = store.create(provider.name, uuid.uuid4().hex[:12])
    job_id = job["id"]
    path = UPLOADS / f"{job_id}.png"
    img.save(path, "PNG")
    thumb = img.convert("RGB")
    thumb.thumbnail((256, 256))
    thumb.save(UPLOADS / f"{job_id}_thumb.jpg", "JPEG", quality=85)
    store.update(job_id, has_thumbnail=True)

    if hasattr(provider, "pipeline"):  # providers with their own pipeline (video2d)
        executor.submit(provider.pipeline, store, job_id, path, MODELS, parts_dict)
    else:
        executor.submit(pipeline.run_pipeline, store, job_id, path, provider, MODELS, parts_dict)
    log.info("job %s queued (%s, %d bytes)", job_id, provider.name, len(data))
    return {"job_id": job_id}


@app.get("/api/jobs/{job_id}")
def get_job(job_id: str):
    _check_id(job_id)
    job = store.get(job_id)
    if not job:
        raise HTTPException(404, "Job not found.")
    done = job["status"] == "done"
    return {
        "status": job["status"],
        "message": job["message"],
        "elapsed_s": JobStore.elapsed(job),
        "model_url": _model_url(job_id) if done else None,
        "error": job["error"],
    }


@app.get("/api/models/{filename}")
def get_model(filename: str):
    if filename.endswith(".json"):  # 2D video avatar manifest
        model_id = filename[:-5]
        _check_id(model_id)
        path = MODELS / f"{model_id}.json"
        if not path.exists():
            raise HTTPException(404, "Model not found.")
        return FileResponse(path, media_type="application/json", headers={"Cache-Control": "no-store"})
    if not filename.endswith(".glb"):
        raise HTTPException(404, "Model not found.")
    model_id = filename[:-4]
    _check_id(model_id)
    path = MODELS / f"{model_id}.glb"
    if not path.exists():
        raise HTTPException(404, "Model not found.")
    return FileResponse(path, media_type="model/gltf-binary", filename=filename)


PUPPET_FILE_RE = re.compile(r"^[A-Za-z0-9_.-]{1,64}$")
PUPPET_TYPES = {".webm": "video/webm", ".png": "image/png", ".mp4": "video/mp4"}


@app.get("/api/puppets/{avatar_id}/{filename}")
def get_puppet_file(avatar_id: str, filename: str):
    _check_id(avatar_id)
    ext = Path(filename).suffix.lower()
    if not PUPPET_FILE_RE.match(filename) or ext not in PUPPET_TYPES:
        raise HTTPException(404, "File not found.")
    path = MODELS / f"{avatar_id}_puppet" / filename
    if not path.exists():
        raise HTTPException(404, "File not found.")
    return FileResponse(path, media_type=PUPPET_TYPES[ext])


@app.get("/api/thumbnails/{filename}")
def get_thumbnail(filename: str):
    if not filename.endswith(".jpg"):
        raise HTTPException(404, "Thumbnail not found.")
    _check_id(filename[:-4])
    path = UPLOADS / f"{filename[:-4]}_thumb.jpg"
    if not path.exists():
        raise HTTPException(404, "Thumbnail not found.")
    return FileResponse(path, media_type="image/jpeg")


@app.get("/api/avatars")
def list_avatars():
    out = []
    for j in store.list_done():
        if not ((MODELS / f"{j['id']}.glb").exists() or (MODELS / f"{j['id']}.json").exists()):
            continue
        has_thumb = (UPLOADS / f"{j['id']}_thumb.jpg").exists()
        out.append({
            "id": j["id"],
            "created_at": j["created_at"],
            "provider": j["provider"],
            "model_url": _model_url(j["id"]),
            "thumbnail": f"/api/thumbnails/{j['id']}.jpg" if has_thumb else None,
        })
    return out


@app.delete("/api/avatars/{avatar_id}")
def delete_avatar(avatar_id: str):
    _check_id(avatar_id)
    job = store.get(avatar_id)
    if not job:
        raise HTTPException(404, "Avatar not found.")
    if job["status"] not in ("done", "error"):
        raise HTTPException(409, "That avatar is still being generated.")
    (MODELS / f"{avatar_id}.glb").unlink(missing_ok=True)
    (MODELS / f"{avatar_id}.json").unlink(missing_ok=True)
    shutil.rmtree(MODELS / f"{avatar_id}_puppet", ignore_errors=True)
    for f in UPLOADS.glob(f"{avatar_id}*"):
        f.unlink(missing_ok=True)
    store.delete(avatar_id)
    return {"deleted": avatar_id}


# Static frontend last so /api/* wins. check_dir=False lets the API start before the frontend exists.
app.mount("/", StaticFiles(directory=FRONTEND, html=True, check_dir=False), name="frontend")
