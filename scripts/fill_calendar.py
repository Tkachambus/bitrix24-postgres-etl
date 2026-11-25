"""
Заполняет dm.calendar из isdayoff.ru (производственный календарь РФ).

Запуск:
    set DATABASE_URL=postgres://user:pass@host:port/db
    python scripts/fill_calendar.py

Либо через PowerShell:
    $env:DATABASE_URL="postgres://user:pass@host:port/db"
    python scripts/fill_calendar.py

Автоматизация: Windows Task Scheduler, раз в год (1 января).

Зависимости (уже есть в requirements.txt):
    - httpx
    - psycopg[binary]
"""

import os
from datetime import date

import httpx
import psycopg
from psycopg.types.json import Jsonb

DB_URL = os.environ.get("DATABASE_URL")
if not DB_URL:
    raise SystemExit(
        "ERROR: Set DATABASE_URL environment variable.\n"
        "Пример: $env:DATABASE_URL=\"postgres://user:pass@host:5433/db\""
    )

MONTH_LENS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

HOLIDAY_NAMES = {
    (1, 1): "Новый год",
    (1, 2): "Новый год",
    (1, 3): "Новый год",
    (1, 4): "Новый год",
    (1, 5): "Новый год",
    (1, 6): "Новый год",
    (1, 7): "Рождество Христово",
    (1, 8): "Новый год",
    (2, 23): "День защитника Отечества",
    (3, 8): "Международный женский день",
    (5, 1): "Праздник Весны и Труда",
    (5, 9): "День Победы",
    (6, 12): "День России",
    (11, 4): "День народного единства",
}


def is_leap(y: int) -> bool:
    return y % 400 == 0 or (y % 4 == 0 and y % 100 != 0)


def fetch_year(year: int) -> str:
    resp = httpx.get(
        "https://isdayoff.ru/api/getdata",
        params={"year": year, "cc": "ru", "pre": 1, "holiday": 1},
        timeout=30,
    )
    resp.raise_for_status()
    return resp.text.strip()


def parse(year: int, raw: str) -> list[dict]:
    days = []
    for month in range(1, 13):
        days_in_month = MONTH_LENS[month - 1]
        if month == 2 and is_leap(year):
            days_in_month = 29
        for day_num in range(1, days_in_month + 1):
            idx = sum(MONTH_LENS[: month - 1]) + day_num - 1
            code = raw[idx] if idx < len(raw) else "0"

            dt = date(year, month, day_num)
            dow = dt.weekday()  # 0=Пн … 6=Вс
            is_weekend = dow >= 5  # Сб=5, Вс=6

            holiday_name = HOLIDAY_NAMES.get((month, day_num))

            if code == "0":
                day_type = "workday"
            elif code == "2":
                day_type = "short_day"
            elif code == "8":
                day_type = "holiday"
            elif code == "1":
                day_type = "weekend" if is_weekend else "holiday"
            else:
                day_type = "workday"

            days.append(
                {
                    "date_key": dt.isoformat(),
                    "year": year,
                    "month": month,
                    "day": day_num,
                    "day_of_week": (dow + 1) % 7,  # 0=Вс 1=Пн … 6=Сб
                    "is_workday": code in ("0", "2", "4"),
                    "is_weekend": is_weekend,
                    "is_holiday": code in ("1", "8"),
                    "is_short_day": code == "2",
                    "day_type": day_type,
                    "holiday_name": holiday_name,
                }
            )
    return days


def main():
    now = date.today()
    for year in [now.year - 1, now.year, now.year + 1]:
        raw = fetch_year(year)
        days = parse(year, raw)
        with psycopg.connect(DB_URL) as conn:
            conn.execute("SELECT staging.merge_calendar(%s)", [Jsonb(days)])
            conn.commit()
        print(f"{year}: {len(days)} days loaded")


if __name__ == "__main__":
    main()
