"""Next bookable slot: next weekday 16:00 or Saturday 09:00 (SAST), not yet booked."""

from __future__ import annotations

from collections.abc import Iterable
from datetime import datetime, time, timedelta

from .timeutil import SAST, ensure_utc

WEEKDAY_SLOT = time(16, 0)
SATURDAY_SLOT = time(9, 0)
MIN_LEAD = timedelta(hours=1)


def candidate_slots(now: datetime, days: int = 28) -> Iterable[datetime]:
    local_now = ensure_utc(now).astimezone(SAST)
    for offset in range(days + 1):
        day = (local_now + timedelta(days=offset)).date()
        wd = day.weekday()  # Mon=0 .. Sun=6
        if wd == 6:
            continue
        slot_time = SATURDAY_SLOT if wd == 5 else WEEKDAY_SLOT
        slot = datetime.combine(day, slot_time, tzinfo=SAST)
        if slot - local_now >= MIN_LEAD:
            yield slot


def next_slot(now: datetime, booked: Iterable[datetime]) -> datetime | None:
    taken = {ensure_utc(b) for b in booked}
    for slot in candidate_slots(now):
        if ensure_utc(slot) not in taken:
            return slot
    return None
