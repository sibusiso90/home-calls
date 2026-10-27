"""Image normalisation, hair-change measurement and mask overlays."""

from __future__ import annotations

import io
from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageFilter, ImageOps, UnidentifiedImageError

from .ai.types import Segmentation
from .errors import validation

MAX_SIDE = 1600
OVERLAY_TINT = (0, 200, 180)
OVERLAY_ALPHA = 0.45
COMPARE_SIDE = 256
PIXEL_DIFF_THRESHOLD = 40  # grey levels (0-255)


def normalise_photo(data: bytes, field: str = "photo") -> bytes:
    """Decode any browser image, apply EXIF rotation, cap size, re-encode as JPEG."""
    if not data:
        raise validation(f"{field}: empty file")
    try:
        with Image.open(io.BytesIO(data)) as im:
            im = ImageOps.exif_transpose(im).convert("RGB")
            im.thumbnail((MAX_SIDE, MAX_SIDE))
            buf = io.BytesIO()
            im.save(buf, "JPEG", quality=88)
            return buf.getvalue()
    except (UnidentifiedImageError, OSError) as exc:
        raise validation(f"{field}: not a readable image") from exc


def render_overlay(image_bytes: bytes, seg: Segmentation) -> bytes:
    """PNG of the photo with the hair mask tinted on top and outlined."""
    with Image.open(io.BytesIO(image_bytes)) as im:
        base = im.convert("RGB")
    mask = seg.union()
    if mask.shape != (base.height, base.width):
        mask = (
            np.asarray(
                Image.fromarray(mask.astype(np.uint8) * 255).resize(
                    base.size, Image.Resampling.NEAREST
                )
            )
            > 127
        )
    arr = np.asarray(base).astype(np.float32)
    tint = np.array(OVERLAY_TINT, dtype=np.float32)
    arr[mask] = arr[mask] * (1 - OVERLAY_ALPHA) + tint * OVERLAY_ALPHA
    m_img = Image.fromarray(mask.astype(np.uint8) * 255)
    edge = np.asarray(m_img.filter(ImageFilter.FIND_EDGES)) > 0
    edge = (
        np.asarray(Image.fromarray(edge.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(3)))
        > 0
    )
    arr[edge] = tint
    out = Image.fromarray(arr.clip(0, 255).astype(np.uint8))
    buf = io.BytesIO()
    out.save(buf, "PNG", optimize=True)
    return buf.getvalue()


@dataclass(frozen=True, slots=True)
class HairChange:
    change_ratio: float | None
    area_before: float
    area_after: float
    pixel_change: float


def _grey(image_bytes: bytes) -> np.ndarray:
    with Image.open(io.BytesIO(image_bytes)) as im:
        g = im.convert("L").resize((COMPARE_SIDE, COMPARE_SIDE), Image.Resampling.BILINEAR)
        return np.asarray(g).astype(np.int16)


def _resize_mask(mask: np.ndarray) -> np.ndarray:
    img = Image.fromarray(mask.astype(np.uint8) * 255)
    return np.asarray(img.resize((COMPARE_SIDE, COMPARE_SIDE), Image.Resampling.NEAREST)) > 127


def measure_hair_change(
    before: bytes, after: bytes, seg_before: Segmentation, seg_after: Segmentation
) -> HairChange:
    """Combine two signals; change_ratio is the larger of:

    - relative change in SAM hair-mask area (each normalised to its image area), and
    - share of pixels inside the before-mask whose grey level moved by > 40/255.
    """
    a_b, a_a = seg_before.area_ratio(), seg_after.area_ratio()
    if a_b <= 0:
        return HairChange(None, a_b, a_a, 0.0)
    area_change = abs(a_a - a_b) / a_b
    region = _resize_mask(seg_before.union())
    if region.sum() == 0:
        pixel_change = 0.0
    else:
        diff = np.abs(_grey(before) - _grey(after))
        pixel_change = float((diff[region] > PIXEL_DIFF_THRESHOLD).mean())
    ratio = max(area_change, pixel_change)
    return HairChange(round(ratio, 4), a_b, a_a, round(pixel_change, 4))
