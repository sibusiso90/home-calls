"""Model layer: live Meta Model API client or deterministic mock."""

from __future__ import annotations

from ..config import Settings
from .types import Mask, ModelClient, Segmentation, Transcript

__all__ = ["Mask", "ModelClient", "Segmentation", "Transcript", "make_model_client"]


def make_model_client(settings: Settings) -> ModelClient:
    if settings.model_api_key:
        from .meta import MetaModelClient

        return MetaModelClient(settings)
    from .mock import MockModelClient

    return MockModelClient(settings)
