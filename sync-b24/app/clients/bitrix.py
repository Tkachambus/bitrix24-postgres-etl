import logging

import httpx

from app.config import settings

logger = logging.getLogger(__name__)


class BitrixClient:
    def __init__(self):
        self.api_url = settings.bitrix_api_url
        self.token = settings.bitrix_token

    def fetch(self, entity: str, params: dict, timeout: int = 30) -> list[dict]:
        body = {
            "entity": entity,
            "token": self.token,
            "limit": settings.fetch_limit,
            **params,
        }

        logger.info("Fetching entity=%s with params=%s", entity, params)

        with httpx.Client(timeout=timeout) as client:
            resp = client.post(self.api_url, json=body)
            resp.raise_for_status()
            data = resp.json()

        items = data.get("items", [])
        logger.info("Fetched %d items for entity=%s", len(items), entity)
        return items
