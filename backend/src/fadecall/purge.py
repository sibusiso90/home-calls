"""Delete expired raw proof-of-job photos (run daily).

uv run python -m fadecall.purge
"""

from __future__ import annotations

import asyncio

from .config import Settings, get_settings
from .db import make_engine, make_sessionmaker
from .services.retention import purge_expired_evidence
from .storage import make_storage


async def run_purge(settings: Settings) -> list[str]:
    engine = make_engine(settings.sqlalchemy_url)
    storage = make_storage(settings)
    try:
        with make_sessionmaker(engine)() as db:
            return await purge_expired_evidence(db, storage, settings.evidence_retention_days)
    finally:
        await storage.aclose()
        engine.dispose()


def main() -> None:
    settings = get_settings()
    purged = asyncio.run(run_purge(settings))
    days = settings.evidence_retention_days
    print(f"Purged raw evidence for {len(purged)} job(s) (retention {days} days).")


if __name__ == "__main__":
    main()
