"""Full demo flow through the HTTP API in mock mode."""

from __future__ import annotations

from collections.abc import Callable
from datetime import datetime, timedelta
from typing import Any

from fastapi.testclient import TestClient

from fadecall.samples import SKIN_TONES, head_image, sine_wav

from .conftest import login

OPS = ("operator", "Ops", "+27100000000", "letmein")


def img(skin: int, style: str, seed: int) -> bytes:
    return head_image(SKIN_TONES[skin], style, seed)  # type: ignore[arg-type]


def media_get(c: TestClient, url: str) -> Any:
    return c.get(url[url.index("/media/") :])


def onboard_barber(
    c: TestClient, ops: dict[str, str], name: str, phone: str, area: str
) -> tuple[dict[str, str], dict[str, Any]]:
    h = login(c, "barber", name, phone)
    r = c.put(
        "/barbers/me/profile",
        headers=h,
        json={
            "name": name,
            "area_id": area,
            "years_cutting": 5,
            "styles": ["taper"],
            "languages": ["English"],
            "availability": "Weekdays",
        },
    )
    assert r.status_code == 200, r.text
    for i in range(5):
        r = c.post(
            "/barbers/me/portfolio",
            headers=h,
            files={
                "before": ("b.jpg", img(i, "full", 50 + i)),
                "after": ("a.jpg", img(i, "fade", 50 + i)),
            },
        )
        assert r.status_code == 200, r.text
    assert c.post("/barbers/me/grade", headers=h).status_code == 200
    barber = c.get("/barbers/me", headers=h).json()
    assert (
        c.post(
            f"/ops/barbers/{barber['id']}/approve", headers=ops, json={"reason": "ok"}
        ).status_code
        == 200
    )
    return h, barber


def quote_and_book(
    c: TestClient,
    ch: dict[str, str],
    barber_id: str,
    area: str = "midrand-central",
    *,
    pay_deposit: bool = True,
) -> dict[str, Any]:
    q = c.post(
        "/quotes",
        headers=ch,
        data={"area_id": area},
        files={"selfie": ("s.jpg", img(1, "full", 3)), "reference": ("r.jpg", img(3, "fade", 4))},
    )
    assert q.status_code == 200, q.text
    matches = c.get(f"/quotes/{q.json()['id']}/matches", headers=ch).json()
    m = next(m for m in matches if m["barber"]["id"] == barber_id)
    job = c.post(
        "/jobs",
        headers=ch,
        json={
            "quote_id": q.json()["id"],
            "barber_id": barber_id,
            "slot_start": m["next_slot"],
            "address": "12 Example Rd, Midrand",
            "lat": -25.99,
            "lng": 28.12,
        },
    )
    assert job.status_code == 200, job.text
    if pay_deposit:
        paid = c.post(f"/jobs/{job.json()['id']}/pay-deposit", headers=ch)
        assert paid.json()["payment_status"] == "deposit_paid"
    return job.json()


def proof(
    c: TestClient,
    bh: dict[str, str],
    job: dict[str, Any],
    which: str,
    photo: bytes,
    minutes: int,
    **extra: str,
) -> Any:
    slot = datetime.fromisoformat(job["slot_start"])
    data = {
        "captured_at": (slot + timedelta(minutes=minutes)).isoformat(),
        "lat": str(job["lat"] + 0.0002),
        "lng": str(job["lng"]),
        "accuracy_m": "12",
        "capture_mode": "live",
    }
    data.update(extra)
    return c.post(
        f"/jobs/{job['id']}/proof/{which}", headers=bh, data=data, files={"photo": ("p.jpg", photo)}
    )


