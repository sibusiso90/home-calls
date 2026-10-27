"""Live smoke test for the Meta Model API: one real call per model.

    uv run python -m fadecall.smoke                 # Spark + Transcribe + SAM, PASS/FAIL each
    uv run python -m fadecall.smoke --list-models   # GET /v1/models, check our model IDs
    uv run python -m fadecall.smoke --voice FILE    # transcribe a real recording two ways
                                                    # (languageBias ["English"] vs none)

Exit codes: 0 all passed, 1 a call failed, 2 MODEL_API_KEY is not set.
`--mock` runs the same code paths against the offline mock (for tests).
"""

from __future__ import annotations

import argparse
import asyncio
import json
import shutil
import sys
import tempfile
import time
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import httpx

from .ai import prompts as P
from .ai.meta import MetaModelClient
from .ai.mock import MockModelClient
from .ai.types import ModelClient
from .audio import to_wav
from .config import Settings, get_settings
from .samples import SKIN_TONES, head_image, sine_wav

SPEECH_TEXT = (
    "Hello, my name is Thabo. I have been cutting hair for six years in Midrand. "
    "I do skin fades and tapers, weekdays after four."
)


@dataclass
class Result:
    name: str
    model: str
    ok: bool
    latency_ms: int
    preview: str


def _preview(value: Any, limit: int = 110) -> str:
    text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
    text = " ".join(text.split())
    return text if len(text) <= limit else text[: limit - 1] + "…"


async def _timed(
    name: str, model: str, call: Callable[[], Awaitable[Any]], show: Callable[[Any], Any]
) -> Result:
    started = time.perf_counter()
    try:
        out = await call()
        return Result(
            name, model, True, int((time.perf_counter() - started) * 1000), _preview(show(out))
        )
    except Exception as exc:  # report every failure, never crash the run
        ms = int((time.perf_counter() - started) * 1000)
        return Result(name, model, False, ms, f"{type(exc).__name__}: {_preview(str(exc), 200)}")


async def speech_wav(settings: Settings) -> tuple[bytes, str]:
    """A short spoken English clip via macOS `say` if available, else a sine tone."""
    say = shutil.which("say")
    if say:
        with tempfile.TemporaryDirectory() as tmp:
            aiff = Path(tmp) / "speech.aiff"
            proc = await asyncio.create_subprocess_exec(say, "-o", str(aiff), SPEECH_TEXT)
            if await proc.wait() == 0 and aiff.is_file():
                wav = await to_wav(aiff.read_bytes(), settings.ffmpeg_path, required=False)
                if wav[:4] == b"RIFF":
                    return wav, "macOS `say` speech"
    return sine_wav(), "sine tone (no speech; expect an empty transcript)"


async def run_smoke(models: ModelClient, wav: bytes) -> list[Result]:
    before = head_image(SKIN_TONES[2], "full", 1)
    image = head_image(SKIN_TONES[2], "fade", 1)
    v = models.versions
    spark = _timed(
        "Muse Spark (JSON + images)",
        v["spark"],
        lambda: models.spark_json(
            P.GRADE_SYSTEM, P.grade_user_text(), [before, image], P.GRADE_SCHEMA, P.GRADE_NAME
        ),
        lambda out: out.get("scores", out),
    )
    asr = _timed(
        "Muse Voice Transcribe",
        v["transcribe"],
        lambda: models.transcribe(wav, P.TRANSCRIBE_LANGUAGE_BIAS, P.TRANSCRIBE_KEYWORDS),
        lambda t: repr(t.text),
    )
    sam = _timed(
        'SAM 3.1 ("hair")',
        v["sam"],
        lambda: models.segment_hair(image),
        lambda s: f"{len(s.masks)} mask(s), hair area {s.area_ratio():.1%} of frame",
    )
    return list(await asyncio.gather(spark, asr, sam))


