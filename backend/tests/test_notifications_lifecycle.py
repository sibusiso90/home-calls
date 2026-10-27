"""Notifications, day-before reminders, cancel and reschedule."""

from __future__ import annotations

import json
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

import httpx
import pytest
from fastapi.testclient import TestClient

from fadecall.config import Settings
from fadecall.models import Job, Notification
from fadecall.services import notifications as notify_svc
from fadecall.services.lifecycle import cancel_job
from fadecall.timeutil import parse_iso

from .conftest import login, make_settings
from .test_api_flow import img, proof, quote_and_book
from .test_review_fixes import passed_job, setup, state


def inbox(c: TestClient, h: dict[str, str]) -> dict[str, Any]:
    r = c.get("/notifications", headers=h)
    assert r.status_code == 200, r.text
    return r.json()


def kinds(c: TestClient, h: dict[str, str]) -> list[str]:
    return [n["kind"] for n in inbox(c, h)["items"]]


def db_session(c: TestClient) -> Any:
    return state(c).sessionmaker()


# --- notifications ------------------------------------------------------------


def test_booking_confirm_deposit_notify_the_other_side(client: TestClient) -> None:
    c = client
    _, bh, ch, barber = setup(c)
    job = quote_and_book(c, ch, barber["id"], pay_deposit=False)

    b_inbox = inbox(c, bh)
    assert b_inbox["unread_count"] == 1
    n = b_inbox["items"][0]
    assert n["kind"] == "booking_created" and n["job_id"] == job["id"]
    assert n["title"] == "New booking" and n["read_at"] is None
    assert kinds(c, ch) == ["booking_created"]

    c.post(f"/jobs/{job['id']}/confirm", headers=bh)
    assert kinds(c, ch)[0] == "job_confirmed"
    c.post(f"/jobs/{job['id']}/pay-deposit", headers=ch)
    assert kinds(c, bh)[0] == "deposit_paid"
    assert inbox(c, bh)["unread_count"] == 2


def test_read_one_read_all_and_ownership(client: TestClient) -> None:
    c = client
    _, bh, ch, barber = setup(c)
    quote_and_book(c, ch, barber["id"])
    mine = inbox(c, bh)["items"][0]

    assert c.post(f"/notifications/{mine['id']}/read", headers=ch).status_code == 404
    assert c.post("/notifications/not-a-uuid/read", headers=bh).status_code == 404
    r = c.post(f"/notifications/{mine['id']}/read", headers=bh)
    assert r.status_code == 200 and r.json()["read_at"] is not None
    assert inbox(c, bh)["unread_count"] == 1  # deposit_paid still unread

    assert c.post("/notifications/read-all", headers=bh).json() == {"marked": 1, "unread_count": 0}
    assert inbox(c, bh)["unread_count"] == 0
    assert inbox(c, ch)["unread_count"] == 1  # the client's inbox is untouched
    assert c.get("/notifications").status_code == 401


def test_verdicts_and_disputes_notify(client: TestClient) -> None:
    c = client
    oh, bh, ch, job = passed_job(c)
    assert kinds(c, ch)[0] == "verdict_pass"
    assert "Payment released" in inbox(c, bh)["items"][0]["body"]

    r = c.post(f"/jobs/{job['id']}/dispute", headers=ch, data={"text": "Uneven sides"})
    assert r.status_code == 200, r.text
    assert kinds(c, bh)[0] == "dispute_opened"
    assert kinds(c, oh)[0] == "dispute_opened"
    c.post(
        f"/ops/disputes/{r.json()['id']}/resolve",
        headers=oh,
        json={"outcome": "release", "reason": "Photos show an even fade"},
    )
    assert kinds(c, ch)[0] == "dispute_resolved"
    assert "Photos show an even fade" in inbox(c, bh)["items"][0]["body"]


