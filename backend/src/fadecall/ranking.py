"""Match ranking: 0.35 tier + 0.25 verified jobs + 0.25 rating + 0.15 proximity."""

from __future__ import annotations

from .pricing import MAX_TRAVEL_KM

TIER_SCORE: dict[str, float] = {"starter": 0.0, "pro": 0.5, "elite": 1.0}
VERIFIED_JOBS_CAP = 20
NULL_RATING_SCORE = 0.6

W_TIER, W_JOBS, W_RATING, W_PROXIMITY = 0.35, 0.25, 0.25, 0.15


def rank_score(
    tier: str | None, verified_jobs: int, rating: float | None, distance_km: float
) -> float:
    """Each component is normalised to 0–1 before weighting."""
    tier_n = TIER_SCORE.get(tier or "", 0.0)
    jobs_n = min(max(verified_jobs, 0), VERIFIED_JOBS_CAP) / VERIFIED_JOBS_CAP
    rating_n = NULL_RATING_SCORE if rating is None else min(max(rating, 0.0), 5.0) / 5.0
    prox_n = max(0.0, 1.0 - distance_km / MAX_TRAVEL_KM)
    score = W_TIER * tier_n + W_JOBS * jobs_n + W_RATING * rating_n + W_PROXIMITY * prox_n
    return round(score, 2)
