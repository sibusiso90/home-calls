"""Deterministic offline stand-in for the Meta models (used when MODEL_API_KEY is unset).

Outputs are derived from the input bytes so different photos give different
results, and they are always schema-valid:

- segment_hair: finds dark pixels in the top of the frame (hair in the synthetic
  samples; falls back to an upper ellipse), encodes them in the real SAM 3.1 wire
  format and parses them back with meta_sam_parser — the same path as live output.
- same_person: compares the mean colour of the central face region. Similar →
  pass; noticeably different → uncertain (operator review); very different → fail.
- cut_match: pass unless MOCK_FORCE_REVIEW is set (then uncertain).
- grading, cut identification, profile and dispute outputs are seeded by a hash.
"""

from __future__ import annotations

import asyncio
import hashlib
import io
import re
from typing import Any

import numpy as np
from PIL import Image

from ..areas import AREAS
from ..config import Settings
from . import prompts as P
from .sam import encode_sam_line, parse_sam_output
from .types import Segmentation, Transcript

MOCK_TRANSCRIPTS = [
    (
        "Sawubona, igama lami ngu Thabo Mokoena. Ngisebenza e Midrand Central. "
        "I have been cutting for six years. Ngenza skin fade, taper ne line-up. "
        "I'm available weekdays after four and on Saturdays."
    ),
    (
        "Hello, my name is Sipho Dlamini, ngihlala e Centurion Central. "
        "Sengigunda iminyaka eyisishiyagalombili, eight years. "
        "I do chiskop, brush cut and mid fade. Available Saturdays and Sundays morning."
    ),
    (
        "Dumela, ke nna Kabelo Molefe from Halfway House. "
        "I've been cutting hair for four years, mostly low fade and waves with a beard trim. "
        "I can come through weekdays after five."
    ),
]

DISPUTE_TRANSCRIPTS = [
    (
        "The fade is not even, the left side is higher than the right. "
        "Ngicela uku-refunda ingxenye yemali, I paid for a mid fade."
    ),
    (
        "He came late and rushed the line-up, my hairline is now pushed back. "
        "I'm not happy with the result."
    ),
]

NUMBER_WORDS = {
    "one": 1,
    "two": 2,
    "three": 3,
    "four": 4,
    "five": 5,
    "six": 6,
    "seven": 7,
    "eight": 8,
    "nine": 9,
    "ten": 10,
    "twelve": 12,
    "fifteen": 15,
}
ZULU_MARKERS = ("sawubona", "igama", "ngi", "ngenza", "sengigunda", "iminyaka")
SOTHO_MARKERS = ("dumela", "ke nna")

CUTS = [
    ("Mid skin fade with textured top", 50),
    ("Low taper with line-up", 40),
    ("High skin fade with brush cut", 45),
    ("Chiskop with beard line-up", 30),
    ("Drop fade with waves", 55),
    ("Burst fade with twists", 70),
]
GRADE_REASONS = {
    "fade_blend": [
        "Gradient is smooth from the skin to the guard, no visible lines.",
        "Blend is mostly even but a faint line shows above the ear.",
        "Visible step between guard lengths on the left side.",
    ],
    "line_up": [
        "Hairline is crisp and the temples are squared off cleanly.",
        "Line-up is straight but the corners are slightly soft.",
        "Edge wanders at the temple and the corner is rounded.",
    ],
    "symmetry": [
        "Both sides sit at the same height and length.",
        "Right side sits slightly higher than the left.",
        "Fade height differs noticeably between sides.",
    ],
    "finish": [
        "Clean neckline and no stray hairs; looks finished.",
        "Good overall shape; a few stray hairs on the crown.",
        "Top is uneven and the neckline needs tidying.",
    ],
}


def _h(*parts: bytes | str) -> int:
    m = hashlib.sha256()
    for p in parts:
        m.update(p.encode() if isinstance(p, str) else p)
    return int.from_bytes(m.digest()[:8], "big")


def _load(image_bytes: bytes) -> Image.Image:
    return Image.open(io.BytesIO(image_bytes)).convert("RGB")


def hair_mask(image_bytes: bytes) -> np.ndarray:
    """Heuristic hair segmentation for the mock: dark pixels in the top of the frame."""
    img = _load(image_bytes)
    arr = np.asarray(img).astype(np.float32)
    h, w = arr.shape[:2]
    lum = 0.299 * arr[..., 0] + 0.587 * arr[..., 1] + 0.114 * arr[..., 2]
    mask = lum < 50
    mask[int(h * 0.62) :, :] = False
    if mask.sum() < 0.005 * h * w:
        yy, xx = np.ogrid[:h, :w]
        mask = ((xx - w / 2) / (w * 0.3)) ** 2 + ((yy - h * 0.28) / (h * 0.2)) ** 2 <= 1
    return mask


