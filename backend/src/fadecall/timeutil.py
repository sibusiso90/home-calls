"""Time helpers. Stored times are UTC; API output is in South African time."""

from __future__ import annotations

from datetime import UTC, datetime
from zoneinfo import ZoneInfo

SAST = ZoneInfo("Africa/Johannesburg")


def utcnow() -> datetime:
    return datetime.now(UTC)


def ensure_aware(value: datetime) -> datetime:
    """Treat naive datetimes as SAST (what a local device clock would mean)."""
    return value if value.tzinfo is not None else value.replace(tzinfo=SAST)


def iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    return ensure_utc(value).astimezone(SAST).isoformat()


def ensure_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


def parse_iso(value: str) -> datetime:
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    return ensure_aware(datetime.fromisoformat(text))


def hhmm(value: datetime) -> str:
    return ensure_utc(value).astimezone(SAST).strftime("%H:%M")
