from datetime import date, timedelta

from app.clients.bitrix import BitrixClient
from app.workers.base import BaseWorker


class ScudRegimeWorker(BaseWorker):
    def __init__(self, client: BitrixClient):
        super().__init__(entity="scud_regime", interval_sec=3600, client=client)

    def build_params(self) -> dict:
        today = date.today()
        yesterday = today - timedelta(days=7)
        return {
            "date_from": yesterday.isoformat(),
            "date_to": today.isoformat(),
            "ignore_last_id_for_period": True,
        }
