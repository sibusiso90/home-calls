"""Synthetic, illustrated sample media (no real faces — see docs/consent-and-data.md).

Generates simple cartoon heads with Pillow: a skin-tone oval head with a dark hair
cap. "full" hair is a big, messy cap (a before photo); "fade" is a short cap whose
sides blend into the skin (an after photo). Also a short sine-tone WAV.

    uv run python -m fadecall.samples          # writes backend/samples/
"""

from __future__ import annotations

import io
import math
import random
import struct
import wave
from pathlib import Path
from typing import Literal

from PIL import Image, ImageDraw, ImageFilter

HairStyle = Literal["full", "fade", "taper", "chiskop", "afro"]

SKIN_TONES: list[tuple[int, int, int]] = [
    (198, 134, 66),
    (161, 102, 54),
    (141, 85, 36),
    (120, 72, 40),
    (224, 172, 105),
]
HAIR = (22, 18, 16)
BACKGROUNDS = [(226, 230, 236), (236, 228, 214), (214, 230, 222), (232, 222, 232)]
SHIRTS = [(40, 90, 160), (170, 50, 50), (60, 130, 90), (90, 90, 100), (200, 150, 40)]

W, H = 512, 640
CX, CY, RX, RY = 256, 320, 118, 150  # head oval


def _mix(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b, strict=True))  # type: ignore[return-value]


def head_image(
    skin: tuple[int, int, int],
    style: HairStyle,
    seed: int = 0,
    *,
    bg: tuple[int, int, int] | None = None,
    shirt: tuple[int, int, int] | None = None,
    beard: bool = False,
    quality: float = 1.0,
    fmt: str = "JPEG",
) -> bytes:
    """Render one synthetic head. `quality` < 1 makes a rougher, less even cut."""
    rng = random.Random(seed)
    bg = bg or BACKGROUNDS[seed % len(BACKGROUNDS)]
    shirt = shirt or SHIRTS[seed % len(SHIRTS)]
    img = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(img)

    # shoulders + neck
    d.ellipse((40, 520, 472, 820), fill=shirt)
    d.rectangle((CX - 52, CY + 110, CX + 52, 560), fill=_mix(skin, (0, 0, 0), 0.12))
    # ears
    for ex in (CX - RX - 6, CX + RX + 6):
        d.ellipse((ex - 22, CY - 30, ex + 22, CY + 32), fill=_mix(skin, (0, 0, 0), 0.06))
    # head
    d.ellipse((CX - RX, CY - RY, CX + RX, CY + RY), fill=skin)

    _draw_hair(img, skin, style, rng, quality)
    d = ImageDraw.Draw(img)

    # illustrated features (kept lighter than hair so they never read as hair)
    feature = _mix(skin, (40, 30, 30), 0.55)
    for sx in (-1, 1):
        ex = CX + sx * 44
        d.ellipse((ex - 13, CY - 12, ex + 13, CY + 6), fill=(245, 245, 245))
        d.ellipse((ex - 6, CY - 9, ex + 6, CY + 3), fill=(80, 58, 46))
        d.line((ex - 20, CY - 30, ex + 20, CY - 32 - sx), fill=feature, width=6)
    d.line((CX, CY + 5, CX - 8, CY + 52), fill=_mix(skin, (0, 0, 0), 0.25), width=4)
    d.arc((CX - 38, CY + 60, CX + 38, CY + 100), 20, 160, fill=(120, 60, 60), width=5)
    if beard:
        d.chord(
            (CX - RX + 10, CY + 20, CX + RX - 10, CY + RY + 8),
            10,
            170,
            fill=_mix(skin, (40, 30, 26), 0.6),
        )

    img = img.filter(ImageFilter.GaussianBlur(0.8))
    buf = io.BytesIO()
    img.save(buf, fmt, **({"quality": 90} if fmt == "JPEG" else {}))
    return buf.getvalue()


