"""Regression tests for the independent review findings (one section per finding)."""

from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import json
from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from fadecall.ai.mock import MockModelClient
from fadecall.auth import read_token
from fadecall.config import Settings
from fadecall.errors import ApiError
from fadecall.models import Job, Payout
from fadecall.services.effects import apply_verdict
from fadecall.services.proof import Capture, capture_after
from fadecall.timeutil import parse_iso

from .conftest import login, make_settings
from .test_api_flow import OPS, img, onboard_barber, proof, quote_and_book


def setup(c: TestClient) -> tuple[dict[str, str], dict[str, str], dict[str, str], dict[str, Any]]:
    oh = login(c, *OPS)
    bh, barber = onboard_barber(c, oh, "Thabo", "+27821234567", "midrand-central")
    ch = login(c, "client", "Lerato", "+27831234567")
    return oh, bh, ch, barber


def ready_for_after(
    c: TestClient,
) -> tuple[dict[str, str], dict[str, str], dict[str, str], dict[str, Any]]:
    oh, bh, ch, barber = setup(c)
    job = quote_and_book(c, ch, barber["id"])
    c.post(f"/jobs/{job['id']}/confirm", headers=bh)
    assert proof(c, bh, job, "before", img(2, "full", 5), 1).status_code == 200
    return oh, bh, ch, job


def passed_job(
    c: TestClient,
) -> tuple[dict[str, str], dict[str, str], dict[str, str], dict[str, Any]]:
    oh, bh, ch, job = ready_for_after(c)
    assert proof(c, bh, job, "after", img(2, "fade", 5), 40).json()["verdict"] == "pass"
    return oh, bh, ch, job


def state(c: TestClient) -> Any:
    return c.app.state  # type: ignore[attr-defined]


# 1. Double payout race ---------------------------------------------------------


def test_concurrent_after_uploads_apply_pass_once(client: TestClient, settings: Settings) -> None:
    c = client
    *_, job = ready_for_after(c)
    st = state(c)
    slow = MockModelClient(settings.model_copy(update={"mock_latency_ms": 50}))
    slot = parse_iso(job["slot_start"])
    cap = Capture(slot, job["lat"], job["lng"], 5.0)
    photo = img(2, "fade", 5)

    async def race() -> list[Any]:
        with st.sessionmaker() as s1, st.sessionmaker() as s2:
            j1, j2 = s1.get(Job, job["id"]), s2.get(Job, job["id"])
            _ = (j1.evidence, j2.evidence)  # both loaded while still in_progress
            return await asyncio.gather(
                capture_after(s1, slow, st.storage, j1, photo, cap),
                capture_after(s2, slow, st.storage, j2, photo, cap),
                return_exceptions=True,
            )

    results = asyncio.run(race())
    conflicts = [r for r in results if isinstance(r, ApiError)]
    assert len(conflicts) == 1 and conflicts[0].status == 409
    with st.sessionmaker() as db:
        payouts = list(db.scalars(select(Payout).where(Payout.job_id == job["id"])))
        j = db.get(Job, job["id"])
        assert len(payouts) == 1
        assert j.status == "verified" and j.barber.verified_jobs == 1


def test_apply_verdict_never_adds_second_live_payout(client: TestClient) -> None:
    c = client
    _, _, _, job = passed_job(c)
    with state(c).sessionmaker() as db:
        j = db.get(Job, job["id"])
        j.evidence.verdict = None  # simulate a racing pipeline that missed the pass
        apply_verdict(db, j, "pass", [], "model")
        db.commit()
        live = [
            p
            for p in db.scalars(select(Payout).where(Payout.job_id == j.id))
            if p.status != "reversed"
        ]
        assert len(live) == 1


def test_db_unique_index_blocks_two_live_payouts(client: TestClient) -> None:
    c = client
    _, _, _, job = passed_job(c)
    with state(c).sessionmaker() as db:
        j = db.get(Job, job["id"])
        db.add(Payout(job_id=j.id, barber_id=j.barber_id, amount_zar=1, status="released"))
        with pytest.raises(IntegrityError):
            db.commit()


# 2. Deposit must be paid -------------------------------------------------------


def test_before_photo_requires_paid_deposit(client: TestClient) -> None:
    c = client
    _, bh, ch, barber = setup(c)
    job = quote_and_book(c, ch, barber["id"], pay_deposit=False)
    c.post(f"/jobs/{job['id']}/confirm", headers=bh)
    r = proof(c, bh, job, "before", img(2, "full", 5), 1)
    assert r.status_code == 409
    assert r.json()["error"] == {"code": "conflict", "message": "Deposit not paid yet"}


def test_pass_never_releases_unpaid_deposit(client: TestClient) -> None:
    c = client
    oh, bh, ch, barber = setup(c)
    job = quote_and_book(c, ch, barber["id"], pay_deposit=False)
    c.post(f"/jobs/{job['id']}/confirm", headers=bh)
    v = c.post(
        f"/ops/jobs/{job['id']}/verdict", headers=oh, json={"verdict": "pass", "reason": "x"}
    )
    assert v.json()["payment_status"] == "deposit_pending"
    assert c.get("/ops/payouts", headers=oh).json() == []


