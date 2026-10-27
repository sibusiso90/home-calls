"""Error envelope: {"error": {"code": ..., "message": ...}}."""

from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message


class ModelError(Exception):
    """A model call failed after retries. Surfaces as 502 model_error."""


def not_found(what: str = "Resource") -> ApiError:
    return ApiError(404, "not_found", f"{what} not found")


def conflict(message: str) -> ApiError:
    return ApiError(409, "conflict", message)


def forbidden(message: str = "You do not have access to this resource") -> ApiError:
    return ApiError(403, "forbidden", message)


def validation(message: str) -> ApiError:
    return ApiError(422, "validation", message)


_STATUS_CODES = {
    400: "validation",
    401: "unauthorized",
    403: "forbidden",
    404: "not_found",
    405: "validation",
    409: "conflict",
    413: "validation",
    422: "validation",
    502: "model_error",
}


def _envelope(status: int, code: str, message: str) -> JSONResponse:
    return JSONResponse(status_code=status, content={"error": {"code": code, "message": message}})


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def _api_error(_: Request, exc: ApiError) -> JSONResponse:
        return _envelope(exc.status, exc.code, exc.message)

    @app.exception_handler(ModelError)
    async def _model_error(_: Request, exc: ModelError) -> JSONResponse:
        return _envelope(502, "model_error", str(exc) or "Model call failed")

    @app.exception_handler(RequestValidationError)
    async def _validation(_: Request, exc: RequestValidationError) -> JSONResponse:
        parts = []
        for err in exc.errors():
            loc = ".".join(str(p) for p in err.get("loc", ()) if p != "body")
            parts.append(f"{loc}: {err.get('msg')}" if loc else str(err.get("msg")))
        return _envelope(422, "validation", "; ".join(parts) or "Invalid request")

    @app.exception_handler(StarletteHTTPException)
    async def _http(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        code = _STATUS_CODES.get(exc.status_code, "error")
        return _envelope(exc.status_code, code, str(exc.detail))
