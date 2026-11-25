from app.clients.bitrix import BitrixClient
from app.workers.base import BaseWorker


class TimemanWorker(BaseWorker):
    def __init__(self, client: BitrixClient):
        super().__init__(entity="timeman_entry", interval_sec=600, client=client)
