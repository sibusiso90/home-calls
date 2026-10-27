"""The ONE place a verdict takes effect (model or operator).

A `pass` verdict is the only thing that releases payment, writes a payout
ledger row, increments `verified_jobs` and unlocks rating.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..models import Evidence, Job, Payout, Rating
from ..timeutil import utcnow
from .notifications import barber_uid, client_uid, notify, operator_uids

FinalVerdict = Literal["pass", "needs_review", "fail"]
JOB_STATUS = {"pass": "verified", "needs_review": "needs_review", "fail": "failed"}


# A pass never moves money for these: no deposit yet, or the client was refunded.
NO_MONEY_STATUSES = ("deposit_pending", "refunded", "partially_refunded")


def has_open_dispute(job: Job) -> bool:
    return any(d.outcome is None for d in job.disputes)


def apply_verdict(
    db: Session,
    job: Job,
    verdict: FinalVerdict,
    reasons: list[str],
    decided_by: Literal["model", "operator"],
    operator_reason: str | None = None,
    now: datetime | None = None,
) -> Evidence:
    ev = job.evidence
    if ev is None:
        ev = Evidence(job_id=job.id, checks={}, masks={}, model_versions={})
        db.add(ev)
        job.evidence = ev
    was_pass = ev.verdict == "pass"

    ev.verdict = verdict
    ev.verdict_reasons = list(reasons)
    ev.decided_by = decided_by
    ev.operator_reason = operator_reason
    ev.decided_at = now or utcnow()
    job.status = JOB_STATUS[verdict]

    payouts = list(db.scalars(select(Payout).where(Payout.job_id == job.id)))
    if verdict == "pass" and not was_pass:
        job.barber.verified_jobs += 1
        _release_money(db, job, payouts)
    elif verdict != "pass" and was_pass:
        # An operator overturned an earlier pass: claw every effect back.
        job.barber.verified_jobs = max(0, job.barber.verified_jobs - 1)
        if job.payment_status not in NO_MONEY_STATUSES:
            job.payment_status = "held"
        for p in payouts:
            p.status = "reversed"
        _remove_rating(db, job)
    _announce(db, job, verdict, decided_by, operator_reason)
    db.flush()
    return ev


def _announce(
    db: Session,
    job: Job,
    verdict: FinalVerdict,
    decided_by: Literal["model", "operator"],
    operator_reason: str | None,
) -> None:
    both = [client_uid(job), barber_uid(job)]
    if decided_by == "operator":
        outcome = "passed" if verdict == "pass" else "did not pass"
        extra = (
            " Payment released and rating unlocked."
            if verdict == "pass" and job.payment_status == "released"
            else ""
        )
        why = f" Reason: {operator_reason}" if operator_reason else ""
        notify(
            db,
            both,
            "verdict_operator",
            f"Operator decision: {job.cut} {outcome}",
            f"A Fade Call operator reviewed the proof.{extra}{why}",
            job,
        )
    elif verdict == "pass":
        notify(
            db,
            both,
            "verdict_pass",
            "Job verified",
            "Every check passed. Payment released and rating unlocked."
            if job.payment_status == "released"
            else "Every check passed. Rating unlocked.",
            job,
        )
    else:
        notify(
            db,
            both,
            "verdict_needs_review",
            "Sent to operator review",
            "Some checks were not certain, so a person will look at the photos. "
            "Payment stays on hold until then.",
            job,
        )
        notify(
            db,
            operator_uids(db),
            "verdict_needs_review",
            "Job needs review",
            f"{job.barber.name} → {job.client.name}: {job.cut}.",
            job,
        )


def _release_money(db: Session, job: Job, payouts: list[Payout]) -> None:
    if job.payment_status in NO_MONEY_STATUSES:
        return
    status = "held" if has_open_dispute(job) else "released"
    job.payment_status = status
    active = [p for p in payouts if p.status != "reversed"]
    if active:  # idempotent: never a second live payout for one job
        for p in active:
            p.status = status
        return
    db.add(Payout(job_id=job.id, barber_id=job.barber_id, amount_zar=job.quote_zar, status=status))


def _remove_rating(db: Session, job: Job) -> None:
    rating = db.scalar(select(Rating).where(Rating.job_id == job.id))
    if rating is None:
        return
    db.delete(rating)
    db.flush()
    job.rating = None
    stars = list(
        db.scalars(
            select(Rating.stars)
            .join(Job, Rating.job_id == Job.id)
            .where(Job.barber_id == job.barber_id)
        )
    )
    job.barber.rating = round(sum(stars) / len(stars), 1) if stars else None