def face_colour(image_bytes: bytes) -> np.ndarray:
    img = _load(image_bytes)
    w, h = img.size
    crop = img.crop((int(w * 0.4), int(h * 0.5), int(w * 0.6), int(h * 0.62)))
    return np.asarray(crop).reshape(-1, 3).mean(axis=0)


class MockModelClient:
    mode = "mock"

    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.versions = {"spark": "mock", "transcribe": "mock", "sam": "mock"}

    async def aclose(self) -> None:
        return None

    async def _latency(self) -> None:
        if self.settings.mock_latency_ms:
            await asyncio.sleep(self.settings.mock_latency_ms / 1000)

    async def transcribe(
        self,
        wav_bytes: bytes,
        language_bias: list[str],
        keywords: list[str] | None = None,
        purpose: str = "profile",
    ) -> Transcript:
        await self._latency()
        pool = DISPUTE_TRANSCRIPTS if purpose == "dispute" else MOCK_TRANSCRIPTS
        text = pool[_h(wav_bytes) % len(pool)]
        return Transcript(text=text, duration_ms=len(wav_bytes) // 48, session_id="mock")

    async def segment_hair(self, image_bytes: bytes) -> Segmentation:
        await self._latency()
        mask = hair_mask(image_bytes)
        h, w = mask.shape
        line = encode_sam_line(mask)
        return parse_sam_output(line, w, h)

    async def spark_json(
        self,
        system: str,
        user_text: str,
        images: list[bytes],
        schema: dict[str, Any],
        name: str,
    ) -> dict[str, Any]:
        await self._latency()
        handler = {
            P.PROFILE_NAME: self._profile,
            P.GRADE_NAME: self._grade,
            P.CUT_NAME: self._cut,
            P.SAME_PERSON_NAME: self._same_person,
            P.CUT_MATCH_NAME: self._cut_match,
            P.DISPUTE_NAME: self._dispute,
        }.get(name)
        if handler is None:
            raise ValueError(f"Mock has no handler for schema {name!r}")
        return handler(user_text, images)

    # -- handlers ---------------------------------------------------------------
    def _profile(self, user_text: str, _: list[bytes]) -> dict[str, Any]:
        m = re.search(r'"""\n(.*)\n"""', user_text, re.S)
        transcript = m.group(1) if m else user_text
        low = transcript.lower()
        fallback = re.search(r"signed up as: (.+)", user_text)
        name = fallback.group(1).strip() if fallback else "Barber"
        nm = re.search(
            r"(?:igama lami ngu|my name is|ke nna)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)", transcript
        )
        if nm:
            name = nm.group(1)
        area = next((a for a in AREAS if a.name.lower() in low), None)
        years = 0
        ym = re.search(r"(\d+)\s+years", low)
        if ym:
            years = int(ym.group(1))
        else:
            for word, n in NUMBER_WORDS.items():
                if re.search(rf"\b{word}\s+years", low):
                    years = n
                    break
        styles = [s for s in P.STYLE_VOCAB if s.replace("-", " ") in low.replace("-", " ")]
        languages = []
        if any(k in low for k in ZULU_MARKERS):
            languages.append("isiZulu")
        if any(k in low for k in SOTHO_MARKERS):
            languages.append("Setswana")
        languages.append("English")
        avail = []
        if "weekday" in low:
            after = re.search(r"after (\w+)", low)
            hour = NUMBER_WORDS.get(after.group(1), 0) if after else 0
            avail.append(f"Weekdays after {hour + 12}:00" if hour else "Weekdays")
        if "saturday" in low:
            avail.append("Saturdays")
        if "sunday" in low:
            avail.append("Sundays")
        availability = ", ".join(avail) or "Not stated"
        area_id = area.id if area else "unknown"
        where = f" in {area.name}" if area else ""
        read_back = (
            f"You are {name}, cutting for {years} years{where}. "
            f"You do {', '.join(styles) or 'general cuts'} and you're available "
            f"{availability.lower()}. Is that right?"
        )
        return {
            "clean_transcript": transcript,
            "language_detected": " + ".join(languages),
            "profile": {
                "name": name,
                "area_id": area_id,
                "years_cutting": years,
                "styles": styles,
                "languages": languages,
                "availability": availability,
            },
            "read_back": read_back,
        }

    def _grade(self, _: str, images: list[bytes]) -> dict[str, Any]:
        seed = _h(*images)
        base = 5.5 + (seed % 40) / 10  # 5.5 .. 9.4
        scores: dict[str, int] = {}
        reasons: dict[str, str] = {}
        for i, key in enumerate(("fade_blend", "line_up", "symmetry", "finish")):
            jitter = ((seed >> (8 * (i + 1))) % 3) - 1
            score = int(max(0, min(10, round(base + jitter))))
            scores[key] = score
            bucket = 0 if score >= 8 else 1 if score >= 6 else 2
            reasons[key] = GRADE_REASONS[key][bucket]
        return {"scores": scores, "reasons": reasons}

    def _cut(self, user_text: str, images: list[bytes]) -> dict[str, Any]:
        ref = images[1] if len(images) > 1 else images[0]
        seed = _h(ref)
        cut_name, minutes = CUTS[seed % len(CUTS)]
        minutes += (seed >> 8) % 3 * 5
        ratios = [float(x) for x in re.findall(r"([\d.]+)% of frame", user_text)]
        fit_issues: list[str] = []
        if len(ratios) == 2 and ratios[0] < ratios[1] * 0.8:
            fit_issues.append(
                "Current hair is shorter than the reference on top; expect a shorter result"
            )
        if (seed >> 16) % 4 == 0:
            fit_issues.append("Dense hair on the crown adds about 10 minutes of thinning")
            minutes += 10
        return {
            "cut_name": cut_name,
            "minutes": minutes,
            "fit_issues": fit_issues,
            "reasons": (
                f"Reference shows the sides taken down close to the skin with a defined "
                f"top, which matches a {cut_name.lower()}. Estimated {minutes} minutes for a "
                f"home call including the line-up."
            ),
        }

    def _same_person(self, _: str, images: list[bytes]) -> dict[str, Any]:
        if len(images) < 2:
            return {"result": "uncertain", "confidence": 0.4, "reason": "Only one photo."}
        dist = float(np.linalg.norm(face_colour(images[0]) - face_colour(images[1])))
        if dist < 25:
            conf = round(0.97 - dist / 100, 2)
            return {
                "result": "pass",
                "confidence": conf,
                "reason": "Face shape, ears and skin tone match across both photos.",
            }
        if dist < 70:
            return {
                "result": "uncertain",
                "confidence": 0.5,
                "reason": "Skin tone and lighting differ between the photos; cannot confirm.",
            }
        return {
            "result": "fail",
            "confidence": 0.8,
            "reason": "Face shape and skin tone differ clearly between the photos.",
        }

    def _cut_match(self, user_text: str, images: list[bytes]) -> dict[str, Any]:
        if self.settings.mock_force_review:
            return {
                "result": "uncertain",
                "confidence": 0.55,
                "reason": "The back of the head is not visible, so the fade height can't be "
                "confirmed against the order.",
            }
        cut = re.search(r"Ordered cut: (.+)", user_text)
        cut_name = cut.group(1) if cut else "the ordered cut"
        conf = 0.8 + (_h(*images) % 16) / 100
        return {
            "result": "pass",
            "confidence": round(conf, 2),
            "reason": f"Sides are taken down and the top is kept, consistent with "
            f"{cut_name.lower()}.",
        }

    def _dispute(self, user_text: str, _: list[bytes]) -> dict[str, Any]:
        tm = re.search(r'Voice-note transcript: """(.*?)"""', user_text, re.S)
        xm = re.search(r'Typed complaint: """(.*?)"""', user_text, re.S)
        claim = " ".join(s for s in ((tm and tm.group(1)), (xm and xm.group(1))) if s).strip()
        claim = claim or "Client is unhappy with the cut."
        failing = re.findall(r'"(\w+)": \{"result": "(fail|uncertain)"', user_text)
        if failing:
            notes = "Evidence flags: " + ", ".join(f"{n} {r}" for n, r in failing) + "."
            outcome = "partial_refund"
        else:
            notes = "All proof-of-job checks passed; photos show the cut was done on time."
            outcome = "release" if (_h(claim) % 3) else "partial_refund"
        return {
            "summary": f"Client disputes the job: {claim[:140]}",
            "client_claim": claim,
            "evidence_notes": notes,
            "suggested_outcome": outcome,
        }
