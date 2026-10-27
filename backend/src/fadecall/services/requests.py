"""Booking requests: client asks for a day and time windows, a barber takes the job.

Chosen barber: they have OFFER_MINUTES to accept; if they decline or the time runs
out, every barber in range is asked. No barber chosen: everyone in range is asked
straight away. The barber who accepts picks the start time from their own free
slots inside the windows, which books a confirmed Job. A request expires once no
start time is left in its windows.

sweep() applies the time-based transitions. It runs on every request read and on
notification polls, plus a once-a-minute cron in production.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..areas import area_distance_km, get_area
from ..errors import ApiError, conflict, forbidden, not_found, validation
from ..models import Barber, BookingRequest, Client, Job, Quote, User
from ..pricing import quote_price, travel_band
from ..scheduling import WINDOW_LABELS, WINDOWS, is_free, slots_in_windows
from ..serializers import barber_card_json
from ..storage import UrlSigner
from ..timeutil import SAST, ensure_utc, iso, utcnow
from .notifications import notify, when
from .quotes import book_job, busy_intervals

OFFER_MINUTES = 10


def _day(r: BookingRequest) -> date:
    return date.fromisoformat(r.day)


def day_label(day: date, now: datetime) -> str:
    today = ensure_utc(now).astimezone(SAST).date()
    if day == today:
        return "today"
    if day == today + timedelta(days=1):
        return "tomorrow"
    return day.strftime("%a %-d %b")


def describe(r: BookingRequest, now: datetime) -> str:
    """'today, afternoon or evening'"""
    names = [WINDOW_LABELS[w].lower() for w in WINDOWS if w in r.windows]
    when_text = names[0] if len(names) == 1 else ", ".join(names[:-1]) + " or " + names[-1]
    return f"{day_label(_day(r), now)}, {when_text}"


# --- who can take it ------------------------------------------------------------


def _in_range(barber: Barber, area_id: str) -> tuple[float, str] | None:
    b_area, c_area = get_area(barber.area_id), get_area(area_id)
    if b_area is None or c_area is None:
        return None
    dist = area_distance_km(b_area, c_area)
    band = travel_band(dist)
    return None if band is None else (dist, band)


def nearby_barbers(db: Session, area_id: str) -> list[Barber]:
    return [
        b
        for b in db.scalars(select(Barber).where(Barber.status == "approved"))
        if _in_range(b, area_id) is not None
    ]


def offered_to(r: BookingRequest, barber: Barber) -> bool:
    """Can this barber see and accept the request right now?"""
    if r.status != "open" or barber.id in (r.declined_by or []):
        return False
    if barber.status != "approved" or _in_range(barber, r.quote.area_id) is None:
        return False
    return r.broadcast_at is not None or r.chosen_barber_id == barber.id


# --- transitions ----------------------------------------------------------------


def _broadcast(db: Session, r: BookingRequest, now: datetime, reason: str) -> None:
    r.broadcast_at = now
    others = [
        b.user_id
        for b in nearby_barbers(db, r.quote.area_id)
        if b.id not in (r.declined_by or []) and b.id != r.chosen_barber_id
    ]
    notify(
        db,
        others,
        "request_new",
        "New home-call request",
        f"{r.quote.cut_name}, {describe(r, now)} near {_area_name(r)}. First to accept gets it.",
        request=r,
    )
    if r.chosen_barber_id:
        notify(
            db,
            [r.client.user_id],
            "request_update",
            "Asking other barbers",
            f"{reason} We've sent your request to {len(others)} barber(s) nearby.",
            request=r,
        )


def _area_name(r: BookingRequest) -> str:
    area = get_area(r.quote.area_id)
    return area.name if area else "you"


def sweep(db: Session, now: datetime | None = None) -> int:
    """Open lapsed offers to everyone and expire requests with no time left."""
    now = now or utcnow()
    changed = 0
    for r in db.scalars(select(BookingRequest).where(BookingRequest.status == "open")):
        if not slots_in_windows(now, _day(r), r.windows):
            r.status, r.closed_at = "expired", now
            notify(
                db,
                [r.client.user_id],
                "request_update",
                "No barber took your request",
                f"Nobody could take the {r.quote.cut_name} {describe(r, now)}. "
                "Try another time or day.",
                request=r,
            )
            changed += 1
        elif (
            r.broadcast_at is None
            and r.offered_until is not None
            and ensure_utc(r.offered_until) <= now
        ):
            name = r.chosen_barber.name if r.chosen_barber else "Your barber"
            _broadcast(db, r, now, f"{name} didn't answer in {OFFER_MINUTES} minutes.")
            changed += 1
    if changed:
        db.commit()
    return changed


def create_request(
    db: Session,
    client: Client,
    *,
    quote_id: str,
    day: date,
    windows: list[str],
    address: str,
    lat: float,
    lng: float,
    barber_id: str | None = None,
    now: datetime | None = None,
) -> BookingRequest:
    now = now or utcnow()
    quote = db.get(Quote, quote_id)
    if quote is None or quote.client_id != client.id:
        raise not_found("Quote")
    windows = [w for w in WINDOWS if w in set(windows)]
    if not windows:
        raise validation("Pick at least one time window: morning, afternoon or evening")
    if not slots_in_windows(now, day, windows):
        raise validation("Those windows have no times left on that day; pick a later one")
    if not address.strip():
        raise validation("address is required")
    chosen: Barber | None = None
    if barber_id:
        chosen = db.get(Barber, barber_id)
        if chosen is None or chosen.status != "approved":
            raise not_found("Approved barber")
        if _in_range(chosen, quote.area_id) is None:
            raise conflict("That barber is out of travel range for this area")
    r = BookingRequest(
        quote_id=quote.id,
        client_id=client.id,
        day=day.isoformat(),
        windows=windows,
        address=address.strip(),
        lat=lat,
        lng=lng,
        chosen_barber_id=chosen.id if chosen else None,
        offered_until=now + timedelta(minutes=OFFER_MINUTES) if chosen else None,
        status="open",
        declined_by=[],
    )
    db.add(r)
    db.flush()
    db.refresh(r)
    if chosen is not None:
        notify(
            db,
            [chosen.user_id],
            "request_new",
            f"{client.name} asked for you",
            f"{quote.cut_name}, {describe(r, now)} near {_area_name(r)}. "
            f"Accept within {OFFER_MINUTES} minutes or it goes to other barbers.",
            request=r,
        )
    else:
        _broadcast(db, r, now, "")
    db.commit()
    return r


def _barber_for(db: Session, user: User) -> Barber:
    b = db.scalar(select(Barber).where(Barber.user_id == user.id))
    if b is None:
        raise forbidden("Only barbers can take requests")
    return b


def accept(
    db: Session, user: User, r: BookingRequest, slot_start: datetime, now: datetime | None = None
) -> Job:
    now = now or utcnow()
    sweep(db, now)
    db.refresh(r)
    barber = _barber_for(db, user)
    if r.status != "open":
        raise ApiError(409, "conflict", f"This request is no longer open ({r.status})")
    if not offered_to(r, barber):
        raise forbidden("This request isn't offered to you")
    slot = ensure_utc(slot_start)
    if slot not in {ensure_utc(s) for s in slots_in_windows(now, _day(r), r.windows)}:
        raise validation("Pick a start time inside the client's windows")
    job = book_job(
        db,
        r.client,
        quote_id=r.quote_id,
        barber_id=barber.id,
        slot_start=slot,
        address=r.address,
        lat=r.lat,
        lng=r.lng,
        accepted=True,
    )
    r.status, r.job_id, r.closed_at = "accepted", job.id, now
    notify(
        db,
        [r.client.user_id],
        "request_accepted",
        f"{barber.name} is coming",
        f"{barber.name} took your {r.quote.cut_name} for {when(job)}. Pay the deposit to hold it.",
        job,
        r,
    )
    db.commit()
    return job


def decline(db: Session, user: User, r: BookingRequest, now: datetime | None = None) -> None:
    now = now or utcnow()
    barber = _barber_for(db, user)
    if not offered_to(r, barber):
        raise forbidden("This request isn't offered to you")
    r.declined_by = [*(r.declined_by or []), barber.id]
    if r.chosen_barber_id == barber.id and r.broadcast_at is None:
        _broadcast(db, r, now, f"{barber.name} can't make it.")
    db.commit()


def cancel(db: Session, r: BookingRequest, now: datetime | None = None) -> None:
    if r.status != "open":
        raise conflict(f"Only open requests can be cancelled (status is {r.status})")
    r.status, r.closed_at = "cancelled", now or utcnow()
    db.commit()


# --- views ----------------------------------------------------------------------


def request_json(
    db: Session,
    r: BookingRequest,
    signer: UrlSigner,
    now: datetime | None = None,
    barber: Barber | None = None,
) -> dict[str, Any]:
    """The client's view, plus price, distance and free start times for `barber`."""
    now = now or utcnow()
    out: dict[str, Any] = {
        "id": r.id,
        "status": r.status,
        "day": r.day,
        "windows": [{"id": w, "label": WINDOW_LABELS[w]} for w in WINDOWS if w in r.windows],
        "summary": describe(r, now),
        "cut": r.quote.cut_name,
        "minutes": r.quote.minutes,
        "area_name": _area_name(r),
        "quote_id": r.quote_id,
        "chosen_barber": barber_card_json(r.chosen_barber, signer) if r.chosen_barber else None,
        "offered_until": iso(r.offered_until),
        "broadcast": r.broadcast_at is not None,
        "job_id": r.job_id,
        "created_at": iso(r.created_at),
    }
    if barber is not None:
        reach = _in_range(barber, r.quote.area_id)
        busy = busy_intervals(db, barber.id)
        out |= {
            "offered_to_you": r.chosen_barber_id == barber.id and r.broadcast_at is None,
            "client_name": r.client.name,
            "distance_km": round(reach[0], 1) if reach else None,
            "travel_band": reach[1] if reach else None,
            "price": quote_price(barber.tier, r.quote.minutes, reach[1]).as_dict()
            if reach
            else None,
            "slots": [
                iso(s)
                for s in slots_in_windows(now, _day(r), r.windows)
                if is_free(s, r.quote.minutes, busy)
            ],
        }
    return out


def for_barber(db: Session, barber: Barber) -> list[BookingRequest]:
    rows = db.scalars(
        select(BookingRequest)
        .where(BookingRequest.status == "open")
        .order_by(BookingRequest.created_at.desc())
    )
    return [r for r in rows if offered_to(r, barber)]
