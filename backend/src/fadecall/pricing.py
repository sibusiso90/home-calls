"""Tier bands, travel bands and quote pricing (numbers from docs/api-contract.md)."""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Literal

Tier = Literal["starter", "pro", "elite"]
TravelBand = Literal["A", "B", "C"]

PRICE_BANDS: dict[str, tuple[int, int]] = {
    "starter": (250, 320),
    "pro": (320, 420),
    "elite": (420, 550),
}

TRAVEL_FEES: dict[str, int] = {"A": 0, "B": 40, "C": 80}
MAX_TRAVEL_KM = 20.0


def tier_for_average(average: float) -> Tier:
    """Below 6.5 starter; 6.5 to below 8.0 pro; 8.0 or higher elite."""
    if average >= 8.0:
        return "elite"
    if average >= 6.5:
        return "pro"
    return "starter"


def price_band(tier: str | None) -> dict[str, int] | None:
    if tier not in PRICE_BANDS:
        return None
    lo, hi = PRICE_BANDS[tier]
    return {"min_zar": lo, "max_zar": hi}


def tier_rate_zar(tier: str | None) -> int:
    """The tier's base home-call rate is the bottom of its price band."""
    return PRICE_BANDS.get(tier or "starter", PRICE_BANDS["starter"])[0]


def time_charge_zar(minutes: int) -> int:
    """R5 per started 10 minutes over 30 minutes."""
    over = max(0, minutes - 30)
    return 5 * math.ceil(over / 10)


def travel_band(distance_km: float) -> TravelBand | None:
    """A under 5 km, B 5–12 km, C 12–20 km, None (out of range) over 20 km."""
    if distance_km < 5:
        return "A"
    if distance_km <= 12:
        return "B"
    if distance_km <= MAX_TRAVEL_KM:
        return "C"
    return None


@dataclass(frozen=True, slots=True)
class Price:
    tier_rate_zar: int
    time_zar: int
    travel_zar: int

    @property
    def total_zar(self) -> int:
        return self.tier_rate_zar + self.time_zar + self.travel_zar

    def as_dict(self) -> dict[str, int]:
        return {
            "tier_rate_zar": self.tier_rate_zar,
            "time_zar": self.time_zar,
            "travel_zar": self.travel_zar,
            "total_zar": self.total_zar,
        }


def quote_price(tier: str | None, minutes: int, band: str) -> Price:
    return Price(tier_rate_zar(tier), time_charge_zar(minutes), TRAVEL_FEES[band])
