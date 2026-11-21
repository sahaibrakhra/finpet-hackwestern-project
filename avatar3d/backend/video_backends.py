"""Image-to-video backends for the 2D video avatar mode.

Every backend turns a first frame (the sprite on a solid green background) into a short video clip on the same
green background, ideally returning to the first frame at the end so clips loop and chain back into idle.

    generate(first_png, last_png, prompt, seconds, aspect, say) -> path of an .mp4

Backends: ``mock`` (offline, procedural motion for testing), ``omni`` (Gemini Omni through the Gemini Developer
API, needs GEMINI_API_KEY), ``veo`` (legacy, shut down on the Developer API), ``hf_wan`` (a public Hugging Face Space on ZeroGPU; free but with a tiny daily quota).
"""
from __future__ import annotations

import logging
import math
import os
import time
from pathlib import Path
from typing import Callable, Optional

import numpy as np
from PIL import Image

log = logging.getLogger("avatar3d.video")
Say = Callable[[str], None]

GREEN = (0, 177, 64)  # default chroma-key colour; the pipeline picks the best of green / blue / magenta per sprite


class VideoError(Exception):
    """Raised with a short, human-friendly message that is shown in the UI."""


class VideoBackend:
    name = "base"
    third_party = False
    #: clip lengths this backend can produce (seconds); the pipeline picks the closest to what it wants
    seconds_options: tuple[int, ...] = (4,)

    def pick_seconds(self, want: float) -> int:
        return min(self.seconds_options, key=lambda s: abs(s - want))

    def generate(self, first_png: Path, last_png: Optional[Path], prompt: str, seconds: int, aspect: str,
                 say: Say, key: tuple = GREEN) -> Path:
        raise NotImplementedError


# ----------------------------------------------------------------------------------------------- mock
class MockBackend(VideoBackend):
    """Procedural clips made from the sprite itself: no AI, no network. For testing the pipeline and viewer.

    Motion starts and ends exactly at the rest pose, like a good AI clip would.
    """
    name = "mock"
    seconds_options = (4, 5, 6)

    def generate(self, first_png, last_png, prompt, seconds, aspect, say, key=GREEN):
        import imageio_ffmpeg

        say("Rendering a demo clip (mock backend)...")
        frame = Image.open(first_png).convert("RGB")
        W, H = frame.size
        fps = 24
        n = int(seconds * fps)
        kind = "idle" if "breath" in prompt.lower() else ("wave" if "wave" in prompt.lower() else "dance")
        # sprite = everything that is not green; rotate/scale it around its feet and re-composite on green
        arr = np.asarray(frame).astype(np.int16)
        mask = (np.abs(arr - np.array(key)).sum(axis=2) > 60)
        ys, xs = np.nonzero(mask)
        if len(xs) == 0:
            raise VideoError("The sprite frame is empty.")
        bbox = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
        sprite = frame.crop(bbox).convert("RGBA")
        sprite.putalpha(Image.fromarray((mask[bbox[1]:bbox[3], bbox[0]:bbox[2]] * 255).astype(np.uint8)))
        feet = ((bbox[0] + bbox[2]) / 2, bbox[3])

        out = Path(first_png).with_name(f"{Path(first_png).stem}_{kind}_mock.mp4")
        writer = imageio_ffmpeg.write_frames(str(out), (W, H), fps=fps, codec="libx264", pix_fmt_in="rgb24",
                                             pix_fmt_out="yuv420p", macro_block_size=2,
                                             output_params=["-crf", "20", "-preset", "fast"])
        writer.send(None)
        for i in range(n):
            t = i / n  # 0..1, periodic so the last frame returns to the first
            s = math.sin(2 * math.pi * t)
            if kind == "idle":
                sx, sy, rot, dy = 1 - 0.006 * s, 1 + 0.012 * s, 0.6 * s, 0
            elif kind == "wave":
                env = math.sin(math.pi * t) ** 2
                sx, sy, rot, dy = 1, 1, 7 * math.sin(2 * math.pi * 3 * t) * env, 0
            else:  # dance
                beat = math.sin(2 * math.pi * 4 * t)
                env = math.sin(math.pi * t) ** 0.5
                sx, sy = 1 + 0.03 * beat * env, 1 - 0.03 * beat * env
                rot, dy = 9 * math.sin(2 * math.pi * 2 * t) * env, -abs(beat) * 0.03 * H * env
            sp = sprite.resize((max(1, int(sprite.width * sx)), max(1, int(sprite.height * sy))), Image.BICUBIC)
            sp = sp.rotate(rot, resample=Image.BICUBIC, expand=True, center=(sp.width / 2, sp.height))
            canvas = Image.new("RGB", (W, H), tuple(key))
            canvas.paste(sp, (int(feet[0] - sp.width / 2), int(feet[1] - sp.height + dy)), sp)
            writer.send(np.asarray(canvas).tobytes())
        writer.close()
        return out


