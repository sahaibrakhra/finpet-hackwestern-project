"""Provider interface: turn a (preprocessed) photo into a GLB file."""
from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path
from typing import Callable, Optional

ProgressCb = Callable[[str], None]


class ProviderError(Exception):
    """Raised with a short, human-friendly message that is shown in the UI."""


class Provider(ABC):
    name: str = "base"
    #: True when the photo leaves this machine (shown as a warning in the UI).
    third_party: bool = False

    @abstractmethod
    def generate(self, image_path: Path, on_progress: Optional[ProgressCb] = None) -> Path:
        """Generate a GLB for ``image_path`` and return the path of the GLB file.

        The returned file may live anywhere; the pipeline moves it into storage/models.
        Raise ProviderError with a friendly message on failure.
        """
