from app.clients.bitrix import BitrixClient
from app.workers.base import BaseWorker


class ScudDepartmentsWorker(BaseWorker):
    def __init__(self, client: BitrixClient):
        super().__init__(entity="scud_department", interval_sec=86400, client=client)
