"""Film-day seed, operator KPIs, barber detail and model latency fields."""

from __future__ import annotations

import asyncio
from datetime import datetime, timedelta
from typing import Any

import pytest
from fastapi.testclient import TestClient

from fadecall.config import Settings
from fadecall.main import create_app
from fadecall.samples import SKIN_TONES, head_image
from fadecall.seed import BARBERS, DEMO_CLIENT, DEMO_ONBOARDING_BARBER, demo_slot, seed_demo
from fadecall.timeutil import SAST

from .conftest import login
from .test_api_flow import OPS, img, proof, quote_and_book
from .test_review_fixes import passed_job, setup

NOW = datetime(2026, 11, 2, 9, 7, tzinfo=SAST)


def test_demo_slot_is_about_now_or_given_time() -> None:
    assert demo_slot(NOW) == datetime(2026, 11, 2, 8, 55, tzinfo=SAST)
    assert demo_slot(NOW, "14:30") == datetime(2026, 11, 2, 14, 30, tzinfo=SAST)


@pytest.fixture
def demo(settings: Settings) -> tuple[TestClient, dict[str, str]]:
    ids = asyncio.run(seed_demo(settings, lat=-26.01, lng=28.11))
    c = TestClient(create_app(settings))
    c.__enter__()
    yield c, ids  # type: ignore[misc]
    c.__exit__(None, None, None)


def test_demo_seed_film_day_set(demo: tuple[TestClient, dict[str, str]]) -> None:
    c, ids = demo
    oh = login(c, *OPS)
    s = c.get("/ops/summary", headers=oh).json()
    assert s["jobs_needs_review"] == 1 and s["open_disputes"] == 1
    assert s["verified_jobs"] >= 1

    # fresh barber and a barber one pair short of grading
    fresh = login(c, "barber", "Ayanda K", "+27825550101")
    me = c.get("/barbers/me", headers=fresh).json()
    assert me["status"] == "onboarding" and me["profile_confirmed"] is False
    almost = login(c, "barber", DEMO_ONBOARDING_BARBER[0], DEMO_ONBOARDING_BARBER[1])
    me = c.get("/barbers/me", headers=almost).json()
    assert me["profile_confirmed"] is True and len(me["portfolio"]) == 4 and me["tier"] is None

    # today's job: confirmed, deposit paid, at the given GPS, slot near now
    ch = login(c, "client", DEMO_CLIENT["name"], DEMO_CLIENT["phone"])
    job = c.get(f"/jobs/{ids['job_id']}", headers=ch).json()
    assert job["status"] == "confirmed" and job["payment_status"] == "deposit_paid"
    assert (job["lat"], job["lng"]) == (-26.01, 28.11)
    assert c.get(f"/quotes/{ids['quote_id']}/matches", headers=ch).status_code == 200

    # live capture "now" passes every check
    bh = login(c, "barber", BARBERS[0][0], BARBERS[0][1])
    skin = SKIN_TONES[2]
    now = datetime.now(SAST)
    for which, photo in (
        ("before", head_image(skin, "full", 5)),
        ("after", head_image(skin, "fade", 5)),
    ):
        r = c.post(
            f"/jobs/{job['id']}/proof/{which}",
            headers=bh,
            data={
                "captured_at": now.isoformat(),
                "lat": "-26.0101",
                "lng": "28.1101",
                "accuracy_m": "10",
                "capture_mode": "live",
            },
            files={"photo": ("p.jpg", photo)},
        )
        assert r.status_code == 200, r.text
    ev = r.json()
    assert ev["checks"]["before_timestamp"]["result"] == "pass"
    assert ev["checks"]["after_gps"]["result"] == "pass"
    assert ev["elapsed_ms"] is not None and ev["elapsed_ms"] >= 0


def test_summary_kpis(client: TestClient) -> None:
    c = client
    empty = c.get("/ops/summary", headers=login(c, *OPS)).json()
    assert empty["pass_rate"] is None and empty["avg_verdict_ms"] is None
    assert empty["jobs_total"] == 0 and empty["decided_jobs"] == 0

    oh, _, _, _ = passed_job(c)
    s = c.get("/ops/summary", headers=oh).json()
    assert s["jobs_total"] == 1 and s["verified_jobs"] == 1 and s["decided_jobs"] == 1
    assert s["pass_rate"] == 1.0
    assert isinstance(s["avg_verdict_ms"], int)
    assert s["payouts_released_zar"] > 0


def test_barber_detail_page(client: TestClient) -> None:
    c = client
    oh, bh, ch, job = passed_job(c)
    assert c.post(f"/jobs/{job['id']}/rating", headers=ch, json={"stars": 4}).status_code == 200
    barber_id = c.get("/barbers/me", headers=bh).json()["id"]

    r = c.get(f"/ops/barbers/{barber_id}", headers=oh)
    assert r.status_code == 200, r.text
    d: dict[str, Any] = r.json()
    assert d["barber"]["id"] == barber_id and len(d["barber"]["portfolio"]) == 5
    assert [j["id"] for j in d["jobs"]] == [job["id"]]
    assert d["ratings"][0]["stars"] == 4 and d["ratings"][0]["client_name"] == "Lerato"
    assert c.get(f"/ops/barbers/{barber_id}", headers=bh).status_code == 403
    assert c.get("/ops/barbers/not-a-uuid", headers=oh).status_code == 404


def test_ops_jobs_lists_every_status(client: TestClient) -> None:
    c = client
    oh, bh, ch, barber = setup(c)
    quote_and_book(c, ch, barber["id"])
    confirmed = quote_and_book(c, ch, barber["id"])
    c.post(f"/jobs/{confirmed['id']}/confirm", headers=bh)
    all_jobs = c.get("/ops/jobs", headers=oh).json()
    assert {j["status"] for j in all_jobs} == {"booked", "confirmed"}
    only = c.get("/ops/jobs", headers=oh, params={"status": "confirmed"}).json()
    assert [j["id"] for j in only] == [confirmed["id"]]


def test_latency_and_model_versions_on_ai_output(client: TestClient) -> None:
    c = client
    oh, bh, ch, job = passed_job(c)
    item = c.get("/barbers/me", headers=bh).json()["portfolio"][0]
    assert item["model_versions"] == {"spark": "mock"} and item["elapsed_ms"] is not None
    d = c.post(f"/jobs/{job['id']}/dispute", headers=ch, data={"text": "Uneven"}).json()
    assert d["model_versions"] == {"spark": "mock"} and d["elapsed_ms"] is not None
    listed = c.get("/ops/disputes", headers=oh).json()[0]
    assert listed["model_versions"] == {"spark": "mock"}


def test_needs_review_counts_against_pass_rate(client: TestClient) -> None:
    c = client
    oh, bh, ch, barber = setup(c)
    job = quote_and_book(c, ch, barber["id"])
    c.post(f"/jobs/{job['id']}/confirm", headers=bh)
    proof(c, bh, job, "before", img(2, "full", 5), 1)
    proof(c, bh, job, "after", img(2, "fade", 5), 40, capture_mode="upload_fallback")
    s = c.get("/ops/summary", headers=oh).json()
    assert s["decided_jobs"] == 1 and s["pass_rate"] == 0.0
    assert timedelta(milliseconds=s["avg_verdict_ms"]) < timedelta(minutes=1)
