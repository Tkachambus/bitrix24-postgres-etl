from app.clients.bitrix import BitrixClient
from app.workers.base import BaseWorker


class ScudEventsWorker(BaseWorker):
    def __init__(self, client: BitrixClient):
        super().__init__(entity="scud_event", interval_sec=60, client=client)
