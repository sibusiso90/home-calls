"""Launch suburbs (Midrand / Centurion) with approximate centre coordinates."""

from __future__ import annotations

import math
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class Area:
    id: str
    name: str
    lat: float
    lng: float

    def as_dict(self) -> dict[str, object]:
        return {"id": self.id, "name": self.name, "lat": self.lat, "lng": self.lng}


AREAS: tuple[Area, ...] = (
    Area("midrand-central", "Midrand Central", -25.9992, 28.1263),
    Area("halfway-house", "Halfway House", -25.9970, 28.1290),
    Area("vorna-valley", "Vorna Valley", -25.9930, 28.1050),
    Area("kyalami", "Kyalami", -26.0060, 28.0700),
    Area("noordwyk", "Noordwyk", -25.9580, 28.1270),
    Area("carlswald", "Carlswald", -25.9800, 28.1050),
    Area("waterfall", "Waterfall", -26.0170, 28.1050),
    Area("centurion-central", "Centurion Central", -25.8600, 28.1890),
    Area("lyttelton", "Lyttelton", -25.8370, 28.2050),
    Area("irene", "Irene", -25.8820, 28.2240),
    Area("eldoraigne", "Eldoraigne", -25.8550, 28.1550),
    Area("rooihuiskraal", "Rooihuiskraal", -25.8970, 28.1420),
)

AREAS_BY_ID: dict[str, Area] = {a.id: a for a in AREAS}


def get_area(area_id: str | None) -> Area | None:
    return AREAS_BY_ID.get(area_id) if area_id else None


EARTH_RADIUS_M = 6_371_000.0


def haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle distance in metres."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(a))


def area_distance_km(a: Area, b: Area) -> float:
    return haversine_m(a.lat, a.lng, b.lat, b.lng) / 1000.0