def _draw_hair(
    img: Image.Image,
    skin: tuple[int, int, int],
    style: HairStyle,
    rng: random.Random,
    quality: float,
) -> None:
    d = ImageDraw.Draw(img)
    top = CY - RY
    if style in ("full", "afro"):
        grow = 70 if style == "afro" else 46
        d.ellipse((CX - RX - grow // 2, top - grow, CX + RX + grow // 2, CY + 10), fill=HAIR)
        # messy bumps along the outline
        for i in range(28):
            a = math.pi + math.pi * i / 27
            r = rng.randint(14, 30)
            x = CX + (RX + grow // 2 - 6) * math.cos(a)
            y = (CY - RY // 2 - grow // 2) + (RY // 2 + grow // 2) * math.sin(a)
            d.ellipse((x - r, y - r, x + r, y + r), fill=HAIR)
        # re-expose the face below the hairline
        d.ellipse((CX - RX + 18, CY - 70, CX + RX - 18, CY + RY), fill=skin)
        return
    if style == "chiskop":
        d.chord((CX - RX, top, CX + RX, CY + 40), 180, 360, fill=_mix(skin, HAIR, 0.18))
        return
    # fade / taper: short cap + gradient down the sides
    cap_h = 70 if style == "fade" else 90
    jitter = int((1.0 - quality) * 18)
    d.chord((CX - RX + 4, top - 14, CX + RX - 4, top + 2 * cap_h), 180, 360, fill=HAIR)
    band_top, band_bot = top + cap_h - 6, CY + (10 if style == "fade" else 40)
    for y in range(band_top, band_bot):
        t = (y - band_top) / max(1, band_bot - band_top)
        colour = _mix(HAIR, skin, min(1.0, t * (1.4 if style == "fade" else 1.0)))
        half = math.sqrt(max(0.0, 1 - ((y - CY) / RY) ** 2)) * RX
        for sx in (-1, 1):
            x_out = CX + sx * half
            x_in = CX + sx * (half - 26 - rng.randint(0, jitter))
            d.line((min(x_out, x_in), y, max(x_out, x_in), y), fill=colour)
    # line-up at the forehead
    d.line(
        (CX - 64, top + cap_h - 2, CX + 64, top + cap_h - 2 + rng.randint(-jitter, jitter)),
        fill=HAIR,
        width=4,
    )


def sine_wav(seconds: float = 1.5, freq: float = 220.0, rate: int = 24_000) -> bytes:
    """Mono 16-bit PCM WAV (the format Muse Voice Transcribe accepts)."""
    n = int(seconds * rate)
    frames = b"".join(
        struct.pack("<h", int(8000 * math.sin(2 * math.pi * freq * i / rate))) for i in range(n)
    )
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(frames)
    return buf.getvalue()


def demo_set() -> dict[str, bytes]:
    """Named sample files used by the README, seed and tests."""
    s0, s1 = SKIN_TONES[2], SKIN_TONES[4]
    files = {
        "before.jpg": head_image(s0, "full", 1),
        "after.jpg": head_image(s0, "fade", 1),
        "after_different_person.jpg": head_image(s1, "fade", 7, bg=BACKGROUNDS[1]),
        "selfie.jpg": head_image(SKIN_TONES[1], "full", 3),
        "reference.jpg": head_image(SKIN_TONES[3], "fade", 4),
        "voice_note.wav": sine_wav(),
    }
    for i in range(5):
        skin = SKIN_TONES[i % len(SKIN_TONES)]
        files[f"portfolio_{i + 1}_before.jpg"] = head_image(skin, "full", 20 + i)
        style: HairStyle = "fade" if i % 2 == 0 else "taper"
        files[f"portfolio_{i + 1}_after.jpg"] = head_image(skin, style, 20 + i)
    return files


def main() -> None:
    out = Path(__file__).resolve().parents[2] / "samples"
    out.mkdir(exist_ok=True)
    for name, data in demo_set().items():
        (out / name).write_bytes(data)
    print(f"Wrote {len(demo_set())} synthetic samples to {out}")


if __name__ == "__main__":
    main()
