"""video2d provider: no mesh and no rig. The pipeline lives in video_pipeline.py (sprite + AI video clips)."""
from __future__ import annotations

from pathlib import Path
from typing import Optional

from .base import Provider, ProgressCb


class Video2DProvider(Provider):
    name = "video2d"

    def __init__(self) -> None:
        from video_backends import get_video_backend

        self.backend = get_video_backend()  # raises with a friendly message when misconfigured (e.g. no key)
        self.third_party = self.backend.third_party

    def pipeline(self, *args, **kwargs):
        from video_pipeline import run_video_pipeline

        return run_video_pipeline(*args, **kwargs)

    def generate(self, image_path: Path, on_progress: Optional[ProgressCb] = None) -> Path:
        raise NotImplementedError("video2d uses video_pipeline.run_video_pipeline instead of generate().")
