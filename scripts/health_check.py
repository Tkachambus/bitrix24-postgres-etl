"""
Диагностика расхождений между API Bitrix24 и staging.

Сравнивает количество записей по дням/сотрудникам в источнике (через API scud_health_check)
с тем, что уже загружено в staging.incoming_b24.

Запуск:
    set DATABASE_URL=postgres://user:pass@host:port/db
    set BITRIX_API_URL=https://...
    set BITRIX_TOKEN=...
    python scripts/health_check.py --entity scud_event --date-from 2026-04-02 --date-to 2026-04-03

Для конкретного сотрудника:
    python scripts/health_check.py --entity scud_event --date-from 2026-04-02 --date-to 2026-04-03 --person-id 253

Зависимости: httpx, psycopg (уже есть в requirements.txt проекта sync-b24)
"""

import argparse
import os
from datetime import date, timedelta

import httpx
import psycopg

API_URL = os.environ.get("BITRIX_API_URL", "")
API_TOKEN = os.environ.get("BITRIX_TOKEN", "")
DB_URL = os.environ.get("DATABASE_URL")

# Маппинг entity → источник в API + поле даты в staging
SOURCE_CONFIG = {
    "scud_event":   {"source": "demo_skud_events",        "date_field": "timestamp",      "resp_field": "scud_events_count"},
    "scud_session": {"source": "demo_skud_sessions",      "date_field": "entry_time",     "resp_field": "scud_sessions_count"},
    "timeman_entry":{"source": "b_timeman_entries",       "date_field": "date_start",    "resp_field": "timeman_entries_count"},
    "scud_regime":  {"source": "demo_skud_regime_tracking_records", "date_field": "tracking_date", "resp_field": "scud_regime_count"},
}


def count_staging(entity: str, day: date, person_id: int | None = None) -> int:
    date_field = SOURCE_CONFIG[entity]["date_field"]
    with psycopg.connect(DB_URL) as conn:
        sql = f"""
            SELECT COUNT(*) AS cnt
            FROM staging.incoming_b24
            WHERE entity = %s
              AND (payload->>'{date_field}')::date = %s
        """
        params = [entity, day]
        row = conn.execute(sql, params).fetchone()
        return row[0] if row else 0


def fetch_api(entity: str, date_from: date, date_to: date,
              person_id: int | None = None) -> dict:
    cfg = SOURCE_CONFIG.get(entity)
    if not cfg:
        raise ValueError(f"Unknown entity: {entity}")

    body = {
        "entity": "scud_health_check",
        "token": API_TOKEN,
        "source": cfg["source"],
        "date_from": date_from.isoformat(),
        "date_to": date_to.isoformat(),
    }
    if person_id is not None:
        body["person_id"] = person_id

    resp = httpx.post(API_URL, json=body, timeout=60)
    resp.raise_for_status()
    return resp.json()


def main():
    parser = argparse.ArgumentParser(description="Health check: compare API vs staging")
    parser.add_argument("--entity", required=True, choices=list(SOURCE_CONFIG.keys()),
                        help="Сущность для проверки")
    parser.add_argument("--date-from", type=date.fromisoformat, required=True,
                        help="Начало периода (YYYY-MM-DD)")
    parser.add_argument("--date-to", type=date.fromisoformat, required=True,
                        help="Конец периода (YYYY-MM-DD)")
    parser.add_argument("--person-id", type=int, default=None,
                        help="ID сотрудника для фильтра (person_id для СКУД)")
    parser.add_argument("--user-id", type=int, default=None,
                        help="ID сотрудника для фильтра (user_id для timeman/regime)")
    args = parser.parse_args()

    if not DB_URL:
        raise SystemExit("ERROR: Set DATABASE_URL environment variable.")
    if not API_URL:
        raise SystemExit("ERROR: Set BITRIX_API_URL environment variable.")
    if not API_TOKEN:
        raise SystemExit("ERROR: Set BITRIX_TOKEN environment variable.")

    person_id = args.person_id or args.user_id

    print(f"Entity: {args.entity}")
    print(f"Period: {args.date_from} -> {args.date_to}")
    if person_id:
        print(f"Person/User ID: {person_id}")
    print()
    print(f"{'Date':<12} {'API':<8} {'Staging':<8} {'Diff':<8} {'Status'}")
    print("-" * 52)

    day = args.date_from
    while day <= args.date_to:
        api_data = fetch_api(args.entity, day, day, person_id)
        items = api_data.get("items", [])
        cfg = SOURCE_CONFIG[args.entity]
        api_count = items[0].get(cfg["resp_field"], 0) if items else 0

        staging_count = count_staging(args.entity, day, person_id)
        diff = api_count - staging_count

        if diff == 0:
            status = "OK"
        elif diff > 0:
            status = "MISSING"
        else:
            status = "OVERFLOW"

        print(f"{day.isoformat():<12} {api_count:<8} {staging_count:<8} {diff:<8} {status}")
        day += timedelta(days=1)


if __name__ == "__main__":
    main()
