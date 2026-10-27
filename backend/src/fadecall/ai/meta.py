"""Live Meta Model API client (https://api.meta.ai/v1).

- Muse Spark: Chat Completions, base64 data-URL images, response_format json_schema.
- Muse Voice Transcribe: multipart POST /asr/transcribe (WAV mono 16-bit, 16/24 kHz).
- SAM 3.1: streaming /responses, concept prompt "hair", output_text deltas parsed
  with meta_sam_parser.
"""

from __future__ import annotations

import asyncio
import base64
import io
import json
import logging
import random
from typing import Any

import httpx
import openai
from openai import AsyncOpenAI
from PIL import Image

from ..config import Settings
from ..errors import ModelError
from .sam import parse_sam_output
from .types import Segmentation, Transcript

log = logging.getLogger(__name__)

RETRY_STATUS = {429, 500, 502, 503}


def data_url(image_bytes: bytes) -> str:
    mime = "image/png" if image_bytes[:8] == b"\x89PNG\r\n\x1a\n" else "image/jpeg"
    return f"data:{mime};base64,{base64.b64encode(image_bytes).decode()}"


def image_size(image_bytes: bytes) -> tuple[int, int]:
    with Image.open(io.BytesIO(image_bytes)) as im:
        return im.size


class MetaModelClient:
    mode = "live"

    def __init__(
        self, settings: Settings, transport: httpx.AsyncBaseTransport | None = None
    ) -> None:
        self.settings = settings
        self.versions = {
            "spark": settings.spark_model,
            "transcribe": settings.transcribe_model,
            "sam": settings.sam_model,
        }
        timeout = httpx.Timeout(settings.model_timeout_s, connect=10.0)
        # The SDK retries 408/409/429/5xx with exponential backoff and honours Retry-After.
        self._openai = AsyncOpenAI(
            api_key=settings.model_api_key,
            base_url=settings.model_api_base_url,
            timeout=timeout,
            max_retries=settings.model_max_retries,
            http_client=httpx.AsyncClient(transport=transport, timeout=timeout)
            if transport
            else None,
        )
        self._http = httpx.AsyncClient(
            base_url=settings.model_api_base_url.rstrip("/") + "/",
            timeout=timeout,
            transport=transport,
            headers={"Authorization": f"Bearer {settings.model_api_key}"},
        )

    async def aclose(self) -> None:
        await self._openai.close()
        await self._http.aclose()

    # -- Muse Spark -----------------------------------------------------------
    async def spark_json(
        self,
        system: str,
        user_text: str,
        images: list[bytes],
        schema: dict[str, Any],
        name: str,
    ) -> dict[str, Any]:
        content: list[dict[str, Any]] = [{"type": "text", "text": user_text}]
        content += [{"type": "image_url", "image_url": {"url": data_url(i)}} for i in images]
        try:
            resp = await self._openai.chat.completions.create(
                model=self.settings.spark_model,
                messages=[
                    {"role": "system", "content": system},
                    {"role": "user", "content": content},
                ],
                response_format={
                    "type": "json_schema",
                    "json_schema": {"name": name, "schema": schema},
                },
            )
        except openai.APIError as exc:
            log.warning("Muse Spark %s failed: %s", name, exc)
            raise ModelError(f"Muse Spark ({name}) failed: {exc}") from exc
        text = (resp.choices[0].message.content or "").strip() if resp.choices else ""
        try:
            data = json.loads(text)
        except json.JSONDecodeError as exc:
            raise ModelError(f"Muse Spark ({name}) returned invalid JSON") from exc
        if not isinstance(data, dict):
            raise ModelError(f"Muse Spark ({name}) returned a non-object")
        return data

    # -- Muse Voice Transcribe -----------------------------------------------
    async def transcribe(
        self,
        wav_bytes: bytes,
        language_bias: list[str],
        keywords: list[str] | None = None,
        purpose: str = "profile",
    ) -> Transcript:
        request: dict[str, Any] = {
            "model": self.settings.transcribe_model,
            "audioEncoding": "WAV",
            "mode": "PUSH_TO_TALK",
        }
        if language_bias:
            request["languageBias"] = language_bias
        if keywords:
            request["keywords"] = keywords
        files = {
            "request": (None, json.dumps(request), "application/json"),
            "audio": ("audio.wav", wav_bytes, "audio/wav"),
        }
        resp = await self._post_with_retry(
            "asr/transcribe", files=files, headers={"Accept": "application/json"}
        )
        body = resp.json()
        return Transcript(
            text=str(body.get("transcript", "")).strip(),
            duration_ms=body.get("audioDurationMs"),
            session_id=body.get("sessionId"),
        )

    async def _post_with_retry(self, path: str, **kwargs: Any) -> httpx.Response:
        attempts = self.settings.model_max_retries + 1
        for attempt in range(attempts):
            try:
                resp = await self._http.post(path, **kwargs)
            except httpx.HTTPError as exc:
                if attempt + 1 >= attempts:
                    raise ModelError(f"Transcription request failed: {exc}") from exc
                await asyncio.sleep(self._backoff(attempt, None))
                continue
            if resp.status_code < 400:
                return resp
            if resp.status_code in RETRY_STATUS and attempt + 1 < attempts:
                await asyncio.sleep(self._backoff(attempt, resp.headers.get("Retry-After")))
                continue
            raise ModelError(f"Transcription failed ({resp.status_code}): {resp.text[:300]}")
        raise ModelError("Transcription failed after retries")

    @staticmethod
    def _backoff(attempt: int, retry_after: str | None) -> float:
        if retry_after:
            try:
                return min(float(retry_after), 30.0)
            except ValueError:
                pass
        return min(0.5 * 2**attempt, 8.0) + random.uniform(0, 0.25)

    # -- SAM 3.1 --------------------------------------------------------------
    async def segment_hair(self, image_bytes: bytes) -> Segmentation:
        width, height = image_size(image_bytes)
        chunks: list[str] = []
        try:
            stream = await self._openai.responses.create(
                model=self.settings.sam_model,
                input=[
                    {
                        "type": "message",
                        "role": "user",
                        "content": [
                            {"type": "input_text", "text": "hair"},
                            {"type": "input_image", "image_url": data_url(image_bytes)},
                        ],
                    }
                ],
                stream=True,
                metadata={"mask_encoding": "one_bit"},
            )
            async for event in stream:
                etype = getattr(event, "type", "")
                if etype == "response.output_text.delta":
                    chunks.append(getattr(event, "delta", "") or "")
                elif etype == "response.completed":
                    break
                elif etype in ("response.failed", "error", "response.incomplete"):
                    raise ModelError(f"SAM 3.1 stream ended with {etype}")
        except openai.APIError as exc:
            log.warning("SAM 3.1 failed: %s", exc)
            raise ModelError(f"SAM 3.1 failed: {exc}") from exc
        try:
            return parse_sam_output("".join(chunks), width, height)
        except Exception as exc:  # parser/decoder errors
            raise ModelError(f"Could not parse SAM 3.1 output: {exc}") from exc
