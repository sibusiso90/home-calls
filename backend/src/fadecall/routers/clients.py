"""Client quote, matches and booking (role: client)."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Any

from fastapi import APIRouter, File, Form, Query, UploadFile
from pydantic import BaseModel

from ..auth import ClientUser, CurrentUser
from ..deps import DB, Models, Signer, Store
from ..errors import forbidden, not_found
from ..models import Barber, Quote, get_by_id
from ..serializers import job_json, quote_json
from ..services import quotes as svc
from ..services.accounts import client_for, find_client
from ..services.lifecycle import MAX_SLOT_DAYS, free_slots
from ..timeutil import ensure_aware, iso

router = APIRouter(tags=["client"])


@router.post("/quotes")
async def create_quote(
    user: ClientUser,
    db: DB,
    models: Models,
    storage: Store,
    signer: Signer,
    selfie: Annotated[UploadFile, File()],
    reference: Annotated[UploadFile, File()],
    area_id: Annotated[str, Form()],
) -> dict[str, Any]:
    client = client_for(db, user)
    quote = await svc.create_quote(
        db, models, storage, client, area_id, await selfie.read(), await reference.read()
    )
    return quote_json(quote, signer)


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
) -> dict[str, Any]:
    barber = get_by_id(db, Barber, barber_id)
    if barber is None or (barber.status != "approved" and user.role != "operator"):
        raise not_found("Approved barber")
    return {"barber_id": barber.id, "slots": [iso(s) for s in free_slots(db, barber.id, days)]}


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
