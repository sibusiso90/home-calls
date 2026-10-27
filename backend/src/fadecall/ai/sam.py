"""SAM 3.1 output parsing (via meta_sam_parser) and a wire-format encoder.

Wire grammar (docs: sam_reading-segmentation): one line per frame,
``<0f>id<|box;x1=..;y1=..;x2=..;y2=..;w=..;h=..|><|mask;x=0;y=0;data=H,W,<enc>payload|>,...``.
Box corners are inclusive source pixels; the mask raster is box-local
(H rows x W columns), so we scale it onto the box and paste it into a
full-frame raster.
"""

from __future__ import annotations

import re

import numpy as np
from meta_sam_parser import (
    CompletedOutcome,
    SegmentationBoxRecord,
    SegmentationMaskRecord,
    decode_mask_to_raster,
    image_segmentation_format,
)
from PIL import Image

from .types import Mask, Segmentation

_FRAME_JOIN = re.compile(r"\|>(<\d+f[;>])")


def normalise_stream_text(text: str) -> str:
    """Put each frame on its own line even if deltas arrived without newlines."""
    return _FRAME_JOIN.sub(lambda m: "|>\n" + m.group(1), text).strip()


def parse_sam_output(text: str, width: int, height: int) -> Segmentation:
    seg = Segmentation(width=width, height=height, raw_output=text)
    body = normalise_stream_text(text)
    if not body:
        return seg  # zero matches is a valid outcome
    parser = image_segmentation_format().create_parser()
    parser.push(body + "\n")
    result = parser.finish(CompletedOutcome()).result
    boxes = {r.object_id: r for r in result.records if isinstance(r, SegmentationBoxRecord)}
    for rec in result.records:
        if not isinstance(rec, SegmentationMaskRecord):
            continue
        local = np.frombuffer(decode_mask_to_raster(rec.mask), dtype=np.uint8).reshape(
            rec.mask.height, rec.mask.width
        )
        b = rec.bounds
        left, top = int(b.left), int(b.top)
        right, bottom = min(int(b.right), width), min(int(b.bottom), height)
        bw, bh = right - left, bottom - top
        if bw <= 0 or bh <= 0:
            continue
        scaled = Image.fromarray(local * 255).resize((bw, bh), Image.Resampling.NEAREST)
        full = np.zeros((height, width), dtype=bool)
        full[top:bottom, left:right] = np.asarray(scaled) > 127
        box = boxes.get(rec.object_id)
        conf = rec.confidence if rec.confidence is not None else (box.confidence if box else None)
        seg.masks.append(Mask(rec.object_id, full, (left, top, right, bottom), conf))
    return seg


def encode_mask_payload(local: np.ndarray) -> str:
    """Encode a box-local binary raster as a one_bit (``!``) payload.

    Uses the parser's own canonical encoder so the output round-trips through
    ``decode_mask_to_raster``. Only used by the mock client and tests.
    """
    from meta_sam_parser._mask_codec import _encode_raster

    h, w = local.shape
    return _encode_raster(local.astype(np.uint8).ravel().tolist(), w, h)


def encode_sam_line(full_mask: np.ndarray, object_id: int = 0, max_side: int = 96) -> str:
    """Build a one-object SAM wire line for a full-frame boolean mask."""
    height, width = full_mask.shape
    ys, xs = np.nonzero(full_mask)
    if len(xs) == 0:
        return ""
    left, top, right, bottom = int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1
    crop = full_mask[top:bottom, left:right]
    bh, bw = crop.shape
    scale = min(1.0, max_side / max(bw, bh))
    mw, mh = max(1, round(bw * scale)), max(1, round(bh * scale))
    local = (
        np.asarray(
            Image.fromarray(crop.astype(np.uint8) * 255).resize((mw, mh), Image.Resampling.NEAREST)
        )
        > 127
    )
    payload = encode_mask_payload(local)
    box = f"<|box;x1={left};y1={top};x2={right - 1};y2={bottom - 1};w={width};h={height}|>"
    mask = f"<|mask;x=0;y=0;data={mh},{mw},{payload}|>"
    return f"<0f>{object_id}{box}{mask}"
