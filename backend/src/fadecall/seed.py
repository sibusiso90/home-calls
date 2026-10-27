"""Seed demo data with synthetic media (always uses the offline mock models).

uv run python -m fadecall.seed            # only if the DB is empty
uv run python -m fadecall.seed --reset    # wipe and reseed
uv run python -m fadecall.seed --demo [--lat -25.99 --lng 28.12] [--slot 14:30]
    # wipe, reseed, then add the film-day set (see docs/demo-script.md)
"""

from __future__ import annotations

import argparse
import asyncio
from datetime import datetime, timedelta
from statistics import mean

from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from .ai.mock import GRADE_REASONS, MockModelClient
from .areas import AREAS_BY_ID
from .config import Settings, get_settings
from .db import Base, make_engine, make_sessionmaker
from .models import Barber, Client, Job, Notification, PortfolioItem, Rating, User, new_id
from .pricing import PRICE_BANDS, tier_for_average
from .samples import SKIN_TONES, head_image, sine_wav
from .scheduling import candidate_slots
from .services.accounts import phone_key
from .services.disputes import open_dispute
from .services.onboarding import DIMENSIONS, grade_summary
from .services.proof import Capture, capture_after, capture_before
from .services.quotes import book_job, create_quote
from .storage import Storage, make_storage
from .timeutil import SAST, utcnow

OPERATOR = {"name": "Fade Call Ops", "phone": "+27100000000"}
CLIENT = {"name": "Lerato", "phone": "+27831234567", "area_id": "midrand-central"}
BARBERS = [
    # name, phone, area, years, styles, languages, availability, target avg, jobs, rating
    (
        "Thabo M",
        "+27821234567",
        "midrand-central",
        6,
        ["skin fade", "taper", "line-up"],
        ["isiZulu", "English"],
        "Weekdays after 16:00, Saturdays",
        8.4,
        12,
        4.8,
    ),
    (
        "Sipho D",
        "+27822345678",
        "centurion-central",
        8,
        ["chiskop", "brush cut", "mid fade"],
        ["isiZulu", "English"],
        "Saturdays and Sundays",
        7.4,
        7,
        4.5,
    ),
    (
        "Kabelo M",
        "+27823456789",
        "halfway-house",
        4,
        ["low fade", "waves", "beard trim"],
        ["Setswana", "English"],
        "Weekdays after 17:00",
        7.0,
        3,
        4.2,
    ),
    (
        "Neo K",
        "+27824567890",
        "irene",
        2,
        ["buzz cut", "taper"],
        ["Sesotho", "English"],
        "Weekdays after 16:00",
        6.0,
        0,
        None,
    ),
]
PENDING = (
    "Lwazi N",
    "+27825678901",
    "vorna-valley",
    3,
    ["high fade", "line-up"],
    ["isiXhosa", "English"],
    "Saturdays",
    7.8,
)


def _reset(settings: Settings) -> None:
    engine = make_engine(settings.sqlalchemy_url)
    if engine.dialect.name == "sqlite":
        Base.metadata.drop_all(engine)
        Base.metadata.create_all(engine)
    else:
        with engine.begin() as conn:
            for table in reversed(Base.metadata.sorted_tables):
                conn.execute(table.delete())
    engine.dispose()


def _scores(target: float, i: int) -> dict[str, int]:
    offsets = [(0, 1, -1, 0), (1, 0, 0, -1), (-1, 0, 1, 0), (0, -1, 0, 1), (0, 0, 0, 0)][i % 5]
    return {k: max(0, min(10, round(target + o))) for k, o in zip(DIMENSIONS, offsets, strict=True)}


