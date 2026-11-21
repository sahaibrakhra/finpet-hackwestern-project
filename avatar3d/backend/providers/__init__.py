"""Provider factory."""
from __future__ import annotations

import os

from .base import Provider, ProviderError

__all__ = ["Provider", "ProviderError", "get_provider"]


def get_provider(name: str | None = None) -> Provider:
    name = (name or os.getenv("PROVIDER", "sprite2d")).strip().lower()
    if name == "mock":
        from .mock import MockProvider
        return MockProvider()
    if name == "video2d":
        from .video2d import Video2DProvider
        return Video2DProvider()
    if name == "sprite2d":
        from .sprite2d import Sprite2DProvider
        return Sprite2DProvider()
    if name == "hf_space":
        from .hf_space import HfSpaceProvider
        return HfSpaceProvider()
    if name == "hf_rigged":
        from .hf_rigged import HfRiggedProvider
        return HfRiggedProvider()
    if name == "local_gpu":
        from .local_gpu import LocalGpuProvider
        return LocalGpuProvider()
    raise ValueError(f"Unknown PROVIDER '{name}'. Use video2d, sprite2d, mock, hf_space, hf_rigged or local_gpu.")