# 3. Refunded job can't be paid out by a later pass ------------------------------


def test_refund_then_operator_pass_moves_no_money(client: TestClient) -> None:
    c = client
    oh, _, ch, job = passed_job(c)
    d = c.post(f"/jobs/{job['id']}/dispute", headers=ch, data={"text": "Bad cut"}).json()
    c.post(f"/ops/disputes/{d['id']}/resolve", headers=oh, json={"outcome": "refund"})
    c.post(f"/ops/jobs/{job['id']}/verdict", headers=oh, json={"verdict": "fail", "reason": "a"})
    v = c.post(
        f"/ops/jobs/{job['id']}/verdict", headers=oh, json={"verdict": "pass", "reason": "b"}
    )
    assert v.json()["payment_status"] == "refunded"
    assert all(p["status"] == "reversed" for p in c.get("/ops/payouts", headers=oh).json())
    assert c.get("/ops/summary", headers=oh).json()["payouts_released_zar"] == 0


# 4. Never stuck in 'verifying' ---------------------------------------------------


def test_null_confidence_is_handled(client: TestClient, monkeypatch: pytest.MonkeyPatch) -> None:
    c = client
    _, bh, _, job = ready_for_after(c)
    models = state(c).models
    real = models.spark_json

    async def null_conf(*args: Any, **kwargs: Any) -> dict[str, Any]:
        out = await real(*args, **kwargs)
        return {**out, "confidence": None, "reason": None}

    monkeypatch.setattr(models, "spark_json", null_conf)
    r = proof(c, bh, job, "after", img(2, "fade", 5), 40)
    assert r.status_code == 200, r.text
    ev = r.json()
    assert ev["checks"]["same_person"]["confidence"] == 0.0
    assert ev["verdict"] == "needs_review"


def test_unexpected_error_resets_to_in_progress(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    c = client
    _, bh, ch, job = ready_for_after(c)
    models = state(c).models

    async def boom(_: bytes) -> Any:
        raise RuntimeError("unexpected")

    with monkeypatch.context() as m:
        m.setattr(models, "segment_hair", boom)
        with pytest.raises(RuntimeError):
            proof(c, bh, job, "after", img(2, "fade", 5), 40)
    assert c.get(f"/jobs/{job['id']}", headers=ch).json()["status"] == "in_progress"
    assert proof(c, bh, job, "after", img(2, "fade", 5), 40).json()["verdict"] == "pass"


# 5. No default secrets outside dev ----------------------------------------------


def test_prod_refuses_default_secrets(tmp_path: Path) -> None:
    with pytest.raises(ValidationError, match="SECRET_KEY and OPERATOR_PASSCODE"):
        Settings(_env_file=None, env="prod")  # type: ignore[call-arg]
    with pytest.raises(ValidationError, match="OPERATOR_PASSCODE"):
        Settings(_env_file=None, env="prod", secret_key="x" * 32, operator_passcode="")  # type: ignore[call-arg]
    ok = make_settings(tmp_path, env="prod", secret_key="x" * 32, operator_passcode="s3cret")
    assert ok.env == "prod"
    assert Settings(_env_file=None).env == "dev"  # type: ignore[call-arg]


# 6. Non-ASCII signatures / bad exp -> 403/401, never 500 ---------------------------


def test_non_ascii_media_signature_is_403(client: TestClient) -> None:
    r = client.get("/media/a.png", params={"exp": 9999999999, "sig": "é"})
    assert r.status_code == 403


def test_non_ascii_or_malformed_token_is_401(client: TestClient) -> None:
    assert read_token("s", "abc.é") is None
    # Servers decode raw header bytes as latin-1, so non-ASCII reaches the verifier.
    r = client.get("/me", headers={"Authorization": "Bearer abc.é".encode("latin-1")})
    assert r.status_code == 401 and r.json()["error"]["code"] == "unauthorized"
    secret = "s"
    payload = base64.urlsafe_b64encode(json.dumps({"sub": "u", "exp": "soon"}).encode()).rstrip(
        b"="
    )
    sig = base64.urlsafe_b64encode(
        hmac.new(secret.encode(), payload, hashlib.sha256).digest()
    ).rstrip(b"=")
    assert read_token(secret, f"{payload.decode()}.{sig.decode()}") is None


# 7. Reversing a pass removes the rating ---------------------------------------------


def test_reversal_removes_rating_and_recomputes(client: TestClient) -> None:
    c = client
    oh, bh, ch, job = passed_job(c)
    assert c.post(f"/jobs/{job['id']}/rating", headers=ch, json={"stars": 2}).status_code == 200
    assert c.get("/barbers/me", headers=bh).json()["rating"] == 2.0
    v = c.post(
        f"/ops/jobs/{job['id']}/verdict", headers=oh, json={"verdict": "fail", "reason": "x"}
    ).json()
    assert v["rating"] is None and v["can_rate"] is False
    me = c.get("/barbers/me", headers=bh).json()
    assert me["rating"] is None and me["verified_jobs"] == 0
