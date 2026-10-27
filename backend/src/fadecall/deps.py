"""FastAPI dependencies that read shared services from app.state."""

from __future__ import annotations

from collections.abc import Iterator
from typing import Annotated

from fastapi import Depends, Request
from sqlalchemy.orm import Session

from .ai.types import ModelClient
from .config import Settings
from .storage import Storage, UrlSigner


def get_db(request: Request) -> Iterator[Session]:
    with request.app.state.sessionmaker() as session:
        yield session


def get_settings_dep(request: Request) -> Settings:
    return request.app.state.settings


def get_models(request: Request) -> ModelClient:
    return request.app.state.models


def get_storage(request: Request) -> Storage:
    return request.app.state.storage


def get_signer(request: Request) -> UrlSigner:
    return request.app.state.signer


DB = Annotated[Session, Depends(get_db)]
AppSettings = Annotated[Settings, Depends(get_settings_dep)]
Models = Annotated[ModelClient, Depends(get_models)]
Store = Annotated[Storage, Depends(get_storage)]
Signer = Annotated[UrlSigner, Depends(get_signer)]