def test_full_flow(client: TestClient) -> None:
    c = client
    assert c.get("/health").json()["mode"] == "mock"
    assert len(c.get("/areas").json()) == 12

    # --- barber onboarding ------------------------------------------------
    bh = login(c, "barber", "Thabo", "+27821234567")
    again = c.post(
        "/auth/demo-login", json={"role": "barber", "name": "Thabo", "phone": "082 123 4567"}
    )
    assert again.json()["user"]["id"] == c.get("/me", headers=bh).json()["id"]
    me = c.get("/barbers/me", headers=bh).json()
    assert me["status"] == "onboarding" and me["tier"] is None and me["profile_confirmed"] is False

    vn = c.post("/barbers/me/voice-note", headers=bh, files={"audio": ("note.wav", sine_wav())})
    assert vn.status_code == 200, vn.text
    vj = vn.json()
    assert set(vj) >= {"transcript", "language_detected", "profile", "read_back", "model_versions"}
    assert vj["profile"]["area_id"] in {a["id"] for a in c.get("/areas").json()}
    assert vj["read_back"].startswith("You are")
    assert c.get("/barbers/me", headers=bh).json()["profile_confirmed"] is False  # not saved yet

    profile = {**vj["profile"], "area_id": "midrand-central"}
    r = c.put("/barbers/me/profile", headers=bh, json=profile)
    assert r.status_code == 200 and r.json()["profile_confirmed"] is True
    assert (
        c.put("/barbers/me/profile", headers=bh, json={**profile, "area_id": "joburg"}).status_code
        == 422
    )

    g = c.post("/barbers/me/grade", headers=bh)
    assert g.status_code == 409 and g.json()["error"]["code"] == "conflict"

    items = []
    for i in range(6):
        r = c.post(
            "/barbers/me/portfolio",
            headers=bh,
            files={
                "before": ("b.jpg", img(i % 5, "full", i)),
                "after": ("a.jpg", img(i % 5, "fade", i)),
            },
        )
        assert r.status_code == 200, r.text
        items.append(r.json())
    it = items[0]
    assert set(it["scores"]) == {"fade_blend", "line_up", "symmetry", "finish"}
    assert set(it["reasons"]) == set(it["scores"]) and it["model_versions"] == {"spark": "mock"}
    assert media_get(c, it["after_url"]).status_code == 200
    assert c.delete(f"/barbers/me/portfolio/{items[-1]['id']}", headers=bh).status_code == 200
    assert c.delete("/barbers/me/portfolio/not-a-uuid", headers=bh).status_code == 404

    g = c.post("/barbers/me/grade", headers=bh)
    assert g.status_code == 200, g.text
    gj = g.json()
    assert gj["tier"] in ("starter", "pro", "elite") and gj["summary"]
    assert gj["barber"]["status"] == "pending_approval"
    assert gj["barber"]["price_band"]["min_zar"] in (250, 320, 420)
    barber_id = gj["barber"]["id"]

    # --- operator approval --------------------------------------------------
    bad = c.post("/auth/demo-login", json={"role": "operator", "name": "Ops", "passcode": "nope"})
    assert bad.status_code == 401 and bad.json()["error"]["code"] == "unauthorized"
    oh = login(c, *OPS)
    assert c.get("/ops/summary", headers=bh).status_code == 403
    assert c.get("/ops/summary", headers=oh).json()["barbers_pending"] == 1
    pending = c.get("/ops/barbers", headers=oh, params={"status": "pending_approval"}).json()
    assert [b["id"] for b in pending] == [barber_id]
    assert (
        c.post(
            f"/ops/barbers/{barber_id}/approve", headers=oh, json={"reason": "Good blends"}
        ).json()["status"]
        == "approved"
    )

    # --- client quote, match, book -----------------------------------------
    ch = login(c, "client", "Lerato", "+27831234567")
    q = c.post(
        "/quotes",
        headers=ch,
        data={"area_id": "midrand-central"},
        files={"selfie": ("s.jpg", img(1, "full", 3)), "reference": ("r.jpg", img(3, "fade", 4))},
    )
    assert q.status_code == 200, q.text
    qj = q.json()
    assert qj["cut_name"] and qj["minutes"] > 0 and isinstance(qj["fit_issues"], list)
    assert qj["model_versions"] == {"spark": "mock", "sam": "mock"}
    ov = media_get(c, qj["selfie_overlay_url"])
    assert ov.status_code == 200 and ov.content.startswith(b"\x89PNG")
    assert c.get(f"/quotes/{qj['id']}/matches", headers=bh).status_code == 403

    matches = c.get(f"/quotes/{qj['id']}/matches", headers=ch).json()
    assert len(matches) == 1
    m = matches[0]
    assert m["barber"]["id"] == barber_id and m["travel_band"] == "A"
    assert (
        m["price"]["total_zar"]
        == m["price"]["tier_rate_zar"] + m["price"]["time_zar"] + m["price"]["travel_zar"]
    )
    assert m["next_slot"] and 0 <= m["score"] <= 1

    booking = {
        "quote_id": qj["id"],
        "barber_id": barber_id,
        "slot_start": m["next_slot"],
        "address": "12 Example Rd, Midrand",
        "lat": -25.99,
        "lng": 28.12,
    }
    jr = c.post("/jobs", headers=ch, json=booking)
    assert jr.status_code == 200, jr.text
    job = jr.json()
    assert job["status"] == "booked" and job["deposit_url"].startswith("https://pay.example/mock/")
    assert job["payment_status"] == "deposit_pending" and job["can_rate"] is False
    assert job["quote_zar"] == m["price"]["total_zar"]
    assert c.post("/jobs", headers=ch, json=booking).status_code == 409  # slot taken
    next_matches = c.get(f"/quotes/{qj['id']}/matches", headers=ch).json()
    assert next_matches[0]["next_slot"] != m["next_slot"]

    assert (
        c.post(f"/jobs/{job['id']}/pay-deposit", headers=ch).json()["payment_status"]
        == "deposit_paid"
    )

    # --- barber confirms; proof of job ---------------------------------------
    assert proof(c, bh, job, "before", img(1, "full", 11), 2).status_code == 409  # not confirmed
    assert c.post(f"/jobs/{job['id']}/confirm", headers=ch).status_code == 403
    assert c.post(f"/jobs/{job['id']}/confirm", headers=bh).json()["status"] == "confirmed"

    before = proof(c, bh, job, "before", img(1, "full", 11), 2)
    assert before.status_code == 200, before.text
    bj = before.json()
    assert set(bj["checks"]) == {"before_timestamp", "before_gps"}
    assert bj["checks"]["before_timestamp"]["result"] == "pass"
    assert bj["verdict"] is None and bj["after_url"] is None

    early = c.post(f"/jobs/{job['id']}/rating", headers=ch, json={"stars": 5, "comment": "x"})
    assert early.status_code == 409 and early.json()["error"]["code"] == "verdict_required"

    after = proof(c, bh, job, "after", img(1, "fade", 11), 55)
    assert after.status_code == 200, after.text
    ev = after.json()
    assert list(ev["checks"]) == [
        "before_timestamp",
        "before_gps",
        "after_timestamp",
        "after_gps",
        "same_person",
        "hair_changed",
        "cut_match",
    ]
    assert ev["checks"]["hair_changed"]["change_ratio"] >= 0.10
    assert "confidence" in ev["checks"]["same_person"]
    assert ev["verdict"] == "pass", ev
    assert ev["decided_by"] == "model" and ev["verdict_reasons"] == []
    assert media_get(c, ev["after_overlay_url"]).status_code == 200

    jd = c.get(f"/jobs/{job['id']}", headers=ch).json()
    assert (
        jd["status"] == "verified" and jd["payment_status"] == "released" and jd["can_rate"] is True
    )
    assert c.get("/barbers/me", headers=bh).json()["verified_jobs"] == 1
    payouts = c.get("/ops/payouts", headers=oh).json()
    assert payouts[0]["job_id"] == job["id"] and payouts[0]["status"] == "released"
    assert payouts[0]["amount_zar"] == job["quote_zar"] and payouts[0]["barber_name"]

    # --- rating ---------------------------------------------------------------
    rr = c.post(f"/jobs/{job['id']}/rating", headers=ch, json={"stars": 5, "comment": "Sharp!"})
    assert rr.status_code == 200 and rr.json() == {"stars": 5, "comment": "Sharp!"}
    assert c.post(f"/jobs/{job['id']}/rating", headers=ch, json={"stars": 4}).status_code == 409
    assert c.get("/barbers/me", headers=bh).json()["rating"] == 5.0
    assert c.get(f"/jobs/{job['id']}", headers=ch).json()["can_rate"] is False

    # --- dispute + resolution -------------------------------------------------
    d = c.post(
        f"/jobs/{job['id']}/dispute",
        headers=ch,
        data={"text": "Left side is higher"},
        files={"audio": ("c.wav", sine_wav(1.0, 330.0))},
    )
    assert d.status_code == 200, d.text
    dj = d.json()
    assert dj["transcript"] and dj["summary"] and dj["outcome"] is None
    assert dj["suggested_outcome"] in ("release", "refund", "partial_refund")
    assert c.get(f"/jobs/{job['id']}", headers=ch).json()["payment_status"] == "held"
    assert c.get("/ops/summary", headers=oh).json()["open_disputes"] == 1
    assert c.get("/ops/summary", headers=oh).json()["payouts_released_zar"] == 0
    listed = c.get("/ops/disputes", headers=oh).json()
    assert listed[0]["id"] == dj["id"] and listed[0]["job"]["id"] == job["id"]

    res = c.post(
        f"/ops/disputes/{dj['id']}/resolve",
        headers=oh,
        json={"outcome": "release", "reason": "Evidence is clean"},
    )
    assert res.status_code == 200, res.text
    assert res.json()["outcome"] == "release" and res.json()["job"]["payment_status"] == "released"
    s = c.get("/ops/summary", headers=oh).json()
    assert s["open_disputes"] == 0 and s["payouts_released_zar"] == job["quote_zar"]
    assert (
        c.post(
            f"/ops/disputes/{dj['id']}/resolve", headers=oh, json={"outcome": "refund"}
        ).status_code
        == 409
    )

    # job lists are scoped per role
    assert len(c.get("/jobs", headers=bh).json()) == 1
    other = login(c, "client", "Zanele", "+27839999999")
    assert c.get("/jobs", headers=other).json() == []
    assert c.get(f"/jobs/{job['id']}", headers=other).status_code == 403


