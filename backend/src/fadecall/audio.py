"""Audio conversion to the WAV format Muse Voice Transcribe accepts.

WAV only: mono, 16-bit PCM, 16 or 24 kHz, max 10 minutes / 32 MB.
"""

from __future__ import annotations

import asyncio
import io
import shutil
import wave

from .errors import validation

MAX_BYTES = 32 * 1024 * 1024


def is_accepted_wav(data: bytes) -> bool:
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        return False
    try:
        with wave.open(io.BytesIO(data)) as w:
            return (
                w.getnchannels() == 1
                and w.getsampwidth() == 2
                and w.getframerate() in (16_000, 24_000)
                and w.getnframes() / w.getframerate() <= 600
            )
    except (wave.Error, EOFError):
        return False


async def to_wav(data: bytes, ffmpeg: str = "ffmpeg", *, required: bool = True) -> bytes:
    """Convert any browser audio (webm/ogg/m4a/wav...) to mono 16-bit 24 kHz WAV.

    If ffmpeg is unavailable and `required` is False (mock mode), the input is
    returned unchanged.
    """
    if not data:
        raise validation("audio: empty file")
    if len(data) > MAX_BYTES:
        raise validation("audio: larger than 32 MB")
    if is_accepted_wav(data):
        return data
    exe = shutil.which(ffmpeg)
    if exe is None:
        if required:
            raise validation("audio: ffmpeg is not installed on the server")
        return data
    proc = await asyncio.create_subprocess_exec(
        exe,
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        "pipe:0",
        "-t",
        "600",
        "-ac",
        "1",
        "-ar",
        "24000",
        "-c:a",
        "pcm_s16le",
        "-map_metadata",
        "-1",
        "-f",
        "wav",
        "pipe:1",
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    out, err = await proc.communicate(data)
    if proc.returncode != 0 or not out:
        if not required:
            return data
        raise validation(f"audio: could not decode ({err.decode(errors='ignore')[:200]})")
    return _fix_wav_header(out)


def _fix_wav_header(data: bytes) -> bytes:
    """ffmpeg writing to a pipe leaves RIFF sizes unset; rewrite a clean header."""
    try:
        idx = data.index(b"data") + 8
    except ValueError:
        return data
    pcm = data[idx:]
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(24_000)
        w.writeframes(pcm[: len(pcm) - (len(pcm) % 2)])
    return buf.getvalue()