async def list_models(settings: Settings) -> int:
    url = settings.model_api_base_url.rstrip("/") + "/models"
    async with httpx.AsyncClient(timeout=30) as http:
        resp = await http.get(url, headers={"Authorization": f"Bearer {settings.model_api_key}"})
    if resp.status_code != 200:
        print(f"FAIL  GET {url} -> {resp.status_code}: {resp.text[:300]}")
        return 1
    body = resp.json()
    ids = sorted(str(m.get("id")) for m in body.get("data", []) if isinstance(m, dict))
    print(f"{len(ids)} model(s) available to this key:")
    for i in ids:
        print(f"  {i}")
    wanted = {
        "spark": settings.spark_model,
        "transcribe": settings.transcribe_model,
        "sam": settings.sam_model,
    }
    missing = [m for m in wanted.values() if m not in ids]
    for role, m in wanted.items():
        print(f"{'OK   ' if m in ids else 'MISS '} {role:<10} {m}")
    return 1 if missing else 0


async def voice_check(models: ModelClient, settings: Settings, name: str, audio: bytes) -> int:
    wav = await to_wav(audio, settings.ffmpeg_path)
    print(f"Converted {name} -> {len(wav) / 1024:.0f} KB mono 16-bit 24 kHz WAV\n")
    status = 0
    for label, bias in (('languageBias ["English"]', ["English"]), ("no languageBias", [])):
        print(f"=== {label} ===")
        started = time.perf_counter()
        try:
            t = await models.transcribe(wav, bias, P.TRANSCRIBE_KEYWORDS)
        except Exception as exc:
            print(f"FAIL  {type(exc).__name__}: {exc}\n")
            status = 1
            continue
        print(f"transcript ({int((time.perf_counter() - started) * 1000)} ms): {t.text!r}")
        try:
            data = await models.spark_json(
                P.PROFILE_SYSTEM,
                P.profile_user_text(t.text, "Barber"),
                [],
                P.PROFILE_SCHEMA,
                P.PROFILE_NAME,
            )
        except Exception as exc:
            print(f"Muse Spark FAIL  {type(exc).__name__}: {exc}\n")
            status = 1
            continue
        print(f"Muse Spark language: {data.get('language_detected')}")
        print(f"Muse Spark cleaned:  {data.get('clean_transcript')}")
        print(f"Profile: {json.dumps(data.get('profile'), ensure_ascii=False)}")
        print(f"Read-back: {data.get('read_back')}\n")
    return status


async def _run(args: argparse.Namespace, settings: Settings) -> int:
    if args.list_models:
        return await list_models(settings)
    models: ModelClient = MockModelClient(settings) if args.mock else MetaModelClient(settings)
    try:
        if args.voice:
            return await voice_check(models, settings, args.voice.name, args.voice.read_bytes())
        wav, source = (sine_wav(), "sine tone") if args.mock else await speech_wav(settings)
        print(f"Mode: {models.mode}  base: {settings.model_api_base_url}  audio: {source}\n")
        results = await run_smoke(models, wav)
    finally:
        await models.aclose()
    for r in results:
        status = "PASS" if r.ok else "FAIL"
        print(f"{status}  {r.name:<28} {r.model:<26} {r.latency_ms:>6} ms  {r.preview}")
    return 0 if all(r.ok for r in results) else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--list-models", action="store_true", help="GET /v1/models and check IDs")
    parser.add_argument(
        "--voice", type=Path, help="transcribe this recording with two bias settings"
    )
    parser.add_argument("--mock", action="store_true", help="use the offline mock (tests only)")
    args = parser.parse_args(argv)

    settings = get_settings()
    if not settings.model_api_key and not args.mock:
        print("MODEL_API_KEY is not set. Set it (env or backend/.env) to run the live smoke test.")
        return 2
    if args.list_models and args.mock:
        print("--list-models needs the live API")
        return 2
    if args.voice and not args.voice.is_file():
        print(f"No such file: {args.voice}")
        return 2
    return asyncio.run(_run(args, settings))


if __name__ == "__main__":
    sys.exit(main())
