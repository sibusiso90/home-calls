from __future__ import annotations

import os
from collections.abc import Callable, Iterator
from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient

from fadecall.config import Settings
from fadecall.main import create_app

# Opt-in: run the suite against a Postgres database built ONLY from
# supabase/migrations (the app never create_all()s on Postgres). Every test
# starts from empty tables. Example:
#   TEST_DATABASE_URL=postgresql://postgres:pg@localhost:55432/fadecall uv run pytest
TEST_DATABASE_URL = os.environ.get("TEST_DATABASE_URL")


def make_settings(tmp_path: Path, **overrides: Any) -> Settings:
    base: dict[str, Any] = {
        "database_url": TEST_DATABASE_URL or f"sqlite:///{tmp_path / 'test.db'}",
        "local_media_dir": tmp_path / "media",
        "model_api_key": None,
        "secret_key": "test-secret",
        "operator_passcode": "letmein",
        "mock_force_review": False,
        "public_base_url": None,
    }
    base.update(overrides)
    return Settings(_env_file=None, **base)  # type: ignore[call-arg]


@pytest.fixture(autouse=True)
def _empty_test_database(tmp_path: Path) -> None:
    if not TEST_DATABASE_URL:
        return
    from sqlalchemy import text

    from fadecall.db import Base, make_engine

    engine = make_engine(make_settings(tmp_path).sqlalchemy_url)
    tables = ", ".join(t.name for t in Base.metadata.sorted_tables)
    with engine.begin() as conn:
        conn.execute(text(f"TRUNCATE {tables} CASCADE"))
    engine.dispose()


@pytest.fixture
def settings(tmp_path: Path) -> Settings:
    return make_settings(tmp_path)


@pytest.fixture
def client(settings: Settings) -> Iterator[TestClient]:
    with TestClient(create_app(settings)) as c:
        yield c


@pytest.fixture
def client_factory(tmp_path: Path) -> Iterator[Callable[..., TestClient]]:
    opened: list[TestClient] = []

    def factory(**overrides: Any) -> TestClient:
        c = TestClient(create_app(make_settings(tmp_path, **overrides)))
        c.__enter__()
        opened.append(c)
        return c

    yield factory
    for c in opened:
        c.__exit__(None, None, None)


def login(
    c: TestClient, role: str, name: str, phone: str, passcode: str | None = None
) -> dict[str, str]:
    r = c.post(
        "/auth/demo-login", json={"role": role, "name": name, "phone": phone, "passcode": passcode}
    )
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}
