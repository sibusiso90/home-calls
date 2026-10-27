"""Runtime settings, read from the environment (and `.env` for local dev)."""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parents[2]
DEFAULT_SECRET_KEY = "dev-only-change-me"
DEFAULT_OPERATOR_PASSCODE = "fadecall-ops"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=BACKEND_DIR / ".env", env_file_encoding="utf-8", extra="ignore"
    )

    # Core. Anything other than "dev" refuses to start with default secrets.
    env: str = "dev"
    database_url: str = "sqlite:///./fadecall.db"
    secret_key: str = DEFAULT_SECRET_KEY
    operator_passcode: str = DEFAULT_OPERATOR_PASSCODE
    public_base_url: str | None = None
    cors_origins: list[str] = Field(default_factory=lambda: ["*"])

    # Meta Model API
    model_api_key: str | None = None
    model_api_base_url: str = "https://api.meta.ai/v1"
    spark_model: str = "muse-spark-1.3"
    transcribe_model: str = "muse-voice-transcribe-1.0"
    sam_model: str = "sam-3.1"
    model_timeout_s: float = 90.0
    model_max_retries: int = 3
    ffmpeg_path: str = "ffmpeg"

    # Mock behaviour (only used when MODEL_API_KEY is unset)
    mock_force_review: bool = False
    mock_latency_ms: int = 0

    # Storage
    storage_backend: Literal["local", "supabase"] = "local"
    local_media_dir: Path = BACKEND_DIR / ".data" / "media"
    supabase_url: str | None = None
    supabase_service_key: str | None = None
    supabase_bucket: str = "fadecall-private"

    # Signed URLs and tokens
    media_url_ttl_s: int = 15 * 60
    token_ttl_s: int = 30 * 24 * 3600

    # Raw proof photos are deleted this long after a final verdict (consent rule).
    evidence_retention_days: int = 7

    # Booking rules
    late_cancel_hours: float = 2.0  # client cancels closer than this: deposit forfeited

    # WhatsApp copies of notifications (stretch goal). Off unless both are set.
    whatsapp_token: str | None = None
    whatsapp_phone_id: str | None = None
    whatsapp_api_version: str = "v21.0"

    @model_validator(mode="after")
    def _no_default_secrets_outside_dev(self) -> Settings:
        if self.env != "dev":
            weak = [
                name
                for name, value, default in (
                    ("SECRET_KEY", self.secret_key, DEFAULT_SECRET_KEY),
                    ("OPERATOR_PASSCODE", self.operator_passcode, DEFAULT_OPERATOR_PASSCODE),
                )
                if not value or value == default
            ]
            if weak:
                raise ValueError(
                    f"ENV={self.env} needs non-default {' and '.join(weak)}; refusing to start"
                )
        return self

    @property
    def mode(self) -> Literal["live", "mock"]:
        return "live" if self.model_api_key else "mock"

    @property
    def sqlalchemy_url(self) -> str:
        """Normalise Supabase-style URLs to the psycopg 3 driver."""
        url = self.database_url
        for prefix in ("postgres://", "postgresql://"):
            if url.startswith(prefix):
                return "postgresql+psycopg://" + url[len(prefix) :]
        return url


@lru_cache
def get_settings() -> Settings:
    return Settings()
