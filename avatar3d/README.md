# avatar3d

Localhost prototype: upload a photo, get a 3D avatar shown in the browser with a looping idle animation.
One FastAPI server on http://localhost:8000 serves the API and the frontend (no CORS, no npm).

## Quick start (PowerShell, Windows, Python 3.10+)

```powershell
cd avatar3d
py -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r backend\requirements.txt
copy .env.example .env
cd backend
uvicorn main:app --port 8000
```

Open http://localhost:8000 in Chrome. If script execution is blocked, run once:
`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

The first upload with `REMBG=true` downloads the rembg model (~170 MB) to `~\.u2net`; if that fails
the pipeline continues with the original photo and says so in the job message. Set `REMBG=false` in `.env` to skip it.

## Smoke test

With the server running (`PROVIDER=mock`), in a second PowerShell window (venv activated):

```powershell
python scripts\smoke_test.py
python scripts\smoke_test.py C:\path\to\me.jpg
```

It uploads, polls until done, downloads the GLB and asserts it is a valid GLB.

## API (stable)

| Method | Path | Notes |
|---|---|---|
| POST | `/api/avatars` | multipart field `photo` (jpg/png/webp, max 10 MB) -> `{"job_id": "..."}` |
| GET | `/api/jobs/{job_id}` | `{status, message, elapsed_s, model_url, error}`; status is `queued, removing_background, stylizing, generating_mesh, finalizing, done, error` |
| GET | `/api/models/{id}.glb` | the GLB |
| GET | `/api/avatars` | list of `{id, created_at, provider, model_url, thumbnail}` |
| DELETE | `/api/avatars/{id}` | deletes photo(s) and model |
| GET | `/api/config` | `{provider, third_party, warning, stylize_enabled, rembg_enabled, optional_steps, ...}` |
| GET | `/api/thumbnails/{id}.jpg` | extra: thumbnail used by `/api/avatars` |

curl.exe examples (PowerShell, one line each):

```powershell
curl.exe -F "photo=@me.jpg" http://localhost:8000/api/avatars
curl.exe http://localhost:8000/api/jobs/JOB_ID
curl.exe -o avatar.glb http://localhost:8000/api/models/JOB_ID.glb
curl.exe http://localhost:8000/api/avatars
curl.exe -X DELETE http://localhost:8000/api/avatars/JOB_ID
curl.exe http://localhost:8000/api/config
```

## Providers

Choose with `PROVIDER=` in `.env` (restart the server after changing).

- **mock** (default): a static capsule/sphere mannequin built with trimesh, tinted by the photo's average colour. No GPU, no network (except the one-time rembg model download). Has a short artificial delay (`MOCK_DELAY_S`).
- **hf_space**: calls a public image-to-3D Hugging Face Space through `gradio_client`. **Your photo is sent to a third-party public Space**; `/api/config` reports `third_party: true` and a `warning` string for the UI.
- **local_gpu**: documented stub that raises `NotImplementedError`.

### Switching to hf_space

1. In `.env` set `PROVIDER=hf_space`. Optionally set `HF_SPACE_ID` (default `tencent/Hunyuan3D-2`; a TRELLIS Space also works if it exposes an image-to-3D endpoint).
2. Restart the server.

The provider connects, calls `view_api()`, and picks the endpoint that takes an image and returns a file/3D model.
Nothing about the API is hardcoded. If auto-detection picks wrongly or fails, the error lists the available endpoints; set
`HF_SPACE_ENDPOINT` (e.g. `/shape_generation`) and, for parameters without defaults, `HF_SPACE_ARGS_JSON` (e.g. `{"seed": 1}`).
Non-GLB output (obj/ply/stl...) is converted to GLB with trimesh. Quota errors, timeouts, queue-full and an unavailable Space
produce friendly job errors; the server never crashes. Public Spaces change often, so expect to adjust the ID/endpoint.

### Getting a free HF token

Create a free account at https://huggingface.co, open Settings -> Access Tokens, create a token with *Read* access, and put it in
`.env` as `HF_TOKEN=hf_...`. Logged-in requests get a larger free ZeroGPU quota than anonymous ones. Never commit `.env`.

### Running Hunyuan3D or TRELLIS locally later

You need an NVIDIA GPU (roughly 12+ GB VRAM for shape + texture), CUDA PyTorch, and a separate venv.
Install Hunyuan3D-2 (https://github.com/Tencent/Hunyuan3D-2) or TRELLIS (https://github.com/microsoft/TRELLIS) per their READMEs, then
implement `LocalGpuProvider.generate(image_path)` in `backend\providers\local_gpu.py`: load the pipeline once, run it on the image,
export a GLB, and return its path. Set `PROVIDER=local_gpu`.

## Optional Gemini stylize step

Off by default. Set `STYLIZE=true` and `GEMINI_API_KEY=...` in `.env` to restyle the photo into a clean front-facing full-body
character before mesh generation. This sends the photo to Google. On failure it is skipped. Keys are never logged.

## Storage and persistence

`storage\uploads` (normalized photo, background-removed copy, thumbnail), `storage\models` (GLBs) and `storage\jobs.json` are git-ignored.
Jobs persist across restarts; a job that was running when the server stopped becomes an error. A job stuck over 10 minutes (`JOB_TIMEOUT_S`) is failed.

## Assumptions

- Avatar id equals job id. Only `done` jobs appear in the gallery; deleting removes the job record, photos and model.
- Uploads are normalized (EXIF rotation applied/stripped, max side 1024, saved as PNG); the original bytes are not kept.
- One pipeline job runs at a time (rembg and Space calls are heavy); others wait in `queued`.
- The 10-minute timeout counts from job creation. A timed-out worker thread cannot be killed, but its result is discarded.
- Invalid image -> HTTP 415, over 10 MB -> 413, unknown id -> 404.
- Default HF Space ID is a best guess and may need changing. The Gemini model default is `gemini-2.5-flash-image`.
- Server code lives in `backend\` and must be started from there (`cd backend`), since modules import each other by bare name.

## Local auto-rig (RIG=true, default)

After any provider produces a mesh, `backend/rigging.py` fits a humanoid skeleton (22 joints), computes skin
weights, and adds a looping `idle` animation clip, all on the CPU with no network. The viewer plays that clip.

Assumptions and limits: the model is upright, Y-up and faces +Z. It is a heuristic (proportions plus
nearest-bone weights), so it suits humanoid characters and will deform oddly on unusual shapes. If rigging
fails the unrigged model is shown with a note. Set `RIG=false` in `.env` to skip it (the viewer then falls
back to the procedural idle). Models that already have a skeleton are left alone.