async def _barber(
    db: Session,
    storage: Storage,
    spec: tuple,
    status: str,
    idx: int,  # type: ignore[type-arg]
    items: int = 5,
) -> Barber:
    name, phone, area, years, styles, langs, avail, target = spec[:8]
    user = User(role="barber", name=name, phone=phone, phone_key=phone_key(phone, name))
    db.add(user)
    db.flush()
    b = Barber(
        user_id=user.id,
        name=name,
        area_id=area,
        years_cutting=years,
        styles=styles,
        languages=langs,
        availability=avail,
        profile_confirmed=True,
        status=status,
    )
    db.add(b)
    db.flush()
    for i in range(items):
        skin = SKIN_TONES[(idx + i) % len(SKIN_TONES)]
        scores = _scores(target, i)
        reasons = {
            k: GRADE_REASONS[k][0 if v >= 8 else 1 if v >= 6 else 2] for k, v in scores.items()
        }
        item_id = new_id()
        bk, ak = f"portfolio/{b.id}/{item_id}-before.jpg", f"portfolio/{b.id}/{item_id}-after.jpg"
        seed = 100 * idx + i
        await storage.put(bk, head_image(skin, "full", seed), "image/jpeg")
        style = "fade" if i % 2 == 0 else "taper"
        await storage.put(ak, head_image(skin, style, seed, quality=target / 10), "image/jpeg")
        db.add(
            PortfolioItem(
                id=item_id,
                barber_id=b.id,
                before_key=bk,
                after_key=ak,
                scores=scores,
                reasons=reasons,
                overall=round(mean(scores.values()), 1),
                model_versions={"spark": "mock"},
            )
        )
    db.flush()
    db.refresh(b)
    if items < 5:  # still onboarding: not graded yet
        db.commit()
        return b
    avg = round(mean(p.overall for p in b.portfolio), 1)
    b.tier = tier_for_average(avg)
    b.price_min_zar, b.price_max_zar = PRICE_BANDS[b.tier]
    b.grade_average = avg
    b.grade_summary = grade_summary(list(b.portfolio))
    if len(spec) > 8:
        b.verified_jobs, b.rating = spec[8], spec[9]
    db.commit()
    return b


def _past_slots(n: int) -> list[datetime]:
    start = utcnow() - timedelta(days=12)
    return list(candidate_slots(start, days=10))[:n]


async def _run_job(
    db: Session,
    models: MockModelClient,
    storage: Storage,
    client: Client,
    quote_id: str,
    barber: Barber,
    slot: datetime,
    skin: tuple[int, int, int],
    after_skin: tuple[int, int, int] | None = None,
) -> str:
    area = AREAS_BY_ID[client.area_id or "midrand-central"]
    job = book_job(
        db,
        client,
        quote_id=quote_id,
        barber_id=barber.id,
        slot_start=slot,
        address="12 Example Rd, " + area.name,
        lat=area.lat + 0.0012,
        lng=area.lng - 0.0009,
    )
    job.status, job.payment_status = "confirmed", "deposit_paid"
    job.consented_demo = True  # synthetic demo set: exempt from evidence purge
    db.commit()
    near = Capture(slot + timedelta(minutes=3), job.lat + 0.0002, job.lng, 12.0)
    await capture_before(db, storage, job, head_image(skin, "full", 900), near)
    after = Capture(slot + timedelta(minutes=52), job.lat, job.lng + 0.0002, 9.0)
    after_img = head_image(after_skin or skin, "fade", 900 if after_skin is None else 77)
    await capture_after(db, models, storage, job, after_img, after)
    return job.id


