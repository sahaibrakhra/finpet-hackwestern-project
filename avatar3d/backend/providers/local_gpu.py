"""local_gpu provider: documented stub for running Hunyuan3D / TRELLIS locally."""
from __future__ import annotations

from pathlib import Path
from typing import Optional

from .base import Provider, ProgressCb

INSTRUCTIONS = """The local_gpu provider is not implemented yet.

To add it later (needs an NVIDIA GPU, roughly 12+ GB VRAM, CUDA PyTorch):
  1. Clone and install Hunyuan3D-2 (https://github.com/Tencent/Hunyuan3D-2) or
     TRELLIS (https://github.com/microsoft/TRELLIS) following their README.
     On Windows this is easiest in a separate venv.
  2. Implement LocalGpuProvider.generate(): load the image-to-3D pipeline once
     (cache it on the instance), run it on image_path, export the mesh as GLB
     (trimesh: mesh.export(path)) and return the GLB path.
  3. Set PROVIDER=local_gpu in .env and restart the server.
See README.md ("Running Hunyuan3D or TRELLIS locally") for details."""


class LocalGpuProvider(Provider):
    name = "local_gpu"
    third_party = False

    def generate(self, image_path: Path, on_progress: Optional[ProgressCb] = None) -> Path:
        raise NotImplementedError(INSTRUCTIONS)