# ----------------------------------------------------------------------------------------------- omni
class OmniBackend(VideoBackend):
    """Gemini Omni video generation on the plain Gemini Developer API (google-genai ``interactions``).

    Replaces Veo here: Google shut the Veo 3.1 preview models down on the Developer API on 2026-10-22. Omni takes a
    start image and an end image (two-frame interpolation, 3 to 10 seconds), so a clip can return to the sprite
    pose. The call is synchronous: the video comes back in the response.
    Written from Google's docs and NOT yet run against a real key; errors are reported verbatim to help fix it.
    """
    name = "omni"
    third_party = True
    seconds_options = (3, 4, 5, 6, 7, 8, 9, 10)

    def __init__(self) -> None:
        self.key = os.getenv("GEMINI_API_KEY", "").strip()
        if not self.key:
            raise VideoError("GEMINI_API_KEY is not set in .env, so the Gemini Omni video backend cannot run.")
        self.model = os.getenv("OMNI_MODEL", "gemini-omni-1.2-flash").strip()
        self.resolution = os.getenv("OMNI_RESOLUTION", "720p").strip()
        self.timeout_s = float(os.getenv("OMNI_TIMEOUT_S", "600"))

    @staticmethod
    def _friendly(e: Exception) -> str:
        t = str(e)
        low = t.lower()
        if "429" in low or "quota" in low or "resource_exhausted" in low or ("rate" in low and "limit" in low):
            return "Google's video API quota or rate limit was hit. Wait a bit, or check your Gemini API plan."
        if "api key" in low or "api_key_invalid" in low or "401" in low or "unauthenticated" in low:
            return "The Gemini API key was rejected. Create one at https://aistudio.google.com/apikey and set GEMINI_API_KEY."
        if "billing" in low or "permission" in low or "403" in low or "paid" in low or "not enabled" in low:
            return f"This Gemini key is not allowed to generate video (it may need billing enabled). Details: {t[:200]}"
        if "safety" in low or "blocked" in low or "filtered" in low or "responsible" in low:
            return "Google's safety filter blocked this image or prompt. Try a different character image."
        if "not found" in low or "404" in low:
            return f"The video model was not found. Set OMNI_MODEL in .env to one your key can use. ({t[:140]})"
        return f"The video service failed: {t[:260]}"

    @staticmethod
    def _find_video(obj):
        """Return ('data', bytes) or ('uri', str) from an interaction response (SDK object or dict)."""
        import base64

        def get(o, k):
            return o.get(k) if isinstance(o, dict) else getattr(o, k, None)

        ov = get(obj, "output_video")
        if ov is not None:
            if get(ov, "data"):
                return "data", base64.b64decode(get(ov, "data"))
            if get(ov, "uri"):
                return "uri", get(ov, "uri")
        for step in (get(obj, "steps") or []):
            for part in (get(step, "content") or []):
                if get(part, "type") == "video":
                    if get(part, "data"):
                        return "data", base64.b64decode(get(part, "data"))
                    if get(part, "uri"):
                        return "uri", get(part, "uri")
        return None

    def generate(self, first_png, last_png, prompt, seconds, aspect, say, key=GREEN):
        import base64

        from google import genai

        client = genai.Client(api_key=self.key)
        first = base64.b64encode(Path(first_png).read_bytes()).decode()
        parts = [{"type": "image", "data": first, "mime_type": "image/png"}]
        text = prompt
        if last_png:
            last = base64.b64encode(Path(last_png).read_bytes()).decode()
            parts.append({"type": "image", "data": last, "mime_type": "image/png"})
            text = ("The first image is the starting frame and the last image is the ending frame; the character "
                    "returns to exactly this pose at the end. " + prompt)
        text += " No dialogue, no music, no sound effects. Keep the camera completely still."
        parts.append({"type": "text", "text": text})
        fmt = {"type": "video", "aspect_ratio": aspect, "duration": f"{int(seconds)}s", "resolution": self.resolution}

        say("Sending the sprite to Gemini Omni (this can take a minute or two)...")
        try:
            interaction = client.interactions.create(model=self.model, input=parts, response_format=fmt,
                                                     timeout=self.timeout_s)
        except TypeError:
            # older/newer SDK signature: drop the options it does not know
            interaction = client.interactions.create(model=self.model, input=parts,
                                                     response_format={"type": "video", "aspect_ratio": aspect})
        except Exception as e:  # noqa: BLE001
            raise VideoError(self._friendly(e)) from e

        found = self._find_video(interaction)
        if not found:
            raise VideoError("Gemini returned no video (it may have been filtered). Try again or use another image.")
        out = Path(first_png).with_name(f"{Path(first_png).stem}_omni_{int(time.time())}.mp4")
        kind, val = found
        try:
            if kind == "data":
                out.write_bytes(val)
            else:
                client.files.download(file=val, destination=str(out))
        except Exception as e:  # noqa: BLE001
            raise VideoError(f"Could not download the generated video: {str(e)[:160]}") from e
        return out