async def seed(settings: Settings, reset: bool = False, quiet: bool = False) -> None:
    if reset:
        _reset(settings)
    engine = make_engine(settings.sqlalchemy_url)
    if engine.dialect.name == "sqlite":
        Base.metadata.create_all(engine)
    factory = make_sessionmaker(engine)
    storage = make_storage(settings)
    models = MockModelClient(settings.model_copy(update={"mock_force_review": False}))
    with factory() as db:
        if db.scalar(select(func.count()).select_from(Barber)):
            print("Database already has barbers; use --reset to reseed.")
            return
        db.add(
            User(
                role="operator",
                name=OPERATOR["name"],
                phone=OPERATOR["phone"],
                phone_key=phone_key(OPERATOR["phone"], OPERATOR["name"]),
            )
        )
        barbers = [
            await _barber(db, storage, spec, "approved", i) for i, spec in enumerate(BARBERS)
        ]
        await _barber(db, storage, PENDING, "pending_approval", 9)

        cu = User(
            role="client",
            name=CLIENT["name"],
            phone=CLIENT["phone"],
            phone_key=phone_key(CLIENT["phone"], CLIENT["name"]),
        )
        db.add(cu)
        db.flush()
        client = Client(
            user_id=cu.id, name=CLIENT["name"], phone=CLIENT["phone"], area_id=CLIENT["area_id"]
        )
        db.add(client)
        db.commit()
        quote = await create_quote(
            db,
            models,
            storage,
            client,
            CLIENT["area_id"],
            head_image(SKIN_TONES[1], "full", 3),
            head_image(SKIN_TONES[3], "fade", 4),
        )

        s1, s2, s3 = _past_slots(3)
        skin = SKIN_TONES[1]
        # 1) verified + rated
        j1 = await _run_job(db, models, storage, client, quote.id, barbers[0], s1, skin)
        db.add(Rating(job_id=j1, stars=5, comment="Clean fade, on time, very professional."))
        # 2) needs review: after photo looks like a different person
        await _run_job(db, models, storage, client, quote.id, barbers[1], s2, skin, SKIN_TONES[4])
        # 3) verified, then disputed (payment held)
        j3 = await _run_job(db, models, storage, client, quote.id, barbers[2], s3, skin)
        db.commit()
        job3 = db.get(Job, j3)
        assert job3 is not None
        await open_dispute(
            db,
            models,
            settings,
            job3,
            sine_wav(2.0, 330.0),
            "The left side of the fade is higher than the right.",
        )
        # Seeded history is old news: keep it in the inbox but not as unread.
        db.execute(update(Notification).values(read_at=utcnow()))
        db.commit()
    await storage.aclose()
    engine.dispose()
    if quiet:
        return
    tomorrow = next(candidate_slots(utcnow())).astimezone(SAST)
    print("Seeded Fade Call demo data (mock models, synthetic images).")
    print(f"  operator: name any, passcode = OPERATOR_PASSCODE ({settings.operator_passcode})")
    print(f"  client:   {CLIENT['name']} {CLIENT['phone']}")
    for spec in BARBERS:
        print(f"  barber:   {spec[0]} {spec[1]} ({spec[2]})")
    print(f"  pending:  {PENDING[0]} {PENDING[1]}")
    print(f"  next bookable slot: {tomorrow.isoformat()}")


# --- film-day set ---------------------------------------------------------------

DEMO_FRESH_BARBER = ("Ayanda K", "+27825550101")
DEMO_ONBOARDING_BARBER = (
    "Bongani S",
    "+27825550102",
    "midrand-central",
    5,
    ["skin fade", "taper"],
    ["isiZulu", "English"],
    "Weekdays after 15:00",
    7.6,
)
DEMO_CLIENT = {"name": "Naledi", "phone": "+27845550103", "area_id": "midrand-central"}
DEMO_ADDRESS = "7 Demo Close, Midrand"


def demo_slot(now: datetime, at: str | None = None) -> datetime:
    """Today's demo slot: `at` (HH:MM, SAST) or 10 minutes before now, rounded to 5 min.

    The timestamp check passes from 30 min before the slot to 3 hours after it,
    so filming can start straight away and run for about three hours.
    """
    local = now.astimezone(SAST)
    if at:
        hh, mm = (int(x) for x in at.split(":"))
        return local.replace(hour=hh, minute=mm, second=0, microsecond=0)
    start = local - timedelta(minutes=10)
    return start.replace(minute=start.minute - start.minute % 5, second=0, microsecond=0)


