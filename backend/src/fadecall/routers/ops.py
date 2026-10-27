"""Operator dashboard endpoints (role: operator)."""

from __future__ import annotations

from typing import Any, Literal

from fastapi import APIRouter
from pydantic import BaseModel
from sqlalchemy import func, select

from ..auth import OperatorUser
from ..deps import DB, Signer
from ..errors import conflict, not_found, validation
from ..models import Barber, Dispute, Evidence, Job, Payout, Rating, get_by_id
from ..serializers import barber_json, dispute_json, job_json, payout_json
from ..services.disputes import resolve_dispute
from ..services.effects import apply_verdict
from ..timeutil import iso

router = APIRouter(prefix="/ops", tags=["operator"])

BARBER_STATUSES = ("onboarding", "pending_approval", "approved", "rejected")
JOB_STATUSES = (
    "booked",
    "confirmed",
    "in_progress",
    "verifying",
    "verified",
    "needs_review",
    "failed",
    "cancelled",
)


@router.get("/summary")
def summary(_: OperatorUser, db: DB) -> dict[str, Any]:
    def count(q: Any) -> int:
        return int(db.scalar(q) or 0)

    decided = count(select(func.count()).select_from(Evidence).where(Evidence.verdict.is_not(None)))
    passed = count(select(func.count()).select_from(Evidence).where(Evidence.verdict == "pass"))
    avg_ms = db.scalar(
        select(func.avg(Evidence.elapsed_ms)).where(
            Evidence.elapsed_ms.is_not(None), Evidence.verdict.is_not(None)
        )
    )
    return {
        "barbers_pending": count(
            select(func.count()).select_from(Barber).where(Barber.status == "pending_approval")
        ),
        "jobs_needs_review": count(
            select(func.count()).select_from(Job).where(Job.status == "needs_review")
        ),
        "open_disputes": count(
            select(func.count()).select_from(Dispute).where(Dispute.outcome.is_(None))
        ),
        "payouts_released_zar": count(
            select(func.coalesce(func.sum(Payout.amount_zar), 0)).where(Payout.status == "released")
        ),
        # KPIs (additive)
        "jobs_total": count(select(func.count()).select_from(Job)),
        "verified_jobs": count(
            select(func.count()).select_from(Job).where(Job.status == "verified")
        ),
        "decided_jobs": decided,
        "pass_rate": round(passed / decided, 3) if decided else None,
        "avg_verdict_ms": round(float(avg_ms)) if avg_ms is not None else None,
    }


@router.get("/barbers")
def list_barbers(
    _: OperatorUser, db: DB, signer: Signer, status: str | None = None
) -> list[dict[str, Any]]:
    q = select(Barber).order_by(Barber.created_at.desc())
    if status:
        if status not in BARBER_STATUSES:
            raise validation(f"status must be one of {', '.join(BARBER_STATUSES)}")
        q = q.where(Barber.status == status)
    return [barber_json(b, signer) for b in db.scalars(q)]


@router.get("/barbers/{barber_id}")
def barber_detail(barber_id: str, _: OperatorUser, db: DB, signer: Signer) -> dict[str, Any]:
    """A barber with their jobs (newest first) and ratings, for the operator detail page."""
    b = _barber(db, barber_id)
    jobs = list(
        db.scalars(select(Job).where(Job.barber_id == b.id).order_by(Job.slot_start.desc()))
    )
    ratings = db.execute(
        select(Rating, Job)
        .join(Job, Rating.job_id == Job.id)
        .where(Job.barber_id == b.id)
        .order_by(Rating.created_at.desc())
    ).all()
    return {
        "barber": barber_json(b, signer),
        "jobs": [job_json(j, signer) for j in jobs],
        "ratings": [
            {
                "job_id": j.id,
                "stars": r.stars,
                "comment": r.comment,
                "client_name": j.client.name,
                "created_at": iso(r.created_at),
            }
            for r, j in ratings
        ],
    }


class ReasonBody(BaseModel):
    reason: str = ""