# ------------------------------------------------------------------------------------------------- veo
class VeoBackend(VideoBackend):
    """LEGACY: Google Veo 3.1 preview on the Gemini Developer API, which Google shut down on 2026-10-22.
    Kept only in case you have Veo access elsewhere; use ``omni`` instead.

    The model id is configurable (VEO_MODEL) because Google renames preview models. Veo 3.x produces 4, 6 or 8
    second clips; the last-frame option makes a clip end on the sprite so it can loop.
    """
    name = "veo"
    third_party = True
    seconds_options = (4, 6, 8)

    def __init__(self) -> None:
        self.key = os.getenv("GEMINI_API_KEY", "").strip()
        if not self.key:
            raise VideoError("GEMINI_API_KEY is not set in .env, so the Veo video backend cannot run.")
        self.model = os.getenv("VEO_MODEL", "veo-3.1-fast-generate-preview").strip()
        self.timeout_s = float(os.getenv("VEO_TIMEOUT_S", "600"))

    @staticmethod
    def _friendly(e: Exception) -> str:
        t = str(e)
        low = t.lower()
        if "429" in low or "quota" in low or "resource_exhausted" in low or "rate" in low and "limit" in low:
            return "Google's video API quota or rate limit was hit. Wait a bit, or check your Gemini API plan."
        if "billing" in low or "permission" in low or "403" in low or "not enabled" in low or "paid" in low:
            return ("The Veo video API is not enabled for this key (it needs a paid Gemini API plan). "
                    f"Details: {t[:160]}")
        if "api key" in low or "401" in low or "unauthenticated" in low or "api_key_invalid" in low:
            return "The Gemini API key was rejected. Check GEMINI_API_KEY in .env."
        if "safety" in low or "blocked" in low or "responsible ai" in low or "filtered" in low:
            return "Google's safety filter blocked this image or prompt. Try a different character image."
        if "not found" in low or "404" in low:
            return f"The Veo model was not found. Set VEO_MODEL in .env to a model your key can use. ({t[:120]})"
        return f"The video service failed: {t[:240]}"

    def generate(self, first_png, last_png, prompt, seconds, aspect, say, key=GREEN):
        from google import genai
        from google.genai import types

        client = genai.Client(api_key=self.key)
        img = types.Image(image_bytes=Path(first_png).read_bytes(), mime_type="image/png")
        last = types.Image(image_bytes=Path(last_png).read_bytes(), mime_type="image/png") if last_png else None
        base = dict(aspect_ratio=aspect, duration_seconds=seconds, number_of_videos=1,
                    negative_prompt="camera movement, zoom, extra limbs, deformed, text, subtitles, "
                                    "background change, shadows, cuts")
        attempts = [dict(base, last_frame=last, generate_audio=False), dict(base, last_frame=last), dict(base)]
        op = None
        err: Optional[Exception] = None
        for kwargs in attempts:
            kwargs = {k: v for k, v in kwargs.items() if v is not None}
            try:
                say("Sending the sprite to Google Veo...")
                op = client.models.generate_videos(model=self.model, prompt=prompt, image=img,
                                                   config=types.GenerateVideosConfig(**kwargs))
                break
            except Exception as e:  # noqa: BLE001
                err = e
                low = str(e).lower()
                # a parameter this model does not accept: retry with fewer options
                if any(w in low for w in ("last_frame", "lastframe", "generate_audio", "generateaudio", "not supported",
                                          "unsupported", "invalid_argument", "invalid argument")):
                    log.info("Veo rejected options (%s); retrying with fewer", str(e)[:120])
                    continue
                raise VideoError(self._friendly(e)) from e
        if op is None:
            raise VideoError(self._friendly(err or Exception("unknown error")))

        t0 = time.time()
        while not op.done:
            if time.time() - t0 > self.timeout_s:
                raise VideoError("Google Veo took too long to finish this clip. Try again later.")
            say(f"Veo is generating the clip ({int(time.time() - t0)} s)...")
            time.sleep(8)
            try:
                op = client.operations.get(op)
            except Exception as e:  # noqa: BLE001
                raise VideoError(self._friendly(e)) from e
        if getattr(op, "error", None):
            raise VideoError(self._friendly(Exception(str(op.error))))
        vids = getattr(getattr(op, "response", None), "generated_videos", None) or []
        if not vids:
            raise VideoError("Veo returned no video (it may have been filtered). Try again or use another image.")
        out = Path(first_png).with_name(f"{Path(first_png).stem}_veo_{int(time.time())}.mp4")
        try:
            client.files.download(file=vids[0].video)
            vids[0].video.save(str(out))
        except Exception as e:  # noqa: BLE001
            raise VideoError(f"Could not download the generated video: {str(e)[:160]}") from e
        return out


