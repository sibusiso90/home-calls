# Local stand-in for the Modal image (modal_app.py): Python 3.12, ffmpeg, deps from uv.lock.
# Used by compose.yaml at the repo root; see docs/local-docker.md.
FROM python:3.12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*
COPY --from=ghcr.io/astral-sh/uv:0.10.9 /uv /usr/local/bin/uv

WORKDIR /srv/backend
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy PATH="/srv/backend/.venv/bin:$PATH"

# Dependencies first so code edits don't reinstall them.
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
COPY README.md ./
COPY src ./src
RUN uv sync --frozen --no-dev

ENV ENV=prod STORAGE_BACKEND=supabase FFMPEG_PATH=ffmpeg
EXPOSE 8000
CMD ["uvicorn", "fadecall.webhost:app", "--host", "0.0.0.0", "--port", "8000"]