def test_needs_review_tells_operators_and_operator_decision_tells_both(
    client: TestClient,
) -> None:
    c = client
    oh, bh, ch, barber = setup(c)
    job = quote_and_book(c, ch, barber["id"])
    c.post(f"/jobs/{job['id']}/confirm", headers=bh)
    proof(c, bh, job, "before", img(2, "full", 5), 1)
    ev = proof(c, bh, job, "after", img(2, "fade", 5), 40, capture_mode="upload_fallback").json()
    assert ev["verdict"] == "needs_review"
    assert "verdict_needs_review" in kinds(c, oh)
    assert kinds(c, ch)[0] == "verdict_needs_review"

    c.post(f"/ops/jobs/{job['id']}/verdict", headers=oh, json={"verdict": "pass", "reason": "OK"})
    for h in (bh, ch):
        top = inbox(c, h)["items"][0]
        assert top["kind"] == "verdict_operator" and "Reason: OK" in top["body"]


# --- reminders ------------------------------------------------------------------


def test_reminders_are_sent_once_per_slot(client: TestClient) -> None:
    c = client
    _, bh, ch, barber = setup(c)
    job = quote_and_book(c, ch, barber["id"])
    slot = parse_iso(job["slot_start"])

    with db_session(c) as db:
        assert notify_svc.send_due_reminders(db, slot - timedelta(hours=30)) == []
        assert notify_svc.send_due_reminders(db, slot - timedelta(hours=20)) == [job["id"]]
        assert notify_svc.send_due_reminders(db, slot - timedelta(hours=19)) == []  # idempotent
        assert notify_svc.send_due_reminders(db, slot - timedelta(hours=1)) == []
    assert kinds(c, ch).count("reminder") == 1
    assert kinds(c, bh).count("reminder") == 1
    assert c.get(f"/jobs/{job['id']}", headers=ch).json()["reminder_sent_at"] is not None


def test_reschedule_clears_the_reminder(client: TestClient) -> None:
    c = client
    _, _, ch, barber = setup(c)
    job = quote_and_book(c, ch, barber["id"])
    slot = parse_iso(job["slot_start"])
    with db_session(c) as db:
        assert notify_svc.send_due_reminders(db, slot - timedelta(hours=20)) == [job["id"]]

    slots = c.get(f"/barbers/{barber['id']}/slots", headers=ch).json()["slots"]
    moved = c.post(f"/jobs/{job['id']}/reschedule", headers=ch, json={"slot_start": slots[0]})
    assert moved.status_code == 200, moved.text
    assert moved.json()["reminder_sent_at"] is None
    new_slot = parse_iso(moved.json()["slot_start"])
    with db_session(c) as db:
        assert notify_svc.send_due_reminders(db, new_slot - timedelta(hours=2)) == [job["id"]]


def test_cancelled_and_finished_jobs_get_no_reminder(client: TestClient) -> None:
    c = client
    _, bh, ch, barber = setup(c)
    job = quote_and_book(c, ch, barber["id"])
    c.post(f"/jobs/{job['id']}/cancel", headers=bh, json={"reason": "Sick"})
    with db_session(c) as db:
        slot = parse_iso(job["slot_start"])
        assert notify_svc.send_due_reminders(db, slot - timedelta(hours=3)) == []


# --- cancel ---------------------------------------------------------------------


def test_barber_cancel_refunds_paid_deposit_and_frees_slot(client: TestClient) -> None:
    c = client
    _, bh, ch, barber = setup(c)
    job = quote_and_book(c, ch, barber["id"])
    assert c.post(f"/jobs/{job['id']}/cancel", headers=bh, json={"reason": ""}).status_code == 422

    r = c.post(f"/jobs/{job['id']}/cancel", headers=bh, json={"reason": "Car broke down"})
    assert r.status_code == 200, r.text
    j = r.json()
    assert j["status"] == "cancelled" and j["payment_status"] == "refunded"
    assert j["cancelled_by"] == "barber" and j["cancel_reason"] == "Car broke down"
    assert j["cancelled_at"] is not None
    assert kinds(c, ch)[0] == "job_cancelled"
    assert "refunded" in inbox(c, ch)["items"][0]["body"]

    slots = c.get(f"/barbers/{barber['id']}/slots", headers=ch).json()["slots"]
    assert job["slot_start"] in slots
    again = c.post(f"/jobs/{job['id']}/cancel", headers=ch, json={"reason": "x"})
    assert again.status_code == 409
    assert c.post(f"/jobs/{job['id']}/pay-deposit", headers=ch).status_code == 409


