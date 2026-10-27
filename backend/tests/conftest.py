from __future__ import annotations

from collections.abc import Callable, Iterator
from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient

from fadecall.config import Settings
from fadecall.main import create_app


def make_settings(tmp_path: Path, **overrides: Any) -> Settings:
    base: dict[str, Any] = {
        "database_url": f"sqlite:///{tmp_path / 'test.db'}",
        "local_media_dir": tmp_path / "media",
        "model_api_key": None,
        "secret_key": "test-secret",
        "operator_passcode": "letmein",
        "mock_force_review": False,
        "public_base_url": None,
    }
    base.update(overrides)
    return Settings(_env_file=None, **base)  # type: ignore[call-arg]


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
