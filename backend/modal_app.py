"""Serve the Fade Call FastAPI app on Modal (runbook: docs/deploy.md).

    uv run modal secret create fadecall --from-dotenv .env.modal
    uv run modal serve modal_app.py     # temporary -dev URL, hot reload
    uv run modal deploy modal_app.py    # https://<workspace>--fade-call-api.modal.run
                                        # (+ daily purge and hourly reminder crons)
    uv run modal run modal_app.py::smoke   # live model smoke test inside the image

Run with `uv run` from backend/ so `fadecall` is importable locally (it is mounted
from your checkout, not installed). Deploy-time options, read on your machine:

    FADECALL_WEB_DIR=../app/build/web   also serve the Flutter web build on the same
                                        origin (fadecall.webhost); build it first with
                                        API_BASE_URL set to the Modal URL
    FADECALL_MIN_CONTAINERS=1           keep one warm container (demo day; costs money)
"""

from __future__ import annotations

import os
from pathlib import Path

import modal

BACKEND_DIR = Path(__file__).resolve().parent
WEB_DIR_REMOTE = "/web"


def _web_dir() -> Path | None:
    """The Flutter web build to bundle, if FADECALL_WEB_DIR is set (checked locally)."""
    raw = os.environ.get("FADECALL_WEB_DIR")
    if not raw or not modal.is_local():
        return None
    root = Path(raw).expanduser().resolve()
    main_js = root / "main.dart.js"
    if not (root / "index.html").is_file() or not main_js.is_file():
        raise RuntimeError(f"FADECALL_WEB_DIR={root} is not a Flutter web build")
    if "localhost:8000" in main_js.read_text(errors="ignore"):
        raise RuntimeError(
            "The web build still points at http://localhost:8000. Rebuild it with "
            "--dart-define=API_BASE_URL=https://<workspace>--fade-call-api.modal.run"
        )
    return root


image = (
    modal.Image.debian_slim(python_version="3.12")
    .apt_install("ffmpeg")  # browser audio -> 24 kHz mono WAV for Muse Voice Transcribe
    # Third-party deps (incl. meta-sam-parser) from uv.lock, --frozen; the project
    # itself is not installed, so its source is added below.
    .uv_sync(uv_project_dir=str(BACKEND_DIR))
    .env({"ENV": "prod", "STORAGE_BACKEND": "supabase", "FFMPEG_PATH": "ffmpeg"})
)
web_dir = _web_dir()
if web_dir is not None:
    image = image.env({"SERVE_WEB_DIR": WEB_DIR_REMOTE}).add_local_dir(web_dir, WEB_DIR_REMOTE)
image = image.add_local_python_source("fadecall")  # mounts must come after build steps

app = modal.App("fade-call-api", image=image)
# MODEL_API_KEY is optional on purpose: without it the API runs on the mock models
# (/health says "mode": "mock"). The rest must be there or prod would be wrong/insecure.
REQUIRED_KEYS = [
    "DATABASE_URL",
    "SUPABASE_URL",
    "SUPABASE_SERVICE_KEY",
    "SECRET_KEY",
    "OPERATOR_PASSCODE",
]
secrets = [modal.Secret.from_name("fadecall", required_keys=REQUIRED_KEYS)]


@app.function(
    secrets=secrets,
    min_containers=int(os.environ.get("FADECALL_MIN_CONTAINERS", "0")),
    scaledown_window=300,
    # Modal's proxy answers 303 after 150 s; model calls are capped by MODEL_DEADLINE_S.
    timeout=150,
)
@modal.concurrent(max_inputs=20)
@modal.asgi_app(label="fade-call-api")
def api():
    # Plain API, or API + Flutter web build when the image set SERVE_WEB_DIR.
    from fadecall.webhost import app as web_app

    return web_app


@app.function(
    secrets=secrets,
    schedule=modal.Cron("0 2 * * *", timezone="Africa/Johannesburg"),
    timeout=600,
)
async def purge_evidence() -> None:
    """Daily: delete raw proof photos past EVIDENCE_RETENTION_DAYS (consent rule)."""
    from fadecall.config import get_settings
    from fadecall.purge import run_purge

    purged = await run_purge(get_settings())
    print(f"Purged raw evidence for {len(purged)} job(s)")


@app.function(
    secrets=secrets,
    schedule=modal.Cron("5 * * * *", timezone="Africa/Johannesburg"),
    timeout=300,
)
def send_reminders() -> None:
    """Hourly: day-before reminders for jobs starting in the next 24 hours (idempotent)."""
    from fadecall.config import get_settings
    from fadecall.reminders import run_reminders

    sent = run_reminders(get_settings())
    print(f"Sent reminders for {len(sent)} job(s)")


@app.function(secrets=secrets, schedule=modal.Period(minutes=1), timeout=60)
def sweep_requests() -> None:
    """Every minute: pass lapsed 10-minute offers to all nearby barbers, expire dead requests.

    The API also sweeps whenever anyone polls notifications; this covers quiet periods.
    """
    from fadecall.config import get_settings
    from fadecall.db import make_engine, make_sessionmaker
    from fadecall.services import notifications
    from fadecall.services.requests import sweep

    settings = get_settings()
    notifications.configure(settings)
    engine = make_engine(settings.sqlalchemy_url)
    try:
        with make_sessionmaker(engine)() as db:
            print(f"Swept {sweep(db)} request(s)")
    finally:
        engine.dispose()


@app.function(secrets=secrets, timeout=300)
def smoke() -> None:
    """One live call per model from inside the deployed image (needs MODEL_API_KEY).

    uv run modal run modal_app.py::smoke
    """
    import shutil

    from fadecall.smoke import main

    print(f"ffmpeg: {shutil.which('ffmpeg') or 'MISSING'}")
    code = main([])
    if code:
        raise SystemExit(code)
