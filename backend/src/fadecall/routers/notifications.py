"""The signed-in user's notification inbox (any role)."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Query

from ..auth import CurrentUser
from ..deps import DB
from ..errors import not_found
from ..models import Notification, get_by_id
from ..serializers import notification_json
from ..services import notifications as svc
from ..services import requests as requests_svc
from ..timeutil import utcnow

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("")
def list_notifications(
    user: CurrentUser, db: DB, limit: int = Query(50, ge=1, le=200)
) -> dict[str, Any]:
    # The app polls this, so it doubles as the clock for request offers timing out.
    requests_svc.sweep(db)
    items, unread = svc.inbox(db, user.id, limit)
    return {"items": [notification_json(n) for n in items], "unread_count": unread}


@router.post("/read-all")
def read_all(user: CurrentUser, db: DB) -> dict[str, int]:
    return {"marked": svc.mark_all_read(db, user.id), "unread_count": 0}


@router.post("/{notification_id}/read")
def read_one(notification_id: str, user: CurrentUser, db: DB) -> dict[str, Any]:
    n = get_by_id(db, Notification, notification_id)
    if n is None or n.user_id != user.id:
        raise not_found("Notification")
    if n.read_at is None:
        n.read_at = utcnow()
        db.commit()
    return notification_json(n)
