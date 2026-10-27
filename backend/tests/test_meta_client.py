"""MetaModelClient against a fake Meta Model API (no network, no key needed).

Checks the request shapes from the docs: Chat Completions with json_schema and
data-URL images, multipart /asr/transcribe with a JSON `request` part, and the
streaming /responses SAM call whose output_text deltas are parsed into masks.
"""

from __future__ import annotations

import asyncio
import io
import json
from pathlib import Path
from typing import Any

import httpx
import numpy as np
import pytest
from PIL import Image

from fadecall.ai import prompts as P
from fadecall.ai.meta import MetaModelClient
from fadecall.ai.sam import encode_sam_line
from fadecall.errors import ModelError
from fadecall.samples import SKIN_TONES, head_image, sine_wav

from .conftest import make_settings


class FakeMeta:
    def __init__(self) -> None:
        self.requests: list[httpx.Request] = []
        self.asr_failures = 0

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        assert request.headers["authorization"] == "Bearer test-key"
        path = request.url.path
        if path.endswith("/chat/completions"):
            body = json.loads(request.content)
            content = json.dumps({"result": "pass", "confidence": 0.91, "reason": "Same ears."})
            assert body["response_format"]["type"] == "json_schema"
            return httpx.Response(
                200,
                json={
                    "id": "c1",
                    "object": "chat.completion",
                    "created": 0,
                    "model": body["model"],
                    "choices": [
                        {
                            "index": 0,
                            "message": {"role": "assistant", "content": content},
                            "finish_reason": "stop",
                        }
                    ],
                },
            )
        if path.endswith("/asr/transcribe"):
            if self.asr_failures:
                self.asr_failures -= 1
                return httpx.Response(429, headers={"Retry-After": "0"}, json={"error": {}})
            return httpx.Response(
                200,
                json={
                    "sessionId": "s1",
                    "transcript": "Igama lami ngu Thabo",
                    "audioDurationMs": 1500,
                    "turns": [],
                },
            )
        if path.endswith("/responses"):
            body = json.loads(request.content)
            assert body["model"] == "sam-3.1" and body["stream"] is True
            mask = np.zeros((40, 50), dtype=bool)
            mask[5:20, 10:40] = True
            line = encode_sam_line(mask)
            events = [
                {
                    "type": "response.output_text.delta",
                    "item_id": "m1",
                    "output_index": 0,
                    "content_index": 0,
                    "delta": line[:30],
                    "sequence_number": 1,
                    "logprobs": [],
                },
                {
                    "type": "response.output_text.delta",
                    "item_id": "m1",
                    "output_index": 0,
                    "content_index": 0,
                    "delta": line[30:],
                    "sequence_number": 2,
                    "logprobs": [],
                },
                {
                    "type": "response.completed",
                    "sequence_number": 3,
                    "response": {
                        "id": "r1",
                        "object": "response",
                        "created_at": 0,
                        "status": "completed",
                        "model": "sam-3.1",
                        "output": [],
                    },
                },
            ]
            sse = "".join(f"event: {e['type']}\ndata: {json.dumps(e)}\n\n" for e in events)
            return httpx.Response(200, text=sse, headers={"content-type": "text/event-stream"})
        return httpx.Response(404, json={"error": {"message": "nope"}})


@pytest.fixture
def fake_client(tmp_path: Path) -> tuple[MetaModelClient, FakeMeta]:
    fake = FakeMeta()
    settings = make_settings(tmp_path, model_api_key="test-key", model_max_retries=2)
    return MetaModelClient(settings, transport=httpx.MockTransport(fake)), fake


def test_spark_json_request_shape(fake_client: tuple[MetaModelClient, FakeMeta]) -> None:
    client, fake = fake_client
    img = head_image(SKIN_TONES[0], "fade", 1)
    out = asyncio.run(
        client.spark_json("sys", "hello", [img, img], P.CHECK_SCHEMA, P.SAME_PERSON_NAME)
    )
    assert out["result"] == "pass"
    body = json.loads(fake.requests[-1].content)
    assert body["model"] == "muse-spark-1.3"
    assert body["messages"][0] == {"role": "system", "content": "sys"}
    parts = body["messages"][1]["content"]
    assert parts[0] == {"type": "text", "text": "hello"}
    assert parts[1]["type"] == "image_url"
    assert parts[1]["image_url"]["url"].startswith("data:image/jpeg;base64,")
    assert body["response_format"]["json_schema"]["name"] == P.SAME_PERSON_NAME


def test_transcribe_multipart_and_retry(fake_client: tuple[MetaModelClient, FakeMeta]) -> None:
    client, fake = fake_client
    fake.asr_failures = 1
    t = asyncio.run(client.transcribe(sine_wav(), ["English"], ["Midrand"]))
    assert t.text == "Igama lami ngu Thabo" and t.duration_ms == 1500
    asr = [r for r in fake.requests if r.url.path.endswith("/asr/transcribe")]
    assert len(asr) == 2  # one 429, one success
    body = asr[-1].content
    assert b'name="request"' in body and b'name="audio"' in body
    assert b'"audioEncoding": "WAV"' in body and b'"languageBias": ["English"]' in body
    assert b'"model": "muse-voice-transcribe-1.0"' in body


def test_transcribe_gives_model_error_after_retries(
    fake_client: tuple[MetaModelClient, FakeMeta],
) -> None:
    client, fake = fake_client
    fake.asr_failures = 10
    with pytest.raises(ModelError):
        asyncio.run(client.transcribe(sine_wav(), ["English"]))


def test_sam_stream_parsed_into_masks(fake_client: tuple[MetaModelClient, FakeMeta]) -> None:
    client, fake = fake_client
    buf = io.BytesIO()
    Image.new("RGB", (50, 40), "white").save(buf, "JPEG")
    seg = asyncio.run(client.segment_hair(buf.getvalue()))
    assert len(seg.masks) == 1
    assert seg.masks[0].box == (10, 5, 40, 20)
    assert 0.2 < seg.area_ratio() < 0.25
    body: dict[str, Any] = json.loads(fake.requests[-1].content)
    content = body["input"][0]["content"]
    assert content[0] == {"type": "input_text", "text": "hair"}
    assert content[1]["type"] == "input_image"
    assert body["metadata"] == {"mask_encoding": "one_bit"}