async def seed_demo(
    settings: Settings,
    *,
    lat: float | None = None,
    lng: float | None = None,
    slot_at: str | None = None,
    now: datetime | None = None,
) -> dict[str, str]:
    """Reset, run the normal seed, then add the film-day records. Returns ids for printing."""
    await seed(settings, reset=True, quiet=True)
    now = now or utcnow()
    engine = make_engine(settings.sqlalchemy_url)
    storage = make_storage(settings)
    models = MockModelClient(settings.model_copy(update={"mock_force_review": False}))
    out: dict[str, str] = {}
    try:
        with make_sessionmaker(engine)() as db:
            # 1) a brand-new barber for the voice-note shot
            name, phone = DEMO_FRESH_BARBER
            user = User(role="barber", name=name, phone=phone, phone_key=phone_key(phone, name))
            db.add(user)
            db.flush()
            db.add(Barber(user_id=user.id, name=name, status="onboarding"))
            # 2) a barber with a confirmed profile and 4 of 5 pairs: add one, then grade
            await _barber(db, storage, DEMO_ONBOARDING_BARBER, "onboarding", 7, items=4)

            # 3) a fresh client with a quote ready, booked with Thabo for "today"
            cu = User(
                role="client",
                name=DEMO_CLIENT["name"],
                phone=DEMO_CLIENT["phone"],
                phone_key=phone_key(DEMO_CLIENT["phone"], DEMO_CLIENT["name"]),
            )
            db.add(cu)
            db.flush()
            client = Client(
                user_id=cu.id,
                name=cu.name,
                phone=cu.phone,
                area_id=DEMO_CLIENT["area_id"],
            )
            db.add(client)
            db.commit()
            quote = await create_quote(
                db,
                models,
                storage,
                client,
                DEMO_CLIENT["area_id"],
                head_image(SKIN_TONES[2], "full", 31),
                head_image(SKIN_TONES[0], "fade", 32),
            )
            thabo = db.scalar(select(Barber).where(Barber.name == BARBERS[0][0]))
            assert thabo is not None
            area = AREAS_BY_ID[DEMO_CLIENT["area_id"]]
            slot = demo_slot(now, slot_at)
            job = book_job(
                db,
                client,
                quote_id=quote.id,
                barber_id=thabo.id,
                slot_start=slot,
                address=DEMO_ADDRESS,
                lat=area.lat if lat is None else lat,
                lng=area.lng if lng is None else lng,
            )
            job.status, job.payment_status = "confirmed", "deposit_paid"
            job.consented_demo = True
            db.commit()
            out = {
                "quote_id": quote.id,
                "job_id": job.id,
                "slot": slot.isoformat(),
                "lat": f"{job.lat:.5f}",
                "lng": f"{job.lng:.5f}",
            }
    finally:
        await storage.aclose()
        engine.dispose()
    return out


def print_demo(settings: Settings, ids: dict[str, str]) -> None:
    slot = datetime.fromisoformat(ids["slot"])
    window = f"{(slot - timedelta(minutes=30)):%H:%M}–{(slot + timedelta(hours=3)):%H:%M}"
    rows = [
        ("1 Voice onboarding", "barber", f"{DEMO_FRESH_BARBER[0]} {DEMO_FRESH_BARBER[1]}"),
        (
            "1 Portfolio + grade",
            "barber",
            f"{DEMO_ONBOARDING_BARBER[0]} {DEMO_ONBOARDING_BARBER[1]} (4 of 5 pairs)",
        ),
        ("2 Quote", "client", f"{DEMO_CLIENT['name']} {DEMO_CLIENT['phone']}"),
        (
            "3 Matches (ready)",
            "client",
            f"{DEMO_CLIENT['name']}: #/client/quote/matches/{ids['quote_id']}",
        ),
        (
            "4 Proof of job (live)",
            "barber",
            f"{BARBERS[0][0]} {BARBERS[0][1]}: #/barber/jobs/{ids['job_id']}",
        ),
        (
            "4 Rating unlocked",
            "client",
            f"{DEMO_CLIENT['name']}: #/client/bookings/{ids['job_id']}",
        ),
        ("4 Dispute / history", "client", f"{CLIENT['name']} {CLIENT['phone']}"),
        ("5 Operator", "operator", f"any name, passcode {settings.operator_passcode}"),
    ]
    print("Film-day data ready (mock models, synthetic images).")
    print(f"  Today's job: slot {slot:%H:%M} SAST; live photos pass the time check {window}.")
    print(
        f"  Booking GPS: {ids['lat']}, {ids['lng']} (pass within 300 m). "
        "Re-run with --lat/--lng where you film."
    )
    for shot, role, login in rows:
        print(f"  {shot:<22} {role:<9} {login}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reset", action="store_true", help="drop all data first")
    parser.add_argument("--demo", action="store_true", help="reset + film-day dataset")
    parser.add_argument("--lat", type=float, help="demo booking latitude (where you film)")
    parser.add_argument("--lng", type=float, help="demo booking longitude")
    parser.add_argument("--slot", help="demo slot today, HH:MM SAST (default: about now)")
    args = parser.parse_args()
    settings = get_settings()
    if args.demo:
        ids = asyncio.run(seed_demo(settings, lat=args.lat, lng=args.lng, slot_at=args.slot))
        print_demo(settings, ids)
    else:
        asyncio.run(seed(settings, reset=args.reset))


if __name__ == "__main__":
    main()
