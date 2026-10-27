"""Cut pictures: an illustration per catalog cut, replaceable by an operator photo."""

from __future__ import annotations

from typing import Any
from urllib.parse import urlsplit

from fastapi.testclient import TestClient

from fadecall.cut_art import STYLES, cut_png
from fadecall.cuts import CUT_IDS

from .conftest import login
from .test_api_flow import OPS, img, onboard_barber
from .test_cut_choice import post_quote

PNG = b"\x89PNG"
JPEG = b"\xff\xd8"


def get(c: TestClient, url: str) -> Any:
    return c.get(urlsplit(url).path)


def test_every_catalog_cut_has_an_illustration() -> None:
    assert set(STYLES) == set(CUT_IDS)
    for cut_id in CUT_IDS:
        assert (cut_png(cut_id) or b"").startswith(PNG)
    assert cut_png("mullet") is None


def test_cut_list_links_a_public_picture(client: TestClient) -> None:
    cuts = client.get("/cuts").json()
    assert all(c["image_url"].endswith(f"/cuts/{c['id']}/picture") for c in cuts)
    r = get(client, cuts[0]["image_url"])  # no Authorization header
    assert r.status_code == 200 and r.content.startswith(PNG)
    assert r.headers["content-type"] == "image/png"
    assert client.get("/cuts/mullet/picture").status_code == 404


def test_operator_photo_replaces_the_drawing_until_cleared(client: TestClient) -> None:
    oh = login(client, *OPS)
    ch = login(client, "client", "Lerato", "+27831234567")
    files = {"photo": ("p.jpg", img(2, "fade", 9), "image/jpeg")}
    assert client.put("/ops/cuts/buzz-cut/picture", headers=ch, files=files).status_code == 403
    assert client.put("/ops/cuts/mullet/picture", headers=oh, files=files).status_code == 404

    r = client.put("/ops/cuts/buzz-cut/picture", headers=oh, files=files)
    assert r.status_code == 200, r.text
    assert get(client, r.json()["image_url"]).content.startswith(JPEG)

    assert client.delete("/ops/cuts/buzz-cut/picture", headers=oh).status_code == 200
    assert client.get("/cuts/buzz-cut/picture").content.startswith(PNG)


def test_quote_and_job_carry_the_cut_pictures(client: TestClient) -> None:
    oh = login(client, *OPS)
    _, barber = onboard_barber(client, oh, "Thabo", "+27821234567", "midrand-central")
    ch = login(client, "client", "Lerato", "+27831234567")
    q = post_quote(client, ch, with_reference="1").json()
    assert q["cut_image_url"].endswith(f"/cuts/{q['cut_id']}/picture")
    assert all(s["image_url"].endswith(f"/cuts/{s['cut_id']}/picture") for s in q["suggestions"])

    match = next(
        m
        for m in client.get(f"/quotes/{q['id']}/matches", headers=ch).json()
        if m["barber"]["id"] == barber["id"]
    )
    body = {
        "quote_id": q["id"],
        "barber_id": barber["id"],
        "slot_start": match["next_slot"],
        "address": "12 Example Rd, Midrand",
        "lat": -25.99,
        "lng": 28.12,
    }
    job = client.post("/jobs", headers=ch, json=body).json()
    assert job["cut_id"] == q["cut_id"] and job["cut_image_url"] == q["cut_image_url"]
    assert job["reference_url"] and "/media/" in job["reference_url"]
