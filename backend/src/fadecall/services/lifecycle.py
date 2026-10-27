"""Cancel and reschedule a booking, and list a barber's free slots.

Rules (docs/decisions.md, 27 Oct 2026):
- Either side may cancel while the job is `booked` or `confirmed` (before the
  before-photo). A paid deposit is refunded (mock).
- A client cancelling less than LATE_CANCEL_HOURS before the slot forfeits a
  paid deposit (`payment_status: forfeited`). A barber cancelling never costs
  the client anything.
- Only the client reschedules, to a free slot for the same barber; the job goes
  back to `booked` so the barber re-confirms, and a new reminder is due.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Literal

from sqlalchemy.orm import Session

from .. import scheduling
from ..errors import conflict, validation
from ..models import Job
from ..scheduling import DEFAULT_MINUTES, is_bookable, is_free
from ..timeutil import ensure_utc, utcnow
from .notifications import barber_uid, client_uid, notify, when
from .quotes import busy_intervals

OPEN_STATUSES = ("booked", "confirmed")
MAX_SLOT_DAYS = 28


def free_slots(
    db: Session,
    barber_id: str,
    days: int = 7,
    minutes: int = DEFAULT_MINUTES,
    now: datetime | None = None,
    exclude_job_id: str | None = None,
) -> list[datetime]:
    busy = busy_intervals(db, barber_id, exclude_job_id)
    return scheduling.free_slots(now or utcnow(), busy, minutes, days)


def is_late(job: Job, now: datetime, late_cancel_hours: float) -> bool:
    return ensure_utc(job.slot_start) - ensure_utc(now) < timedelta(hours=late_cancel_hours)


def cancel_job(
    db: Session,
    job: Job,
    by: Literal["client", "barber"],
    reason: str,
    *,
    late_cancel_hours: float,
    now: datetime | None = None,
) -> Job:
    now = now or utcnow()
    if job.status not in OPEN_STATUSES:
        raise conflict(f"Only booked or confirmed jobs can be cancelled (status is {job.status})")
    reason = reason.strip()
    if not reason:
        raise validation("Give a reason for cancelling")
    late = by == "client" and is_late(job, now, late_cancel_hours)
    if job.payment_status == "deposit_paid":
        job.payment_status = "forfeited" if late else "refunded"
    job.status = "cancelled"
    job.cancelled_at = now
    job.cancelled_by = by
    job.cancel_reason = reason

    money = {
        "forfeited": " The deposit is kept because it was a late cancellation.",
        "refunded": " The deposit will be refunded.",
    }.get(job.payment_status, "")
    other = barber_uid(job) if by == "client" else client_uid(job)
    who = job.client.name if by == "client" else job.barber.name
    notify(
        db,
        [other],
        "job_cancelled",
        "Booking cancelled",
        f"{who} cancelled the {when(job)} booking: {reason}.{money}",
        job,
    )
    notify(
        db,
        [client_uid(job) if by == "client" else barber_uid(job)],
        "job_cancelled",
        "You cancelled a booking",
        f"{job.cut}, {when(job)}.{money}",
        job,
    )
    db.commit()
    return job


def reschedule_job(db: Session, job: Job, slot_start: datetime, now: datetime | None = None) -> Job:
    now = now or utcnow()
    if job.status not in OPEN_STATUSES:
        raise conflict(f"Only booked or confirmed jobs can be rescheduled (status is {job.status})")
    new_slot = ensure_utc(slot_start)
    if new_slot == ensure_utc(job.slot_start):
        raise validation("That is already the booked time")
    if not is_bookable(new_slot, now, MAX_SLOT_DAYS):
        raise validation("That time is not a bookable slot")
    if not is_free(new_slot, job.minutes, busy_intervals(db, job.barber_id, job.id)):
        raise conflict("That time clashes with another booking")
    old = when(job)
    job.slot_start = new_slot
    job.slot_end = new_slot + timedelta(minutes=job.minutes)
    job.status = "booked"  # the barber re-confirms the new time
    job.rescheduled_at = now
    job.reminder_sent_at = None
    notify(
        db,
        [barber_uid(job)],
        "job_rescheduled",
        "Booking moved: please re-confirm",
        f"{job.client.name} moved {job.cut} from {old} to {when(job)}.",
        job,
    )
    db.commit()
    return job
