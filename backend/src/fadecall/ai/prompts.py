"""Every Muse Spark prompt and JSON schema in one place, so they are easy to tune.

Each task has a SYSTEM prompt, a JSON schema (sent as
``response_format={"type": "json_schema", ...}``), a schema NAME and a
builder for the user text. Images are attached in the order the builder's
text describes.
"""

from __future__ import annotations

import json
from typing import Any

from ..areas import AREAS
from ..cuts import CUT_IDS, CUTS, Cut

AREA_IDS = [a.id for a in AREAS]
AREA_LIST = ", ".join(f"{a.name} ({a.id})" for a in AREAS)
STYLE_VOCAB = [
    "skin fade",
    "low fade",
    "mid fade",
    "high fade",
    "taper",
    "line-up",
    "chiskop",
    "brush cut",
    "buzz cut",
    "crew cut",
    "textured top",
    "afro shape-up",
    "beard trim",
    "waves",
    "twists",
]
CHECK_RESULTS = ["pass", "fail", "uncertain"]


def _obj(props: dict[str, Any]) -> dict[str, Any]:
    return {
        "type": "object",
        "properties": props,
        "required": list(props),
        "additionalProperties": False,
    }


_STR = {"type": "string"}
_REASON = {"type": "string", "description": "One or two sentences explaining the result."}
_CONF = {"type": "number", "minimum": 0, "maximum": 1}

# ---------------------------------------------------------------------------
# 1. Barber profile extraction from a voice-note transcript
# ---------------------------------------------------------------------------

PROFILE_NAME = "barber_profile"
PROFILE_SYSTEM = f"""You help South African barbers set up a Fade Call profile from a voice note.
The transcript may mix isiZulu, Sesotho, Setswana, Afrikaans, English and township slang, and
the speech recogniser was biased to English, so words in South African languages may be
misspelled phonetically. First rewrite the transcript as clean English (translate where needed,
keep names as spoken). Then extract the profile.

Rules:
- area_id must be one of: {AREA_LIST}; use "unknown" if no suburb fits.
- years_cutting is an integer; 0 if not said.
- styles: lowercase, prefer this vocabulary when it fits: {", ".join(STYLE_VOCAB)}.
- languages: languages the barber speaks or used in the note, e.g. "isiZulu", "English".
- availability: short plain-English summary such as "Weekdays after 16:00, Saturdays".
- language_detected: e.g. "isiZulu + English".
- read_back: 1-2 friendly sentences in second person that confirm the profile, in English,
  e.g. "You are Thabo, cutting for 6 years in Midrand Central...".
Never invent details that were not said; leave them empty instead."""

PROFILE_SCHEMA = _obj(
    {
        "clean_transcript": _STR,
        "language_detected": _STR,
        "profile": _obj(
            {
                "name": _STR,
                "area_id": {"type": "string", "enum": [*AREA_IDS, "unknown"]},
                "years_cutting": {"type": "integer", "minimum": 0, "maximum": 70},
                "styles": {"type": "array", "items": _STR},
                "languages": {"type": "array", "items": _STR},
                "availability": _STR,
            }
        ),
        "read_back": _STR,
    }
)


def profile_user_text(transcript: str, fallback_name: str) -> str:
    return (
        f'The barber signed up as: {fallback_name}\nVoice-note transcript:\n"""\n{transcript}\n"""'
    )


# ---------------------------------------------------------------------------
# 2. Portfolio grading (one before/after pair)
# ---------------------------------------------------------------------------

GRADE_NAME = "portfolio_grade"
GRADE_SYSTEM = """You are a senior barber assessing a home-call barber's work for a marketplace.
Image 1 is BEFORE the cut and image 2 is AFTER. Score the AFTER result 0-10 on:
- fade_blend: smoothness of the gradient, no visible lines or patches.
- line_up: sharpness and straightness of the hairline, temples and edges.
- symmetry: left/right balance and even length.
- finish: overall cleanliness, detailing and how finished the cut looks.
Use the whole scale: 5 is average, 8 is very good professional work, 10 is exceptional.
If a dimension is not visible, score it conservatively and say why.
Give one concrete, specific reason per score that a barber can learn from. Do not identify
or describe the person; talk only about the haircut."""

