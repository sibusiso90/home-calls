"""API + Flutter web build on ONE origin (for phone testing over HTTPS).

    SERVE_WEB_DIR=../app/build/web uv run uvicorn fadecall.webhost:app --port 8000

API routes are matched first; every other path falls through to the static web
build (index.html at "/"). The app uses hash URLs, so client routes never reach
the server. Without SERVE_WEB_DIR this is the plain API app. Opt-in only:
production (Modal) still serves fadecall.main:app.
"""

from __future__ import annotations

import os
from pathlib import Path

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from .config import Settings
from .main import create_app


def create_web_app(web_dir: str | None = None, settings: Settings | None = None) -> FastAPI:
    app = create_app(settings)
    web_dir = web_dir if web_dir is not None else os.environ.get("SERVE_WEB_DIR")
    if web_dir:
        root = Path(web_dir).expanduser().resolve()
        if not (root / "index.html").is_file():
            raise RuntimeError(f"SERVE_WEB_DIR={root} has no index.html; run `flutter build web`")
        app.mount("/", StaticFiles(directory=root, html=True), name="web")
    return app


app = create_web_app()
