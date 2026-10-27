"""Barber onboarding: voice-note profile, portfolio grading, tiering."""

from __future__ import annotations

import asyncio
from statistics import mean
from typing import Any

from sqlalchemy.orm import Session

from ..ai import prompts as P
from ..ai.types import ModelClient
from ..areas import AREAS_BY_ID
from ..audio import to_wav
from ..config import Settings
from ..errors import conflict, validation
from ..imaging import normalise_photo
from ..models import Barber, PortfolioItem, new_id
from ..pricing import PRICE_BANDS, tier_for_average
from ..storage import Storage

DIMENSIONS = ("fade_blend", "line_up", "symmetry", "finish")
MIN_PORTFOLIO = 5


async def voice_note_profile(
    models: ModelClient, settings: Settings, barber: Barber, audio: bytes
) -> dict[str, Any]:
    wav = await to_wav(audio, settings.ffmpeg_path, required=models.mode == "live")
    transcript = await models.transcribe(
        wav, P.TRANSCRIBE_LANGUAGE_BIAS, P.TRANSCRIBE_KEYWORDS, purpose="profile"
    )
    data = await models.spark_json(
        P.PROFILE_SYSTEM,
        P.profile_user_text(transcript.text, barber.name),
        [],
        P.PROFILE_SCHEMA,
        P.PROFILE_NAME,
    )
    prof = data.get("profile") or {}
    area_id = prof.get("area_id")
    profile = {
        "name": (prof.get("name") or barber.name).strip(),
        "area_id": area_id if area_id in AREAS_BY_ID else None,
        "years_cutting": int(prof.get("years_cutting") or 0),
        "styles": [str(s) for s in prof.get("styles") or []],
        "languages": [str(s) for s in prof.get("languages") or []],
        "availability": prof.get("availability") or "",
    }
    return {
        "transcript": transcript.text,
        "clean_transcript": data.get("clean_transcript", transcript.text),
        "language_detected": data.get("language_detected", ""),
        "profile": profile,
        "read_back": data.get("read_back", ""),
        "model_versions": {
            "transcribe": models.versions["transcribe"],
            "spark": models.versions["spark"],
        },
    }


def save_profile(db: Session, barber: Barber, profile: dict[str, Any]) -> Barber:
    name = str(profile.get("name") or "").strip()
    if not name:
        raise validation("profile.name is required")
    area_id = profile.get("area_id")
    if area_id is not None and area_id not in AREAS_BY_ID:
        raise validation(f"profile.area_id {area_id!r} is not a launch suburb")
    barber.name = name
    barber.area_id = area_id
    years = profile.get("years_cutting")
    barber.years_cutting = int(years) if years is not None else None
    barber.styles = list(profile.get("styles") or [])
    barber.languages = list(profile.get("languages") or [])
    barber.availability = profile.get("availability")
    barber.profile_confirmed = True
    db.commit()
    return barber


async def add_portfolio_item(
    db: Session,
    models: ModelClient,
    storage: Storage,
    barber: Barber,
    before: bytes,
    after: bytes,
) -> PortfolioItem:
    before_jpg = normalise_photo(before, "before")
    after_jpg = normalise_photo(after, "after")
    data = await models.spark_json(
        P.GRADE_SYSTEM, P.grade_user_text(), [before_jpg, after_jpg], P.GRADE_SCHEMA, P.GRADE_NAME
    )
    raw_scores = data.get("scores") or {}
    raw_reasons = data.get("reasons") or {}
    scores = {k: int(max(0, min(10, round(float(raw_scores.get(k, 0)))))) for k in DIMENSIONS}
    reasons = {k: str(raw_reasons.get(k, "")) for k in DIMENSIONS}
    item_id = new_id()
    before_key = f"portfolio/{barber.id}/{item_id}-before.jpg"
    after_key = f"portfolio/{barber.id}/{item_id}-after.jpg"
    await asyncio.gather(
        storage.put(before_key, before_jpg, "image/jpeg"),
        storage.put(after_key, after_jpg, "image/jpeg"),
    )
    item = PortfolioItem(
        id=item_id,
        barber_id=barber.id,
        before_key=before_key,
        after_key=after_key,
        scores=scores,
        reasons=reasons,
        overall=round(mean(scores.values()), 1),
        model_versions={"spark": models.versions["spark"]},
    )
    db.add(item)
    db.commit()
    db.refresh(barber)
    return item


def grade_summary(items: list[PortfolioItem]) -> str:
    means = {k: mean(float(i.scores.get(k, 0)) for i in items) for k in DIMENSIONS}
    best = max(means, key=lambda k: means[k])
    worst = min(means, key=lambda k: means[k])
    label = {k: k.replace("_", " ") for k in DIMENSIONS}
    weakest = min(items, key=lambda i: float(i.scores.get(worst, 0)))
    note = weakest.reasons.get(worst, "").rstrip(".")
    text = f"Strongest on {label[best]} ({means[best]:.1f}/10)"
    if worst != best:
        text += f"; {label[worst]} is the area to work on ({means[worst]:.1f}/10)"
        if note:
            text += f": {note}"
    return text + "."


def grade_barber(db: Session, barber: Barber) -> dict[str, Any]:
    items = list(barber.portfolio)
    if len(items) < MIN_PORTFOLIO:
        raise conflict(f"Grading needs {MIN_PORTFOLIO} portfolio items; you have {len(items)}")
    average = round(mean(i.overall for i in items), 1)
    tier = tier_for_average(average)
    barber.tier = tier
    barber.price_min_zar, barber.price_max_zar = PRICE_BANDS[tier]
    barber.grade_average = average
    barber.grade_summary = grade_summary(items)
    barber.status = "pending_approval"
    barber.status_reason = None
    db.commit()
    return {"tier": tier, "average": average, "summary": barber.grade_summary}
