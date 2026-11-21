# FinPet backend

Receives the user's photo from the iOS app, asks Gemini for a full-body cartoon avatar, and returns it as a PNG.
The Gemini key lives only in `backend/.env`; the app never sees it.

## Setup (from this directory)
```
python -m venv .venv
.venv\Scripts\activate          # macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
copy .env.example .env          # macOS/Linux: cp .env.example .env  -> then set GEMINI_API_KEY
uvicorn main:app --host 0.0.0.0 --port 8000
```
Needs a billing-enabled Gemini key (image models are not on the free tier).

## API
- `POST /api/avatar` - multipart field `photo` (jpg/png/webp, max 10 MB). Returns `image/png`. Errors are JSON `{"detail": "..."}` (400 bad image, 413 too large, 429 quota, 502 Gemini failure, 503 key missing).
- `GET /health` - `{ok, model, key_configured}`.

## Pointing the iOS app at it
The app reads `FinPetBackendURL` from `ios/Info.plist` (default `http://localhost:8000`, fine for the simulator). On a real iPhone use your computer's LAN IP, e.g. `http://192.168.1.20:8000`.
