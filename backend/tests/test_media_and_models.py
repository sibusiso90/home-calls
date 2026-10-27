import asyncio
import io
import shutil
import time
import wave

import numpy as np
import pytest
from fastapi.testclient import TestClient

from fadecall.ai.mock import MockModelClient
from fadecall.ai.sam import encode_mask_payload, normalise_stream_text, parse_sam_output
from fadecall.audio import is_accepted_wav, to_wav
from fadecall.auth import issue_token, read_token
from fadecall.config import Settings
from fadecall.imaging import measure_hair_change, render_overlay
from fadecall.samples import SKIN_TONES, head_image, sine_wav
from fadecall.storage import UrlSigner, media_signature, verify_media_signature

# Verbatim example line from the SAM 3.1 docs (lossless "~" masks, two objects).
DOC_LINE = (
    "<0f>0<|box;x1=211;y1=228;x2=270;y2=254;w=320;h=334|><|mask;x=0;y=0;data=27,60,"
    "~!!!!M!0c[0o91w?q1!pIH4pPRVp2B3'7`e.ioeAf6-k/#Xd8%dX9x(|>,1<|box;x1=155;y1=228;"
    "x2=202;y2=254;w=320;h=334|><|mask;x=0;y=0;data=27,48,~!!!!J!0c[q=Pj_zs=*4C4(/./x#:"
    "/`S_GnD`=o3?X{emCgO$y@|>"
)


def test_parse_documented_sam_line() -> None:
    seg = parse_sam_output(DOC_LINE, 320, 334)
    assert [m.object_id for m in seg.masks] == ["0", "1"]
    assert seg.masks[0].box == (211, 228, 271, 255)  # x2/y2 inclusive -> half-open
    assert seg.masks[0].raster.shape == (334, 320)
    m0 = seg.masks[0].raster
    ys, xs = np.nonzero(m0)
    assert xs.min() >= 211 and xs.max() <= 270 and ys.min() >= 228 and ys.max() <= 254
    assert 0 < seg.area_ratio() < 0.1


def test_parse_built_one_bit_line_with_confidence_and_sparse_ids() -> None:
    local = np.zeros((10, 20), dtype=np.uint8)
    local[2:8, 5:15] = 1
    payload = encode_mask_payload(local)
    assert payload.startswith("!")
    line = (
        f"<0f>2<|box;x1=40;y1=10;x2=59;y2=19;w=100;h=80;c=0.91|>"
        f"<|mask;x=0;y=0;c=0.91;data=10,20,{payload}|>"
    )
    seg = parse_sam_output(line, 100, 80)
    assert len(seg.masks) == 1
    m = seg.masks[0]
    assert m.object_id == "2" and m.confidence == 0.91
    assert m.area == 60
    assert m.raster[12, 45] and not m.raster[10, 40]


def test_zero_matches_is_valid() -> None:
    assert parse_sam_output("", 100, 100).masks == []


def test_frames_split_onto_lines() -> None:
    joined = "<0f>0<|box;x1=1|><|mask;x=0|><1f>0<|box;x1=1|><|mask;x=0|>"
    assert normalise_stream_text(joined).count("\n") == 1


def test_media_signature() -> None:
    exp = int(time.time()) + 60
    sig = media_signature("k", "a/b.jpg", exp)
    assert verify_media_signature("k", "a/b.jpg", exp, sig)
    assert not verify_media_signature("k", "a/c.jpg", exp, sig)
    assert not verify_media_signature("other", "a/b.jpg", exp, sig)
    assert not verify_media_signature("k", "a/b.jpg", exp, sig, now=exp + 1)


def test_signed_url_expires_in_15_minutes(settings: Settings) -> None:
    url = UrlSigner(settings).url("x/y.png", now=1000.0)
    assert url is not None and "/media/x/y.png?exp=1900&sig=" in url


