"""Private media storage and short-lived signed URLs.

Objects are never public: clients get `/media/{key}?exp=..&sig=..` URLs signed
with HMAC-SHA256 over ``key`` and ``exp`` using SECRET_KEY (15-minute expiry),
and the backend streams the object after checking the signature.
"""

from __future__ import annotations

import contextvars
import hashlib
import hmac
import mimetypes
import time
from pathlib import Path
from typing import Protocol
from urllib.parse import quote

import httpx

from .config import Settings

# Set per request by middleware so signed URLs are absolute for the web app.
request_base_url: contextvars.ContextVar[str] = contextvars.ContextVar(
    "request_base_url", default=""
)


class Storage(Protocol):
    async def put(self, key: str, data: bytes, content_type: str) -> None: ...
    async def get(self, key: str) -> tuple[bytes, str] | None: ...
    async def delete(self, key: str) -> None: ...
    async def aclose(self) -> None: ...


def _guess_type(key: str) -> str:
    return mimetypes.guess_type(key)[0] or "application/octet-stream"


def _safe_key(key: str) -> str:
    parts = [p for p in key.split("/") if p]
    if not parts or any(p in (".", "..") or "\\" in p for p in parts):
        raise ValueError(f"Invalid storage key: {key!r}")
    return "/".join(parts)


class LocalStorage:
    """Files under backend/.data/media (gitignored). For local dev and tests."""

    def __init__(self, root: Path) -> None:
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)

    def _path(self, key: str) -> Path:
        return self.root / _safe_key(key)

    async def put(self, key: str, data: bytes, content_type: str) -> None:
        path = self._path(key)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    async def get(self, key: str) -> tuple[bytes, str] | None:
        try:
            path = self._path(key)
        except ValueError:
            return None
        if not path.is_file():
            return None
        return path.read_bytes(), _guess_type(key)

    async def delete(self, key: str) -> None:
        path = self._path(key)
        if path.is_file():
            path.unlink()

    async def aclose(self) -> None:
        return None


class SupabaseStorage:
    """Supabase Storage REST API against a private bucket, using the service key."""

    def __init__(self, url: str, service_key: str, bucket: str) -> None:
        self.bucket = bucket
        self._http = httpx.AsyncClient(
            base_url=url.rstrip("/") + "/storage/v1/",
            headers={"Authorization": f"Bearer {service_key}", "apikey": service_key},
            timeout=30.0,
        )

    def _obj(self, key: str) -> str:
        return f"object/{self.bucket}/{quote(_safe_key(key))}"

    async def put(self, key: str, data: bytes, content_type: str) -> None:
        resp = await self._http.post(
            self._obj(key),
            content=data,
            headers={"Content-Type": content_type, "x-upsert": "true"},
        )
        resp.raise_for_status()

    async def get(self, key: str) -> tuple[bytes, str] | None:
        resp = await self._http.get(self._obj(key))
        if resp.status_code in (400, 404):
            return None
        resp.raise_for_status()
        return resp.content, resp.headers.get("content-type", _guess_type(key))

    async def delete(self, key: str) -> None:
        resp = await self._http.delete(self._obj(key))
        if resp.status_code not in (200, 204, 404):
            resp.raise_for_status()

    async def aclose(self) -> None:
        await self._http.aclose()


def make_storage(settings: Settings) -> Storage:
    if settings.storage_backend == "supabase":
        if not (settings.supabase_url and settings.supabase_service_key):
            raise RuntimeError(
                "STORAGE_BACKEND=supabase needs SUPABASE_URL and SUPABASE_SERVICE_KEY"
            )
        return SupabaseStorage(
            settings.supabase_url, settings.supabase_service_key, settings.supabase_bucket
        )
    return LocalStorage(settings.local_media_dir)


# -- signing -------------------------------------------------------------------


def media_signature(secret: str, key: str, exp: int) -> str:
    msg = f"{key}\n{exp}".encode()
    return hmac.new(secret.encode(), msg, hashlib.sha256).hexdigest()


def verify_media_signature(
    secret: str, key: str, exp: int, sig: str, now: float | None = None
) -> bool:
    if exp < (now if now is not None else time.time()):
        return False
    # Compare bytes: compare_digest raises TypeError on non-ASCII str input.
    return hmac.compare_digest(
        media_signature(secret, key, exp).encode(), sig.encode("utf-8", "surrogatepass")
    )


class UrlSigner:
    def __init__(self, settings: Settings) -> None:
        self.secret = settings.secret_key
        self.ttl = settings.media_url_ttl_s
        self.public_base = (settings.public_base_url or "").rstrip("/")

    def url(self, key: str | None, now: float | None = None) -> str | None:
        if not key:
            return None
        exp = int((now if now is not None else time.time()) + self.ttl)
        sig = media_signature(self.secret, key, exp)
        base = self.public_base or request_base_url.get().rstrip("/")
        return f"{base}/media/{quote(key)}?exp={exp}&sig={sig}"
