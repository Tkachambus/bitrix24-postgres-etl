
from app.clients.bitrix import BitrixClient
from app.workers.base import BaseWorker


class ScudUsersWorker(BaseWorker):
    def __init__(self, client: BitrixClient):
        super().__init__(entity="scud_user", interval_sec=86400, client=client)

    def build_params(self) -> dict:
        return {"last_id": 0, "user_filter": "all"}
