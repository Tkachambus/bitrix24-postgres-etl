from app.clients.bitrix import BitrixClient
from app.workers.base import BaseWorker


class ScudSessionsWorker(BaseWorker):
    def __init__(self, client: BitrixClient):
        super().__init__(entity="scud_session", interval_sec=300, client=client)
