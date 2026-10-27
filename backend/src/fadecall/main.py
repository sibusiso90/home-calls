"""FastAPI app factory.

Run locally:  uv run uvicorn fadecall.main:app --reload --port 8000
"""

from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from starlette.types import ASGIApp, Receive, Scope, Send

from .ai import make_model_client
from .config import Settings, get_settings
from .db import Base, make_engine, make_sessionmaker
from .errors import install_error_handlers
from .routers import barbers, clients, jobs, notifications, ops, requests, system
from .services import notifications as notify_svc
from .storage import UrlSigner, make_storage, request_base_url

log = logging.getLogger("fadecall")


class BaseUrlMiddleware:
    """Expose the request's base URL to the URL signer (pure ASGI, keeps contextvars)."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        token = request_base_url.set(str(Request(scope).base_url))
        try:
            await self.app(scope, receive, send)
        finally:
            request_base_url.reset(token)


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        engine = make_engine(settings.sqlalchemy_url)
        if engine.dialect.name == "sqlite":
            Base.metadata.create_all(engine)
        app.state.engine = engine
        app.state.sessionmaker = make_sessionmaker(engine)
        app.state.models = make_model_client(settings)
        app.state.storage = make_storage(settings)
        channels = [n.name for n in notify_svc.configure(settings)]
        log.info(
            "Fade Call backend up in %s mode (%s); notifications: %s",
            settings.mode,
            engine.dialect.name,
            ", ".join(channels),
        )
        try:
            yield
        finally:
            await app.state.models.aclose()
            await app.state.storage.aclose()
            engine.dispose()

    app = FastAPI(
        title="Fade Call API",
        version="0.1.0",
        summary="Verified home-call barbers: onboarding, quotes, matching and proof of job.",
        lifespan=lifespan,
    )
    app.state.settings = settings
    app.state.signer = UrlSigner(settings)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.add_middleware(BaseUrlMiddleware)

    install_error_handlers(app)
    for r in (
        system.router,
        barbers.router,
        clients.router,
        jobs.router,
        ops.router,
        notifications.router,
        requests.router,
    ):
        app.include_router(r)
    return app


app = create_app()