def test_client_cancel_with_unpaid_deposit_keeps_payment_status(client: TestClient) -> None:
    c = client
    _, _, ch, barber = setup(c)
    job = quote_and_book(c, ch, barber["id"], pay_deposit=False)
    r = c.post(f"/jobs/{job['id']}/cancel", headers=ch, json={"reason": "Plans changed"})
    assert r.json()["status"] == "cancelled"
    assert r.json()["payment_status"] == "deposit_pending"


@pytest.mark.parametrize(
    ("by", "hours_before", "expected"),
    [
        ("client", 1, "forfeited"),  # late client cancel keeps the deposit
        ("client", 3, "refunded"),
        ("barber", 1, "refunded"),  # a barber cancelling never costs the client
    ],
)
def test_late_cancel_rule(client: TestClient, by: str, hours_before: int, expected: str) -> None:
    c = client
    _, _, ch, barber = setup(c)
    job_json = quote_and_book(c, ch, barber["id"])
    with db_session(c) as db:
        job = db.get(Job, job_json["id"])
        now = job.slot_start - timedelta(hours=hours_before)
        cancel_job(db, job, by, "Reason", late_cancel_hours=2, now=now)  # type: ignore[arg-type]
        assert job.payment_status == expected


def test_cannot_cancel_after_before_photo_or_as_operator(client: TestClient) -> None:
    c = client
    oh, bh, ch, barber = setup(c)
    job = quote_and_book(c, ch, barber["id"])
    assert c.post(f"/jobs/{job['id']}/cancel", headers=oh, json={"reason": "x"}).status_code == 403
    c.post(f"/jobs/{job['id']}/confirm", headers=bh)
    proof(c, bh, job, "before", img(2, "full", 5), 1)
    r = c.post(f"/jobs/{job['id']}/cancel", headers=ch, json={"reason": "Changed mind"})
    assert r.status_code == 409 and r.json()["error"]["code"] == "conflict"
    other = login(c, "client", "Sipho", "+27830000000")
    assert (
        c.post(f"/jobs/{job['id']}/cancel", headers=other, json={"reason": "x"}).status_code == 403
    )


# --- reschedule -----------------------------------------------------------------


def test_reschedule_rules(client: TestClient) -> None:
    c = client
    _, bh, ch, barber = setup(c)
    job = quote_and_book(c, ch, barber["id"])
    c.post(f"/jobs/{job['id']}/confirm", headers=bh)
    other = quote_and_book(c, ch, barber["id"])  # takes the next free slot
    slots = c.get(f"/barbers/{barber['id']}/slots", headers=ch, params={"days": 14}).json()
    assert slots["barber_id"] == barber["id"]
    assert job["slot_start"] not in slots["slots"]
    assert other["slot_start"] not in slots["slots"]
    target = slots["slots"][0]

    url = f"/jobs/{job['id']}/reschedule"
    assert c.post(url, headers=bh, json={"slot_start": target}).status_code == 403
    assert c.post(url, headers=ch, json={"slot_start": job["slot_start"]}).status_code == 422
    odd = (parse_iso(target) + timedelta(minutes=17)).isoformat()
    assert c.post(url, headers=ch, json={"slot_start": odd}).status_code == 422
    taken = c.post(url, headers=ch, json={"slot_start": other["slot_start"]})
    assert taken.status_code == 409

    r = c.post(url, headers=ch, json={"slot_start": target})
    assert r.status_code == 200, r.text
    j = r.json()
    assert j["status"] == "booked" and j["rescheduled_at"] is not None
    assert parse_iso(j["slot_start"]) == parse_iso(target)
    assert parse_iso(j["slot_end"]) - parse_iso(j["slot_start"]) == timedelta(
        minutes=job["minutes"]
    )
    assert kinds(c, bh)[0] == "job_rescheduled"
    assert c.post(f"/jobs/{job['id']}/confirm", headers=bh).json()["status"] == "confirmed"


