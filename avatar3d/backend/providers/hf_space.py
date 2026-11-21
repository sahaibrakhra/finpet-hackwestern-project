"""hf_space provider: image-to-3D through a public Hugging Face Space (gradio_client).

The Space API is discovered at runtime with Client.view_api(); nothing about the
endpoint layout is hardcoded. Override with HF_SPACE_ENDPOINT / HF_SPACE_ARGS_JSON.
"""
from __future__ import annotations

import json
import logging
import os
import shutil
from pathlib import Path
from typing import Any, Optional

from .base import Provider, ProviderError, ProgressCb

log = logging.getLogger("avatar3d.hf_space")

MESH_EXTS = (".glb", ".gltf", ".obj", ".ply", ".stl", ".off", ".fbx")
IMAGE_HINTS = ("image", "img", "photo", "picture")
OUT_HINTS = ("model3d", "3d", "file", "glb", "mesh", "download")
NAME_HINTS = ("image_to_3d", "image-to-3d", "img_to_3d", "img2", "image2", "shape", "generation", "generate", "predict")


def _friendly(exc: Exception) -> str:
    text = str(exc)
    low = text.lower()
    if "quota" in low or "exceeded your" in low or "too many requests" in low or "429" in low:
        return ("The Hugging Face Space is over its free GPU quota. Wait a while, set HF_TOKEN in .env "
                "(a free account gets a bigger quota), or try another Space / PROVIDER=mock.")
    if "timed out" in low or "timeout" in low:
        return "The Hugging Face Space timed out. It may be busy or sleeping; try again later."
    if "queue" in low and "full" in low:
        return "The Hugging Face Space queue is full. Try again in a few minutes."
    if "not found" in low or "404" in low or "could not get space" in low or "paused" in low or "sleeping" in low:
        return f"The Hugging Face Space is unavailable ({text[:200]}). Check HF_SPACE_ID in .env."
    if "401" in low or "403" in low or "unauthorized" in low or "token" in low:
        return f"The Hugging Face Space rejected the request (auth problem: {text[:200]}). Check HF_TOKEN."
    return f"The Hugging Face Space failed: {text[:300]}"


