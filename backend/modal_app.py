"""Serve the Fade Call FastAPI app on Modal.

    uv run modal secret create fadecall MODEL_API_KEY=... DATABASE_URL=... \
        SUPABASE_URL=... SUPABASE_SERVICE_KEY=... SECRET_KEY=... OPERATOR_PASSCODE=...
    uv run modal serve modal_app.py     # temporary dev URL, hot reload
    uv run modal deploy modal_app.py    # persistent URL (+ purge and reminder crons)

Run from the backend/ directory (uv_sync reads ./pyproject.toml and ./uv.lock).
"""

from __future__ import annotations

import modal

image = (
    modal.Image.debian_slim(python_version="3.12")
    .apt_install("ffmpeg")  # browser audio -> 24 kHz mono WAV for Muse Voice Transcribe
    .uv_sync(uv_project_dir=".")  # third-party deps from uv.lock (project not installed)
    .env({"ENV": "prod", "STORAGE_BACKEND": "supabase", "FFMPEG_PATH": "ffmpeg"})
    .add_local_python_source("fadecall")
)

app = modal.App("fade-call-api", image=image)


@app.function(
    secrets=[modal.Secret.from_name("fadecall")],
    min_containers=0,
    scaledown_window=300,
    timeout=120,
)
@modal.concurrent(max_inputs=20)
@modal.asgi_app(label="fade-call-api")
def api():
    from fadecall.main import create_app

    return create_app()


@app.function(
    secrets=[modal.Secret.from_name("fadecall")],
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
    secrets=[modal.Secret.from_name("fadecall")],
    schedule=modal.Cron("5 * * * *", timezone="Africa/Johannesburg"),
    timeout=300,
)
def send_reminders() -> None:
    """Hourly: day-before reminders for jobs starting in the next 24 hours (idempotent)."""
    from fadecall.config import get_settings
    from fadecall.reminders import run_reminders

    sent = run_reminders(get_settings())
    print(f"Sent reminders for {len(sent)} job(s)")
