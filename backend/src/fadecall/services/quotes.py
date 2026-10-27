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
from ..cuts import Cut, get_cut
from ..errors import ApiError, conflict, not_found, validation
from ..imaging import normalise_photo, render_overlay
from ..models import Barber, Client, Job, Quote, new_id
from ..pricing import quote_price, travel_band
from ..ranking import rank_score
from ..scheduling import Busy, is_free, next_slot
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
    reference: bytes | None = None,
    cut_id: str | None = None,
) -> Quote:
    """Quote from a reference photo, a catalog pick (cut_id) or, with neither, our suggestion."""
    if area_id not in AREAS_BY_ID:
        raise validation(f"area_id {area_id!r} is not a launch suburb")
    if reference is not None and cut_id:
        raise validation("Send a reference photo or a cut_id, not both")
    chosen = _catalog_cut(cut_id)
    started = time.perf_counter()
    selfie_jpg = normalise_photo(selfie, "selfie")
    ref_jpg = normalise_photo(reference, "reference") if reference is not None else None
    segs = await asyncio.gather(
        models.segment_hair(selfie_jpg), *([models.segment_hair(ref_jpg)] if ref_jpg else [])
    )
    seg_selfie, seg_ref = segs[0], segs[1] if ref_jpg else None
    qid = new_id()
    keys = {
        "selfie": f"quotes/{qid}/selfie.jpg",
        "selfie_overlay": f"quotes/{qid}/selfie-overlay.png",
    }
    puts = [
        storage.put(keys["selfie"], selfie_jpg, "image/jpeg"),
        storage.put(keys["selfie_overlay"], render_overlay(selfie_jpg, seg_selfie), "image/png"),
    ]
    if ref_jpg is not None and seg_ref is not None:
        keys["reference"] = f"quotes/{qid}/reference.jpg"
        keys["reference_overlay"] = f"quotes/{qid}/reference-overlay.png"
        puts += [
            storage.put(keys["reference"], ref_jpg, "image/jpeg"),
            storage.put(keys["reference_overlay"], render_overlay(ref_jpg, seg_ref), "image/png"),
        ]
    data, *_ = await asyncio.gather(
        _ask_spark(
            models,
            selfie_jpg,
            seg_selfie.area_ratio(),
            ref_jpg,
            seg_ref.area_ratio() if seg_ref else None,
            chosen,
        ),
        *puts,
    )
    masks = {"selfie": seg_selfie.summary()}
    if seg_ref is not None:
        masks["reference"] = seg_ref.summary()
    source = "reference" if ref_jpg else "catalog" if chosen else "suggested"
    quote = _new_quote(qid, client, area_id, source, chosen, data, started, models)
    quote.selfie_key = keys["selfie"]
    quote.selfie_overlay_key = keys["selfie_overlay"]
    quote.reference_key = keys.get("reference")
    quote.reference_overlay_key = keys.get("reference_overlay")
    quote.masks = masks
    if client.area_id is None:
        client.area_id = area_id
    db.add(quote)
    db.commit()
    return quote


async def requote(
    db: Session, models: ModelClient, storage: Storage, quote: Quote, cut_id: str
) -> Quote:
    """A new quote for a catalog cut (usually one we suggested), reusing the same selfie."""
    chosen = _catalog_cut(cut_id)
    if chosen is None:
        raise validation("cut_id is required")
    stored = await storage.get(quote.selfie_key)
    if stored is None:
        raise conflict("The selfie for this quote has expired; start a new quote")
    started = time.perf_counter()
    ratio = float((quote.masks or {}).get("selfie", {}).get("area_ratio") or 0.0)
    data = await _ask_spark(models, stored[0], ratio, None, None, chosen)
    client = db.get(Client, quote.client_id)
    if client is None:
        raise not_found("Client")
    fresh = _new_quote(new_id(), client, quote.area_id, "catalog", chosen, data, started, models)
    fresh.selfie_key = quote.selfie_key
    fresh.selfie_overlay_key = quote.selfie_overlay_key
    fresh.masks = {"selfie": (quote.masks or {}).get("selfie", {})}
    db.add(fresh)
    db.commit()
    return fresh


def _catalog_cut(cut_id: str | None) -> Cut | None:
    if not cut_id:
        return None
    cut = get_cut(cut_id)
    if cut is None:
        raise validation(f"cut_id {cut_id!r} is not in the catalog")
    return cut


async def _ask_spark(
    models: ModelClient,
    selfie_jpg: bytes,
    selfie_ratio: float,
    ref_jpg: bytes | None,
    ref_ratio: float | None,
    chosen: Cut | None,
) -> dict[str, Any]:
    return await models.spark_json(
        P.CUT_SYSTEM,
        P.cut_user_text(selfie_ratio, ref_ratio, chosen),
        [selfie_jpg, *([ref_jpg] if ref_jpg else [])],
        P.CUT_SCHEMA,
        P.CUT_NAME,
    )


def _new_quote(
    qid: str,
    client: Client,
    area_id: str,
    source: str,
    chosen: Cut | None,
    data: dict[str, Any],
    started: float,
    models: ModelClient,
) -> Quote:
    """The model's answer as a Quote. A catalog pick keeps its own name and id."""
    picked = chosen or get_cut(str(data.get("cut_id") or ""))
    if chosen is not None:
        cut_name = chosen.name
    elif source == "suggested" and picked is not None:
        cut_name = picked.name
    else:
        cut_name = str(data.get("cut_name") or "Haircut")
    # Never suggest the cut being quoted: "quote this cut instead" would be a no-op.
    seen = {picked.id} if picked else set()
    suggestions = []
    for s in data.get("suggestions") or []:
        cut = get_cut(str(s.get("cut_id") or ""))
        if cut is not None and cut.id not in seen:
            seen.add(cut.id)
            suggestions.append({"cut_id": cut.id, "why": str(s.get("why") or "")})
    return Quote(
        id=qid,
        client_id=client.id,
        area_id=area_id,
        cut_name=cut_name,
        cut_source=source,
        cut_id=picked.id if picked else None,
        minutes=int(data.get("minutes") or (picked.minutes if picked else 45)),
        fit_issues=[str(x) for x in data.get("fit_issues") or []],
        reasons=str(data.get("reasons") or ""),
        face_advice=str(data.get("face_advice") or "") or None,
        suggestions=suggestions[:3],
        elapsed_ms=int((time.perf_counter() - started) * 1000),
        model_versions={"spark": models.versions["spark"], "sam": models.versions["sam"]},
    )


def busy_intervals(db: Session, barber_id: str, exclude_job_id: str | None = None) -> list[Busy]:
    """Start and end of every live booking for a barber (cancelled ones free their time)."""
    q = select(Job.slot_start, Job.slot_end).where(
        Job.barber_id == barber_id, Job.status != "cancelled"
    )
    if exclude_job_id is not None:
        q = q.where(Job.id != exclude_job_id)
    return [(start, end) for start, end in db.execute(q)]


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
                "next_slot": iso(next_slot(now, busy_intervals(db, b.id), quote.minutes)),
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
    if not is_free(slot_utc, quote.minutes, busy_intervals(db, barber.id)):
        raise ApiError(409, "conflict", "That time clashes with another booking")
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