# ----------------------------------------------------------------------------------------- hf_wan
class HfWanBackend(VideoBackend):
    """Wan 2.2 first/last-frame on a public Hugging Face Space (ZeroGPU). Free, but the daily GPU quota is small."""
    name = "hf_wan"
    third_party = True
    seconds_options = (2, 3)

    def __init__(self) -> None:
        self.space = os.getenv("HF_VIDEO_SPACE", "multimodalart/wan-2-2-first-last-frame").strip()
        self.token = os.getenv("HF_TOKEN", "").strip() or None
        self.timeout_s = float(os.getenv("HF_TIMEOUT_S", "900"))

    def generate(self, first_png, last_png, prompt, seconds, aspect, say, key=GREEN):
        import shutil
        try:
            from gradio_client import Client, handle_file
        except ImportError as e:
            raise VideoError("gradio_client is not installed.") from e
        say(f"Connecting to {self.space}...")
        try:
            try:
                c = Client(self.space, hf_token=self.token, verbose=False)
            except TypeError:
                c = Client(self.space, token=self.token, verbose=False)
            say("Waiting in the Hugging Face GPU queue (this can take minutes)...")
            res = c.submit(handle_file(str(first_png)), handle_file(str(last_png or first_png)), prompt,
                           "camera movement, extra limbs, deformed, blurry, text", float(seconds), 8, 1.0, 1.0, 42,
                           True, api_name="/generate_video").result(timeout=self.timeout_s)
        except Exception as e:  # noqa: BLE001
            low = str(e).lower()
            if "zerogpu" in low or "quota" in low or "exceeded" in low:
                raise VideoError("The free Hugging Face GPU quota is used up for today. Try again later, or switch "
                                 "VIDEO_BACKEND to veo (needs GEMINI_API_KEY).") from e
            raise VideoError(f"The Hugging Face video Space failed: {str(e)[:200]}") from e
        vid = res[0] if isinstance(res, (list, tuple)) else res
        if isinstance(vid, dict):
            vid = vid.get("video") or vid.get("path")
        out = Path(first_png).with_name(f"{Path(first_png).stem}_hfwan_{int(time.time())}.mp4")
        shutil.copyfile(vid, out)
        return out


def get_video_backend(name: Optional[str] = None) -> VideoBackend:
    name = (name or os.getenv("VIDEO_BACKEND", "auto")).strip().lower()
    if name == "auto":
        name = "omni" if os.getenv("GEMINI_API_KEY", "").strip() else "mock"
    if name == "mock":
        return MockBackend()
    if name == "omni":
        return OmniBackend()
    if name == "veo":
        return VeoBackend()
    if name == "hf_wan":
        return HfWanBackend()
    raise VideoError(f"Unknown VIDEO_BACKEND '{name}'. Use auto, mock, omni, veo or hf_wan.")
