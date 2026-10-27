"""Barber onboarding endpoints (role: barber)."""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, File, UploadFile
from pydantic import BaseModel, Field

from ..auth import BarberUser
from ..deps import DB, AppSettings, Models, Signer, Store
from ..errors import not_found
from ..models import PortfolioItem, get_by_id
from ..serializers import barber_json, portfolio_json
from ..services import onboarding
from ..services.accounts import barber_for

router = APIRouter(prefix="/barbers/me", tags=["barber"])


@router.get("")
def get_me(user: BarberUser, db: DB, signer: Signer) -> dict[str, Any]:
    return barber_json(barber_for(db, user), signer)


@router.post("/voice-note")
async def voice_note(
    user: BarberUser,
    db: DB,
    models: Models,
    settings: AppSettings,
    audio: Annotated[UploadFile, File()],
) -> dict[str, Any]:
    barber = barber_for(db, user)
    data = await audio.read()
    return await onboarding.voice_note_profile(models, settings, barber, data)


class ProfileBody(BaseModel):
    name: str
    area_id: str | None = None
    years_cutting: int | None = Field(default=None, ge=0, le=80)
    styles: list[str] = Field(default_factory=list)
    languages: list[str] = Field(default_factory=list)
    availability: str | None = None


@router.put("/profile")
def put_profile(user: BarberUser, db: DB, signer: Signer, body: ProfileBody) -> dict[str, Any]:
    barber = barber_for(db, user)
    onboarding.save_profile(db, barber, body.model_dump())
    return barber_json(barber, signer)


@router.post("/portfolio")
async def add_portfolio(
    user: BarberUser,
    db: DB,
    models: Models,
    storage: Store,
    signer: Signer,
    before: Annotated[UploadFile, File()],
    after: Annotated[UploadFile, File()],
) -> dict[str, Any]:
    barber = barber_for(db, user)
    item = await onboarding.add_portfolio_item(
        db, models, storage, barber, await before.read(), await after.read()
    )
    return portfolio_json(item, signer)


@router.delete("/portfolio/{item_id}")
async def delete_portfolio(
    item_id: str, user: BarberUser, db: DB, storage: Store
) -> dict[str, Any]:
    barber = barber_for(db, user)
    item = get_by_id(db, PortfolioItem, item_id)
    if item is None or item.barber_id != barber.id:
        raise not_found("Portfolio item")
    keys = [item.before_key, item.after_key]
    db.delete(item)
    db.commit()
    for k in keys:
        await storage.delete(k)
    return {"deleted": item_id}


@router.post("/grade")
def grade(user: BarberUser, db: DB, signer: Signer) -> dict[str, Any]:
    barber = barber_for(db, user)
    result = onboarding.grade_barber(db, barber)
    return {"barber": barber_json(barber, signer), **result}
