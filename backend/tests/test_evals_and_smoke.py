"""Prompt eval harness and live smoke script, exercised offline in mock mode."""

from __future__ import annotations

import asyncio
from pathlib import Path
from typing import Any

import pytest

from fadecall import smoke
from fadecall.ai import prompts as P
from fadecall.ai.mock import MockModelClient
from fadecall.config import Settings
from fadecall.evals import harness
from fadecall.evals.schema import validate


def test_harness_mock_all_tasks_pass_and_report(settings: Settings, tmp_path: Path) -> None:
    results = asyncio.run(harness.run_evals(MockModelClient(settings)))
    tasks = {r.task for r in results}
    assert tasks == set(harness.TASKS)
    assert [r for r in results if not r.ok] == []
    assert {r.case for r in results if r.task == "profile"} == {
        "english",
        "isizulu_english",
        "sesotho_english",
    }
    text = harness.render_report(results, "mock", {"spark": "mock"})
    path = harness.write_report(text, tmp_path)
    body = path.read_text()
    assert f"{len(results)}/{len(results)} cases passed" in body
    assert "| same_person | different_faces | PASS |" in body


class BadModel(MockModelClient):
    """Returns schema-invalid or wrong answers to prove the harness catches them."""

    async def spark_json(
        self, system: str, user_text: str, images: list[bytes], schema: dict[str, Any], name: str
    ) -> dict[str, Any]:
        out = await super().spark_json(system, user_text, images, schema, name)
        if name == P.GRADE_NAME:
            out["scores"]["finish"] = 14
        if name == P.SAME_PERSON_NAME:
            out["result"] = "pass"
        if name == P.PROFILE_NAME:
            out["profile"]["area_id"] = "sandton"
        return out


def test_harness_flags_bad_outputs(settings: Settings) -> None:
    results = asyncio.run(harness.run_evals(BadModel(settings)))
    failed = {(r.task, r.case) for r in results if not r.ok}
    assert ("grading", "pair_1") in failed
    assert ("same_person", "different_faces") in failed
    assert ("same_person", "same_face") not in failed
    assert ("profile", "english") in failed


def test_schema_validator() -> None:
    good = {"result": "pass", "confidence": 0.9, "reason": "x"}
    assert validate(good, P.CHECK_SCHEMA) == []
    errs = validate({"result": "maybe", "confidence": 2, "extra": 1}, P.CHECK_SCHEMA)
    assert any("enum" in e for e in errs)
    assert any("maximum" in e for e in errs)
    assert any("missing 'reason'" in e for e in errs)
    assert any("unexpected 'extra'" in e for e in errs)
    assert validate({"minutes": True}, {"properties": {"minutes": {"type": "integer"}}}) != []


def test_harness_cli_rejects_live_without_key(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(harness, "get_settings", lambda: Settings(_env_file=None))  # type: ignore[call-arg]
    assert harness.main(["--live"]) == 2
    assert harness.main(["--only", "nonsense"]) == 2


def test_smoke_without_key_exits_2(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setattr(smoke, "get_settings", lambda: Settings(_env_file=None))  # type: ignore[call-arg]
    assert smoke.main([]) == 2
    assert "MODEL_API_KEY" in capsys.readouterr().out
    assert smoke.main(["--list-models"]) == 2


def test_smoke_mock_paths(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str], tmp_path: Path
) -> None:
    monkeypatch.setattr(smoke, "get_settings", lambda: Settings(_env_file=None))  # type: ignore[call-arg]
    assert smoke.main(["--mock"]) == 0
    out = capsys.readouterr().out
    assert out.count("PASS") == 3
    wav = tmp_path / "note.wav"
    wav.write_bytes(smoke.sine_wav())
    assert smoke.main(["--mock", "--voice", str(wav)]) == 0
    out = capsys.readouterr().out
    assert 'languageBias ["English"]' in out and "no languageBias" in out
    assert "Muse Spark cleaned:" in out


def test_webhost_serves_web_build_and_api(settings: Settings, tmp_path: Path) -> None:
    from fastapi.testclient import TestClient

    from fadecall.webhost import create_web_app

    web = tmp_path / "web"
    web.mkdir()
    (web / "index.html").write_text("<html>fade call</html>")
    (web / "main.dart.js").write_text("console.log(1)")
    with TestClient(create_web_app(str(web), settings)) as c:
        assert c.get("/").text == "<html>fade call</html>"
        assert c.get("/main.dart.js").status_code == 200
        assert c.get("/health").json()["status"] == "ok"
        assert c.get("/jobs").json()["error"]["code"] == "unauthorized"
    with pytest.raises(RuntimeError, match=r"index\.html"):
        create_web_app(str(tmp_path / "missing"), settings)
