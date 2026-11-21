"""FastAPI app: API + static frontend on one port.

Run from avatar3d\\backend:  uvicorn main:app --port 8000
"""
from __future__ import annotations

import asyncio
import logging
import os
import re
import uuid
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, File, HTTPException, UploadFile
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
        "warning": THIRD_PARTY_WARNING if third_party else None,
        "stylize_enabled": pipeline.stylize_enabled(),
        "rembg_enabled": pipeline.rembg_enabled(),
        "rig_enabled": pipeline.rig_enabled(),
        "optional_steps": {"rembg": pipeline.rembg_enabled(), "stylize": pipeline.stylize_enabled(), "rig": pipeline.rig_enabled()},
        "max_upload_mb": MAX_UPLOAD_BYTES // (1024 * 1024),
        "provider_error": provider_error,
    }


@app.post("/api/avatars")
async def create_avatar(photo: UploadFile = File(...)):
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

    job = store.create(provider.name, uuid.uuid4().hex[:12])
    job_id = job["id"]
    path = UPLOADS / f"{job_id}.png"
    img.save(path, "PNG")
    thumb = img.convert("RGB")
    thumb.thumbnail((256, 256))
    thumb.save(UPLOADS / f"{job_id}_thumb.jpg", "JPEG", quality=85)
    store.update(job_id, has_thumbnail=True)

    executor.submit(pipeline.run_pipeline, store, job_id, path, provider, MODELS)
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
    if not filename.endswith(".glb"):
        raise HTTPException(404, "Model not found.")
    model_id = filename[:-4]
    _check_id(model_id)
    path = MODELS / f"{model_id}.glb"
    if not path.exists():
        raise HTTPException(404, "Model not found.")
    return FileResponse(path, media_type="model/gltf-binary", filename=filename)


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
        if not (MODELS / f"{j['id']}.glb").exists():
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
    for f in UPLOADS.glob(f"{avatar_id}*"):
        f.unlink(missing_ok=True)
    store.delete(avatar_id)
    return {"deleted": avatar_id}


# Static frontend last so /api/* wins. check_dir=False lets the API start before the frontend exists.
app.mount("/", StaticFiles(directory=FRONTEND, html=True, check_dir=False), name="frontend")