GRADE_SCHEMA = _obj(
    {
        "scores": _obj(
            {
                k: {"type": "integer", "minimum": 0, "maximum": 10}
                for k in ("fade_blend", "line_up", "symmetry", "finish")
            }
        ),
        "reasons": _obj(dict.fromkeys(("fade_blend", "line_up", "symmetry", "finish"), _STR)),
    }
)


def grade_user_text() -> str:
    return "Image 1: BEFORE. Image 2: AFTER. Grade the AFTER haircut."


# ---------------------------------------------------------------------------
# 3. Client quote: name the cut, time it, and advise on what suits the face
# ---------------------------------------------------------------------------

CUT_NAME = "cut_identification"
_CATALOG = "\n".join(f"- {c.id}: {c.name}, {c.minutes} min" for c in CUTS)
CUT_SYSTEM = f"""You quote men's haircuts for home-call barbers in South Africa and advise
clients on which cuts suit them.
Image 1 is always the client's SELFIE (their current hair). The text says how the client chose
the cut, one of:
- REFERENCE: image 2 is a photo of the cut they want. Name that cut.
- CATALOG: they picked a cut from the catalog below. Quote exactly that cut.
- SUGGEST: they want your recommendation. Pick the catalog cut that best suits them.
A second model has segmented the hair; its coverage numbers are given in the text for your
estimate only. The client reads every field, so never mention coverage, percentages or models.

Catalog (id: name, typical minutes):
{_CATALOG}

Return:
- cut_name: the cut being quoted. For CATALOG and SUGGEST use the catalog name exactly; for
  REFERENCE a short, standard barbershop name such as "Mid skin fade with textured top",
  "Low taper with line-up", "Chiskop", "Brush cut".
- cut_id: the catalog id of the quoted cut, or "custom" if a reference matches none of them.
- minutes: realistic time for a skilled barber to do this cut on THIS client at home
  (include washing only if the style needs it). Typical range 20-90.
- fit_issues: practical problems going from the selfie to the cut, e.g. hair too short for the
  top, receding hairline affects the line-up, very dense hair adds time. Empty if none.
- reasons: 1-3 sentences on what identifies the cut (or why you picked it) and how you
  estimated the time.
- face_advice: 1-2 friendly sentences on what tends to suit this client, judged from face
  shape, hairline and hair texture, and whether the quoted cut is a good match.
- suggestions: up to 3 catalog cuts that would suit this client best, best first, each with a
  one-sentence why. Include the quoted cut only if it is one of the best.
Talk only about hair, face shape and hairline as a barber would. Never identify the person or
comment on age, race, attractiveness or anything else about them."""

_CUT_ID = {"type": "string", "enum": [*CUT_IDS, "custom"]}
CUT_SCHEMA = _obj(
    {
        "cut_name": _STR,
        "cut_id": _CUT_ID,
        "minutes": {"type": "integer", "minimum": 10, "maximum": 180},
        "fit_issues": {"type": "array", "items": _STR},
        "reasons": _STR,
        "face_advice": _STR,
        "suggestions": {
            "type": "array",
            "items": _obj({"cut_id": {"type": "string", "enum": CUT_IDS}, "why": _STR}),
        },
    }
)


def cut_user_text(
    selfie_hair_ratio: float,
    reference_hair_ratio: float | None = None,
    chosen: Cut | None = None,
) -> str:
    if reference_hair_ratio is not None:
        return (
            "Chosen by: REFERENCE. Image 1: SELFIE. Image 2: REFERENCE.\n"
            f"SAM 3.1 hair coverage: selfie {selfie_hair_ratio:.1%} of frame, "
            f"reference {reference_hair_ratio:.1%} of frame."
        )
    head = f"Chosen by: CATALOG ({chosen.id}: {chosen.name})." if chosen else "Chosen by: SUGGEST."
    return (
        f"{head} Image 1: SELFIE.\nSAM 3.1 hair coverage: selfie {selfie_hair_ratio:.1%} of frame."
    )


# ---------------------------------------------------------------------------
# 4. Same-person check (proof of job; within one job only)
# ---------------------------------------------------------------------------

