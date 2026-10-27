"""Send day-before reminders for jobs starting in the next 24 hours (run hourly).

uv run python -m fadecall.reminders
"""

from __future__ import annotations

from .config import Settings, get_settings
from .db import make_engine, make_sessionmaker
from .services import notifications


def run_reminders(settings: Settings) -> list[str]:
    notifications.configure(settings)
    engine = make_engine(settings.sqlalchemy_url)
    try:
        with make_sessionmaker(engine)() as db:
            return notifications.send_due_reminders(db)
    finally:
        engine.dispose()


def main() -> None:
    sent = run_reminders(get_settings())
    print(f"Sent reminders for {len(sent)} job(s).")


if __name__ == "__main__":
    main()
