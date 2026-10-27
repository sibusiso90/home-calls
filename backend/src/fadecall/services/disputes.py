"""Client disputes (voice note → case summary) and operator resolution."""

from __future__ import annotations

from typing import Literal

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..ai import prompts as P
from ..ai.types import ModelClient
from ..audio import to_wav
from ..config import Settings
from ..errors import conflict, validation
from ..models import Dispute, Job, Payout
from ..timeutil import iso, utcnow
from .effects import has_open_dispute
from .notifications import barber_uid, client_uid, notify, operator_uids

Outcome = Literal["release", "refund", "partial_refund"]


async def open_dispute(
    db: Session,
    models: ModelClient,
    settings: Settings,
    job: Job,
    audio: bytes | None,
    text: str | None,
) -> Dispute:
    if job.status in ("booked", "cancelled"):
        raise conflict(f"Cannot dispute a job that is {job.status}")
    if has_open_dispute(job):
        raise conflict("This job already has an open dispute")
    if not audio and not (text and text.strip()):
        raise validation("Send a voice note (audio) or text")
    transcript = ""
    versions: dict[str, str] = {"spark": models.versions["spark"]}
    if audio:
        wav = await to_wav(audio, settings.ffmpeg_path, required=models.mode == "live")
        t = await models.transcribe(
            wav, P.TRANSCRIBE_LANGUAGE_BIAS, P.TRANSCRIBE_KEYWORDS, purpose="dispute"
        )
        transcript = t.text
        versions["transcribe"] = models.versions["transcribe"]
    checks = job.evidence.checks if job.evidence else {}
    context = {
        "cut": job.cut,
        "minutes": job.minutes,
        "quote_zar": job.quote_zar,
        "slot_start": iso(job.slot_start),
        "status": job.status,
        "verdict": job.evidence.verdict if job.evidence else None,
    }
    data = await models.spark_json(
        P.DISPUTE_SYSTEM,
        P.dispute_user_text(transcript, text, context, checks),
        [],
        P.DISPUTE_SCHEMA,
        P.DISPUTE_NAME,
    )
    suggested = data.get("suggested_outcome")
    dispute = Dispute(
        job_id=job.id,
        transcript=transcript,
        summary=str(data.get("summary", "")),
        client_claim=str(data.get("client_claim", text or "")),
        evidence_notes=str(data.get("evidence_notes", "")),
        suggested_outcome=suggested
        if suggested in ("release", "refund", "partial_refund")
        else None,
        payment_status_before=job.payment_status,
        model_versions=versions,
    )
    db.add(dispute)
    notify(
        db,
        [barber_uid(job)],
        "dispute_opened",
        "Client reported a problem",
        f"{job.client.name} disputed {job.cut}. Your payout is on hold while an operator reviews.",
        job,
    )
    notify(
        db,
        operator_uids(db),
        "dispute_opened",
        "New dispute",
        dispute.summary[:200] or f"{job.client.name} disputed {job.cut}.",
        job,
    )
    notify(
        db,
        [client_uid(job)],
        "dispute_opened",
        "We got your report",
        "An operator will review it with the photos.",
        job,
    )
    job.payment_status = "held"
    for p in db.scalars(select(Payout).where(Payout.job_id == job.id)):
        if p.status == "released":
            p.status = "held"
    db.commit()
    db.refresh(job)
    return dispute


def resolve_dispute(db: Session, dispute: Dispute, outcome: Outcome, reason: str) -> Dispute:
    if dispute.outcome is not None:
        raise conflict("Dispute is already resolved")
    job = dispute.job
    verdict_pass = bool(job.evidence and job.evidence.verdict == "pass")
    payouts = list(db.scalars(select(Payout).where(Payout.job_id == job.id)))
    if outcome == "release":
        # Only a pass verdict releases money; otherwise the deposit stays put
        # until an operator verdict passes the job.
        before = dispute.payment_status_before
        job.payment_status = (
            "released"
            if verdict_pass
            else (before if before not in (None, "held") else "deposit_paid")
        )
        for p in payouts:
            if p.status == "held":
                p.status = "released"
    elif outcome == "refund":
        job.payment_status = "refunded"
        for p in payouts:
            p.status = "reversed"
    else:  # partial_refund: barber keeps half
        job.payment_status = "partially_refunded"
        for p in payouts:
            if p.status in ("held", "released"):
                p.amount_zar = p.amount_zar // 2
                p.status = "released" if verdict_pass else "reversed"
    dispute.outcome = outcome
    dispute.resolution_reason = reason
    dispute.resolved_at = utcnow()
    label = {
        "release": "payment released to the barber",
        "refund": "full refund to the client",
        "partial_refund": "partial refund",
    }[outcome]
    notify(
        db,
        [client_uid(job), barber_uid(job)],
        "dispute_resolved",
        "Dispute resolved",
        f"Outcome: {label}." + (f" {reason}" if reason else ""),
        job,
    )
    db.commit()
    return dispute
