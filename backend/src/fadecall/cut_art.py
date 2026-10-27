"""Illustrations of the catalog cuts: a featureless front-view bust with the cut drawn on.

Used until a real, consented photo of the cut is uploaded (see routers/clients.py). No
faces, so the pictures show the hair only.

    uv run python -m fadecall.cut_art      # writes backend/samples/cuts/<id>.png to look at
"""

from __future__ import annotations

import io
import zlib
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from .cuts import CUTS

S = 1000  # drawing canvas; the output is downsampled for smooth edges
OUT = 480
SKULL = (545, 430, 230, 235)  # cx, cy, rx, ry of the cranium, facing left
EAR = (565, 482, 36, 60)
BG = (238, 232, 223)
SKIN = (150, 98, 62)
SHIRT = (52, 66, 84)
HAIR = (24, 20, 18)

# Profile facing left: forehead, nose, lips, chin, jaw, then back up behind the ear.
FACE = [
    (345, 290),
    (322, 360),
    (318, 410),
    (326, 440),
    (308, 480),
    (282, 530),
    (272, 548),
    (284, 560),
    (306, 566),
    (304, 584),
    (296, 600),
    (306, 612),
    (302, 628),
    (296, 646),
    (312, 664),
    (318, 696),
    (340, 726),
    (390, 744),
    (450, 744),
    (520, 712),
    (590, 640),
    (600, 520),
    (560, 380),
]
NECK = [(452, 700), (440, 900), (660, 900), (650, 640), (580, 610)]
# Where hair may grow: behind a line from the forehead over the temple to the sideburn.
FACE_ZONE = [(200, 296), (350, 296), (460, 372), (486, 560), (486, 800), (200, 800)]


@dataclass(frozen=True)
class Style:
    top: str  # none | short | brush | textured | waves | twists | crew | afro
    fade: str  # skin | taper | none
    fade_from: int = 0  # y where side hair starts thinning
    fade_to: int = 0  # y where it is gone (skin) or at its floor (taper)
    drop: bool = False  # fade line drops behind the ear
    burst: bool = False  # fade curves around the ear instead of running level
    lineup: bool = True  # crisp hairline, temple corner and edges
    beard: bool = False


STYLES: dict[str, Style] = {
    "mid-skin-fade-textured": Style("textured", "skin", 400, 470),
    "low-taper-lineup": Style("short", "taper", 470, 560),
    "high-fade-brush": Style("brush", "skin", 330, 390),
    "chiskop-beard": Style("none", "none", beard=True),
    "drop-fade-waves": Style("waves", "skin", 440, 500, drop=True),
    "burst-fade-twists": Style("twists", "skin", burst=True),
    "buzz-cut": Style("buzz", "none", lineup=False),
    "crew-cut": Style("crew", "taper", 420, 540, lineup=False),
    "afro-shape-up": Style("afro", "none"),
}


def _grid() -> tuple[np.ndarray, np.ndarray]:
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    return x, y


def _ellipse(
    x: np.ndarray, y: np.ndarray, cx: float, cy: float, rx: float, ry: float
) -> np.ndarray:
    return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0


def _poly(points: list[tuple[int, int]]) -> np.ndarray:
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).polygon(points, fill=255)
    return np.asarray(m) > 127


def _skull_top(x: np.ndarray) -> np.ndarray:
    cx, cy, rx, ry = SKULL
    u = np.clip((x - cx) / rx, -1, 1)
    return cy - ry * np.sqrt(1 - u**2)


def _hair_alpha(style: Style, rng: np.random.Generator) -> np.ndarray:
    x, y = _grid()
    cx, cy, rx, ry = SKULL
    ex, ey, erx, ery = EAR
    if style.top == "none":
        return np.zeros((S, S), dtype=np.float32)
    zone = _ellipse(x, y, cx, cy, rx + 10, ry + 8) & ~_poly(FACE_ZONE) & (y < 640)
    zone &= ~_ellipse(x, y, ex, ey, erx + 16, ery + 14)  # cleared around the ear
    zone &= ~((x < ex + 20) & (y > ey + 10))  # nothing below the ear at the front
    density = zone.astype(np.float32)

    if style.fade in ("skin", "taper") and style.fade_to > style.fade_from:
        floor = 0.0 if style.fade == "skin" else 0.35
        start = np.full_like(x, float(style.fade_from))
        if style.drop:  # the line drops behind the ear towards the nape
            start = start + np.clip(x - ex, 0, None) * 0.55
        span = style.fade_to - style.fade_from
        fall = np.clip((y - start) / span, 0, 1)
        density *= 1 - fall * (1 - floor)
    if style.burst:
        r = np.hypot(x - ex, y - ey)
        density *= np.clip((r - 110) / 80, 0, 1)
    if style.top == "buzz":
        density *= 0.6

    vol = np.zeros((S, S), dtype=bool)
    top = _skull_top(x)
    front = np.clip((x - 330) / 400, 0, 1)  # 0 at the forehead, 1 at the back
    within = (x > 338) & (x < cx + rx - 6)
    if style.top == "brush":
        vol = within & (y > top - 26) & (y < top + 30)
    elif style.top == "crew":
        vol = within & (y > top - (52 - 34 * front)) & (y < top + 30)
    elif style.top == "textured":
        h = 62 + 22 * np.sin(x / 11.0) * np.cos(x / 27.0) - 30 * front
        vol = within & (x < cx + rx - 40) & (y > top - h) & (y < top + 30)
    elif style.top in ("short", "waves"):
        vol = within & (y > top - 14) & (y < top + 30)
    elif style.top == "twists":
        vol = within & (y > top - 10) & (y < top + 30)
        for i, px in enumerate(range(350, cx + 170, 26)):
            base = float(_skull_top(np.array([px], dtype=np.float32))[0])
            n = 5 if px < cx + 60 else 4 if px < cx + 130 else 3
            for k in range(n):
                wob = 6 if (i + k) % 2 else -6
                vol |= _ellipse(x, y, px + wob, base + 8 - k * 19, 16, 13)
    elif style.top == "afro":
        vol = _ellipse(x, y, cx + 40, cy - 60, rx + 80, ry + 45) & ~_poly(FACE_ZONE)
        vol &= (y < 560) & (x > 345 - np.clip(296 - y, 0, None) * 0.25)
        vol &= ~_ellipse(x, y, ex, ey, erx + 6, ery + 4)
    density = np.maximum(density, vol.astype(np.float32))

    # Clipper texture: stipple the soft parts so fades read as a fade, not a blur.
    noise = rng.random((S, S), dtype=np.float32)
    soft = (density > 0.02) & (density < 0.98)
    return np.where(soft, np.clip(density + (noise - 0.5) * 0.6, 0, 1), density)


