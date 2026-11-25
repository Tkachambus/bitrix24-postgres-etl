import os

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env" if os.path.exists(".env") else None,
        env_file_encoding="utf-8",
    )

    database_url: str
    bitrix_api_url: str
    bitrix_token: str

    poll_interval_scud_events: int = 60
    poll_interval_scud_sessions: int = 300
    poll_interval_scud_regime: int = 3600
    poll_interval_timeman: int = 600
    poll_interval_absence: int = 3600
    poll_interval_scud_users: int = 86400

    fetch_limit: int = 1000
    log_level: str = "INFO"


settings = Settings()
