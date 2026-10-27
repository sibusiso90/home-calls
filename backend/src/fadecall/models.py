"""ORM models. Postgres DDL mirrors these in supabase/migrations/0001_init.sql."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import (
    DDL,
    Boolean,
    CheckConstraint,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    Uuid,
    event,
    text,
)
from sqlalchemy.orm import Mapped, Session, mapped_column, relationship

from .db import Base, JSONType, UTCDateTime
from .timeutil import utcnow


def new_id() -> str:
    return str(uuid.uuid4())


ID = Uuid(as_uuid=False)


def _id_col() -> Mapped[str]:
    return mapped_column(ID, primary_key=True, default=new_id)


def _created() -> Mapped[datetime]:
    return mapped_column(UTCDateTime, default=utcnow, nullable=False)


class User(Base):
    __tablename__ = "users"
    __table_args__ = (UniqueConstraint("role", "phone_key", name="uq_users_role_phone"),)

    id: Mapped[str] = _id_col()
    role: Mapped[str] = mapped_column(String(16))
    name: Mapped[str] = mapped_column(String(120))
    phone: Mapped[str | None] = mapped_column(String(32))
    phone_key: Mapped[str] = mapped_column(String(160))
    created_at: Mapped[datetime] = _created()


class Barber(Base):
    __tablename__ = "barbers"

    id: Mapped[str] = _id_col()
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), unique=True)
    name: Mapped[str] = mapped_column(String(120))
    area_id: Mapped[str | None] = mapped_column(String(64))
    languages: Mapped[list[str]] = mapped_column(JSONType, default=list)
    years_cutting: Mapped[int | None] = mapped_column(Integer)
    styles: Mapped[list[str]] = mapped_column(JSONType, default=list)
    availability: Mapped[str | None] = mapped_column(Text)
    tier: Mapped[str | None] = mapped_column(String(16))
    price_min_zar: Mapped[int | None] = mapped_column(Integer)
    price_max_zar: Mapped[int | None] = mapped_column(Integer)
    grade_average: Mapped[float | None] = mapped_column(Float)
    grade_summary: Mapped[str | None] = mapped_column(Text)
    verified_jobs: Mapped[int] = mapped_column(Integer, default=0)
    rating: Mapped[float | None] = mapped_column(Float)
    status: Mapped[str] = mapped_column(String(24), default="onboarding")
    status_reason: Mapped[str | None] = mapped_column(Text)
    profile_confirmed: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = _created()

    portfolio: Mapped[list[PortfolioItem]] = relationship(
        back_populates="barber",
        order_by="PortfolioItem.created_at",
        cascade="all, delete-orphan",
    )


class PortfolioItem(Base):
    __tablename__ = "portfolio_items"

    id: Mapped[str] = _id_col()
    barber_id: Mapped[str] = mapped_column(ForeignKey("barbers.id", ondelete="CASCADE"))
    before_key: Mapped[str] = mapped_column(Text)
    after_key: Mapped[str] = mapped_column(Text)
    scores: Mapped[dict[str, Any]] = mapped_column(JSONType)
    reasons: Mapped[dict[str, Any]] = mapped_column(JSONType)
    overall: Mapped[float] = mapped_column(Float)
    model_versions: Mapped[dict[str, Any]] = mapped_column(JSONType, default=dict)
    elapsed_ms: Mapped[int | None] = mapped_column(Integer)  # Muse Spark grading time
    created_at: Mapped[datetime] = _created()

    barber: Mapped[Barber] = relationship(back_populates="portfolio")


class Client(Base):
    __tablename__ = "clients"

    id: Mapped[str] = _id_col()
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), unique=True)
    name: Mapped[str] = mapped_column(String(120))
    phone: Mapped[str | None] = mapped_column(String(32))
    area_id: Mapped[str | None] = mapped_column(String(64))
    created_at: Mapped[datetime] = _created()


class Quote(Base):
    __tablename__ = "quotes"

    id: Mapped[str] = _id_col()
    client_id: Mapped[str] = mapped_column(ForeignKey("clients.id"))
    area_id: Mapped[str] = mapped_column(String(64))
    cut_name: Mapped[str] = mapped_column(Text)
    # How the client chose the cut: reference photo, catalog pick, or our suggestion.
    cut_source: Mapped[str] = mapped_column(String(16), default="reference")
    cut_id: Mapped[str | None] = mapped_column(String(64))  # catalog id; None for custom
    minutes: Mapped[int] = mapped_column(Integer)
    fit_issues: Mapped[list[str]] = mapped_column(JSONType, default=list)
    reasons: Mapped[str] = mapped_column(Text)
    face_advice: Mapped[str | None] = mapped_column(Text)
    suggestions: Mapped[list[dict[str, Any]]] = mapped_column(JSONType, default=list)
    selfie_key: Mapped[str] = mapped_column(Text)
    reference_key: Mapped[str | None] = mapped_column(Text)
    selfie_overlay_key: Mapped[str | None] = mapped_column(Text)
    reference_overlay_key: Mapped[str | None] = mapped_column(Text)
    masks: Mapped[dict[str, Any]] = mapped_column(JSONType, default=dict)
    elapsed_ms: Mapped[int] = mapped_column(Integer, default=0)
    model_versions: Mapped[dict[str, Any]] = mapped_column(JSONType, default=dict)
    created_at: Mapped[datetime] = _created()


class Job(Base):
    __tablename__ = "jobs"
    __table_args__ = (
        # One live booking per barber per slot; mirrors 0001_init.sql.
        Index(
            "uq_jobs_barber_slot",
            "barber_id",
            "slot_start",
            unique=True,
            sqlite_where=text("status <> 'cancelled'"),
            postgresql_where=text("status <> 'cancelled'"),
        ),
    )

    id: Mapped[str] = _id_col()
    quote_id: Mapped[str | None] = mapped_column(ForeignKey("quotes.id"))
    barber_id: Mapped[str] = mapped_column(ForeignKey("barbers.id"))
    client_id: Mapped[str] = mapped_column(ForeignKey("clients.id"))
    cut: Mapped[str] = mapped_column(Text)
    minutes: Mapped[int] = mapped_column(Integer)
    quote_zar: Mapped[int] = mapped_column(Integer)
    price: Mapped[dict[str, Any]] = mapped_column(JSONType, default=dict)
    travel_band: Mapped[str] = mapped_column(String(1))
    slot_start: Mapped[datetime] = mapped_column(UTCDateTime)
    slot_end: Mapped[datetime] = mapped_column(UTCDateTime)
    address: Mapped[str] = mapped_column(Text)
    lat: Mapped[float] = mapped_column(Float)
    lng: Mapped[float] = mapped_column(Float)
    status: Mapped[str] = mapped_column(String(24), default="booked")
    payment_status: Mapped[str] = mapped_column(String(24), default="deposit_pending")
    deposit_url: Mapped[str | None] = mapped_column(Text)
    consented_demo: Mapped[bool] = mapped_column(Boolean, default=False)
    # Lifecycle (0004_notifications_cancel.sql)
    reminder_sent_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    cancelled_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    cancelled_by: Mapped[str | None] = mapped_column(String(16))
    cancel_reason: Mapped[str | None] = mapped_column(Text)
    rescheduled_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    created_at: Mapped[datetime] = _created()

    barber: Mapped[Barber] = relationship()
    client: Mapped[Client] = relationship()
    quote: Mapped[Quote | None] = relationship()
    evidence: Mapped[Evidence | None] = relationship(back_populates="job", uselist=False)
    rating: Mapped[Rating | None] = relationship(uselist=False)
    disputes: Mapped[list[Dispute]] = relationship(
        back_populates="job", order_by="Dispute.created_at"
    )


class BookingRequest(Base):
    """A client's ask for a cut on a day, in one or more time windows.

    Offered first to the chosen barber for a few minutes, then to every barber in
    range. The barber who accepts picks the start time, which creates the Job.
    """

    __tablename__ = "booking_requests"

    id: Mapped[str] = _id_col()
    quote_id: Mapped[str] = mapped_column(ForeignKey("quotes.id"))
    client_id: Mapped[str] = mapped_column(ForeignKey("clients.id"))
    day: Mapped[str] = mapped_column(String(10))  # YYYY-MM-DD, South African date
    windows: Mapped[list[str]] = mapped_column(JSONType, default=list)
    address: Mapped[str] = mapped_column(Text)
    lat: Mapped[float] = mapped_column(Float)
    lng: Mapped[float] = mapped_column(Float)
    chosen_barber_id: Mapped[str | None] = mapped_column(ForeignKey("barbers.id"))
    offered_until: Mapped[datetime | None] = mapped_column(UTCDateTime)
    broadcast_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    declined_by: Mapped[list[str]] = mapped_column(JSONType, default=list)
    status: Mapped[str] = mapped_column(String(16), default="open")
    job_id: Mapped[str | None] = mapped_column(ForeignKey("jobs.id"))
    closed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    created_at: Mapped[datetime] = _created()

    quote: Mapped[Quote] = relationship()
    client: Mapped[Client] = relationship()
    chosen_barber: Mapped[Barber | None] = relationship()
    job: Mapped[Job | None] = relationship()


class Evidence(Base):
    __tablename__ = "evidence"

    id: Mapped[str] = _id_col()
    job_id: Mapped[str] = mapped_column(ForeignKey("jobs.id"), unique=True)
    before_key: Mapped[str | None] = mapped_column(Text)
    after_key: Mapped[str | None] = mapped_column(Text)
    before_overlay_key: Mapped[str | None] = mapped_column(Text)
    after_overlay_key: Mapped[str | None] = mapped_column(Text)
    before_capture: Mapped[dict[str, Any]] = mapped_column(JSONType, default=dict)
    after_capture: Mapped[dict[str, Any]] = mapped_column(JSONType, default=dict)
    masks: Mapped[dict[str, Any]] = mapped_column(JSONType, default=dict)
    checks: Mapped[dict[str, Any]] = mapped_column(JSONType, default=dict)
    verdict: Mapped[str | None] = mapped_column(String(16))
    verdict_reasons: Mapped[list[str]] = mapped_column(JSONType, default=list)
    decided_by: Mapped[str | None] = mapped_column(String(16))
    operator_reason: Mapped[str | None] = mapped_column(Text)
    model_versions: Mapped[dict[str, Any]] = mapped_column(JSONType, default=dict)
    decided_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    elapsed_ms: Mapped[int | None] = mapped_column(Integer)  # after photo in -> model verdict
    purged_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    created_at: Mapped[datetime] = _created()

    job: Mapped[Job] = relationship(back_populates="evidence")


class Rating(Base):
    __tablename__ = "ratings"
    __table_args__ = (CheckConstraint("stars BETWEEN 1 AND 5", name="ck_ratings_stars"),)

    id: Mapped[str] = _id_col()
    job_id: Mapped[str] = mapped_column(ForeignKey("jobs.id"), unique=True)
    stars: Mapped[int] = mapped_column(Integer)
    comment: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = _created()


class Dispute(Base):
    __tablename__ = "disputes"
    __table_args__ = (
        # At most one open dispute per job; mirrors 0001_init.sql.
        Index(
            "uq_disputes_open",
            "job_id",
            unique=True,
            sqlite_where=text("outcome IS NULL"),
            postgresql_where=text("outcome IS NULL"),
        ),
    )

    id: Mapped[str] = _id_col()
    job_id: Mapped[str] = mapped_column(ForeignKey("jobs.id"))
    transcript: Mapped[str] = mapped_column(Text, default="")
    summary: Mapped[str] = mapped_column(Text, default="")
    client_claim: Mapped[str] = mapped_column(Text, default="")
    evidence_notes: Mapped[str] = mapped_column(Text, default="")
    suggested_outcome: Mapped[str | None] = mapped_column(String(24))
    outcome: Mapped[str | None] = mapped_column(String(24))
    resolution_reason: Mapped[str | None] = mapped_column(Text)
    payment_status_before: Mapped[str | None] = mapped_column(String(24))
    model_versions: Mapped[dict[str, Any]] = mapped_column(JSONType, default=dict)
    elapsed_ms: Mapped[int | None] = mapped_column(Integer)  # transcribe + summarise time
    created_at: Mapped[datetime] = _created()
    resolved_at: Mapped[datetime | None] = mapped_column(UTCDateTime)

    job: Mapped[Job] = relationship(back_populates="disputes")


class Payout(Base):
    __tablename__ = "payouts"
    __table_args__ = (
        # At most one live (non-reversed) payout per job; mirrors 0003_payout_guard.sql.
        Index(
            "uq_payouts_active_job",
            "job_id",
            unique=True,
            sqlite_where=text("status <> 'reversed'"),
            postgresql_where=text("status <> 'reversed'"),
        ),
    )

    id: Mapped[str] = _id_col()
    job_id: Mapped[str] = mapped_column(ForeignKey("jobs.id"))
    barber_id: Mapped[str] = mapped_column(ForeignKey("barbers.id"))
    amount_zar: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String(16), default="released")
    created_at: Mapped[datetime] = _created()

    barber: Mapped[Barber] = relationship()


class Notification(Base):
    """An in-app notification (and the record of any WhatsApp copy sent)."""

    __tablename__ = "notifications"
    __table_args__ = (Index("ix_notifications_user_created", "user_id", "created_at"),)

    id: Mapped[str] = _id_col()
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    job_id: Mapped[str | None] = mapped_column(ForeignKey("jobs.id", ondelete="SET NULL"))
    request_id: Mapped[str | None] = mapped_column(
        ForeignKey("booking_requests.id", ondelete="SET NULL")
    )
    kind: Mapped[str] = mapped_column(String(32))
    title: Mapped[str] = mapped_column(String(160))
    body: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = _created()
    read_at: Mapped[datetime | None] = mapped_column(UTCDateTime)


# DB-level guard mirroring the app rule: a rating needs a pass verdict.
# (Postgres equivalent lives in supabase/migrations/0001_init.sql.)
event.listen(
    Rating.__table__,
    "after_create",
    DDL(
        """
        CREATE TRIGGER IF NOT EXISTS ratings_require_pass
        BEFORE INSERT ON ratings
        WHEN COALESCE((SELECT verdict FROM evidence WHERE job_id = NEW.job_id), '')
             <> 'pass'
        BEGIN
            SELECT RAISE(ABORT, 'verdict_required: rating needs a pass verdict');
        END;
        """
    ).execute_if(dialect="sqlite"),
)


def get_by_id[T: Base](db: Session, model: type[T], ident: str) -> T | None:
    """db.get that treats malformed ids as missing instead of raising."""
    try:
        uuid.UUID(str(ident))
    except ValueError:
        return None
    return db.get(model, str(ident))
