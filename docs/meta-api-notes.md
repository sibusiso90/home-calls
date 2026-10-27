# Meta Model API notes

What the Fade Call backend relies on, checked against dev.meta.ai/docs on 26 Oct 2026.

## Basics

- Base URL `https://api.meta.ai/v1`, bearer auth with `MODEL_API_KEY`.
- OpenAI-compatible: the `openai` Python SDK works with `base_url` set.
- Models: `muse-spark-1.3` (vision + text), `muse-voice-transcribe-1.0`, `sam-3.1`.
- Errors (rechecked 27 Oct): retry 429/500 with backoff and 503 after `Retry-After`. Never retry 400/401/402/403/404/413. Don't blindly retry 504. A mid-stream failure arrives as an SSE `error` or `response.failed` event under HTTP 200; for `error`, retry the full request. Our client caps each call at `MODEL_DEADLINE_S` and returns a clean 502 `model_error`.

## Muse Spark: images and structured output

- Images go in as `input_image` blocks (Responses API) whose `image_url` is a public URL or a `data:image/jpeg;base64,...` URL. Chat Completions wraps it as `{"type": "image_url", "image_url": {"url": ...}}`.
- Structured output: Chat Completions uses `response_format={"type": "json_schema", "json_schema": {"name", "schema"}}`; Responses uses `text.format`. Decoding is schema-constrained.

## Muse Voice Transcribe

- `POST /v1/asr/transcribe`, multipart: a `request` JSON part (`{"model": "muse-voice-transcribe-1.0", "audioEncoding": "WAV", "mode": "PUSH_TO_TALK", "languageBias": [...]}`) and an `audio` part.
- `languageBias` takes language names (`["English"]`), not codes; omit it to auto-detect. The response is `{sessionId, transcript, audioDurationMs, turns}`.
- WAV only: mono, 16-bit PCM, 16 or 24 kHz, max 10 minutes and 32 MB. Convert browser audio first:
  `ffmpeg -i in.webm -ac 1 -ar 24000 -c:a pcm_s16le -map_metadata -1 out.wav`
- **Language gap:** the 25 supported languages include no South African language (no isiZulu, isiXhosa, Sesotho, Setswana or Afrikaans). English works; isiZulu is untested and best-effort. Muse Spark tidies the transcript and extracts the profile either way.

## SAM 3.1

- `POST /v1/responses` with `model: "sam-3.1"`, `stream: true`, and a user message holding an `input_text` noun phrase (we use `"hair"`) and an `input_image`.
- The output is special-token text, one line per frame: `<0f>id<|box;x1=..;y1=..;x2=..;y2=..;w=..;h=..|><|mask;x=0;y=0;data=H,W,~payload|>,...`
- Masks are base85, not base64. Decode with the `meta-sam-parser` package (`decode_mask_to_raster`).
- `metadata.mask_encoding: "one_bit"` gives the smallest payloads (marker `!`; the default is `~`, lossless).
- Zero matches is valid: the stream completes with empty text.
