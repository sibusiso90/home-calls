"""Health, auth, reference data and signed media."""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Query, Request
from fastapi.responses import Response
from pydantic import BaseModel

from ..areas import AREAS
from ..auth import CurrentUser, issue_token
from ..deps import DB, AppSettings, Store
from ..errors import ApiError
from ..serializers import user_json
from ..services.accounts import demo_login
from ..storage import verify_media_signature

router = APIRouter()


@router.get("/health")
def health(request: Request) -> dict[str, Any]:
    s = request.app.state.settings
    return {
        "status": "ok",
        "mode": s.mode,
        "models": {"spark": s.spark_model, "transcribe": s.transcribe_model, "sam": s.sam_model},
    }


class LoginBody(BaseModel):
    role: str
    name: str
    phone: str | None = None
    passcode: str | None = None


@router.post("/auth/demo-login")
def login(body: LoginBody, db: DB, settings: AppSettings) -> dict[str, Any]:
    user = demo_login(
        db,
        role=body.role,
        name=body.name,
        phone=body.phone,
        passcode=body.passcode,
        operator_passcode=settings.operator_passcode,
    )
    token = issue_token(settings.secret_key, user.id, user.role, settings.token_ttl_s)
    return {"token": token, "user": user_json(user)}


@router.get("/me")
def me(user: CurrentUser) -> dict[str, Any]:
    return user_json(user)


@router.get("/areas")
def areas() -> list[dict[str, object]]:
    return [a.as_dict() for a in AREAS]


@router.get("/media/{key:path}")
async def media(
    key: str,
    settings: AppSettings,
    storage: Store,
    exp: Annotated[int, Query()],
    sig: Annotated[str, Query()],
) -> Response:
    if not verify_media_signature(settings.secret_key, key, exp, sig):
        raise ApiError(403, "forbidden", "Media link is invalid or expired")
    obj = await storage.get(key)
    if obj is None:
        raise ApiError(404, "not_found", "Media not found")
    data, content_type = obj
    return Response(
        data,
        media_type=content_type,
        headers={"Cache-Control": "private, max-age=600", "X-Content-Type-Options": "nosniff"},
    )
