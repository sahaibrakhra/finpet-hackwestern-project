# FinPet backend

Turns the user's photo into a full-body cartoon avatar, then into four short animations, using Gemini.
The Gemini key lives only in `backend/.env`; the app never sees it.

## Setup (from this directory)
```
python3 -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env             # Windows: copy .env.example .env  -> then set GEMINI_API_KEY
uvicorn main:app --host 0.0.0.0 --port 8000
```
Needs a billing-enabled Gemini key (image and video models are not on the free tier).

## Accounts (Supabase)
1. Create a Supabase project, open the SQL editor and run `schema.sql` (safe to re-run).
2. In `.env` set `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (secret, server-side only) and `JWT_SECRET`
   (generate: `python -c "import secrets;print(secrets.token_urlsafe(48))"`).
3. Passwords are stored as bcrypt hashes; login tokens are HS256 JWTs valid for 7 days (`JWT_EXPIRE_DAYS`).
4. Tests (DB mocked, no network): `pytest test_auth.py`. Avatars are not stored in the database.

- `POST /api/auth/register` and `POST /api/auth/login` - `{"username", "password"}` ->
  `{"token", "expires_at", "user": {"id", "username"}}` (400 invalid, 401 bad login, 409 username taken, 503 not configured).
- `GET /api/auth/me` - header `Authorization: Bearer <token>`. Protect other routes with `Depends(auth.get_current_user)`.

## Friends (all need `Authorization: Bearer <token>`)
- `GET /api/friends` - `{friends: [{id, username, streak}], incoming: [{request_id, id, username}], outgoing: [...]}`.
- `POST /api/friends/requests` `{username}` - sends a request (404 if the user does not exist, 409 if already pending or friends).
  Nobody is a friend until the other person accepts.
- `POST /api/friends/requests/{request_id}/accept` / `.../deny` - only the person who received it. Accepting makes the friendship mutual.
- `DELETE /api/friends/{user_id}` - removes an accepted friend for both people.
Tests: `pytest test_friends.py`. After pulling, re-run the grants at the bottom of `schema.sql` in the Supabase SQL editor.

## API
- `POST /api/avatar` - multipart field `photo` (jpg/png/webp, max 10 MB).
  Returns `{"avatar": <base64 transparent PNG, 9:16>, "background": "#RRGGBB"}`.
  Gemini draws the avatar on a flat color; the server samples that color (`background`), removes it, and
  centers the avatar on a 9:16 canvas.
- `POST /api/animate` - multipart fields `avatar` (the PNG above), `background` (the hex above), `kind`
  (`idle` | `wave` | `dance` | `cry`). Returns `{"fps": 10, "frames": [<base64 transparent PNG>, ...]}`.
  One short Gemini image-to-video call per request, always **16:9 landscape**: the app draws every image at the
  mascot box's full height, so the wide frame's side edges fall outside the visible box and a swinging arm is only
  cut off by the box edge, never mid-screen. The clip is decoded to frames and its background removed using the
  known `background` color. The avatar has the same relative height in the still and in the clips.
- `GET /health` - `{ok, image_model, video_model, key_configured}`.
- Errors are JSON `{"detail": "..."}` (400 bad input, 413 too large, 429 quota, 502 Gemini failure, 503 key missing, 504 timeout).

## Cost control (rough, from Google's published prices - verify on the pricing page)
Per avatar: 1 image (about $0.07) + 4 clips of 3 s at 360p (about $0.07 each) = roughly $0.35.
The app saves every avatar and animation on the phone and never re-requests a clip it already has.
Tune in `.env`: `ANIM_SECONDS` (3-15, 3 is cheapest), `ANIM_RESOLUTION` (360p is cheapest), `ANIM_FPS`, `ANIM_FRAME_HEIGHT`.

## Pointing the iOS app at it
The app reads `FinPetBackendURL` from `ios/Info.plist` (default `http://localhost:8000`, fine for the simulator).
On a real iPhone use your computer's LAN IP, e.g. `http://192.168.1.20:8000`.
