import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "sync-b24"))
sys.path.insert(0, str(ROOT))

# Настройки читаются при импорте app.config — подставляем тестовые значения.
os.environ.setdefault(
    "DATABASE_URL", "postgres://integration_writer:demo_password@localhost:5433/analytics_dw"
)
os.environ.setdefault("BITRIX_API_URL", "https://example.com/rest/1/DEMO/ext.analytics/")
os.environ.setdefault("BITRIX_TOKEN", "demo-token")