def test_needs_review_then_operator_pass(client: TestClient) -> None:
    c = client
    oh = login(c, *OPS)
    bh, barber = onboard_barber(c, oh, "Sipho", "+27822345678", "halfway-house")
    ch = login(c, "client", "Lerato", "+27831234567")
    job = quote_and_book(c, ch, barber["id"])
    c.post(f"/jobs/{job['id']}/confirm", headers=bh)
    assert proof(c, bh, job, "before", img(2, "full", 5), 1).status_code == 200
    # after photo shows a different person -> same_person not pass -> needs_review
    ev = proof(c, bh, job, "after", img(4, "fade", 77), 50).json()
    assert ev["verdict"] == "needs_review"
    assert ev["checks"]["same_person"]["result"] in ("uncertain", "fail")
    assert any(r.startswith("same_person") for r in ev["verdict_reasons"])

    jd = c.get(f"/jobs/{job['id']}", headers=ch).json()
    assert (
        jd["status"] == "needs_review"
        and jd["payment_status"] != "released"
        and jd["can_rate"] is False
    )
    assert (
        c.post(f"/jobs/{job['id']}/rating", headers=ch, json={"stars": 5}).json()["error"]["code"]
        == "verdict_required"
    )

    queue = c.get("/ops/jobs", headers=oh, params={"status": "needs_review"}).json()
    assert [j["id"] for j in queue] == [job["id"]] and queue[0]["evidence"]["checks"]
    assert c.get("/ops/summary", headers=oh).json()["jobs_needs_review"] == 1

    v = c.post(
        f"/ops/jobs/{job['id']}/verdict",
        headers=oh,
        json={"verdict": "pass", "reason": "Same client, new lighting"},
    )
    assert v.status_code == 200, v.text
    vj = v.json()
    assert (
        vj["status"] == "verified" and vj["payment_status"] == "released" and vj["can_rate"] is True
    )
    assert vj["evidence"]["decided_by"] == "operator" and vj["evidence"]["verdict"] == "pass"
    assert vj["evidence"]["operator_reason"] == "Same client, new lighting"
    assert c.get("/barbers/me", headers=bh).json()["verified_jobs"] == 1
    assert c.post(f"/jobs/{job['id']}/rating", headers=ch, json={"stars": 4}).status_code == 200
    # passing again must not double-apply effects
    c.post(
        f"/ops/jobs/{job['id']}/verdict", headers=oh, json={"verdict": "pass", "reason": "again"}
    )
    assert c.get("/barbers/me", headers=bh).json()["verified_jobs"] == 1
    assert len(c.get("/ops/payouts", headers=oh).json()) == 1


