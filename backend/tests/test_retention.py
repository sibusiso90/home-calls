"""Evidence retention: raw proof photos are purged after a final verdict."""

from __future__ import annotations

import asyncio
from datetime import timedelta
from typing import Any

from fastapi.testclient import TestClient

from fadecall.services.retention import purge_expired_evidence
from fadecall.timeutil import utcnow

from .conftest import login
from .test_api_flow import OPS, img, media_get, onboard_barber, proof, quote_and_book

URL_FIELDS = ("before_url", "after_url", "before_overlay_url", "after_overlay_url")


def purge(c: TestClient, days_ahead: float) -> list[str]:
    state: Any = c.app.state  # type: ignore[attr-defined]
    with state.sessionmaker() as db:
        return asyncio.run(
            purge_expired_evidence(db, state.storage, 7, now=utcnow() + timedelta(days=days_ahead))
        )


def setup(c: TestClient) -> tuple[dict[str, str], dict[str, str], dict[str, str], dict[str, Any]]:
    oh = login(c, *OPS)
    bh, barber = onboard_barber(c, oh, "Thabo", "+27821234567", "midrand-central")
    ch = login(c, "client", "Lerato", "+27831234567")
    return oh, bh, ch, barber


def run_job(
    c: TestClient, bh: dict[str, str], ch: dict[str, str], barber_id: str, *, review: bool = False
) -> dict[str, Any]:
    job = quote_and_book(c, ch, barber_id)
    c.post(f"/jobs/{job['id']}/confirm", headers=bh)
    assert proof(c, bh, job, "before", img(2, "full", 5), 1).status_code == 200
    after = img(4, "fade", 77) if review else img(2, "fade", 5)
    ev = proof(c, bh, job, "after", after, 40).json()
    assert ev["verdict"] == ("needs_review" if review else "pass")
    return ev


def test_purges_pass_after_window(client: TestClient) -> None:
    c = client
    _, bh, ch, barber = setup(c)
    ev = run_job(c, bh, ch, barber["id"])
    old_url = ev["after_url"]
    assert purge(c, 1) == []  # still inside the 7-day window
    assert purge(c, 8) == [ev["job_id"]]
    got = c.get(f"/jobs/{ev['job_id']}", headers=ch).json()["evidence"]
    assert all(got[f] is None for f in URL_FIELDS)
    assert got["purged_at"] is not None
    assert got["verdict"] == "pass" and got["checks"]["hair_changed"]["result"] == "pass"
    assert media_get(c, old_url).status_code == 404  # file deleted from storage
    assert purge(c, 9) == []  # idempotent


def test_skips_open_dispute_until_resolved(client: TestClient) -> None:
    c = client
    oh, bh, ch, barber = setup(c)
    ev = run_job(c, bh, ch, barber["id"])
    d = c.post(f"/jobs/{ev['job_id']}/dispute", headers=ch, data={"text": "Uneven"}).json()
    assert purge(c, 8) == []
    assert c.get(f"/jobs/{ev['job_id']}", headers=ch).json()["evidence"]["after_url"]
    c.post(f"/ops/disputes/{d['id']}/resolve", headers=oh, json={"outcome": "release"})
    assert purge(c, 8) == [ev["job_id"]]


def test_skips_consented_demo(client: TestClient) -> None:
    c = client
    oh, bh, ch, barber = setup(c)
    ev = run_job(c, bh, ch, barber["id"])
    r = c.post(
        f"/ops/jobs/{ev['job_id']}/consented-demo", headers=oh, json={"consented_demo": True}
    )
    assert r.status_code == 200 and r.json()["consented_demo"] is True
    assert (
        c.post(
            f"/ops/jobs/{ev['job_id']}/consented-demo", headers=ch, json={"consented_demo": True}
        ).status_code
        == 403
    )
    assert purge(c, 30) == []
    assert (
        media_get(
            c, c.get(f"/jobs/{ev['job_id']}", headers=ch).json()["evidence"]["after_url"]
        ).status_code
        == 200
    )


def test_skips_needs_review_until_operator_decides(client: TestClient) -> None:
    c = client
    oh, bh, ch, barber = setup(c)
    ev = run_job(c, bh, ch, barber["id"], review=True)
    assert purge(c, 30) == []
    c.post(
        f"/ops/jobs/{ev['job_id']}/verdict",
        headers=oh,
        json={"verdict": "fail", "reason": "Different client"},
    )
    assert purge(c, 1) == []
    assert purge(c, 8) == [ev["job_id"]]