def test_slots_endpoint_validation(client: TestClient) -> None:
    c = client
    _, _, ch, barber = setup(c)
    assert c.get("/barbers/not-a-uuid/slots", headers=ch).status_code == 404
    assert (
        c.get(f"/barbers/{barber['id']}/slots", headers=ch, params={"days": 0}).status_code == 422
    )
    week = [
        datetime.fromisoformat(s)
        for s in c.get(f"/barbers/{barber['id']}/slots", headers=ch).json()["slots"]
    ]
    assert len(week) > 7 * 10  # every 30 minutes through each day
    assert all(s.minute in (0, 30) for s in week)
    assert all(
        (9, 0) <= (s.hour, s.minute) <= (17, 0)
        if s.weekday() == 6
        else (8, 0) <= (s.hour, s.minute) <= (20, 0)
        for s in week
    )
    assert week[0] - datetime.now(week[0].tzinfo) >= timedelta(hours=1)

    # A booking hides every start time that would clash with it (cut + travel).
    job = quote_and_book(c, ch, barber["id"], pay_deposit=False)
    start = datetime.fromisoformat(job["slot_start"])
    after = [
        datetime.fromisoformat(s)
        for s in c.get(f"/barbers/{barber['id']}/slots", headers=ch).json()["slots"]
    ]
    assert start not in after and start + timedelta(minutes=30) not in after
    moved = c.get(
        f"/barbers/{barber['id']}/slots",
        headers=ch,
        params={"minutes": job["minutes"], "exclude_job_id": job["id"]},
    ).json()["slots"]
    assert job["slot_start"] in moved or start in [datetime.fromisoformat(s) for s in moved]


# --- WhatsApp stub ----------------------------------------------------------------


def test_whatsapp_is_off_unless_fully_configured(tmp_path: Path) -> None:
    def channels(**kw: Any) -> list[str]:
        return [n.name for n in notify_svc.configure(make_settings(tmp_path, **kw))]

    try:
        assert channels() == ["in_app"]
        assert channels(whatsapp_token="t") == ["in_app"]
        assert channels(whatsapp_token="t", whatsapp_phone_id="123") == ["in_app", "whatsapp"]
    finally:
        notify_svc.configure(make_settings(tmp_path))


def test_whatsapp_payload_shape_without_network() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"messages": [{"id": "wamid.x"}]})

    wa = notify_svc.WhatsAppNotifier(
        "tok", "555", client=httpx.Client(transport=httpx.MockTransport(handler))
    )
    msg = notify_svc.Message("u", "+27 82 123 4567", "Your cut is tomorrow", "Thabo at 16:00")
    wa.send(msg)
    assert len(seen) == 1
    req = seen[0]
    assert str(req.url) == "https://graph.facebook.com/v21.0/555/messages"
    assert req.headers["Authorization"] == "Bearer tok"
    assert json.loads(req.content) == {
        "messaging_product": "whatsapp",
        "to": "27821234567",
        "type": "text",
        "text": {"preview_url": False, "body": "Your cut is tomorrow\nThabo at 16:00"},
    }
    wa.send(notify_svc.Message("u", None, "t", "b"))  # no phone: nothing sent
    assert len(seen) == 1


def test_notify_dedupes_and_rejects_unknown_kinds(settings: Settings) -> None:
    from fadecall.db import Base, make_engine, make_sessionmaker
    from fadecall.models import User

    engine = make_engine(settings.sqlalchemy_url)
    Base.metadata.create_all(engine)
    with make_sessionmaker(engine)() as db:
        u = User(role="client", name="A", phone="+27", phone_key="k")
        db.add(u)
        db.flush()
        rows = notify_svc.notify(db, [u.id, u.id, None], "reminder", "t", "b")
        assert len(rows) == 1
        db.commit()
        assert db.query(Notification).count() == 1
        with pytest.raises(ValueError, match="unknown notification kind"):
            notify_svc.notify(db, [u.id], "nope", "t", "b")
    engine.dispose()
