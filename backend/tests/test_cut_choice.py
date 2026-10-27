"""Quote by catalog pick or suggestion (no reference photo), face advice and requote."""

from __future__ import annotations

from typing import Any

from fastapi.testclient import TestClient

from fadecall.cuts import CUT_IDS, CUTS_BY_ID

from .conftest import login
from .test_api_flow import OPS, img, media_get, onboard_barber, proof

SELFIE = ("s.jpg", img(1, "full", 3))


def post_quote(c: TestClient, ch: dict[str, str], **form: str) -> Any:
    files: dict[str, Any] = {"selfie": SELFIE}
    if form.pop("with_reference", None):
        files["reference"] = ("r.jpg", img(3, "fade", 4))
    return c.post("/quotes", headers=ch, data={"area_id": "midrand-central", **form}, files=files)


def assert_advice(q: dict[str, Any]) -> None:
    assert q["face_advice"]
    assert 1 <= len(q["suggestions"]) <= 3
    for s in q["suggestions"]:
        assert s["cut_id"] in CUT_IDS and s["name"] and s["minutes"] > 0 and s["why"]


def test_cut_catalog_is_listed(client: TestClient) -> None:
    cuts = client.get("/cuts").json()
    assert [c["id"] for c in cuts] == CUT_IDS
    assert all(c["name"] and c["description"] and c["minutes"] > 0 for c in cuts)


def test_catalog_pick_quotes_that_cut(client: TestClient) -> None:
    ch = login(client, "client", "Lerato", "+27831234567")
    r = post_quote(client, ch, cut_id="buzz-cut")
    assert r.status_code == 200, r.text
    q = r.json()
    assert q["cut_source"] == "catalog" and q["cut_id"] == "buzz-cut"
    assert q["cut_name"] == CUTS_BY_ID["buzz-cut"].name
    assert q["reference_url"] is None and q["reference_overlay_url"] is None
    assert media_get(client, q["selfie_overlay_url"]).status_code == 200
    assert_advice(q)


def test_suggest_picks_a_catalog_cut(client: TestClient) -> None:
    ch = login(client, "client", "Lerato", "+27831234567")
    q = post_quote(client, ch).json()
    assert q["cut_source"] == "suggested" and q["cut_id"] in CUT_IDS
    assert q["cut_name"] == CUTS_BY_ID[q["cut_id"]].name
    assert q["reference_url"] is None
    assert_advice(q)


def test_reference_quote_also_gets_advice(client: TestClient) -> None:
    ch = login(client, "client", "Lerato", "+27831234567")
    q = post_quote(client, ch, with_reference="1").json()
    assert q["cut_source"] == "reference" and q["reference_url"]
    assert_advice(q)


def test_bad_cut_choice_is_rejected(client: TestClient) -> None:
    ch = login(client, "client", "Lerato", "+27831234567")
    both = post_quote(client, ch, cut_id="buzz-cut", with_reference="1")
    assert both.status_code == 422 and both.json()["error"]["code"] == "validation"
    unknown = post_quote(client, ch, cut_id="mullet")
    assert unknown.status_code == 422 and unknown.json()["error"]["code"] == "validation"


def test_requote_a_suggestion_reuses_the_selfie(client: TestClient) -> None:
    ch = login(client, "client", "Lerato", "+27831234567")
    first = post_quote(client, ch, with_reference="1").json()
    pick = first["suggestions"][-1]["cut_id"]
    r = client.post(f"/quotes/{first['id']}/requote", headers=ch, json={"cut_id": pick})
    assert r.status_code == 200, r.text
    q = r.json()
    assert q["id"] != first["id"] and q["cut_source"] == "catalog" and q["cut_id"] == pick
    assert q["reference_url"] is None
    assert (
        media_get(client, q["selfie_url"]).content == media_get(client, first["selfie_url"]).content
    )
    other = login(client, "client", "Sipho", "+27839999999")
    stolen = client.post(f"/quotes/{first['id']}/requote", headers=other, json={"cut_id": pick})
    assert stolen.status_code == 403


def test_catalog_job_runs_proof_without_reference(client: TestClient) -> None:
    oh = login(client, *OPS)
    bh, barber = onboard_barber(client, oh, "Thabo", "+27821234567", "midrand-central")
    ch = login(client, "client", "Lerato", "+27831234567")
    q = post_quote(client, ch, cut_id="mid-skin-fade-textured").json()
    m = next(
        m
        for m in client.get(f"/quotes/{q['id']}/matches", headers=ch).json()
        if m["barber"]["id"] == barber["id"]
    )
    job = client.post(
        "/jobs",
        headers=ch,
        json={
            "quote_id": q["id"],
            "barber_id": barber["id"],
            "slot_start": m["next_slot"],
            "address": "12 Example Rd, Midrand",
            "lat": -25.99,
            "lng": 28.12,
        },
    ).json()
    assert job["cut"] == q["cut_name"]
    client.post(f"/jobs/{job['id']}/pay-deposit", headers=ch)
    client.post(f"/jobs/{job['id']}/confirm", headers=bh)
    assert proof(client, bh, job, "before", img(2, "full", 5), 1).status_code == 200
    after = proof(client, bh, job, "after", img(2, "fade", 5), 50)
    assert after.status_code == 200, after.text
