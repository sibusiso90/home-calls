from datetime import datetime

import pytest

from fadecall.areas import AREAS, AREAS_BY_ID, area_distance_km, haversine_m
from fadecall.pricing import (
    price_band,
    quote_price,
    tier_for_average,
    time_charge_zar,
    travel_band,
)
from fadecall.ranking import rank_score
from fadecall.scheduling import free_slots, is_free, next_slot
from fadecall.timeutil import SAST


@pytest.mark.parametrize(
    ("avg", "tier"),
    [
        (5.0, "starter"),
        (6.49, "starter"),
        (6.5, "pro"),
        (7.99, "pro"),
        (8.0, "elite"),
        (10, "elite"),
    ],
)
def test_tier_thresholds(avg: float, tier: str) -> None:
    assert tier_for_average(avg) == tier


def test_price_bands() -> None:
    assert price_band("starter") == {"min_zar": 250, "max_zar": 320}
    assert price_band("pro") == {"min_zar": 320, "max_zar": 420}
    assert price_band("elite") == {"min_zar": 420, "max_zar": 550}
    assert price_band(None) is None


@pytest.mark.parametrize(
    ("minutes", "zar"), [(20, 0), (30, 0), (31, 5), (40, 5), (41, 10), (50, 10), (75, 25)]
)
def test_time_charge_per_started_10_minutes_over_30(minutes: int, zar: int) -> None:
    assert time_charge_zar(minutes) == zar


@pytest.mark.parametrize(
    ("km", "band"),
    [(0, "A"), (4.99, "A"), (5, "B"), (12, "B"), (12.01, "C"), (20, "C"), (20.01, None)],
)
def test_travel_bands(km: float, band: str | None) -> None:
    assert travel_band(km) == band


def test_quote_price_total() -> None:
    p = quote_price("pro", 80, "B")
    assert p.as_dict() == {"tier_rate_zar": 320, "time_zar": 25, "travel_zar": 40, "total_zar": 385}


def test_rank_score_weights() -> None:
    assert rank_score("elite", 20, 5.0, 0) == 1.0
    assert rank_score("starter", 0, 0.0, 20) == 0.0
    # null rating counts as 0.6
    assert rank_score("starter", 0, None, 20) == pytest.approx(0.25 * 0.6, abs=0.01)
    # verified jobs cap at 20
    assert rank_score("pro", 40, 4.0, 10) == rank_score("pro", 20, 4.0, 10)
    assert rank_score("pro", 3, 4.7, 4.2) == pytest.approx(
        0.35 * 0.5 + 0.25 * 3 / 20 + 0.25 * 4.7 / 5 + 0.15 * (1 - 4.2 / 20), abs=0.01
    )


def test_areas_are_real_and_close() -> None:
    assert len(AREAS) == 12
    mid, cent = AREAS_BY_ID["midrand-central"], AREAS_BY_ID["centurion-central"]
    assert 15 < area_distance_km(mid, cent) < 20
    assert haversine_m(0, 0, 0, 0) == 0


def test_next_slot_rules() -> None:
    mon_10 = datetime(2026, 10, 26, 10, 0, tzinfo=SAST)  # Monday
    assert next_slot(mon_10, []) == datetime(2026, 10, 26, 11, 0, tzinfo=SAST)  # same day
    mon_1810 = datetime(2026, 10, 26, 18, 10, tzinfo=SAST)
    assert next_slot(mon_1810, []) == datetime(2026, 10, 26, 19, 30, tzinfo=SAST)
    mon_1930 = datetime(2026, 10, 26, 19, 30, tzinfo=SAST)
    assert next_slot(mon_1930, []) == datetime(2026, 10, 27, 8, 0, tzinfo=SAST)
    sat_1630 = datetime(2026, 10, 31, 16, 30, tzinfo=SAST)
    assert next_slot(sat_1630, []) == datetime(2026, 10, 31, 17, 30, tzinfo=SAST)
    sat_2000 = datetime(2026, 10, 31, 20, 0, tzinfo=SAST)
    assert next_slot(sat_2000, []) == datetime(2026, 11, 1, 9, 0, tzinfo=SAST)  # Sunday opens 09:00


def test_bookings_block_overlapping_slots() -> None:
    mon_10 = datetime(2026, 10, 26, 10, 0, tzinfo=SAST)
    # 11:00-11:50 booked: with 30 min travel either side, a 45 min cut fits at 12:30 at the
    # earliest after it, and nothing that would end after 10:30 can start before it.
    busy = [
        (datetime(2026, 10, 26, 11, 0, tzinfo=SAST), datetime(2026, 10, 26, 11, 50, tzinfo=SAST))
    ]
    assert next_slot(mon_10, busy) == datetime(2026, 10, 26, 12, 30, tzinfo=SAST)
    assert not is_free(datetime(2026, 10, 26, 12, 0, tzinfo=SAST), 45, busy)
    assert is_free(datetime(2026, 10, 26, 12, 30, tzinfo=SAST), 45, busy)
    early = datetime(2026, 10, 26, 10, 0, tzinfo=SAST)
    assert not is_free(early, 45, busy) and is_free(early, 30, busy)
    today = free_slots(mon_10, busy, 45, days=0)
    assert today[0] == datetime(2026, 10, 26, 12, 30, tzinfo=SAST)
    assert today[-1] == datetime(2026, 10, 26, 20, 0, tzinfo=SAST)
