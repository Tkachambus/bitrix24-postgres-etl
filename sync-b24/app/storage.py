import logging
from uuid import uuid4

from psycopg.types.json import Jsonb

from app.db import pool

logger = logging.getLogger(__name__)


def insert_items(entity: str, items: list[dict]) -> int:
    batch_id = uuid4()
    inserted = 0

    with pool.connection() as conn:
        with conn.transaction():
            for item in items:
                external_id = str(item.get("id", ""))
                source_updated_at = item.get("timestamp_x") or item.get("timestamp") or item.get("checked_at")

                conn.execute(
                    """
                    INSERT INTO staging.incoming_b24
                        (batch_id, entity, external_id, source_updated_at, payload)
                    VALUES (%s, %s, %s, %s, %s)
                    ON CONFLICT (batch_id, entity, external_id) DO NOTHING
                    """,
                    [batch_id, entity, external_id, source_updated_at, Jsonb(item)],
                )
                inserted += 1

    logger.info("Stored %d items for entity=%s (batch=%s)", inserted, entity, batch_id)
    return inserted