def _beard() -> np.ndarray:
    x, y = _grid()
    # Below a cheek line from the sideburn to the corner of the mouth, plus a moustache.
    cheek = 470 + (486 - x) * 0.62
    region = _poly(FACE) & (y > cheek) & (x < 600)
    moustache = (x < 340) & (y > 566) & (y < 596)
    mouth = (x < 318) & (y > 598) & (y < 608)
    return (region | (moustache & _poly(FACE))) & ~mouth


def _draw(cut_id: str) -> Image.Image:
    style = STYLES[cut_id]
    rng = np.random.default_rng(zlib.crc32(cut_id.encode()))
    img = Image.new("RGB", (S, S), BG)
    d = ImageDraw.Draw(img)
    d.ellipse((230, 850, 900, 1300), fill=SHIRT)  # shoulders
    d.polygon(NECK, fill=_shade(SKIN, 0.84))
    d.polygon(FACE, fill=SKIN)
    cx, cy, rx, ry = SKULL
    d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=SKIN)
    d.line([(328, 404), (372, 398)], fill=_shade(SKIN, 0.45), width=9)  # eyebrow

    # Soft light from the front gives the head some depth.
    x, y = _grid()
    arr = np.asarray(img, dtype=np.float32).copy()
    head = _ellipse(x, y, cx, cy, rx, ry) | _poly(FACE)
    light = np.clip(1.08 - (x - 300) / 500 * 0.2, 0.86, 1.08)
    arr[head] *= light[head][:, None]

    alpha = _hair_alpha(style, rng)
    if style.beard:
        alpha = np.maximum(alpha, _beard().astype(np.float32) * 0.9)
    if not style.lineup:
        alpha = (
            np.asarray(
                Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3)),
                dtype=np.float32,
            )
            / 255
        )
    hair = np.array(HAIR, dtype=np.float32)
    arr = arr * (1 - alpha[..., None]) + hair * alpha[..., None]
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))

    d = ImageDraw.Draw(img)
    ex, ey, erx, ery = EAR
    d.ellipse((ex - erx, ey - ery, ex + erx, ey + ery), fill=_shade(SKIN, 0.95))
    d.arc(
        (ex - erx + 14, ey - ery + 14, ex + erx - 10, ey + ery - 16),
        200,
        100,
        fill=_shade(SKIN, 0.7),
        width=7,
    )
    if style.top == "waves":
        _waves(img, alpha)
    return img.resize((OUT, OUT), Image.Resampling.LANCZOS)


def _waves(img: Image.Image, alpha: np.ndarray) -> None:
    """Concentric ripples from the crown, only where the hair is."""
    layer = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(layer)
    for i in range(9):
        r = 40 + i * 30
        d.arc((640 - r * 1.3, 250 - r, 640 + r * 1.3, 250 + r), 0, 360, fill=255, width=8)
    mask = np.asarray(layer, dtype=np.float32) / 255 * (alpha > 0.9)
    arr = np.asarray(img, dtype=np.float32)
    shine = np.array((92, 82, 74), dtype=np.float32)
    arr = arr * (1 - mask[..., None] * 0.8) + shine * mask[..., None] * 0.8
    img.paste(Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)))


def _shade(c: tuple[int, int, int], f: float) -> tuple[int, int, int]:
    return (round(c[0] * f), round(c[1] * f), round(c[2] * f))


@lru_cache(maxsize=len(STYLES))
def cut_png(cut_id: str) -> bytes | None:
    """The illustration for a catalog cut as PNG bytes, or None for an unknown id."""
    if cut_id not in STYLES:
        return None
    buf = io.BytesIO()
    _draw(cut_id).save(buf, "PNG", optimize=True)
    return buf.getvalue()


def main() -> None:
    out = Path(__file__).resolve().parents[2] / "samples" / "cuts"
    out.mkdir(parents=True, exist_ok=True)
    for c in CUTS:
        (out / f"{c.id}.png").write_bytes(cut_png(c.id) or b"")
    print(f"Wrote {len(CUTS)} cut illustrations to {out}")


if __name__ == "__main__":
    main()
