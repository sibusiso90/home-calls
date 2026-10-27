"""Run every Muse Spark prompt over fixtures and check schema + expectations.

    uv run python -m fadecall.evals            # offline mock models
    uv run python -m fadecall.evals --live     # real Meta Model API (needs MODEL_API_KEY)
    uv run python -m fadecall.evals --only profile,same_person

Uses the exact prompts, schemas and user-text builders from ai/prompts.py (and the
same image normalisation and SAM coverage input as the services), so a report
reflects what production sends. Writes backend/evals/reports/<timestamp>.md.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import time
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

from ..ai import prompts as P
from ..ai.meta import MetaModelClient
from ..ai.mock import MockModelClient
from ..ai.types import ModelClient
from ..areas import AREAS_BY_ID
from ..config import BACKEND_DIR, Settings, get_settings
from ..imaging import normalise_photo
from ..samples import demo_set
from .schema import validate

EVALS_DIR = BACKEND_DIR / "evals"
FIXTURES_DIR = EVALS_DIR / "fixtures"
REPORTS_DIR = EVALS_DIR / "reports"
TASKS = ("profile", "grading", "cut_id", "same_person", "cut_match", "dispute")


@dataclass
class CaseResult:
    task: str
    case: str
    failures: list[str] = field(default_factory=list)
    latency_ms: int = 0
    output: Any = None

    @property
    def ok(self) -> bool:
        return not self.failures


class Ctx:
    def __init__(self, models: ModelClient, fixtures: Path) -> None:
        self.models = models
        self.fixtures = fixtures
        self._images = {k: v for k, v in demo_set().items() if k.endswith(".jpg")}

    def image(self, name: str) -> bytes:
        path = self.fixtures / "images" / name
        data = path.read_bytes() if path.is_file() else self._images[name]
        return normalise_photo(data, name)

    def text(self, name: str) -> str:
        return (self.fixtures / "transcripts" / name).read_text(encoding="utf-8").strip()


def _expect(failures: list[str], cond: bool, message: str) -> None:
    if not cond:
        failures.append(message)


def _lower(items: Any) -> list[str]:
    return [str(i).lower() for i in items] if isinstance(items, list) else []


# -- per-task checks -------------------------------------------------------------


async def eval_profile(ctx: Ctx, case: dict[str, Any], f: list[str]) -> Any:
    text = ctx.text(case["transcript"])
    out = await ctx.models.spark_json(
        P.PROFILE_SYSTEM,
        P.profile_user_text(text, case.get("signed_up_as", "Barber")),
        [],
        P.PROFILE_SCHEMA,
        P.PROFILE_NAME,
    )
    f += validate(out, P.PROFILE_SCHEMA)
    prof = out.get("profile") or {}
    exp = case.get("expect", {})
    area = prof.get("area_id")
    _expect(f, area in AREAS_BY_ID, f"area_id {area!r} is not a launch suburb")
    if "area_id" in exp:
        _expect(f, area == exp["area_id"], f"area_id {area!r} != {exp['area_id']!r}")
    if "years_cutting" in exp:
        got = prof.get("years_cutting")
        _expect(f, got == exp["years_cutting"], f"years_cutting {got!r} != {exp['years_cutting']}")
    if "name_contains" in exp:
        name = str(prof.get("name", ""))
        _expect(
            f,
            exp["name_contains"].lower() in name.lower(),
            f"name {name!r} lacks {exp['name_contains']!r}",
        )
    if "styles_any" in exp:
        styles = _lower(prof.get("styles"))
        hit = any(any(s in got for got in styles) for s in exp["styles_any"])
        _expect(f, hit, f"styles {styles} share none of {exp['styles_any']}")
    if "languages_any" in exp:
        langs = _lower(prof.get("languages"))
        hit = any(lang.lower() in langs for lang in exp["languages_any"])
        _expect(f, hit, f"languages {langs} lack {exp['languages_any']}")
    _expect(f, bool(str(out.get("read_back", "")).strip()), "empty read_back")
    return out


async def eval_grading(ctx: Ctx, case: dict[str, Any], f: list[str]) -> Any:
    imgs = [ctx.image(case["before"]), ctx.image(case["after"])]
    out = await ctx.models.spark_json(
        P.GRADE_SYSTEM, P.grade_user_text(), imgs, P.GRADE_SCHEMA, P.GRADE_NAME
    )
    f += validate(out, P.GRADE_SCHEMA)
    for k, v in (out.get("scores") or {}).items():
        _expect(f, isinstance(v, int) and 0 <= v <= 10, f"score {k}={v!r} outside 0-10")
    for k, v in (out.get("reasons") or {}).items():
        _expect(f, len(str(v).strip()) >= 10, f"reason {k} too short: {v!r}")
    return out


async def eval_cut_id(ctx: Ctx, case: dict[str, Any], f: list[str]) -> Any:
    selfie, ref = ctx.image(case["selfie"]), ctx.image(case["reference"])
    seg_s, seg_r = await asyncio.gather(
        ctx.models.segment_hair(selfie), ctx.models.segment_hair(ref)
    )
    out = await ctx.models.spark_json(
        P.CUT_SYSTEM,
        P.cut_user_text(seg_s.area_ratio(), seg_r.area_ratio()),
        [selfie, ref],
        P.CUT_SCHEMA,
        P.CUT_NAME,
    )
    f += validate(out, P.CUT_SCHEMA)
    _expect(f, bool(str(out.get("cut_name", "")).strip()), "empty cut_name")
    _expect(f, 10 <= int(out.get("minutes") or 0) <= 180, f"minutes {out.get('minutes')!r}")
    _expect(f, bool(str(out.get("reasons", "")).strip()), "empty reasons")
    return out


def _check_expect(out: dict[str, Any], exp: dict[str, Any], f: list[str]) -> None:
    if "result_not" in exp:
        res = out.get("result")
        _expect(f, res != exp["result_not"], f"result {res!r} should not be {exp['result_not']!r}")
    if "result" in exp:
        _expect(f, out.get("result") == exp["result"], f"result {out.get('result')!r}")


async def eval_same_person(ctx: Ctx, case: dict[str, Any], f: list[str]) -> Any:
    imgs = [ctx.image(case["before"]), ctx.image(case["after"])]
    out = await ctx.models.spark_json(
        P.SAME_PERSON_SYSTEM,
        P.same_person_user_text(),
        imgs,
        P.CHECK_SCHEMA,
        P.SAME_PERSON_NAME,
    )
    f += validate(out, P.CHECK_SCHEMA)
    _check_expect(out, case.get("expect", {}), f)
    return out


async def eval_cut_match(ctx: Ctx, case: dict[str, Any], f: list[str]) -> Any:
    imgs = [ctx.image(case["after"])]
    if case.get("reference"):
        imgs.append(ctx.image(case["reference"]))
    out = await ctx.models.spark_json(
        P.CUT_MATCH_SYSTEM,
        P.cut_match_user_text(case["cut_name"], case.get("fit_issues", []), len(imgs) > 1),
        imgs,
        P.CHECK_SCHEMA,
        P.CUT_MATCH_NAME,
    )
    f += validate(out, P.CHECK_SCHEMA)
    _check_expect(out, case.get("expect", {}), f)
    return out


async def eval_dispute(ctx: Ctx, case: dict[str, Any], f: list[str]) -> Any:
    job = {"cut": "Mid skin fade", "minutes": 50, "quote_zar": 385, "status": "verified"}
    out = await ctx.models.spark_json(
        P.DISPUTE_SYSTEM,
        P.dispute_user_text(case["transcript"], case.get("text"), job, case.get("checks", {})),
        [],
        P.DISPUTE_SCHEMA,
        P.DISPUTE_NAME,
    )
    f += validate(out, P.DISPUTE_SCHEMA)
    for k in ("summary", "client_claim", "evidence_notes"):
        _expect(f, bool(str(out.get(k, "")).strip()), f"empty {k}")
    exp = case.get("expect", {})
    if "outcome_not" in exp:
        got = out.get("suggested_outcome")
        _expect(
            f,
            got != exp["outcome_not"],
            f"suggested_outcome {got!r} should not be {exp['outcome_not']!r}",
        )
    return out


RUNNERS: dict[str, Callable[[Ctx, dict[str, Any], list[str]], Awaitable[Any]]] = {
    "profile": eval_profile,
    "grading": eval_grading,
    "cut_id": eval_cut_id,
    "same_person": eval_same_person,
    "cut_match": eval_cut_match,
    "dispute": eval_dispute,
}


async def run_evals(
    models: ModelClient, fixtures: Path = FIXTURES_DIR, only: list[str] | None = None
) -> list[CaseResult]:
    cases = json.loads((fixtures / "cases.json").read_text(encoding="utf-8"))
    ctx = Ctx(models, fixtures)
    results: list[CaseResult] = []
    for task in TASKS:
        if only and task not in only:
            continue
        for case in cases.get(task, []):
            r = CaseResult(task, case["id"])
            started = time.perf_counter()
            try:
                r.output = await RUNNERS[task](ctx, case, r.failures)
            except Exception as exc:  # a crashing case is a failed case
                r.failures.append(f"{type(exc).__name__}: {exc}")
            r.latency_ms = int((time.perf_counter() - started) * 1000)
            results.append(r)
    return results


def render_report(results: list[CaseResult], mode: str, versions: dict[str, str]) -> str:
    passed = sum(r.ok for r in results)
    lines = [
        f"# Prompt eval report — {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        "",
        f"- Mode: **{mode}**; models: {', '.join(f'{k}={v}' for k, v in versions.items())}",
        f"- Result: **{passed}/{len(results)} cases passed**",
        "",
        "| Task | Case | Result | Latency | Failures |",
        "| --- | --- | --- | --- | --- |",
    ]
    for r in results:
        fails = "<br>".join(x.replace("|", "\\|") for x in r.failures) or "–"
        status = "PASS" if r.ok else "FAIL"
        lines.append(f"| {r.task} | {r.case} | {status} | {r.latency_ms} ms | {fails} |")
    lines += ["", "## Outputs", ""]
    for r in results:
        lines += [
            f"### {r.task} / {r.case}",
            "",
            "```json",
            json.dumps(r.output, ensure_ascii=False, indent=2),
            "```",
            "",
        ]
    return "\n".join(lines)


def write_report(text: str, out_dir: Path = REPORTS_DIR) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"{datetime.now().strftime('%Y%m%d-%H%M%S')}.md"
    path.write_text(text, encoding="utf-8")
    return path


async def _run(settings: Settings, live: bool, only: list[str] | None, out_dir: Path) -> int:
    models: ModelClient = MetaModelClient(settings) if live else MockModelClient(settings)
    try:
        results = await run_evals(models, only=only)
    finally:
        await models.aclose()
    path = write_report(render_report(results, models.mode, models.versions), out_dir)
    for r in results:
        detail = "" if r.ok else "  <- " + "; ".join(r.failures)
        print(
            f"{'PASS' if r.ok else 'FAIL'}  {r.task:<12} {r.case:<28} {r.latency_ms:>6} ms{detail}"
        )
    print(f"\n{sum(r.ok for r in results)}/{len(results)} passed. Report: {path}")
    return 0 if all(r.ok for r in results) else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--live", action="store_true", help="call the real Meta Model API")
    parser.add_argument("--only", help=f"comma-separated subset of: {', '.join(TASKS)}")
    parser.add_argument("--out", type=Path, default=REPORTS_DIR, help="report directory")
    args = parser.parse_args(argv)
    settings = get_settings()
    if args.live and not settings.model_api_key:
        print("--live needs MODEL_API_KEY (env or backend/.env).")
        return 2
    only = [t.strip() for t in args.only.split(",")] if args.only else None
    if only and (bad := [t for t in only if t not in TASKS]):
        print(f"Unknown task(s): {', '.join(bad)}")
        return 2
    if not args.live:
        settings = settings.model_copy(update={"mock_force_review": False})
    return asyncio.run(_run(settings, args.live, only, args.out))
