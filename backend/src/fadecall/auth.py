"""Demo auth: HMAC-signed bearer tokens and role-based dependencies."""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import time
from collections.abc import Callable
from typing import Annotated

from fastapi import Depends, Header, Request
from sqlalchemy.orm import Session

from .deps import get_db
from .errors import ApiError
from .models import User

ROLES = ("barber", "client", "operator")


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _unb64(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def issue_token(secret: str, user_id: str, role: str, ttl_s: int, now: float | None = None) -> str:
    iat = int(now if now is not None else time.time())
    payload = _b64(
        json.dumps({"sub": user_id, "role": role, "iat": iat, "exp": iat + ttl_s}).encode()
    )
    sig = _b64(hmac.new(secret.encode(), payload.encode(), hashlib.sha256).digest())
    return f"{payload}.{sig}"


def read_token(secret: str, token: str, now: float | None = None) -> dict[str, object] | None:
    try:
        payload, sig = token.split(".", 1)
        expected = _b64(hmac.new(secret.encode(), payload.encode(), hashlib.sha256).digest())
        # Compare bytes: compare_digest raises TypeError on non-ASCII str input.
        if not hmac.compare_digest(expected.encode(), sig.encode("utf-8", "surrogatepass")):
            return None
        data = json.loads(_unb64(payload))
        if not isinstance(data, dict):
            return None
        exp = int(data.get("exp", 0))
    except (ValueError, TypeError, json.JSONDecodeError, UnicodeError):
        return None
    if exp < (now if now is not None else time.time()):
        return None
    return data


def _unauthorized(message: str = "Sign in required") -> ApiError:
    return ApiError(401, "unauthorized", message)


def current_user(
    request: Request,
    db: Annotated[Session, Depends(get_db)],
    authorization: Annotated[str | None, Header()] = None,
) -> User:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise _unauthorized()
    claims = read_token(request.app.state.settings.secret_key, authorization[7:].strip())
    if claims is None:
        raise _unauthorized("Invalid or expired token")
    user = db.get(User, str(claims["sub"]))
    if user is None or user.role != claims.get("role"):
        raise _unauthorized("Unknown user")
    return user


CurrentUser = Annotated[User, Depends(current_user)]


def require_role(*roles: str) -> Callable[[User], User]:
    def dep(user: CurrentUser) -> User:
        if user.role not in roles:
            raise ApiError(403, "forbidden", f"This needs the {' or '.join(roles)} role")
        return user

    return dep


BarberUser = Annotated[User, Depends(require_role("barber"))]
ClientUser = Annotated[User, Depends(require_role("client"))]
OperatorUser = Annotated[User, Depends(require_role("operator"))]
