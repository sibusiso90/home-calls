"""Booking requests: the client asks for time windows, a barber takes the job."""

from __future__ import annotations

from datetime import date, datetime
from typing import Any

from fastapi import APIRouter
from pydantic import BaseModel
from sqlalchemy import select

from ..auth import BarberUser, ClientUser, CurrentUser
from ..deps import DB, Signer
from ..errors import forbidden, not_found
from ..models import BookingRequest, get_by_id
from ..serializers import job_json
from ..services import requests as svc
from ..services.accounts import client_for, find_barber, find_client
from ..timeutil import ensure_aware

router = APIRouter(prefix="/requests", tags=["requests"])


class RequestBody(BaseModel):
    quote_id: str
    day: date
    windows: list[str]
    address: str
    lat: float
    lng: float
    barber_id: str | None = None  # None asks every barber in range


class AcceptBody(BaseModel):
    slot_start: datetime


def _load(db: DB, user: CurrentUser, request_id: str) -> BookingRequest:
    r = get_by_id(db, BookingRequest, request_id)
    if r is None:
        raise not_found("Request")
    if user.role == "client":
        c = find_client(db, user)
        if c is None or r.client_id != c.id:
            raise forbidden("This request belongs to another client")
    elif user.role == "barber":
        b = find_barber(db, user)
        if b is None or not (svc.offered_to(r, b) or (r.job and r.job.barber_id == b.id)):
            raise forbidden("This request isn't offered to you")
    return r


def _json(db: DB, user: CurrentUser, r: BookingRequest, signer: Signer) -> dict[str, Any]:
    barber = find_barber(db, user) if user.role == "barber" else None
    return svc.request_json(db, r, signer, barber=barber)


@router.post("")
def create(body: RequestBody, user: ClientUser, db: DB, signer: Signer) -> dict[str, Any]:
    r = svc.create_request(
        db,
        client_for(db, user),
        quote_id=body.quote_id,
        day=body.day,
        windows=body.windows,
        address=body.address,
        lat=body.lat,
        lng=body.lng,
        barber_id=body.barber_id,
    )
    return _json(db, user, r, signer)


@router.get("")
def list_requests(user: CurrentUser, db: DB, signer: Signer) -> list[dict[str, Any]]:
    """Barber: open requests offered to them. Client: their own. Operator: all."""
    svc.sweep(db)
    if user.role == "barber":
        b = find_barber(db, user)
        rows = svc.for_barber(db, b) if b else []
    else:
        q = select(BookingRequest).order_by(BookingRequest.created_at.desc())
        if user.role == "client":
            c = find_client(db, user)
            q = q.where(BookingRequest.client_id == (c.id if c else ""))
        rows = list(db.scalars(q))
    return [_json(db, user, r, signer) for r in rows]


@router.get("/{request_id}")
def get_request(request_id: str, user: CurrentUser, db: DB, signer: Signer) -> dict[str, Any]:
    svc.sweep(db)
    return _json(db, user, _load(db, user, request_id), signer)


@router.post("/{request_id}/accept")
def accept(
    request_id: str, body: AcceptBody, user: BarberUser, db: DB, signer: Signer
) -> dict[str, Any]:
    """The barber takes the job at a start time inside the client's windows."""
    r = get_by_id(db, BookingRequest, request_id)
    if r is None:
        raise not_found("Request")
    job = svc.accept(db, user, r, ensure_aware(body.slot_start))
    return job_json(job, signer)


@router.post("/{request_id}/decline")
def decline(request_id: str, user: BarberUser, db: DB, signer: Signer) -> dict[str, Any]:
    r = _load(db, user, request_id)
    svc.decline(db, user, r)
    return {"id": r.id, "declined": True}


@router.post("/{request_id}/cancel")
def cancel(request_id: str, user: ClientUser, db: DB, signer: Signer) -> dict[str, Any]:
    r = _load(db, user, request_id)
    svc.cancel(db, r)
    return _json(db, user, r, signer)