def _barber(db: DB, barber_id: str) -> Barber:
    b = get_by_id(db, Barber, barber_id)
    if b is None:
        raise not_found("Barber")
    return b


@router.post("/barbers/{barber_id}/approve")
def approve(
    barber_id: str, body: ReasonBody, _: OperatorUser, db: DB, signer: Signer
) -> dict[str, Any]:
    b = _barber(db, barber_id)
    if b.tier is None or b.area_id is None:
        raise conflict("Barber needs a graded portfolio and an area before approval")
    b.status, b.status_reason = "approved", body.reason or None
    db.commit()
    return barber_json(b, signer)


@router.post("/barbers/{barber_id}/reject")
def reject(
    barber_id: str, body: ReasonBody, _: OperatorUser, db: DB, signer: Signer
) -> dict[str, Any]:
    b = _barber(db, barber_id)
    b.status, b.status_reason = "rejected", body.reason or None
    db.commit()
    return barber_json(b, signer)


@router.get("/jobs")
def list_jobs(
    _: OperatorUser, db: DB, signer: Signer, status: str | None = None
) -> list[dict[str, Any]]:
    q = select(Job).order_by(Job.created_at.desc())
    if status:
        if status not in JOB_STATUSES:
            raise validation(f"status must be one of {', '.join(JOB_STATUSES)}")
        q = q.where(Job.status == status)
    return [job_json(j, signer) for j in db.scalars(q)]


class VerdictBody(BaseModel):
    verdict: Literal["pass", "fail"]
    reason: str


@router.post("/jobs/{job_id}/verdict")
def operator_verdict(
    job_id: str, body: VerdictBody, _: OperatorUser, db: DB, signer: Signer
) -> dict[str, Any]:
    job = get_by_id(db, Job, job_id)
    if job is None:
        raise not_found("Job")
    if job.status in ("booked", "cancelled"):
        raise conflict(f"Cannot give a verdict on a {job.status} job")
    if not body.reason.strip():
        raise validation("reason is required")
    reasons = [f"operator {body.verdict}: {body.reason.strip()}"]
    apply_verdict(db, job, body.verdict, reasons, "operator", body.reason.strip())
    db.commit()
    db.refresh(job)
    return job_json(job, signer)


class ConsentBody(BaseModel):
    consented_demo: bool


@router.post("/jobs/{job_id}/consented-demo")
def set_consented_demo(
    job_id: str, body: ConsentBody, _: OperatorUser, db: DB, signer: Signer
) -> dict[str, Any]:
    """Flag a job as part of the consented demo set (exempt from evidence purge)."""
    job = get_by_id(db, Job, job_id)
    if job is None:
        raise not_found("Job")
    job.consented_demo = body.consented_demo
    db.commit()
    return job_json(job, signer)


@router.get("/disputes")
def list_disputes(
    _: OperatorUser, db: DB, signer: Signer, status: str | None = None
) -> list[dict[str, Any]]:
    q = select(Dispute).order_by(Dispute.created_at.desc())
    if status == "open":
        q = q.where(Dispute.outcome.is_(None))
    elif status == "resolved":
        q = q.where(Dispute.outcome.is_not(None))
    return [dispute_json(d, signer, with_job=True) for d in db.scalars(q)]


class ResolveBody(BaseModel):
    outcome: Literal["release", "refund", "partial_refund"]
    reason: str = ""


@router.post("/disputes/{dispute_id}/resolve")
def resolve(
    dispute_id: str, body: ResolveBody, _: OperatorUser, db: DB, signer: Signer
) -> dict[str, Any]:
    d = get_by_id(db, Dispute, dispute_id)
    if d is None:
        raise not_found("Dispute")
    resolve_dispute(db, d, body.outcome, body.reason)
    db.refresh(d.job)
    return dispute_json(d, signer, with_job=True)


@router.get("/payouts")
def payouts(_: OperatorUser, db: DB) -> list[dict[str, Any]]:
    return [payout_json(p) for p in db.scalars(select(Payout).order_by(Payout.created_at.desc()))]
