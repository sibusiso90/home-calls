"""Drive every Fade Call flow over HTTP against a running API and report each step.

    cd backend && uv run python ../scripts/live_e2e.py                        # local Docker stack
    cd backend && uv run python ../scripts/live_e2e.py --base https://<modal-url> --passcode <op>

Barber: voice note -> confirm profile -> 5 portfolio pairs -> grade. Operator approves.
Client: catalog list -> quote from a reference -> re-quote a suggestion -> matches -> book.
Job 1: confirm, deposit, before/after proof of the same person -> rating (operator passes it
if the model sends it to review). Job 2: after photo of a different person -> dispute by
voice note -> operator resolves. Uses synthetic illustrated faces only. Each run uses fresh
phone numbers, so it never collides with seeded or real data.
"""

from __future__ import annotations

import argparse
import random
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

import httpx

from fadecall.samples import demo_set, sine_wav

VOICE_NOTE = (
    "Hi, my name is Thabo. I have been cutting hair for six years in Midrand. "
    "I do skin fades, tapers and line-ups. I speak isiZulu and English and I work weekday evenings."
)
COMPLAINT = "The barber left the fade uneven on the left side and did not finish the line-up."


class Step:
    def __init__(self, name: str) -> None:
        self.name = name

    def __enter__(self) -> Step:
        self.started = time.perf_counter()
        return self

    def __exit__(self, kind: Any, exc: BaseException | None, tb: Any) -> bool:
        ms = int((time.perf_counter() - self.started) * 1000)
        if exc is None:
            print(f"PASS  {self.name:<38} {ms:>6} ms  {getattr(self, 'note', '')}")
            return False
        print(f"FAIL  {self.name:<38} {ms:>6} ms  {type(exc).__name__}: {str(exc)[:300]}")
        print("\nStopped: later steps depend on this one.")
        raise SystemExit(1)


def speech(text: str) -> tuple[bytes, str, str]:
    """Spoken audio via macOS `say`, else a sine tone (the transcript will then be empty)."""
    say = shutil.which("say")
    if say:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "note.aiff"
            if subprocess.run([say, "-o", str(out), text], check=False).returncode == 0:
                return out.read_bytes(), "note.aiff", "audio/aiff"
    return sine_wav(), "note.wav", "audio/wav"


class Api:
    def __init__(self, base: str) -> None:
        self.http = httpx.Client(base_url=base, timeout=180)
        self.token: str | None = None

    def login(self, role: str, name: str, phone: str, passcode: str | None = None) -> Api:
        other = Api(str(self.http.base_url))
        body = {"role": role, "name": name, "phone": phone, "passcode": passcode}
        other.token = other.call("POST", "/auth/demo-login", json=body)["token"]
        return other

    def call(self, method: str, path: str, **kw: Any) -> Any:
        headers = {"Authorization": f"Bearer {self.token}"} if self.token else {}
        r = self.http.request(method, path, headers=headers, **kw)
        if r.status_code >= 400:
            raise RuntimeError(f"{method} {path} -> {r.status_code} {r.text[:300]}")
        return r.json() if r.content else None


def proof(barber: Api, job: dict[str, Any], phase: str, photo: bytes, minutes: int) -> Any:
    slot = datetime.fromisoformat(job["slot_start"])
    data = {
        "captured_at": (slot + timedelta(minutes=minutes)).isoformat(),
        "lat": str(job["lat"]),
        "lng": str(job["lng"]),
        "accuracy_m": "12",
        "capture_mode": "live",
    }
    files = {"photo": (f"{phase}.jpg", photo, "image/jpeg")}
    return barber.call("POST", f"/jobs/{job['id']}/proof/{phase}", data=data, files=files)


