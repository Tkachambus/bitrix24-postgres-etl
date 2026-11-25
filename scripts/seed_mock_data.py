"""Generate synthetic data and push it through the staging → master → dm pipeline.

No corporate data is used: users, events, timeman entries and absences are
generated from scratch. Safe to run on the demo database from docker-compose.

Usage:
    python scripts/seed_mock_data.py --days 14 --users 20
"""

from __future__ import annotations

import argparse
import os
import random
from datetime import date, datetime, time, timedelta, timezone
from uuid import uuid4

import psycopg
from psycopg.types.json import Jsonb

DEPARTMENTS = [
    (1, "Engineering", None, True, 100, "ENG"),
    (2, "Analytics", 1, True, 200, "ANL"),
    (3, "Operations", None, True, 300, "OPS"),
]

TURNSTILES = [1, 2, 3]


def build_departments() -> list[dict]:
    return [
        {
            "id": dep_id,
            "name": name,
            "parent_id": parent,
            "active": active,
            "sort": sort,
            "code": code,
        }
        for dep_id, name, parent, active, sort, code in DEPARTMENTS
    ]


def build_users(count: int) -> list[dict]:
    rng = random.Random(42)
    users = []
    for user_id in range(1, count + 1):
        dep_id, dep_name, *_ = rng.choice(DEPARTMENTS)
        users.append(
            {
                "id": user_id,
                "name": f"Employee {user_id:03d}",
                "scud_key": f"key-{user_id:04d}",
                "time_scheduler": True,
                "time_arrival": "09:00:00",
                "time_departure": "18:00:00",
                "timeman_type": "type1",
                "department": {"ID": dep_id},
                "active": True,
                "departments": [dep_id],
                "department_names": [dep_name],
            }
        )
    return users


def workdays(days: int, today: date | None = None) -> list[date]:
    today = today or date.today()
    start = today - timedelta(days=days - 1)
    return [
        start + timedelta(days=offset)
        for offset in range(days)
        if (start + timedelta(days=offset)).weekday() < 5
    ]


def build_events(users: list[dict], days: list[date]) -> list[dict]:
    rng = random.Random(7)
    events: list[dict] = []
    event_id = 1
    tz = timezone.utc
    for day in days:
        for user in users:
            in_ts = datetime.combine(day, time(9, 0), tzinfo=tz) + timedelta(
                minutes=rng.randint(-15, 20)
            )
            out_ts = datetime.combine(day, time(18, 0), tzinfo=tz) + timedelta(
                minutes=rng.randint(-25, 45)
            )
            for direction, ts in (("IN", in_ts), ("OUT", out_ts)):
                events.append(
                    {
                        "id": event_id,
                        "person_id": user["id"],
                        "direction": direction,
                        "timestamp": ts.isoformat(),
                        "turnstile_id": rng.choice(TURNSTILES),
                        "source": "scud",
                    }
                )
                event_id += 1
    return events


def build_timeman(users: list[dict], days: list[date]) -> list[dict]:
    rng = random.Random(11)
    rows: list[dict] = []
    entry_id = 1
    tz = timezone.utc
    for day in days:
        for user in users:
            start = datetime.combine(day, time(9, 0), tzinfo=tz) + timedelta(
                minutes=rng.randint(-10, 10)
            )
            finish = start + timedelta(minutes=rng.randint(470, 540))
            rows.append(
                {
                    "id": entry_id,
                    "user_id": user["id"],
                    "current_status": "CLOSED",
                    "date_start": start.isoformat(),
                    "date_finish": finish.isoformat(),
                    "time_start": int(start.timestamp()),
                    "time_finish": int(finish.timestamp()),
                    "duration": int((finish - start).total_seconds()),
                    "recorded_duration": int((finish - start).total_seconds()),
                    "time_leaks": 0,
                    "active": False,
                    "paused": False,
                    "approved": True,
                    "approved_by": 1,
                    "schedule_id": 1,
                    "timestamp_x": finish.isoformat(),
                }
            )
            entry_id += 1
    return rows


def build_absences(users: list[dict], days: list[date]) -> list[dict]:
    if not days:
        return []
    day = days[len(days) // 2]
    return [
        {
            "id": 1,
            "user_id": users[0]["id"],
            "name": "Vacation",
            "date_active_from": datetime.combine(
                day, time(0, 0), tzinfo=timezone.utc
            ).isoformat(),
            "date_active_to": datetime.combine(
                day + timedelta(days=2), time(0, 0), tzinfo=timezone.utc
            ).isoformat(),
            "active": True,
            "absence_type": "VACATION",
        }
    ]


def build_calendar(days: list[date]) -> list[tuple]:
    rows = []
    for day in days:
        rows.append(
            (
                day,
                day.year,
                day.month,
                day.day,
                day.isoweekday(),
                True,
                False,
                False,
                False,
                "workday",
                None,
            )
        )
    return rows


def insert_batch(
    conn: psycopg.Connection, entity: str, items: list[dict]
) -> int:
    if not items:
        return 0
    batch_id = uuid4()
    with conn.transaction():
        with conn.cursor() as cur:
            cur.executemany(
                """
                INSERT INTO staging.incoming_b24
                    (batch_id, entity, external_id, source_updated_at, payload)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (batch_id, entity, external_id) DO NOTHING
                """,
                [
                    (
                        batch_id,
                        entity,
                        str(item.get("id", "")),
                        item.get("timestamp_x") or item.get("timestamp"),
                        Jsonb(item),
                    )
                    for item in items
                ],
            )
    return len(items)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--days", type=int, default=14)
    parser.add_argument("--users", type=int, default=20)
    parser.add_argument(
        "--database-url",
        default=os.environ.get(
            "DATABASE_URL",
            "postgres://integration_writer:demo_password@localhost:5433/analytics_dw",
        ),
    )
    args = parser.parse_args()

    days = workdays(args.days)
    users = build_users(args.users)

    with psycopg.connect(args.database_url, autocommit=True) as conn:
        counters = {
            "scud_department": insert_batch(conn, "scud_department", build_departments()),
            "scud_user": insert_batch(conn, "scud_user", users),
            "scud_event": insert_batch(conn, "scud_event", build_events(users, days)),
            "timeman_entry": insert_batch(conn, "timeman_entry", build_timeman(users, days)),
            "absence": insert_batch(conn, "absence", build_absences(users, days)),
        }

        with conn.cursor() as cur:
            cur.execute("SELECT master.merge_unmerged()")
            merged = cur.fetchone()[0]

            cur.executemany(
                """
                INSERT INTO dm.calendar
                    (date_key, year, month, day, day_of_week, is_workday,
                     is_weekend, is_holiday, is_short_day, day_type, holiday_name)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (date_key) DO NOTHING
                """,
                build_calendar(days),
            )

            cur.execute("SELECT master.refresh_mv_employee_day()")

            cur.execute("SELECT count(*) FROM master.scud_event")
            events_total = cur.fetchone()[0]
            cur.execute("SELECT count(*) FROM dm.mv_employee_day")
            day_rows = cur.fetchone()[0]

    print("inserted into staging:", counters)
    print("merged batches:", merged)
    print("master.scud_event rows:", events_total)
    print("dm.mv_employee_day rows:", day_rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
