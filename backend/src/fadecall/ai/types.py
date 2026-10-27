"""Model-layer types and the ModelClient protocol."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Protocol

import numpy as np


@dataclass(slots=True)
class Transcript:
    text: str
    duration_ms: int | None = None
    session_id: str | None = None


@dataclass(slots=True)
class Mask:
    """One segmented object, placed on the full image raster."""

    object_id: str
    raster: np.ndarray  # bool, shape (image_h, image_w)
    box: tuple[int, int, int, int]  # left, top, right, bottom (half-open, source px)
    confidence: float | None = None

    @property
    def area(self) -> int:
        return int(self.raster.sum())


@dataclass(slots=True)
class Segmentation:
    width: int
    height: int
    masks: list[Mask] = field(default_factory=list)
    raw_output: str = ""

    def union(self) -> np.ndarray:
        out = np.zeros((self.height, self.width), dtype=bool)
        for m in self.masks:
            out |= m.raster
        return out

    def area_ratio(self) -> float:
        total = self.width * self.height
        return float(self.union().sum()) / total if total else 0.0

    def summary(self) -> dict[str, Any]:
        return {
            "width": self.width,
            "height": self.height,
            "objects": len(self.masks),
            "area_ratio": round(self.area_ratio(), 4),
            "boxes": [list(m.box) for m in self.masks],
        }


class ModelClient(Protocol):
    mode: str
    versions: dict[str, str]

    async def transcribe(
        self,
        wav_bytes: bytes,
        language_bias: list[str],
        keywords: list[str] | None = None,
        purpose: str = "profile",
    ) -> Transcript: ...

    async def spark_json(
        self,
        system: str,
        user_text: str,
        images: list[bytes],
        schema: dict[str, Any],
        name: str,
    ) -> dict[str, Any]: ...

    async def segment_hair(self, image_bytes: bytes) -> Segmentation: ...

    async def aclose(self) -> None: ...
