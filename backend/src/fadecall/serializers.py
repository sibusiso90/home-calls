"""ORM → contract JSON. Keys and shapes follow docs/api-contract.md exactly."""

from __future__ import annotations

from typing import Any

from .areas import get_area
from .models import (
    Barber,
    Dispute,
    Evidence,
    Job,
    Notification,
    Payout,
    PortfolioItem,
    Quote,
    User,
)
from .pricing import price_band
from .storage import UrlSigner
from .timeutil import iso
from .verdict import CHECK_ORDER


def user_json(u: User) -> dict[str, Any]:
    return {"id": u.id, "role": u.role, "name": u.name, "phone": u.phone}


def portfolio_json(p: PortfolioItem, s: UrlSigner) -> dict[str, Any]:
    return {
        "id": p.id,
        "before_url": s.url(p.before_key),
        "after_url": s.url(p.after_key),
        "scores": p.scores,
        "reasons": p.reasons,
        "overall": p.overall,
        "model_versions": p.model_versions,
        "elapsed_ms": p.elapsed_ms,
    }


def profile_json(b: Barber) -> dict[str, Any]:
    return {
        "name": b.name,
        "area_id": b.area_id,
        "years_cutting": b.years_cutting,
        "styles": b.styles or [],
        "languages": b.languages or [],
        "availability": b.availability,
    }


def barber_json(b: Barber, s: UrlSigner) -> dict[str, Any]:
    area = get_area(b.area_id)
    return {
        "id": b.id,
        "name": b.name,
        "area_id": b.area_id,
        "area_name": area.name if area else None,
        "languages": b.languages or [],
        "years_cutting": b.years_cutting,
        "styles": b.styles or [],
        "availability": b.availability,
        "tier": b.tier,
        "price_band": price_band(b.tier),
        "verified_jobs": b.verified_jobs,
        "rating": b.rating,
        "status": b.status,
        "portfolio": [portfolio_json(p, s) for p in b.portfolio],
        "profile_confirmed": b.profile_confirmed,
    }


def barber_card_json(b: Barber, s: UrlSigner) -> dict[str, Any]:
    area = get_area(b.area_id)
    thumb = b.portfolio[0].after_key if b.portfolio else None
    return {
        "id": b.id,
        "name": b.name,
        "tier": b.tier,
        "verified_jobs": b.verified_jobs,
        "rating": b.rating,
        "area_name": area.name if area else None,
        "styles": b.styles or [],
        "thumbnail_url": s.url(thumb),
    }


def quote_json(q: Quote, s: UrlSigner) -> dict[str, Any]:
    return {
        "id": q.id,
        "cut_name": q.cut_name,
        "minutes": q.minutes,
        "fit_issues": q.fit_issues or [],
        "reasons": q.reasons,
        "selfie_url": s.url(q.selfie_key),
        "reference_url": s.url(q.reference_key),
        "selfie_overlay_url": s.url(q.selfie_overlay_key),
        "reference_overlay_url": s.url(q.reference_overlay_key),
        "area_id": q.area_id,
        "elapsed_ms": q.elapsed_ms,
        "model_versions": q.model_versions,
    }


def evidence_json(e: Evidence, s: UrlSigner) -> dict[str, Any]:
    checks = {k: e.checks[k] for k in CHECK_ORDER if k in (e.checks or {})}
    return {
        "job_id": e.job_id,
        "before_url": s.url(e.before_key),
        "after_url": s.url(e.after_key),
        "before_overlay_url": s.url(e.before_overlay_key),
        "after_overlay_url": s.url(e.after_overlay_key),
        "checks": checks,
        "verdict": e.verdict,
        "verdict_reasons": e.verdict_reasons or [],
        "decided_by": e.decided_by,
        "operator_reason": e.operator_reason,
        "model_versions": e.model_versions,
        "elapsed_ms": e.elapsed_ms,
        "purged_at": iso(e.purged_at),
    }


def dispute_json(
    d: Dispute, s: UrlSigner | None = None, *, with_job: bool = False
) -> dict[str, Any]:
    out: dict[str, Any] = {
        "id": d.id,
        "job_id": d.job_id,
        "transcript": d.transcript,
        "summary": d.summary,
        "client_claim": d.client_claim,
        "evidence_notes": d.evidence_notes,
        "suggested_outcome": d.suggested_outcome,
        "outcome": d.outcome,
        "resolution_reason": d.resolution_reason,
        "model_versions": d.model_versions or {},
        "elapsed_ms": d.elapsed_ms,
        "created_at": iso(d.created_at),
        "resolved_at": iso(d.resolved_at),
    }
    if with_job and s is not None:
        out["job"] = job_json(d.job, s)
    return out


def latest_dispute(job: Job) -> Dispute | None:
    return job.disputes[-1] if job.disputes else None


def can_rate(job: Job) -> bool:
    return bool(job.evidence and job.evidence.verdict == "pass" and job.rating is None)


def job_json(j: Job, s: UrlSigner) -> dict[str, Any]:
    d = latest_dispute(j)
    return {
        "id": j.id,
        "status": j.status,
        "barber": {"id": j.barber.id, "name": j.barber.name, "tier": j.barber.tier},
        "client": {"id": j.client.id, "name": j.client.name},
        "cut": j.cut,
        "minutes": j.minutes,
        "quote_zar": j.quote_zar,
        "travel_band": j.travel_band,
        "slot_start": iso(j.slot_start),
        "slot_end": iso(j.slot_end),
        "address": j.address,
        "lat": j.lat,
        "lng": j.lng,
        "deposit_url": j.deposit_url,
        "payment_status": j.payment_status,
        "evidence": evidence_json(j.evidence, s) if j.evidence else None,
        "rating": {"stars": j.rating.stars, "comment": j.rating.comment} if j.rating else None,
        "dispute": dispute_json(d) if d else None,
        "can_rate": can_rate(j),
        "consented_demo": j.consented_demo,
        "cancelled_at": iso(j.cancelled_at),
        "cancelled_by": j.cancelled_by,
        "cancel_reason": j.cancel_reason,
        "rescheduled_at": iso(j.rescheduled_at),
        "reminder_sent_at": iso(j.reminder_sent_at),
    }


def payout_json(p: Payout) -> dict[str, Any]:
    return {
        "job_id": p.job_id,
        "barber_id": p.barber_id,
        "barber_name": p.barber.name,
        "amount_zar": p.amount_zar,
        "status": p.status,
        "created_at": iso(p.created_at),
    }


def notification_json(n: Notification) -> dict[str, Any]:
    return {
        "id": n.id,
        "job_id": n.job_id,
        "kind": n.kind,
        "title": n.title,
        "body": n.body,
        "created_at": iso(n.created_at),
        "read_at": iso(n.read_at),
    }