class HfSpaceProvider(Provider):
    name = "hf_space"
    third_party = True

    def __init__(self) -> None:
        self.space_id = os.getenv("HF_SPACE_ID", "tencent/Hunyuan3D-2").strip()
        self.endpoint = os.getenv("HF_SPACE_ENDPOINT", "").strip() or None
        self.token = os.getenv("HF_TOKEN", "").strip() or None
        self.timeout_s = float(os.getenv("HF_TIMEOUT_S", "420"))
        raw = os.getenv("HF_SPACE_ARGS_JSON", "").strip()
        try:
            self.extra_args: dict[str, Any] = json.loads(raw) if raw else {}
        except json.JSONDecodeError as e:
            raise ProviderError(f"HF_SPACE_ARGS_JSON is not valid JSON: {e}") from e

    # -- discovery ---------------------------------------------------------
    @staticmethod
    def _is_image_param(p: dict) -> bool:
        blob = " ".join(str(p.get(k, "")) for k in ("label", "parameter_name", "component", "type", "python_type")).lower()
        return any(h in blob for h in IMAGE_HINTS) and ("file" in blob or "image" in blob)

    def _pick_endpoint(self, api: dict) -> tuple[str, dict]:
        named = api.get("named_endpoints") or {}
        if not named:
            raise ProviderError(f"Space {self.space_id} exposes no named API endpoints.")
        if self.endpoint:
            key = self.endpoint if self.endpoint.startswith("/") else "/" + self.endpoint
            if key not in named:
                raise ProviderError(f"Endpoint {key} not found in {self.space_id}. Available: {', '.join(named)}")
            return key, named[key]
        best, best_score = None, 0
        for name, info in named.items():
            params = info.get("parameters") or []
            if not any(self._is_image_param(p) for p in params):
                continue
            score = 1
            lname = name.lower()
            score += 3 * any(h in lname for h in NAME_HINTS)
            rets = " ".join(str(r) for r in (info.get("returns") or [])).lower()
            score += 2 * any(h in rets for h in OUT_HINTS)
            # prefer the endpoint with a full set of defaults (we can fill everything else)
            score += all(p.get("parameter_has_default") or self._is_image_param(p) for p in params)
            if score > best_score:
                best, best_score = name, score
        if not best:
            raise ProviderError(
                f"Could not find an image-to-3D endpoint in {self.space_id}. Available endpoints: "
                f"{', '.join(named)}. Set HF_SPACE_ENDPOINT in .env.")
        log.info("auto-selected endpoint %s", best)
        return best, named[best]

    def _build_kwargs(self, info: dict, image_path: Path) -> dict:
        from gradio_client import handle_file

        kwargs: dict[str, Any] = {}
        image_set = False
        for p in info.get("parameters") or []:
            pname = p["parameter_name"]
            if pname in self.extra_args:
                kwargs[pname] = self.extra_args[pname]
            elif not image_set and self._is_image_param(p):
                kwargs[pname] = handle_file(str(image_path))
                image_set = True
            elif p.get("parameter_has_default"):
                continue  # let the Space use its own default
            else:
                raise ProviderError(
                    f"Space parameter '{pname}' has no default. Provide it via HF_SPACE_ARGS_JSON "
                    f'(e.g. {{"{pname}": "value"}}).')
        if not image_set:
            raise ProviderError("No image parameter found on the selected endpoint; set HF_SPACE_ENDPOINT.")
        return kwargs

    @staticmethod
    def _find_mesh(result: Any) -> Optional[str]:
        """Walk the result structure and return the first path to a mesh file."""
        if isinstance(result, str):
            return result if result.lower().endswith(MESH_EXTS) else None
        if isinstance(result, dict):
            for key in ("value", "path", "name", "url"):
                if key in result:
                    hit = HfSpaceProvider._find_mesh(result[key])
                    if hit:
                        return hit
            for v in result.values():
                hit = HfSpaceProvider._find_mesh(v)
                if hit:
                    return hit
        if isinstance(result, (list, tuple)):
            for v in result:
                hit = HfSpaceProvider._find_mesh(v)
                if hit:
                    return hit
        return None

    # -- main --------------------------------------------------------------
    def generate(self, image_path: Path, on_progress: Optional[ProgressCb] = None) -> Path:
        say = on_progress or (lambda _m: None)
        try:
            from gradio_client import Client
        except ImportError as e:
            raise ProviderError("gradio_client is not installed. Run: pip install -r backend\\requirements.txt") from e

        say(f"Connecting to Hugging Face Space {self.space_id}...")
        try:
            try:
                client = Client(self.space_id, hf_token=self.token, verbose=False)
            except TypeError:  # newer gradio_client renamed the argument
                client = Client(self.space_id, token=self.token, verbose=False)
            api = client.view_api(return_format="dict", print_info=False)
        except Exception as e:  # noqa: BLE001
            log.warning("HF connect failed: %s", e)
            raise ProviderError(_friendly(e)) from e

        endpoint, info = self._pick_endpoint(api)
        kwargs = self._build_kwargs(info, image_path)
        say(f"Submitted to {self.space_id}{endpoint}; waiting in the Space queue (this can take minutes)...")
        try:
            job = client.submit(api_name=endpoint, **kwargs)
            result = job.result(timeout=self.timeout_s)
        except Exception as e:  # noqa: BLE001
            log.warning("HF generation failed: %s: %s", type(e).__name__, e)
            if type(e).__name__ == "TimeoutError":
                raise ProviderError("The Hugging Face Space timed out. It may be busy; try again later.") from e
            raise ProviderError(_friendly(e)) from e

        mesh = self._find_mesh(result)
        if not mesh or not Path(mesh).exists():
            raise ProviderError(f"The Space returned no mesh file I could use (got: {str(result)[:200]}).")

        out = image_path.with_name(f"{image_path.stem}_hf.glb")
        if mesh.lower().endswith(".glb"):
            shutil.copyfile(mesh, out)
        else:
            say("Converting Space output to GLB...")
            try:
                import trimesh
                loaded = trimesh.load(mesh, force="scene")
                loaded.export(str(out), file_type="glb")
            except Exception as e:  # noqa: BLE001
                raise ProviderError(f"Could not convert the Space output ({Path(mesh).suffix}) to GLB: {e}") from e
        return out