def test_upload_fallback_and_missing_gps_need_review(client: TestClient) -> None:
    c = client
    oh = login(c, *OPS)
    bh, barber = onboard_barber(c, oh, "Kabelo", "+27823456789", "midrand-central")
    ch = login(c, "client", "Lerato", "+27831234567")
    job = quote_and_book(c, ch, barber["id"])
    c.post(f"/jobs/{job['id']}/confirm", headers=bh)
    b = proof(c, bh, job, "before", img(2, "full", 5), 1, lat="", lng="", accuracy_m="")
    assert b.json()["checks"]["before_gps"]["result"] == "uncertain"
    ev = proof(c, bh, job, "after", img(2, "fade", 5), 40, capture_mode="upload_fallback").json()
    assert ev["verdict"] == "needs_review"
    assert "after photo used upload_fallback" in ev["verdict_reasons"]
    assert "before_gps uncertain" in ev["verdict_reasons"]


def test_operator_fail_and_refund(client: TestClient) -> None:
    c = client
    oh = login(c, *OPS)
    bh, barber = onboard_barber(c, oh, "Neo", "+27824567890", "midrand-central")
    ch = login(c, "client", "Lerato", "+27831234567")
    job = quote_and_book(c, ch, barber["id"])
    c.post(f"/jobs/{job['id']}/confirm", headers=bh)
    proof(c, bh, job, "before", img(2, "full", 5), 1)
    same = img(2, "full", 5)
    ev = proof(c, bh, job, "after", same, 40).json()  # no visible change
    assert ev["checks"]["hair_changed"]["result"] == "fail" and ev["verdict"] == "needs_review"
    v = c.post(
        f"/ops/jobs/{job['id']}/verdict",
        headers=oh,
        json={"verdict": "fail", "reason": "No cut done"},
    ).json()
    assert v["status"] == "failed" and v["payment_status"] != "released"
    d = c.post(
        f"/jobs/{job['id']}/dispute", headers=ch, data={"text": "He never cut my hair"}
    ).json()
    r = c.post(
        f"/ops/disputes/{d['id']}/resolve",
        headers=oh,
        json={"outcome": "refund", "reason": "No cut"},
    ).json()
    assert r["job"]["payment_status"] == "refunded"
    assert c.get("/ops/summary", headers=oh).json()["payouts_released_zar"] == 0


