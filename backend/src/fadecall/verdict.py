"""Proof-of-job checks and the verdict rule. Pure functions, no I/O.

Verdict rule (docs/api-contract.md): `pass` only if every check passes.
Anything else is `needs_review` — never an automatic fail. Upload-fallback
capture always goes to `needs_review`.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, Literal

from .areas import haversine_m
from .timeutil import ensure_utc, hhmm

Result = Literal["pass", "fail", "uncertain"]
Verdict = Literal["pass", "needs_review"]

TIMESTAMP_BEFORE = timedelta(minutes=30)
TIMESTAMP_AFTER = timedelta(hours=3)
GPS_RADIUS_M = 300.0
HAIR_PASS = 0.10
HAIR_UNCERTAIN = 0.05
MIN_PASS_CONFIDENCE = 0.7

CHECK_ORDER = (
    "before_timestamp",
    "before_gps",
    "after_timestamp",
    "after_gps",
    "same_person",
    "hair_changed",
    "cut_match",
)


def check(result: Result, reason: str, **extra: Any) -> dict[str, Any]:
    return {"result": result, "reason": reason, **extra}


def timestamp_check(
    captured_at: datetime | None, slot_start: datetime, slot_end: datetime
) -> dict[str, Any]:
    window = f"slot {hhmm(slot_start)}–{hhmm(slot_end)}"
    if captured_at is None:
        return check("uncertain", f"No capture time sent; {window}")
    cap = ensure_utc(captured_at)
    start = ensure_utc(slot_start)
    lo, hi = start - TIMESTAMP_BEFORE, start + TIMESTAMP_AFTER
    if lo <= cap <= hi:
        return check("pass", f"Captured {hhmm(cap)}, {window}")
    delta_min = round((cap - start).total_seconds() / 60)
    when = f"{_fmt_duration(abs(delta_min))} {'before' if delta_min < 0 else 'after'} slot start"
    return check("fail", f"Captured {hhmm(cap)} ({when}); {window}")


def _fmt_duration(minutes: int) -> str:
    if minutes < 60:
        return f"{minutes} min"
    days, rem = divmod(minutes, 24 * 60)
    hours, mins = divmod(rem, 60)
    if days:
        return f"{days} d {hours} h"
    return f"{hours} h {mins} min" if mins else f"{hours} h"


def _fmt_distance(m: float) -> str:
    return f"{round(m)} m" if m < 1000 else f"{m / 1000:.1f} km"


def gps_check(
    lat: float | None,
    lng: float | None,
    accuracy_m: float | None,
    job_lat: float,
    job_lng: float,
) -> dict[str, Any]:
    if lat is None or lng is None:
        return check("uncertain", "No GPS fix (permission denied or unavailable)")
    dist = haversine_m(lat, lng, job_lat, job_lng)
    extra = {"distance_m": round(dist)}
    if dist <= GPS_RADIUS_M:
        return check("pass", f"{_fmt_distance(dist)} from booking address", **extra)
    if accuracy_m is not None and dist - accuracy_m <= GPS_RADIUS_M:
        return check(
            "uncertain",
            f"{_fmt_distance(dist)} from booking address, "
            f"but GPS accuracy is ±{round(accuracy_m)} m",
            **extra,
        )
    return check("fail", f"{_fmt_distance(dist)} from booking address", **extra)


def hair_change_check(
    change_ratio: float | None, area_before: float, area_after: float, pixel_change: float
) -> dict[str, Any]:
    """Pass if change ≥ 10%, uncertain 5–10%, fail below 5%."""
    if change_ratio is None:
        return check("uncertain", "No hair region found in the before photo", change_ratio=None)
    ratio = round(change_ratio, 3)
    if area_before > 0:
        area_delta = (area_after - area_before) / area_before
        direction = "down" if area_delta < 0 else "up"
        area_text = f"Hair area {direction} {abs(round(area_delta * 100))}%"
    else:
        area_text = "Hair area unchanged"
    text = f"{area_text}; {round(pixel_change * 100)}% of the hair region changed"
    if ratio >= HAIR_PASS:
        return check("pass", text, change_ratio=ratio)
    if ratio >= HAIR_UNCERTAIN:
        return check("uncertain", f"Small change: {text}", change_ratio=ratio)
    return check("fail", f"Little visible change: {text}", change_ratio=ratio)


def _confidence(value: Any) -> float:
    try:
        conf = float(value)
    except (TypeError, ValueError):
        return 0.0
    return conf if conf == conf else 0.0  # NaN -> 0


def model_check(result: Any, reason: Any, confidence: Any) -> dict[str, Any]:
    """Normalise a model's check (null-safe). A low-confidence pass becomes uncertain."""
    conf = round(min(max(_confidence(confidence), 0.0), 1.0), 2)
    reason = "" if reason is None else str(reason)
    res: Result = result if result in ("pass", "fail", "uncertain") else "uncertain"  # type: ignore[assignment]
    if res == "pass" and conf < MIN_PASS_CONFIDENCE:
        res = "uncertain"
    return check(res, reason, confidence=conf)


@dataclass(frozen=True, slots=True)
class VerdictResult:
    verdict: Verdict
    reasons: list[str]


def decide(
    checks: Mapping[str, Mapping[str, Any]],
    capture_modes: Mapping[str, str] | None = None,
    required: tuple[str, ...] = CHECK_ORDER,
) -> VerdictResult:
    reasons: list[str] = []
    for name, mode in (capture_modes or {}).items():
        if mode == "upload_fallback":
            reasons.append(f"{name} photo used upload_fallback")
    names = [n for n in CHECK_ORDER if n in checks] + [n for n in checks if n not in CHECK_ORDER]
    for name in names:
        result = checks[name].get("result")
        if result != "pass":
            reasons.append(f"{name} {result or 'missing'}")
    reasons.extend(f"{name} missing" for name in required if name not in checks)
    return VerdictResult("needs_review" if reasons else "pass", reasons)
