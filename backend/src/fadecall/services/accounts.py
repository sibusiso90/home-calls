"""Demo login and role profile lookup."""

from __future__ import annotations

import re

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..errors import ApiError, not_found, validation
from ..models import Barber, Client, User

ROLES = ("barber", "client", "operator")


def phone_key(phone: str | None, name: str) -> str:
    if phone:
        digits = re.sub(r"[^\d+]", "", phone)
        if digits.startswith("0") and len(digits) == 10:
            digits = "+27" + digits[1:]
        if digits:
            return digits
    return "name:" + name.strip().lower()


def demo_login(
    db: Session,
    *,
    role: str,
    name: str,
    phone: str | None,
    passcode: str | None,
    operator_passcode: str,
) -> User:
    if role not in ROLES:
        raise validation("role must be barber, client or operator")
    name = (name or "").strip()
    if not name:
        raise validation("name is required")
    if role == "operator" and passcode != operator_passcode:
        raise ApiError(401, "unauthorized", "Operator passcode is incorrect")
    key = phone_key(phone, name)
    user = db.scalar(select(User).where(User.role == role, User.phone_key == key))
    if user is None:
        user = User(role=role, name=name, phone=phone, phone_key=key)
        db.add(user)
        db.flush()
    ensure_role_profile(db, user)
    db.commit()
    return user


def ensure_role_profile(db: Session, user: User) -> None:
    if user.role == "barber" and find_barber(db, user) is None:
        db.add(Barber(user_id=user.id, name=user.name, languages=[], styles=[]))
    elif user.role == "client" and find_client(db, user) is None:
        db.add(Client(user_id=user.id, name=user.name, phone=user.phone))
    db.flush()


def find_barber(db: Session, user: User) -> Barber | None:
    return db.scalar(select(Barber).where(Barber.user_id == user.id))


def find_client(db: Session, user: User) -> Client | None:
    return db.scalar(select(Client).where(Client.user_id == user.id))


def barber_for(db: Session, user: User) -> Barber:
    b = find_barber(db, user)
    if b is None:
        ensure_role_profile(db, user)
        db.commit()
        b = find_barber(db, user)
    if b is None:
        raise not_found("Barber profile")
    return b


def client_for(db: Session, user: User) -> Client:
    c = find_client(db, user)
    if c is None:
        ensure_role_profile(db, user)
        db.commit()
        c = find_client(db, user)
    if c is None:
        raise not_found("Client profile")
    return c