def test_mock_force_review(client_factory: Callable[..., TestClient]) -> None:
    c = client_factory(mock_force_review=True)
    oh = login(c, *OPS)
    bh, barber = onboard_barber(c, oh, "Lwazi", "+27825678901", "midrand-central")
    ch = login(c, "client", "Lerato", "+27831234567")
    job = quote_and_book(c, ch, barber["id"])
    c.post(f"/jobs/{job['id']}/confirm", headers=bh)
    proof(c, bh, job, "before", img(2, "full", 5), 1)
    ev = proof(c, bh, job, "after", img(2, "fade", 5), 40).json()
    assert ev["checks"]["cut_match"]["result"] == "uncertain"
    assert ev["verdict"] == "needs_review" and ev["verdict_reasons"] == ["cut_match uncertain"]


def test_errors_use_envelope(client: TestClient) -> None:
    c = client
    r = c.get("/jobs")
    assert r.status_code == 401 and r.json()["error"]["code"] == "unauthorized"
    r = c.post("/auth/demo-login", json={"role": "admin", "name": "x"})
    assert r.status_code == 422 and r.json()["error"]["code"] == "validation"
    ch = login(c, "client", "Lerato", "+27831234567")
    r = c.post(
        "/quotes",
        headers=ch,
        data={"area_id": "midrand-central"},
        files={"selfie": ("s.jpg", b"nope"), "reference": ("r.jpg", b"nope")},
    )
    assert r.status_code == 422 and r.json()["error"]["code"] == "validation"
    r = c.get("/jobs/00000000-0000-0000-0000-000000000000", headers=ch)
    assert r.status_code == 404 and r.json()["error"]["code"] == "not_found"
    bh = login(c, "barber", "T", "+27820000000")
    assert (
        c.post("/quotes", headers=bh, data={"area_id": "x"}).json()["error"]["code"] == "forbidden"
    )
