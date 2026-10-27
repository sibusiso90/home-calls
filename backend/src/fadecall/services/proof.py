"""Proof of job: capture checks, SAM hair change, Muse Spark checks, verdict."""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from sqlalchemy import update
from sqlalchemy.orm import Session

from ..ai import prompts as P
from ..ai.types import ModelClient
from ..errors import conflict
from ..imaging import measure_hair_change, normalise_photo, render_overlay
from ..models import Evidence, Job, Quote
from ..storage import Storage
from ..timeutil import ensure_utc
from ..verdict import decide, gps_check, hair_change_check, model_check, timestamp_check
from .effects import apply_verdict

log = logging.getLogger(__name__)


@dataclass(slots=True)
class Capture:
    captured_at: datetime | None
    lat: float | None
    lng: float | None
    accuracy_m: float | None
    capture_mode: str = "live"

    def as_dict(self) -> dict[str, Any]:
        return {
            "captured_at": ensure_utc(self.captured_at).isoformat() if self.captured_at else None,
            "lat": self.lat,
            "lng": self.lng,
            "accuracy_m": self.accuracy_m,
            "capture_mode": self.capture_mode,
        }


def capture_checks(job: Job, cap: Capture, prefix: str) -> dict[str, dict[str, Any]]:
    return {
        f"{prefix}_timestamp": timestamp_check(cap.captured_at, job.slot_start, job.slot_end),
        f"{prefix}_gps": gps_check(cap.lat, cap.lng, cap.accuracy_m, job.lat, job.lng),
    }


async def capture_before(
    db: Session, storage: Storage, job: Job, photo: bytes, cap: Capture
) -> Evidence:
    if job.status not in ("confirmed", "in_progress"):
        raise conflict(f"Before photo needs a confirmed job (status is {job.status})")
    if job.payment_status != "deposit_paid":
        raise conflict("Deposit not paid yet")
    jpg = normalise_photo(photo)
    key = f"jobs/{job.id}/before.jpg"
    await storage.put(key, jpg, "image/jpeg")
    ev = job.evidence
    if ev is None:
        ev = Evidence(job_id=job.id)
        db.add(ev)
        job.evidence = ev
    ev.before_key = key
    ev.after_key = ev.before_overlay_key = ev.after_overlay_key = None
    ev.before_capture = cap.as_dict()
    ev.after_capture = {}
    ev.checks = capture_checks(job, cap, "before")
    ev.masks = {}
    ev.verdict = None
    ev.verdict_reasons = []
    ev.decided_by = None
    ev.model_versions = {}
    job.status = "in_progress"
    db.commit()
    return ev


async def capture_after(
    db: Session,
    models: ModelClient,
    storage: Storage,
    job: Job,
    photo: bytes,
    cap: Capture,
) -> Evidence:
    ev = job.evidence
    if job.status in ("verifying", "verified", "needs_review", "failed"):
        raise conflict("This job is already being verified")
    if job.status != "in_progress" or ev is None or not ev.before_key:
        raise conflict(f"After photo needs a before photo first (status is {job.status})")
    after_jpg = normalise_photo(photo)
    # Atomic compare-and-set before any await: only one upload can run the pipeline,
    # so pass effects (payout, verified_jobs) can never be applied twice.
    claimed = db.execute(
        update(Job)
        .where(Job.id == job.id, Job.status == "in_progress")
        .values(status="verifying")
        .execution_options(synchronize_session=False)
    )
    if claimed.rowcount != 1:
        db.rollback()
        raise conflict("This job is already being verified")
    db.commit()
    db.refresh(job)
    try:
        return await _verify(db, models, storage, job, after_jpg, cap)
    except BaseException:
        # Never leave a job stuck in 'verifying': let the barber retry the after photo.
        db.rollback()
        db.execute(
            update(Job)
            .where(Job.id == job.id, Job.status == "verifying")
            .values(status="in_progress")
            .execution_options(synchronize_session=False)
        )
        db.commit()
        db.refresh(job)
        raise


async def _verify(
    db: Session,
    models: ModelClient,
    storage: Storage,
    job: Job,
    after_jpg: bytes,
    cap: Capture,
) -> Evidence:
    ev = job.evidence
    if ev is None or not ev.before_key:
        raise conflict("Before photo is missing; retake it")
    stored = await storage.get(ev.before_key)
    if stored is None:
        raise conflict("Before photo is missing from storage; retake it")
    before_jpg = stored[0]
    reference_jpg: bytes | None = None
    quote = db.get(Quote, job.quote_id) if job.quote_id else None
    fit_issues: list[str] = quote.fit_issues if quote else []
    if quote is not None:
        ref = await storage.get(quote.reference_key)
        reference_jpg = ref[0] if ref else None

    after_key = f"jobs/{job.id}/after.jpg"
    await storage.put(after_key, after_jpg, "image/jpeg")
    ev.after_key = after_key
    ev.after_capture = cap.as_dict()
    db.commit()

    seg_b, seg_a, same, match = await asyncio.gather(
        models.segment_hair(before_jpg),
        models.segment_hair(after_jpg),
        models.spark_json(
            P.SAME_PERSON_SYSTEM,
            P.same_person_user_text(),
            [before_jpg, after_jpg],
            P.CHECK_SCHEMA,
            P.SAME_PERSON_NAME,
        ),
        models.spark_json(
            P.CUT_MATCH_SYSTEM,
            P.cut_match_user_text(job.cut, fit_issues, reference_jpg is not None),
            [after_jpg] + ([reference_jpg] if reference_jpg else []),
            P.CHECK_SCHEMA,
            P.CUT_MATCH_NAME,
        ),
    )
    change = measure_hair_change(before_jpg, after_jpg, seg_b, seg_a)
    b_overlay = f"jobs/{job.id}/before-overlay.png"
    a_overlay = f"jobs/{job.id}/after-overlay.png"
    await asyncio.gather(
        storage.put(b_overlay, render_overlay(before_jpg, seg_b), "image/png"),
        storage.put(a_overlay, render_overlay(after_jpg, seg_a), "image/png"),
    )
    ev.before_overlay_key, ev.after_overlay_key = b_overlay, a_overlay
    ev.masks = {
        "before": seg_b.summary(),
        "after": seg_a.summary(),
        "pixel_change": change.pixel_change,
    }
    checks = dict(ev.checks or {})
    checks.update(capture_checks(job, cap, "after"))
    checks["same_person"] = model_check(
        same.get("result"), same.get("reason"), same.get("confidence")
    )
    checks["hair_changed"] = hair_change_check(
        change.change_ratio, change.area_before, change.area_after, change.pixel_change
    )
    checks["cut_match"] = model_check(
        match.get("result"), match.get("reason"), match.get("confidence")
    )
    ev.checks = checks
    ev.model_versions = {"spark": models.versions["spark"], "sam": models.versions["sam"]}
    result = decide(
        checks,
        {
            "before": (ev.before_capture or {}).get("capture_mode", "live"),
            "after": cap.capture_mode,
        },
    )
    apply_verdict(db, job, result.verdict, result.reasons, "model")
    db.commit()
    return ev
