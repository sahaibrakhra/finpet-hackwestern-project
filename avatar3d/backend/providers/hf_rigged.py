"""hf_rigged provider: photo -> textured mesh -> auto-rigged GLB (skeleton + skin weights).

Uses a public Hugging Face Space that chains TRELLIS (image to textured 3D) and UniRig
(auto-rigging). The Space is stateful: generate_3d stores the mesh in the session and
rig_3d rigs it, so both calls must use the same gradio Client. Endpoint names are
verified against view_api() before use. If rigging fails, the textured (unrigged) mesh
is returned with a note, so the app still shows something.
"""
from __future__ import annotations

import logging
import os
import shutil
from pathlib import Path
from typing import Any, Optional

from .base import Provider, ProviderError, ProgressCb
from .hf_space import _friendly

log = logging.getLogger("avatar3d.hf_rigged")


def _first_glb(result: Any) -> Optional[str]:
    if isinstance(result, str):
        return result if result.lower().endswith(".glb") else None
    if isinstance(result, dict):
        for k in ("value", "path", "name", "url"):
            if k in result and (hit := _first_glb(result[k])):
                return hit
        for v in result.values():
            if hit := _first_glb(v):
                return hit
    if isinstance(result, (list, tuple)):
        for v in result:
            if hit := _first_glb(v):
                return hit
    return None


class HfRiggedProvider(Provider):
    name = "hf_rigged"
    third_party = True

    def __init__(self) -> None:
        self.space_id = os.getenv("HF_RIG_SPACE_ID", "kirikir13/image-to-rigged-3d").strip()
        self.token = os.getenv("HF_TOKEN", "").strip() or None
        self.timeout_s = float(os.getenv("HF_TIMEOUT_S", "900"))
        self.resolution = os.getenv("HF_RIG_RESOLUTION", "512")
        self.decimation = float(os.getenv("HF_RIG_DECIMATION", "100000"))
        self.texture_size = float(os.getenv("HF_RIG_TEXTURE_SIZE", "1024"))

    def _call(self, client, api_name: str, say: ProgressCb, label: str, **kwargs):
        say(label)
        try:
            return client.submit(api_name=api_name, **kwargs).result(timeout=self.timeout_s)
        except Exception as e:  # noqa: BLE001
            log.warning("%s failed: %s: %s", api_name, type(e).__name__, e)
            if type(e).__name__ == "TimeoutError":
                raise ProviderError("The Hugging Face Space timed out. It may be busy; try again later.") from e
            raise ProviderError(_friendly(e)) from e

    def generate(self, image_path: Path, on_progress: Optional[ProgressCb] = None) -> Path:
        say = on_progress or (lambda _m: None)
        try:
            from gradio_client import Client, handle_file
        except ImportError as e:
            raise ProviderError("gradio_client is not installed. Run: pip install -r backend\requirements.txt") from e

        say(f"Connecting to Hugging Face Space {self.space_id}...")
        try:
            try:
                client = Client(self.space_id, hf_token=self.token, verbose=False)
            except TypeError:
                client = Client(self.space_id, token=self.token, verbose=False)
            named = client.view_api(return_format="dict", print_info=False).get("named_endpoints") or {}
        except Exception as e:  # noqa: BLE001
            log.warning("HF connect failed: %s", e)
            raise ProviderError(_friendly(e)) from e
        for needed in ("/generate_3d", "/rig_3d"):
            if needed not in named:
                raise ProviderError(
                    f"Space {self.space_id} no longer has the {needed} endpoint (found: {', '.join(named)}). "
                    "Set HF_RIG_SPACE_ID to a compatible Space or use PROVIDER=hf_space.")

        if "/start_session" in named:
            self._call(client, "/start_session", say, "Starting Space session...")
        gen = self._call(
            client, "/generate_3d", say,
            "Generating textured 3D model from your photo (queue + GPU, can take minutes)...",
            image=handle_file(str(image_path)), resolution=self.resolution,
            decimation_target=self.decimation, texture_size=self.texture_size)
        unrigged = _first_glb(gen)
        if not unrigged or not Path(unrigged).exists():
            raise ProviderError(f"The Space returned no mesh (got: {str(gen)[:200]}).")

        out = image_path.with_name(f"{image_path.stem}_rigged.glb")
        try:
            rig = self._call(client, "/rig_3d", say, "Rigging the model (skeleton + skin weights)...")
            rigged = _first_glb(rig[1:] if isinstance(rig, (list, tuple)) else rig) or _first_glb(rig)
            if not rigged or not Path(rigged).exists():
                raise ProviderError(f"The rigging step returned no GLB (got: {str(rig)[:200]}).")
            shutil.copyfile(rigged, out)
        except ProviderError as e:
            log.warning("rigging failed, using unrigged mesh: %s", e)
            say(f"Rigging failed ({e}); using the unrigged textured mesh instead.")
            shutil.copyfile(unrigged, out)
        return out
