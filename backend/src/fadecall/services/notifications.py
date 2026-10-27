"""Notifications: an in-app inbox for every user, plus optional WhatsApp copies.

Every event writes a `notifications` row (the in-app inbox). External channels
are `Notifier`s. `InAppNotifier` is the default and does nothing beyond the row;
`WhatsAppNotifier` (the product-spec stretch goal) sends a text message through
the Meta WhatsApp Cloud API and is enabled only when both WHATSAPP_TOKEN and
WHATSAPP_PHONE_ID are set. It is never constructed in tests.
"""

from __future__ import annotations

import logging
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, Protocol

import httpx
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from ..config import Settings
from ..models import BookingRequest, Job, Notification, User
from ..timeutil import SAST, ensure_utc, utcnow

log = logging.getLogger("fadecall.notifications")

KINDS = (
    "booking_created",
    "job_confirmed",
    "deposit_paid",
    "verdict_pass",
    "verdict_needs_review",
    "verdict_operator",
    "dispute_opened",
    "dispute_resolved",
    "job_cancelled",
    "job_rescheduled",
    "reminder",
    "request_new",
    "request_accepted",
    "request_update",
)


@dataclass(frozen=True)
class Message:
    user_id: str
    phone: str | None
    title: str
    body: str


class Notifier(Protocol):
    name: str

    def send(self, message: Message) -> None: ...


class InAppNotifier:
    """The inbox row is the notification; nothing else to send."""

    name = "in_app"

    def send(self, message: Message) -> None:
        return None


class WhatsAppNotifier:
    """Meta WhatsApp Cloud API text message (stretch goal; off unless configured).

    POST https://graph.facebook.com/{version}/{phone_id}/messages
    {"messaging_product": "whatsapp", "to": "27821234567", "type": "text",
     "text": {"preview_url": false, "body": "..."}}

    Production use needs an approved message template for business-initiated
    messages outside the 24-hour window; this stub sends free-form text.
    """

    name = "whatsapp"

    def __init__(
        self,
        token: str,
        phone_id: str,
        api_version: str = "v21.0",
        client: httpx.Client | None = None,
    ) -> None:
        self.url = f"https://graph.facebook.com/{api_version}/{phone_id}/messages"
        self._token = token
        self._client = client or httpx.Client(timeout=10)

    @staticmethod
    def payload(message: Message) -> dict[str, Any] | None:
        digits = "".join(ch for ch in (message.phone or "") if ch.isdigit())
        if not digits:
            return None
        return {
            "messaging_product": "whatsapp",
            "to": digits,
            "type": "text",
            "text": {"preview_url": False, "body": f"{message.title}\n{message.body}".strip()},
        }

    def send(self, message: Message) -> None:
        body = self.payload(message)
        if body is None:
            return
        try:
            r = self._client.post(
                self.url, json=body, headers={"Authorization": f"Bearer {self._token}"}
            )
            if r.status_code >= 400:
                log.warning("WhatsApp send failed (%s): %s", r.status_code, r.text[:200])
        except httpx.HTTPError as exc:  # never break the request over a side channel
            log.warning("WhatsApp send failed: %s", exc)


_external: list[Notifier] = []


def configure(settings: Settings) -> list[Notifier]:
    """Pick the external notifiers for this process (called at app start)."""
    _external.clear()
    if settings.whatsapp_token and settings.whatsapp_phone_id:
        _external.append(
            WhatsAppNotifier(
                settings.whatsapp_token, settings.whatsapp_phone_id, settings.whatsapp_api_version
            )
        )
    return [InAppNotifier(), *_external]


def notify(
    db: Session,
    user_ids: Iterable[str | None],
    kind: str,
    title: str,
    body: str,
    job: Job | None = None,
    request: BookingRequest | None = None,
) -> list[Notification]:
    """Write one inbox row per user (deduplicated) and fan out to external channels.

    Rows are added to the session; the caller commits with its own change.
    """
    if kind not in KINDS:
        raise ValueError(f"unknown notification kind: {kind}")
    rows: list[Notification] = []
    seen: set[str] = set()
    for uid in user_ids:
        if not uid or uid in seen:
            continue
        seen.add(uid)
        row = Notification(
            user_id=uid,
            job_id=job.id if job else None,
            request_id=request.id if request else None,
            kind=kind,
            title=title,
            body=body,
        )
        db.add(row)
        rows.append(row)
        if _external:
            user = db.get(User, uid)
            msg = Message(uid, user.phone if user else None, title, body)
            for n in _external:
                n.send(msg)
    return rows


# --- who to tell -------------------------------------------------------------


def client_uid(job: Job) -> str:
    return job.client.user_id


def barber_uid(job: Job) -> str:
    return job.barber.user_id


def operator_uids(db: Session) -> list[str]:
    return list(db.scalars(select(User.id).where(User.role == "operator")))


def when(job: Job) -> str:
    """'Tue 28 Oct, 16:00' in South African time."""
    return ensure_utc(job.slot_start).astimezone(SAST).strftime("%a %-d %b, %H:%M")


# --- inbox --------------------------------------------------------------------


def inbox(db: Session, user_id: str, limit: int = 50) -> tuple[Sequence[Notification], int]:
    items = db.scalars(
        select(Notification)
        .where(Notification.user_id == user_id)
        .order_by(Notification.created_at.desc(), Notification.id.desc())
        .limit(limit)
    ).all()
    unread = len(
        db.scalars(
            select(Notification.id).where(
                Notification.user_id == user_id, Notification.read_at.is_(None)
            )
        ).all()
    )
    return items, unread


def mark_all_read(db: Session, user_id: str, now: datetime | None = None) -> int:
    res = db.execute(
        update(Notification)
        .where(Notification.user_id == user_id, Notification.read_at.is_(None))
        .values(read_at=now or utcnow())
        .execution_options(synchronize_session=False)
    )
    db.commit()
    return int(res.rowcount or 0)


# --- day-before reminders -----------------------------------------------------

REMINDER_WINDOW = timedelta(hours=24)


def send_due_reminders(db: Session, now: datetime | None = None) -> list[str]:
    """Remind both sides of every live job starting in the next 24 hours.

    Idempotent: `jobs.reminder_sent_at` is set in the same commit, and a
    reschedule clears it so the new time gets its own reminder.
    """
    now = ensure_utc(now or utcnow())
    due = db.scalars(
        select(Job).where(
            Job.status.in_(("booked", "confirmed")),
            Job.reminder_sent_at.is_(None),
            Job.slot_start > now,
            Job.slot_start <= now + REMINDER_WINDOW,
        )
    ).all()
    for job in due:
        notify(
            db,
            [client_uid(job)],
            "reminder",
            "Your cut is tomorrow" if _is_tomorrow(job, now) else "Your cut is coming up",
            f"{job.barber.name} arrives {when(job)} at {job.address}.",
            job,
        )
        notify(
            db,
            [barber_uid(job)],
            "reminder",
            "Home call coming up",
            f"{job.cut} for {job.client.name}, {when(job)} at {job.address}.",
            job,
        )
        job.reminder_sent_at = now
    db.commit()
    return [j.id for j in due]


def _is_tomorrow(job: Job, now: datetime) -> bool:
    slot_day = ensure_utc(job.slot_start).astimezone(SAST).date()
    return slot_day == (now.astimezone(SAST) + timedelta(days=1)).date()
