"""Booking requests: time windows, the chosen barber's 10-minute offer, then everyone."""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any

from fastapi.testclient import TestClient

from fadecall.models import BookingRequest
from fadecall.scheduling import window_of
from fadecall.timeutil import SAST, utcnow

from .conftest import login
from .test_api_flow import OPS, img, onboard_barber


def tomorrow() -> str:
    return (utcnow().astimezone(SAST) + timedelta(days=1)).date().isoformat()


def setup(c: TestClient) -> dict[str, Any]:
    oh = login(c, *OPS)
    th, thabo = onboard_barber(c, oh, "Thabo", "+27821234567", "midrand-central")
    kh, kabelo = onboard_barber(c, oh, "Kabelo", "+27823456789", "halfway-house")
    ch = login(c, "client", "Lerato", "+27831234567")
    q = c.post(
        "/quotes",
        headers=ch,
        data={"area_id": "midrand-central", "cut_id": "low-taper-lineup"},
        files={"selfie": ("s.jpg", img(1, "full", 3))},
    ).json()
    return {"th": th, "thabo": thabo, "kh": kh, "kabelo": kabelo, "ch": ch, "quote": q}


def ask(c: TestClient, s: dict[str, Any], barber_id: str | None, **extra: Any) -> Any:
    return c.post(
        "/requests",
        headers=s["ch"],
        json={
            "quote_id": s["quote"]["id"],
            "day": tomorrow(),
            "windows": ["afternoon"],
            "address": "12 Example Rd, Midrand",
            "lat": -25.99,
            "lng": 28.12,
            "barber_id": barber_id,
            **extra,
        },
    )


def visible(c: TestClient, h: dict[str, str]) -> list[str]:
    return [r["id"] for r in c.get("/requests", headers=h).json()]


def kinds(c: TestClient, h: dict[str, str]) -> list[str]:
    return [n["kind"] for n in c.get("/notifications", headers=h).json()["items"]]


def lapse_offer(c: TestClient, request_id: str) -> None:
    state: Any = c.app.state  # type: ignore[attr-defined]
    with state.sessionmaker() as db:
        r = db.get(BookingRequest, request_id)
        r.offered_until = utcnow() - timedelta(seconds=1)
        db.commit()


def test_chosen_barber_gets_it_first_then_everyone_after_ten_minutes(client: TestClient) -> None:
    c = client
    s = setup(c)
    r = ask(c, s, s["thabo"]["id"])
    assert r.status_code == 200, r.text
    req = r.json()
    assert req["status"] == "open" and not req["broadcast"]
    assert req["windows"] == [{"id": "afternoon", "label": "Afternoon"}]
    assert visible(c, s["th"]) == [req["id"]] and visible(c, s["kh"]) == []
    assert "request_new" in kinds(c, s["th"]) and "request_new" not in kinds(c, s["kh"])

    lapse_offer(c, req["id"])
    assert visible(c, s["kh"]) == [req["id"]]  # the read sweeps the lapsed offer
    assert "request_new" in kinds(c, s["kh"]) and "request_update" in kinds(c, s["ch"])
    assert c.get(f"/requests/{req['id']}", headers=s["ch"]).json()["broadcast"] is True


def test_decline_by_chosen_barber_opens_it_to_everyone(client: TestClient) -> None:
    c = client
    s = setup(c)
    req = ask(c, s, s["thabo"]["id"]).json()
    assert c.post(f"/requests/{req['id']}/decline", headers=s["th"]).status_code == 200
    assert visible(c, s["th"]) == [] and visible(c, s["kh"]) == [req["id"]]


def test_no_barber_chosen_asks_everyone_and_the_taker_sets_the_time(client: TestClient) -> None:
    c = client
    s = setup(c)
    req = ask(c, s, None).json()
    assert req["broadcast"] is True
    mine = next(r for r in c.get("/requests", headers=s["kh"]).json() if r["id"] == req["id"])
    assert mine["price"]["total_zar"] > 0 and mine["slots"]
    assert all(window_of(datetime.fromisoformat(t)) == "afternoon" for t in mine["slots"])
    assert visible(c, s["th"]) == [req["id"]]

    outside = (datetime.fromisoformat(mine["slots"][0]).replace(hour=9)).isoformat()
    bad = c.post(f"/requests/{req['id']}/accept", headers=s["kh"], json={"slot_start": outside})
    assert bad.status_code == 422

    slot = mine["slots"][2]
    r = c.post(f"/requests/{req['id']}/accept", headers=s["kh"], json={"slot_start": slot})
    assert r.status_code == 200, r.text
    job = r.json()
    assert job["status"] == "confirmed" and job["barber"]["name"] == "Kabelo"
    assert datetime.fromisoformat(job["slot_start"]) == datetime.fromisoformat(slot)
    assert job["quote_zar"] == mine["price"]["total_zar"]
    assert "request_accepted" in kinds(c, s["ch"])

    late = c.post(f"/requests/{req['id']}/accept", headers=s["th"], json={"slot_start": slot})
    assert late.status_code in (403, 409)
    assert visible(c, s["th"]) == []
    done = c.get(f"/requests/{req['id']}", headers=s["ch"]).json()
    assert done["status"] == "accepted" and done["job_id"] == job["id"]


def test_windows_with_no_time_left_are_rejected_and_requests_expire(client: TestClient) -> None:
    c = client
    s = setup(c)
    yesterday = (utcnow().astimezone(SAST) - timedelta(days=1)).date().isoformat()
    assert ask(c, s, None, day=yesterday).status_code == 422
    assert ask(c, s, None, windows=[]).status_code == 422

    req = ask(c, s, None).json()
    state: Any = c.app.state  # type: ignore[attr-defined]
    with state.sessionmaker() as db:
        db.get(BookingRequest, req["id"]).day = yesterday
        db.commit()
    assert c.get(f"/requests/{req['id']}", headers=s["ch"]).json()["status"] == "expired"
    assert visible(c, s["kh"]) == []


def test_client_can_cancel_an_open_request(client: TestClient) -> None:
    c = client
    s = setup(c)
    req = ask(c, s, s["thabo"]["id"]).json()
    r = c.post(f"/requests/{req['id']}/cancel", headers=s["ch"])
    assert r.status_code == 200 and r.json()["status"] == "cancelled"
    assert visible(c, s["th"]) == []
    assert c.post(f"/requests/{req['id']}/cancel", headers=s["ch"]).status_code == 409
