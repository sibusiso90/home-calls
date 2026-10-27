"""Client quote, matches and booking (role: client)."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Any

from fastapi import APIRouter, File, Form, Query, UploadFile
from pydantic import BaseModel

from ..auth import ClientUser, CurrentUser
from ..cuts import CUTS
from ..deps import DB, Models, Signer, Store
from ..errors import forbidden, not_found, validation
from ..models import Barber, Quote, get_by_id
from ..scheduling import DEFAULT_MINUTES, is_bookable
from ..serializers import job_json, quote_json
from ..services import quotes as svc
from ..services.accounts import client_for, find_client
from ..services.lifecycle import MAX_SLOT_DAYS, free_slots
from ..timeutil import ensure_aware, iso, utcnow

router = APIRouter(tags=["client"])


@router.post("/quotes")
async def create_quote(
    user: ClientUser,
    db: DB,
    models: Models,
    storage: Store,
    signer: Signer,
    selfie: Annotated[UploadFile, File()],
    area_id: Annotated[str, Form()],
    reference: Annotated[UploadFile | None, File()] = None,
    cut_id: Annotated[str | None, Form()] = None,
) -> dict[str, Any]:
    """Send a reference photo, or a catalog cut_id, or neither for a suggested cut."""
    client = client_for(db, user)
    quote = await svc.create_quote(
        db,
        models,
        storage,
        client,
        area_id,
        await selfie.read(),
        await reference.read() if reference is not None else None,
        cut_id or None,
    )
    return quote_json(quote, signer)


@router.get("/cuts")
def cuts() -> list[dict[str, Any]]:
    return [c.as_dict() for c in CUTS]


class RequoteBody(BaseModel):
    cut_id: str


@router.post("/quotes/{quote_id}/requote")
async def requote(
    quote_id: str,
    body: RequoteBody,
    user: ClientUser,
    db: DB,
    models: Models,
    storage: Store,
    signer: Signer,
) -> dict[str, Any]:
    """Quote one of the suggested (or any catalog) cuts with the same selfie."""
    quote = _own_quote(db, user, quote_id)
    return quote_json(await svc.requote(db, models, storage, quote, body.cut_id), signer)


def _own_quote(db: DB, user: CurrentUser, quote_id: str) -> Quote:
    quote = get_by_id(db, Quote, quote_id)
    if quote is None:
        raise not_found("Quote")
    if user.role == "operator":
        return quote
    client = find_client(db, user) if user.role == "client" else None
    if client is None or quote.client_id != client.id:
        raise forbidden("This quote belongs to another client")
    return quote


@router.get("/quotes/{quote_id}")
def get_quote(quote_id: str, user: CurrentUser, db: DB, signer: Signer) -> dict[str, Any]:
    return quote_json(_own_quote(db, user, quote_id), signer)


@router.get("/quotes/{quote_id}/matches")
def matches(quote_id: str, user: CurrentUser, db: DB, signer: Signer) -> list[dict[str, Any]]:
    return svc.match_barbers(db, _own_quote(db, user, quote_id), signer)


@router.get("/barbers/{barber_id}/slots")
def barber_slots(
    barber_id: str,
    user: CurrentUser,
    db: DB,
    days: int = Query(7, ge=1, le=MAX_SLOT_DAYS),
    minutes: int = Query(DEFAULT_MINUTES, ge=10, le=180),
    exclude_job_id: str | None = None,
) -> dict[str, Any]:
    """Free start times for a cut of `minutes`; pass the job being moved as exclude_job_id."""
    barber = get_by_id(db, Barber, barber_id)
    if barber is None or (barber.status != "approved" and user.role != "operator"):
        raise not_found("Approved barber")
    slots = free_slots(db, barber.id, days, minutes, exclude_job_id=exclude_job_id)
    return {"barber_id": barber.id, "slots": [iso(s) for s in slots]}


class BookBody(BaseModel):
    quote_id: str
    barber_id: str
    slot_start: datetime
    address: str
    lat: float
    lng: float


@router.post("/jobs")
def book(body: BookBody, user: ClientUser, db: DB, signer: Signer) -> dict[str, Any]:
    client = client_for(db, user)
    if not is_bookable(ensure_aware(body.slot_start), utcnow(), MAX_SLOT_DAYS):
        raise validation("That time is not a bookable slot")
    job = svc.book_job(
        db,
        client,
        quote_id=body.quote_id,
        barber_id=body.barber_id,
        slot_start=ensure_aware(body.slot_start),
        address=body.address,
        lat=body.lat,
        lng=body.lng,
    )
    return job_json(job, signer)
