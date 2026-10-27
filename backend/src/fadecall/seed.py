"""Seed demo data with synthetic media (always uses the offline mock models).

uv run python -m fadecall.seed            # only if the DB is empty
uv run python -m fadecall.seed --reset    # wipe and reseed
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
    for i in range(5):
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


async def seed(settings: Settings, reset: bool = False) -> None:
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
    tomorrow = next(candidate_slots(utcnow())).astimezone(SAST)
    print("Seeded Fade Call demo data (mock models, synthetic images).")
    print(f"  operator: name any, passcode = OPERATOR_PASSCODE ({settings.operator_passcode})")
    print(f"  client:   {CLIENT['name']} {CLIENT['phone']}")
    for spec in BARBERS:
        print(f"  barber:   {spec[0]} {spec[1]} ({spec[2]})")
    print(f"  pending:  {PENDING[0]} {PENDING[1]}")
    print(f"  next bookable slot: {tomorrow.isoformat()}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reset", action="store_true", help="drop all data first")
    args = parser.parse_args()
    asyncio.run(seed(get_settings(), reset=args.reset))


if __name__ == "__main__":
    main()
