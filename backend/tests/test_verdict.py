from datetime import datetime, timedelta

import pytest

from fadecall.timeutil import SAST
from fadecall.verdict import (
    CHECK_ORDER,
    decide,
    gps_check,
    hair_change_check,
    model_check,
    timestamp_check,
)

SLOT = datetime(2026, 10, 28, 16, 0, tzinfo=SAST)
SLOT_END = SLOT + timedelta(minutes=50)


def all_pass() -> dict[str, dict[str, str]]:
    return {name: {"result": "pass", "reason": "ok"} for name in CHECK_ORDER}


def test_pass_only_when_every_check_passes() -> None:
    v = decide(all_pass(), {"before": "live", "after": "live"})
    assert v.verdict == "pass"
    assert v.reasons == []


@pytest.mark.parametrize("result", ["uncertain", "fail"])
def test_any_non_pass_is_needs_review_never_fail(result: str) -> None:
    checks = all_pass()
    checks["cut_match"]["result"] = result
    v = decide(checks)
    assert v.verdict == "needs_review"
    assert v.reasons == [f"cut_match {result}"]


def test_upload_fallback_always_needs_review() -> None:
    v = decide(all_pass(), {"before": "live", "after": "upload_fallback"})
    assert v.verdict == "needs_review"
    assert v.reasons == ["after photo used upload_fallback"]


def test_missing_check_blocks_pass() -> None:
    checks = all_pass()
    del checks["same_person"]
    v = decide(checks)
    assert v.verdict == "needs_review"
    assert "same_person missing" in v.reasons


def test_reasons_follow_check_order() -> None:
    checks = all_pass()
    checks["hair_changed"]["result"] = "fail"
    checks["before_gps"]["result"] = "uncertain"
    assert decide(checks).reasons == ["before_gps uncertain", "hair_changed fail"]


@pytest.mark.parametrize(
    ("offset_min", "expected"),
    [(-30, "pass"), (-31, "fail"), (0, "pass"), (180, "pass"), (181, "fail")],
)
def test_timestamp_window(offset_min: int, expected: str) -> None:
    c = timestamp_check(SLOT + timedelta(minutes=offset_min), SLOT, SLOT_END)
    assert c["result"] == expected


def test_timestamp_reason_format_and_missing() -> None:
    c = timestamp_check(SLOT + timedelta(minutes=2), SLOT, SLOT_END)
    assert c["reason"] == "Captured 16:02, slot 16:00–16:50"
    assert timestamp_check(None, SLOT, SLOT_END)["result"] == "uncertain"


@pytest.mark.parametrize(
    ("offset_min", "when"),
    [(-45, "45 min before"), (240, "4 h after"), (-2498, "1 d 17 h before")],
)
def test_timestamp_fail_reason_is_readable(offset_min: int, when: str) -> None:
    c = timestamp_check(SLOT + timedelta(minutes=offset_min), SLOT, SLOT_END)
    assert f"({when} slot start)" in c["reason"]


def test_timestamp_accepts_utc_input() -> None:
    utc = (SLOT + timedelta(minutes=5)).astimezone(tz=None)
    assert timestamp_check(utc, SLOT, SLOT_END)["result"] == "pass"


JOB = (-25.9992, 28.1263)


def test_gps_within_300m_passes() -> None:
    c = gps_check(JOB[0] + 0.0003, JOB[1], 10, *JOB)  # ~33 m north
    assert c["result"] == "pass"
    assert c["reason"].endswith("m from booking address")
    assert 25 <= c["distance_m"] <= 40


def test_gps_far_fails_and_missing_is_uncertain() -> None:
    assert gps_check(JOB[0] + 0.01, JOB[1], 10, *JOB)["result"] == "fail"  # ~1.1 km
    assert gps_check(None, None, None, *JOB)["result"] == "uncertain"


def test_gps_poor_accuracy_near_edge_is_uncertain() -> None:
    c = gps_check(JOB[0] + 0.0035, JOB[1], 150, *JOB)  # ~390 m, ±150 m
    assert c["result"] == "uncertain"


@pytest.mark.parametrize(
    ("ratio", "expected"),
    [(0.31, "pass"), (0.10, "pass"), (0.07, "uncertain"), (0.05, "uncertain"), (0.02, "fail")],
)
def test_hair_change_thresholds(ratio: float, expected: str) -> None:
    c = hair_change_check(ratio, 0.4, 0.4 * (1 - ratio), ratio)
    assert c["result"] == expected
    assert c["change_ratio"] == ratio


def test_hair_change_no_hair_is_uncertain() -> None:
    assert hair_change_check(None, 0.0, 0.1, 0.0)["result"] == "uncertain"


def test_model_check_downgrades_low_confidence_pass() -> None:
    assert model_check("pass", "r", 0.93)["result"] == "pass"
    assert model_check("pass", "r", 0.55)["result"] == "uncertain"
    assert model_check("weird", "r", 0.9)["result"] == "uncertain"
    assert model_check("fail", "r", 1.4)["confidence"] == 1.0
