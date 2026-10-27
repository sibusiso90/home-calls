"""Client quote (SAM 3.1 + Muse Spark), matching and booking."""

from __future__ import annotations

import asyncio
import time
from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..ai import prompts as P
from ..ai.types import ModelClient
from ..areas import AREAS_BY_ID, area_distance_km, get_area
from ..errors import ApiError, conflict, not_found, validation
from ..imaging import normalise_photo, render_overlay
from ..models import Barber, Client, Job, Quote, new_id
from ..pricing import quote_price, travel_band
from ..ranking import rank_score
from ..scheduling import next_slot
from ..serializers import barber_card_json
from ..storage import Storage, UrlSigner
from ..timeutil import ensure_utc, iso, utcnow
from .notifications import notify, when


async def create_quote(
    db: Session,
    models: ModelClient,
    storage: Storage,
    client: Client,
    area_id: str,
    selfie: bytes,
    reference: bytes,
) -> Quote:
    if area_id not in AREAS_BY_ID:
        raise validation(f"area_id {area_id!r} is not a launch suburb")
    started = time.perf_counter()
    selfie_jpg = normalise_photo(selfie, "selfie")
    ref_jpg = normalise_photo(reference, "reference")
    seg_selfie, seg_ref = await asyncio.gather(
        models.segment_hair(selfie_jpg), models.segment_hair(ref_jpg)
    )
    data = await models.spark_json(
        P.CUT_SYSTEM,
        P.cut_user_text(seg_selfie.area_ratio(), seg_ref.area_ratio()),
        [selfie_jpg, ref_jpg],
        P.CUT_SCHEMA,
        P.CUT_NAME,
    )
    qid = new_id()
    keys = {
        "selfie": f"quotes/{qid}/selfie.jpg",
        "reference": f"quotes/{qid}/reference.jpg",
        "selfie_overlay": f"quotes/{qid}/selfie-overlay.png",
        "reference_overlay": f"quotes/{qid}/reference-overlay.png",
    }
    await asyncio.gather(
        storage.put(keys["selfie"], selfie_jpg, "image/jpeg"),
        storage.put(keys["reference"], ref_jpg, "image/jpeg"),
        storage.put(keys["selfie_overlay"], render_overlay(selfie_jpg, seg_selfie), "image/png"),
        storage.put(keys["reference_overlay"], render_overlay(ref_jpg, seg_ref), "image/png"),
    )
    quote = Quote(
        id=qid,
        client_id=client.id,
        area_id=area_id,
        cut_name=str(data.get("cut_name") or "Haircut"),
        minutes=int(data.get("minutes") or 45),
        fit_issues=[str(x) for x in data.get("fit_issues") or []],
        reasons=str(data.get("reasons") or ""),
        selfie_key=keys["selfie"],
        reference_key=keys["reference"],
        selfie_overlay_key=keys["selfie_overlay"],
        reference_overlay_key=keys["reference_overlay"],
        masks={"selfie": seg_selfie.summary(), "reference": seg_ref.summary()},
        elapsed_ms=int((time.perf_counter() - started) * 1000),
        model_versions={"spark": models.versions["spark"], "sam": models.versions["sam"]},
    )
    if client.area_id is None:
        client.area_id = area_id
    db.add(quote)
    db.commit()
    return quote


def booked_slots(db: Session, barber_id: str) -> list[datetime]:
    return list(
        db.scalars(
            select(Job.slot_start).where(Job.barber_id == barber_id, Job.status != "cancelled")
        )
    )


def match_barbers(
    db: Session, quote: Quote, signer: UrlSigner, now: datetime | None = None
) -> list[dict[str, Any]]:
    now = now or utcnow()
    client_area = get_area(quote.area_id)
    if client_area is None:
        return []
    results: list[dict[str, Any]] = []
    for b in db.scalars(select(Barber).where(Barber.status == "approved")):
        area = get_area(b.area_id)
        if area is None:
            continue
        dist = area_distance_km(area, client_area)
        band = travel_band(dist)
        if band is None:
            continue
        price = quote_price(b.tier, quote.minutes, band)
        results.append(
            {
                "barber": barber_card_json(b, signer),
                "distance_km": round(dist, 1),
                "travel_band": band,
                "price": price.as_dict(),
                "next_slot": iso(next_slot(now, booked_slots(db, b.id))),
                "score": rank_score(b.tier, b.verified_jobs, b.rating, dist),
            }
        )
    results.sort(key=lambda r: (-r["score"], r["distance_km"]))
    return results


def book_job(
    db: Session,
    client: Client,
    *,
    quote_id: str,
    barber_id: str,
    slot_start: datetime,
    address: str,
    lat: float,
    lng: float,
) -> Job:
    quote = db.get(Quote, quote_id)
    if quote is None or quote.client_id != client.id:
        raise not_found("Quote")
    barber = db.get(Barber, barber_id)
    if barber is None or barber.status != "approved":
        raise not_found("Approved barber")
    b_area, c_area = get_area(barber.area_id), get_area(quote.area_id)
    if b_area is None or c_area is None:
        raise validation("Barber or quote has no area")
    band = travel_band(area_distance_km(b_area, c_area))
    if band is None:
        raise conflict("That barber is out of travel range for this area")
    slot_utc = ensure_utc(slot_start)
    if slot_utc in {ensure_utc(s) for s in booked_slots(db, barber.id)}:
        raise ApiError(409, "conflict", "That slot is already booked")
    if not address.strip():
        raise validation("address is required")
    price = quote_price(barber.tier, quote.minutes, band)
    job_id = new_id()
    job = Job(
        id=job_id,
        quote_id=quote.id,
        barber_id=barber.id,
        client_id=client.id,
        cut=quote.cut_name,
        minutes=quote.minutes,
        quote_zar=price.total_zar,
        price=price.as_dict(),
        travel_band=band,
        slot_start=slot_utc,
        slot_end=slot_utc + timedelta(minutes=quote.minutes),
        address=address.strip(),
        lat=lat,
        lng=lng,
        status="booked",
        payment_status="deposit_pending",
        deposit_url=f"https://pay.example/mock/{job_id}",
    )
    db.add(job)
    db.flush()
    db.refresh(job)
    notify(
        db,
        [client.user_id],
        "booking_created",
        "You're booked",
        f"{barber.name}, {when(job)}. Pay the deposit to hold the slot.",
        job,
    )
    notify(
        db,
        [barber.user_id],
        "booking_created",
        "New booking",
        f"{quote.cut_name} for {client.name}, {when(job)} at {job.address}. Please confirm.",
        job,
    )
    db.commit()
    return job
