from datetime import date, timedelta

from app.clients.bitrix import BitrixClient
from app.workers.base import BaseWorker


class AbsenceWorker(BaseWorker):
    def __init__(self, client: BitrixClient):
        super().__init__(entity="absence", interval_sec=3600, client=client)

    def build_params(self) -> dict:
        today = date.today()
        month_ago = today - timedelta(days=60)
        return {
            "date_from": month_ago.isoformat(),
            "date_to": today.isoformat(),
            "ignore_last_id_for_period": True,
        }
