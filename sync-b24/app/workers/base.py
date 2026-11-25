import logging
import time

from app.clients.bitrix import BitrixClient
from app.db import pool
from app.storage import insert_items

logger = logging.getLogger(__name__)


class BaseWorker:
    def __init__(
        self,
        entity: str,
        interval_sec: int,
        client: BitrixClient,
    ):
        self.entity = entity
        self.interval = interval_sec
        self.client = client

    def get_last_id(self) -> int:
        with pool.connection() as conn:
            result = conn.execute(
                """
                SELECT COALESCE(MAX((payload->>'id')::bigint), 0) AS last_id
                FROM staging.incoming_b24
                WHERE entity = %s
                """,
                [self.entity],
            )
            return result.fetchone()["last_id"]

    def build_params(self) -> dict:
        return {"last_id": self.get_last_id()}

    def work(self):
        params = self.build_params()
        items = self.client.fetch(self.entity, params)
        if items:
            insert_items(self.entity, items)

    def run_forever(self):
        logger.info(
            "Worker %s started, interval=%ds",
            self.entity,
            self.interval,
        )
        while True:
            try:
                self.work()
            except Exception:
                logger.exception("Worker %s failed, will retry", self.entity)
            time.sleep(self.interval)