SAME_PERSON_NAME = "same_person_check"
SAME_PERSON_SYSTEM = """You verify a home haircut job. Image 1 was taken BEFORE the cut and
image 2 AFTER, minutes to hours apart, at the same address. Decide whether they show the same
client. The haircut itself is expected to change the hair, so ignore hair length and style;
compare stable cues such as face shape, ears, skin tone, facial hair outside the cut area,
clothing and background.
- result "pass": clearly the same person. "fail": clearly different people.
  "uncertain": a face is hidden, blurred, cropped or the photos are too different to tell.
- confidence: 0-1 for your result.
- reason: one sentence naming the cues you used, without describing identity.
This comparison is only for this one job. Do not identify the person or describe features
beyond what is needed for the reason."""

CHECK_SCHEMA = _obj(
    {
        "result": {"type": "string", "enum": CHECK_RESULTS},
        "confidence": _CONF,
        "reason": _REASON,
    }
)


def same_person_user_text() -> str:
    return "Image 1: BEFORE. Image 2: AFTER. Same client?"


# ---------------------------------------------------------------------------
# 5. Cut-match check (after photo vs ordered cut)
# ---------------------------------------------------------------------------

CUT_MATCH_NAME = "cut_match_check"
CUT_MATCH_SYSTEM = """You verify that a home haircut matches what the client ordered.
Image 1 is the AFTER photo from the job. Image 2 (if present) is the client's REFERENCE photo.
The ordered cut name is given in the text.
- result "pass": the after photo shows the ordered cut (allow for normal variation and for
  fit issues the barber was warned about). "fail": clearly a different cut.
  "uncertain": the relevant part of the head is not visible or the photo is unclear.
- confidence: 0-1.
- reason: one or two sentences about the cut features you compared (fade height, taper,
  top length, line-up). Talk only about hair."""


def cut_match_user_text(cut_name: str, fit_issues: list[str], has_reference: bool) -> str:
    lines = [f"Ordered cut: {cut_name}"]
    if fit_issues:
        lines.append("Known fit issues: " + "; ".join(fit_issues))
    lines.append(
        "Image 1: AFTER." + (" Image 2: REFERENCE." if has_reference else " No reference.")
    )
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# 6. Dispute summary
# ---------------------------------------------------------------------------

DISPUTE_NAME = "dispute_summary"
DISPUTE_SYSTEM = """You prepare a case file for a Fade Call operator reviewing a client's
complaint about a home haircut. The complaint was a voice note (possibly mixing South African
languages; the recogniser was biased to English) and/or typed text. You also get the job
details and the proof-of-job checks with their reasons.
- summary: 1-2 neutral sentences an operator can read in five seconds.
- client_claim: what the client says went wrong, in plain English.
- evidence_notes: what the proof-of-job evidence supports or contradicts, citing the checks.
- suggested_outcome: "release" (pay the barber), "partial_refund" or "refund".
Be fair to both sides. Do not invent facts that are not in the complaint or the evidence."""

DISPUTE_SCHEMA = _obj(
    {
        "summary": _STR,
        "client_claim": _STR,
        "evidence_notes": _STR,
        "suggested_outcome": {"type": "string", "enum": ["release", "partial_refund", "refund"]},
    }
)


def dispute_user_text(
    transcript: str, text: str | None, job: dict[str, Any], checks: dict[str, Any]
) -> str:
    return (
        f"Job: {json.dumps(job, ensure_ascii=False)}\n"
        f"Proof-of-job checks: {json.dumps(checks, ensure_ascii=False)}\n"
        f'Voice-note transcript: """{transcript}"""\n'
        f'Typed complaint: """{text or ""}"""'
    )


# Transcription hints (Muse Voice Transcribe has no South African language in its
# supported list; we bias to English and let Muse Spark tidy/translate).
TRANSCRIBE_LANGUAGE_BIAS = ["English"]
TRANSCRIBE_KEYWORDS = [a.name for a in AREAS] + [
    "skin fade",
    "taper",
    "line-up",
    "chiskop",
    "Fade Call",
    "Midrand",
    "Centurion",
]
