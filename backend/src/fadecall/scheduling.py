"""Bookable slots: every 30 minutes in working hours (SAST), same day included.

A slot is free when the cut (plus travel either side) doesn't overlap any live
booking for that barber. The first slot is at least MIN_LEAD away so the barber
can get there.
"""

from __future__ import annotations

from collections.abc import Iterable
from datetime import date, datetime, time, timedelta

from .timeutil import SAST, ensure_utc

STEP = timedelta(minutes=30)
MIN_LEAD = timedelta(hours=1)
TRAVEL_BUFFER = timedelta(minutes=30)
DEFAULT_MINUTES = 45

# Weekday (Mon=0) -> first and last start time.
HOURS = {
    **{d: (time(8, 0), time(20, 0)) for d in range(6)},
    6: (time(9, 0), time(17, 0)),
}

Busy = tuple[datetime, datetime]


def candidate_slots(now: datetime, days: int = 28) -> Iterable[datetime]:
    local_now = ensure_utc(now).astimezone(SAST)
    for offset in range(days + 1):
        day = (local_now + timedelta(days=offset)).date()
        first, last = HOURS[day.weekday()]
        slot = datetime.combine(day, first, tzinfo=SAST)
        end = datetime.combine(day, last, tzinfo=SAST)
        while slot <= end:
            if slot - local_now >= MIN_LEAD:
                yield slot
            slot += STEP


def is_free(slot: datetime, minutes: int, busy: Iterable[Busy]) -> bool:
    start = ensure_utc(slot)
    end = start + timedelta(minutes=minutes)
    return all(
        not (
            start < ensure_utc(b_end) + TRAVEL_BUFFER and ensure_utc(b_start) < end + TRAVEL_BUFFER
        )
        for b_start, b_end in busy
    )


def free_slots(
    now: datetime, busy: Iterable[Busy], minutes: int = DEFAULT_MINUTES, days: int = 28
) -> list[datetime]:
    busy = list(busy)
    return [s for s in candidate_slots(now, days) if is_free(s, minutes, busy)]


def is_bookable(slot: datetime, now: datetime, days: int = 28) -> bool:
    target = ensure_utc(slot)
    return any(ensure_utc(s) == target for s in candidate_slots(now, days))


def next_slot(
    now: datetime, busy: Iterable[Busy], minutes: int = DEFAULT_MINUTES
) -> datetime | None:
    busy = list(busy)
    return next((s for s in candidate_slots(now) if is_free(s, minutes, busy)), None)


# --- Time windows a client asks for; the barber who takes the job picks the start ---

WINDOWS = {
    "morning": (time(8, 0), time(12, 0)),
    "afternoon": (time(12, 0), time(17, 0)),
    "evening": (time(17, 0), time(20, 30)),
}
WINDOW_LABELS = {"morning": "Morning", "afternoon": "Afternoon", "evening": "Evening"}


def window_of(slot: datetime) -> str | None:
    t = ensure_utc(slot).astimezone(SAST).time()
    return next((w for w, (start, end) in WINDOWS.items() if start <= t < end), None)


def slots_in_windows(now: datetime, day: date, windows: Iterable[str]) -> list[datetime]:
    """Bookable starts on `day` (SAST) inside any of `windows`, at least MIN_LEAD away."""
    wanted = set(windows)
    offset = (day - ensure_utc(now).astimezone(SAST).date()).days
    if offset < 0:
        return []
    return [s for s in candidate_slots(now, offset) if s.date() == day and window_of(s) in wanted]