def book(client: Api, barber: Api, quote_id: str, barber_id: str, slot: str) -> dict[str, Any]:
    body = {
        "quote_id": quote_id,
        "barber_id": barber_id,
        "slot_start": slot,
        "address": "12 Example Rd, Midrand",
        "lat": -25.99,
        "lng": 28.12,
    }
    job = client.call("POST", "/jobs", json=body)
    barber.call("POST", f"/jobs/{job['id']}/confirm")
    client.call("POST", f"/jobs/{job['id']}/pay-deposit")
    return job


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base", default="http://localhost:8000")
    parser.add_argument("--passcode", default="fadecall-local", help="OPERATOR_PASSCODE of the target")
    parser.add_argument("--allow-mock", action="store_true", help="run even if the API is on mock models")
    args = parser.parse_args()

    api = Api(args.base)
    health = api.call("GET", "/health")
    print(f"API {args.base}  mode={health['mode']}  models={health['models']}\n")
    if health["mode"] != "live" and not args.allow_mock:
        print("API is on mock models; set MODEL_API_KEY or pass --allow-mock")
        return 2

    media = demo_set()
    run = random.randint(1_000_000, 9_999_999)
    barber = api.login("barber", "Thabo E2E", f"+2782{run}")
    client = api.login("client", "Lerato E2E", f"+2783{run}")
    operator = api.login("operator", "Ops E2E", f"+2784{run}", args.passcode)
    state: dict[str, Any] = {}

    with Step("barber voice note -> profile") as s:
        audio, name, mime = speech(VOICE_NOTE)
        note = barber.call("POST", "/barbers/me/voice-note", files={"audio": (name, audio, mime)})
        profile = note["profile"]
        profile["area_id"] = profile.get("area_id") or "midrand-central"
        barber.call("PUT", "/barbers/me/profile", json=profile)
        s.note = f"{profile.get('name')}, {profile.get('years_cutting')} yrs, {profile.get('area_id')}"

    with Step("portfolio x5 -> grade") as s:
        for i in range(1, 6):
            files = {
                "before": ("b.jpg", media[f"portfolio_{i}_before.jpg"], "image/jpeg"),
                "after": ("a.jpg", media[f"portfolio_{i}_after.jpg"], "image/jpeg"),
            }
            barber.call("POST", "/barbers/me/portfolio", files=files)
        grade = barber.call("POST", "/barbers/me/grade")
        s.note = f"tier={grade['tier']} average={grade['average']}"

    with Step("operator approves barber") as s:
        me = barber.call("GET", "/barbers/me")
        state["barber_id"] = me["id"]
        operator.call("POST", f"/ops/barbers/{me['id']}/approve", json={"reason": "E2E run"})

    with Step("client quote from reference photo") as s:
        cuts = client.call("GET", "/cuts")
        files = {
            "selfie": ("s.jpg", media["selfie.jpg"], "image/jpeg"),
            "reference": ("r.jpg", media["reference.jpg"], "image/jpeg"),
        }
        quote = client.call("POST", "/quotes", data={"area_id": "midrand-central"}, files=files)
        state["quote"] = quote
        s.note = f"{len(cuts)} cuts; '{quote['cut_name']}' {quote['minutes']} min, {quote['elapsed_ms']} ms"

    with Step("re-quote a suggested cut") as s:
        suggestion = state["quote"]["suggestions"][0]["cut_id"]
        requote = client.call("POST", f"/quotes/{state['quote']['id']}/requote", json={"cut_id": suggestion})
        state["quote"] = requote
        s.note = f"'{requote['cut_name']}' advice: {requote['face_advice'][:60]}"

    with Step("matches include the new barber") as s:
        matches = client.call("GET", f"/quotes/{state['quote']['id']}/matches")
        mine = next(m for m in matches if m["barber"]["id"] == state["barber_id"])
        s.note = f"{len(matches)} matches; ours R{mine['price']['total_zar']} band {mine['travel_band']}"

    with Step("book two slots, confirm, deposit") as s:
        slots = client.call("GET", f"/barbers/{state['barber_id']}/slots?days=7")
        starts = slots["slots"]
        state["job1"] = book(client, barber, state["quote"]["id"], state["barber_id"], starts[0])
        state["job2"] = book(client, barber, state["quote"]["id"], state["barber_id"], starts[1])
        s.note = f"{starts[0]} and {starts[1]}"

    with Step("job 1 proof: same person") as s:
        proof(barber, state["job1"], "before", media["before.jpg"], 3)
        ev = proof(barber, state["job1"], "after", media["after.jpg"], 45)
        checks = {k: v["result"] for k, v in ev["checks"].items()}
        s.note = f"verdict={ev['verdict']} {checks}"
        state["verdict1"] = ev["verdict"]

    with Step("job 1 rating (operator passes if review)") as s:
        if state["verdict1"] != "pass":
            body = {"verdict": "pass", "reason": "E2E: reviewed photos"}
            operator.call("POST", f"/ops/jobs/{state['job1']['id']}/verdict", json=body)
        client.call("POST", f"/jobs/{state['job1']['id']}/rating", json={"stars": 5, "comment": "Clean fade"})
        s.note = "operator review needed" if state["verdict1"] != "pass" else "model passed it"

    with Step("job 2 proof: different person") as s:
        proof(barber, state["job2"], "before", media["before.jpg"], 3)
        ev = proof(barber, state["job2"], "after", media["after_different_person.jpg"], 45)
        s.note = f"verdict={ev['verdict']} same_person={ev['checks']['same_person']['result']}"
        if ev["verdict"] == "pass":
            raise AssertionError("a different person must not pass")

    with Step("job 2 dispute by voice note") as s:
        audio, name, mime = speech(COMPLAINT)
        dispute = client.call(
            "POST", f"/jobs/{state['job2']['id']}/dispute", files={"audio": (name, audio, mime)}
        )
        state["dispute"] = dispute
        s.note = f"suggested={dispute['suggested_outcome']}: {dispute['summary'][:60]}"

    with Step("operator resolves dispute, summary") as s:
        body = {"outcome": state["dispute"]["suggested_outcome"] or "refund", "reason": "E2E run"}
        operator.call("POST", f"/ops/disputes/{state['dispute']['id']}/resolve", json=body)
        summary = operator.call("GET", "/ops/summary")
        s.note = f"pass_rate={summary['pass_rate']} avg_verdict_ms={summary['avg_verdict_ms']}"

    print("\nAll steps passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
