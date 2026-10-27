"""Evidence retention (docs/consent-and-data.md).

Raw proof-of-job photos (and their mask overlays) are deleted once a verdict is
final and the retention window has passed. Kept: open disputes (the operator
needs the evidence), `needs_review` jobs (not final) and the consented demo
set. Checks, reasons and the verdict stay in the database.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..models import Evidence, Job
from ..storage import Storage
from ..timeutil import ensure_utc, utcnow
from .effects import has_open_dispute

log = logging.getLogger(__name__)

FINAL_VERDICTS = ("pass", "fail")
MEDIA_FIELDS = ("before_key", "after_key", "before_overlay_key", "after_overlay_key")


async def purge_expired_evidence(
    db: Session, storage: Storage, retention_days: int, now: datetime | None = None
) -> list[str]:
    """Delete raw photos for eligible jobs. Returns the ids of purged jobs."""
    now = now or utcnow()
    cutoff = ensure_utc(now) - timedelta(days=retention_days)
    candidates = db.scalars(
        select(Evidence)
        .join(Job, Evidence.job_id == Job.id)
        .where(
            Evidence.purged_at.is_(None),
            Evidence.verdict.in_(FINAL_VERDICTS),
            Evidence.decided_at.is_not(None),
            Evidence.decided_at <= cutoff,
            Job.consented_demo.is_(False),
        )
    )
    purged: list[str] = []
    for ev in list(candidates):
        if has_open_dispute(ev.job):
            continue
        for field in MEDIA_FIELDS:
            key = getattr(ev, field)
            if key:
                try:
                    await storage.delete(key)
                except Exception:  # keep going; the key is retried on the next run
                    log.exception("Could not delete %s for job %s", key, ev.job_id)
                    continue
                setattr(ev, field, None)
        if not any(getattr(ev, f) for f in MEDIA_FIELDS):
            ev.purged_at = now
            purged.append(ev.job_id)
    db.commit()
    return purged