def test_media_endpoint_checks_signature(client: TestClient, settings: Settings) -> None:
    store_dir = settings.local_media_dir / "t"
    store_dir.mkdir(parents=True)
    (store_dir / "a.png").write_bytes(b"\x89PNG data")
    url = UrlSigner(settings).url("t/a.png")
    assert url is not None
    path = url[url.index("/media/") :]
    ok = client.get(path)
    assert ok.status_code == 200 and ok.content == b"\x89PNG data"
    bad = client.get(path.replace("sig=", "sig=0"))
    assert bad.status_code == 403 and bad.json()["error"]["code"] == "forbidden"
    expired = UrlSigner(settings).url("t/a.png", now=time.time() - 3600)
    assert expired is not None
    assert client.get(expired[expired.index("/media/") :]).status_code == 403


def test_tokens() -> None:
    t = issue_token("s", "u1", "barber", 60)
    claims = read_token("s", t)
    assert claims is not None and claims["sub"] == "u1"
    assert read_token("other", t) is None
    assert read_token("s", t + "x") is None
    assert read_token("s", issue_token("s", "u1", "barber", 60, now=0)) is None


def test_hair_change_and_overlay(settings: Settings) -> None:
    mock = MockModelClient(settings)
    before = head_image(SKIN_TONES[2], "full", 1)
    after = head_image(SKIN_TONES[2], "fade", 1)

    async def run() -> tuple:
        return await asyncio.gather(mock.segment_hair(before), mock.segment_hair(after))

    seg_b, seg_a = asyncio.run(run())
    assert seg_b.area_ratio() > seg_a.area_ratio() > 0
    change = measure_hair_change(before, after, seg_b, seg_a)
    assert change.change_ratio is not None and change.change_ratio >= 0.10
    same = measure_hair_change(before, before, seg_b, seg_b)
    assert same.change_ratio == 0
    png = render_overlay(before, seg_b)
    assert png.startswith(b"\x89PNG")


def test_mock_outputs_vary_with_input(settings: Settings) -> None:
    from fadecall.ai import prompts as P

    mock = MockModelClient(settings)
    a = [head_image(SKIN_TONES[0], "full", 1), head_image(SKIN_TONES[0], "fade", 1)]
    b = [head_image(SKIN_TONES[3], "full", 9), head_image(SKIN_TONES[3], "taper", 9)]
    g1 = asyncio.run(mock.spark_json("", "", a, P.GRADE_SCHEMA, P.GRADE_NAME))
    assert set(g1["scores"]) == {"fade_blend", "line_up", "symmetry", "finish"}
    assert all(0 <= v <= 10 for v in g1["scores"].values())
    assert set(g1["reasons"]) == set(g1["scores"])
    grades = {
        tuple(
            asyncio.run(mock.spark_json("", "", [*b, bytes([i])], P.GRADE_SCHEMA, P.GRADE_NAME))[
                "scores"
            ].values()
        )
        for i in range(6)
    }
    assert len(grades) > 1  # different photos -> different scores
    forced = MockModelClient(settings.model_copy(update={"mock_force_review": True}))
    r = asyncio.run(
        forced.spark_json("", "Ordered cut: X", a[1:], P.CHECK_SCHEMA, P.CUT_MATCH_NAME)
    )
    assert r["result"] == "uncertain"


@pytest.mark.skipif(shutil.which("ffmpeg") is None, reason="ffmpeg not installed")
def test_audio_converted_to_mono_24k_wav() -> None:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:  # stereo 44.1 kHz: not accepted as-is
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(44_100)
        w.writeframes(b"\x00\x01" * 2 * 44_100)
    src = buf.getvalue()
    assert not is_accepted_wav(src)
    out = asyncio.run(to_wav(src))
    assert is_accepted_wav(out)
    with wave.open(io.BytesIO(out)) as w:
        assert (w.getnchannels(), w.getsampwidth(), w.getframerate()) == (1, 2, 24_000)
        assert 0.9 < w.getnframes() / 24_000 < 1.1
    assert asyncio.run(to_wav(sine_wav())) == sine_wav()  # already valid: untouched
