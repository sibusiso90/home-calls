"""Jobs, proof of job, rating and disputes."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Any

from fastapi import APIRouter, File, Form, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy import select

from ..auth import BarberUser, ClientUser, CurrentUser
from ..deps import DB, AppSettings, Models, Signer, Store
from ..errors import ApiError, conflict, forbidden, not_found, validation
from ..models import Job, Rating, User, get_by_id
from ..serializers import dispute_json, evidence_json, job_json
from ..services import disputes as dispute_svc
from ..services import lifecycle, proof
from ..services.accounts import find_barber, find_client
from ..services.notifications import barber_uid, client_uid, notify, when
from ..timeutil import ensure_aware, parse_iso

router = APIRouter(prefix="/jobs", tags=["jobs"])


def _scope_filter(db: DB, user: User) -> Any:
    if user.role == "operator":
        return None
    if user.role == "barber":
        b = find_barber(db, user)
        return Job.barber_id == (b.id if b else "")
    c = find_client(db, user)
    return Job.client_id == (c.id if c else "")


def load_job(db: DB, user: User, job_id: str) -> Job:
    job = get_by_id(db, Job, job_id)
    if job is None:
        raise not_found("Job")
    if user.role == "operator":
        return job
    if user.role == "barber":
        b = find_barber(db, user)
        if b is None or job.barber_id != b.id:
            raise forbidden("This job belongs to another barber")
    else:
        c = find_client(db, user)
        if c is None or job.client_id != c.id:
            raise forbidden("This job belongs to another client")
    return job


@router.get("")
def list_jobs(user: CurrentUser, db: DB, signer: Signer) -> list[dict[str, Any]]:
    q = select(Job).order_by(Job.created_at.desc())
    flt = _scope_filter(db, user)
    if flt is not None:
        q = q.where(flt)
    return [job_json(j, signer) for j in db.scalars(q)]


@router.get("/{job_id}")
def get_job(job_id: str, user: CurrentUser, db: DB, signer: Signer) -> dict[str, Any]:
    return job_json(load_job(db, user, job_id), signer)


@router.post("/{job_id}/confirm")
def confirm(job_id: str, user: BarberUser, db: DB, signer: Signer) -> dict[str, Any]:
    job = load_job(db, user, job_id)
    if job.status != "booked":
        raise conflict(f"Only booked jobs can be confirmed (status is {job.status})")
    job.status = "confirmed"
    notify(
        db,
        [client_uid(job)],
        "job_confirmed",
        "Your barber confirmed",
        f"{job.barber.name} confirmed {when(job)}. Pay the deposit to hold the slot."
        if job.payment_status == "deposit_pending"
        else f"{job.barber.name} confirmed {when(job)}.",
        job,
    )
    db.commit()
    return job_json(job, signer)


@router.post("/{job_id}/pay-deposit")
def pay_deposit(job_id: str, user: ClientUser, db: DB, signer: Signer) -> dict[str, Any]:
    job = load_job(db, user, job_id)
    if job.status == "cancelled":
        raise conflict("This booking was cancelled")
    if job.payment_status == "deposit_pending":
        job.payment_status = "deposit_paid"
        notify(
            db,
            [barber_uid(job)],
            "deposit_paid",
            "Deposit paid",
            f"{job.client.name} paid the deposit for {when(job)}. Proof photos can go ahead.",
            job,
        )
        db.commit()
    elif job.payment_status != "deposit_paid":
        raise conflict(f"Deposit cannot be paid now (payment is {job.payment_status})")
    return job_json(job, signer)


class CancelBody(BaseModel):
    reason: str = Field(min_length=1, max_length=500)


@router.post("/{job_id}/cancel")
def cancel(
    job_id: str, body: CancelBody, user: CurrentUser, db: DB, settings: AppSettings, signer: Signer
) -> dict[str, Any]:
    if user.role not in ("client", "barber"):
        raise forbidden("Only the client or the barber can cancel a booking")
    job = load_job(db, user, job_id)
    lifecycle.cancel_job(
        db,
        job,
        "client" if user.role == "client" else "barber",
        body.reason,
        late_cancel_hours=settings.late_cancel_hours,
    )
    return job_json(job, signer)


class RescheduleBody(BaseModel):
    slot_start: datetime


@router.post("/{job_id}/reschedule")
def reschedule(
    job_id: str, body: RescheduleBody, user: ClientUser, db: DB, signer: Signer
) -> dict[str, Any]:
    job = load_job(db, user, job_id)
    lifecycle.reschedule_job(db, job, ensure_aware(body.slot_start))
    return job_json(job, signer)


def _opt_float(value: str | None, field: str) -> float | None:
    if value is None or value.strip() == "" or value.strip().lower() == "null":
        return None
    try:
        return float(value)
    except ValueError as exc:
        raise validation(f"{field} must be a number") from exc


def _capture(
    captured_at: str | None,
    lat: str | None,
    lng: str | None,
    accuracy_m: str | None,
    capture_mode: str | None,
) -> proof.Capture:
    mode = (capture_mode or "live").strip()
    if mode not in ("live", "upload_fallback"):
        raise validation("capture_mode must be live or upload_fallback")
    when = None
    if captured_at and captured_at.strip():
        try:
            when = parse_iso(captured_at)
        except ValueError as exc:
            raise validation("captured_at must be an ISO 8601 time") from exc
    return proof.Capture(
        captured_at=when,
        lat=_opt_float(lat, "lat"),
        lng=_opt_float(lng, "lng"),
        accuracy_m=_opt_float(accuracy_m, "accuracy_m"),
        capture_mode=mode,
    )


Opt = Annotated[str | None, Form()]


@router.post("/{job_id}/proof/before")
async def proof_before(
    job_id: str,
    user: BarberUser,
    db: DB,
    storage: Store,
    signer: Signer,
    photo: Annotated[UploadFile, File()],
    captured_at: Opt = None,
    lat: Opt = None,
    lng: Opt = None,
    accuracy_m: Opt = None,
    capture_mode: Opt = None,
) -> dict[str, Any]:
    job = load_job(db, user, job_id)
    cap = _capture(captured_at, lat, lng, accuracy_m, capture_mode)
    ev = await proof.capture_before(db, storage, job, await photo.read(), cap)
    return evidence_json(ev, signer)


@router.post("/{job_id}/proof/after")
async def proof_after(
    job_id: str,
    user: BarberUser,
    db: DB,
    models: Models,
    storage: Store,
    signer: Signer,
    photo: Annotated[UploadFile, File()],
    captured_at: Opt = None,
    lat: Opt = None,
    lng: Opt = None,
    accuracy_m: Opt = None,
    capture_mode: Opt = None,
) -> dict[str, Any]:
    job = load_job(db, user, job_id)
    cap = _capture(captured_at, lat, lng, accuracy_m, capture_mode)
    ev = await proof.capture_after(db, models, storage, job, await photo.read(), cap)
    return evidence_json(ev, signer)


class RatingBody(BaseModel):
    stars: int = Field(ge=1, le=5)
    comment: str | None = None


@router.post("/{job_id}/rating")
def rate(job_id: str, body: RatingBody, user: ClientUser, db: DB) -> dict[str, Any]:
    job = load_job(db, user, job_id)
    if not (job.evidence and job.evidence.verdict == "pass"):
        raise ApiError(409, "verdict_required", "Rating unlocks only after a pass verdict")
    if job.rating is not None:
        raise conflict("This job is already rated")
    db.add(Rating(job_id=job.id, stars=body.stars, comment=body.comment))
    db.flush()
    stars = list(
        db.scalars(
            select(Rating.stars)
            .join(Job, Rating.job_id == Job.id)
            .where(Job.barber_id == job.barber_id)
        )
    )
    job.barber.rating = round(sum(stars) / len(stars), 1)
    db.commit()
    return {"stars": body.stars, "comment": body.comment}


@router.post("/{job_id}/dispute")
async def dispute(
    job_id: str,
    user: ClientUser,
    db: DB,
    models: Models,
    settings: AppSettings,
    audio: Annotated[UploadFile | None, File()] = None,
    text: Opt = None,
) -> dict[str, Any]:
    job = load_job(db, user, job_id)
    data = await audio.read() if audio is not None else None
    d = await dispute_svc.open_dispute(db, models, settings, job, data or None, text)
    return dispute_json(d)
