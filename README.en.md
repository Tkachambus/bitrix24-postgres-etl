[RU](README.md) | EN

# Bitrix24 → PostgreSQL ETL (demo)

[![CI](https://github.com/Tkachambus/bitrix24-postgres-etl/actions/workflows/ci.yml/badge.svg)](https://github.com/Tkachambus/bitrix24-postgres-etl/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

A demo ETL service that pulls data from a corporate API (Bitrix24-like) and loads it
into PostgreSQL using **staging → master → data mart** layers. The project is based on
a real production case; all data, names and addresses here are **synthetic**.

![Attendance dashboard](docs/preview/attendance.png)

## Highlights

- Python pull-service with background workers and incremental loading (`last_id`).
- Append-only staging with idempotent batches (`batch_id`).
- Normalisation into master via a single SQL function (`master.merge_unmerged()`).
- Analytical views and a materialized view refreshed with `REFRESH CONCURRENTLY`.
- Working calendar, late-arrival and early-leave calculations.
- Health check comparing the source and staging per day.
- Tests, linter, CI and a secret scan.

## Architecture

![Pipeline architecture](docs/preview/architecture.png)

<details>
<summary>Text diagram (Mermaid)</summary>

```mermaid
flowchart LR
    A["Source API"] -->|"pull, last_id"| B[("staging.incoming_b24")]
    B -->|"merge_unmerged()"| C[("master tables")]
    C --> D["dm.v_employee_day"]
    C --> E["dm.v_session_detail"]
    C --> F["dm.v_employee_month"]
    D --> G[("dm.mv_employee_day")]
```

</details>

## Stack

Python 3.12, psycopg 3, httpx, pydantic-settings, PostgreSQL 16, Docker Compose,
pytest, ruff, GitHub Actions.

## Quick start

```bash
cp .env.example .env
docker compose up -d db
make sql        # applies sql/*.sql in order
make seed       # generates synthetic employees and events
docker compose up -d sync
```

Verify:

```bash
psql postgres://postgres:postgres@localhost:5433/analytics_dw -c \
  "SELECT count(*) FROM dm.mv_employee_day;"
```

No Docker? Use any local PostgreSQL 16: create `analytics_dw`, apply `sql/*.sql` in order,
then run `python scripts/seed_mock_data.py`.

## Screenshots

| Attendance dashboard | Employee detail |
|---|---|
| ![attendance](docs/preview/attendance.png) | ![employee](docs/preview/employee.png) |

![pipeline](docs/preview/pipeline.png)

## Layout

```text
sql/                  DDL: staging → master → dm
sync-b24/             pull-service: workers, source client, staging writer
scripts/seed_mock_data.py   synthetic data generator and pipeline run
scripts/health_check.py     source vs staging reconciliation
scripts/check_secrets.py    repository secret/corporate-name scan
tests/                unit tests
docs/preview/         dashboard mockups (PNG + HTML sources)
```

## Design notes

- Incremental loads by `last_id`, period-based for entities without it.
- Idempotent batches; merge progress is tracked in `staging.merge_log`.
- All normalisation lives in one SQL function, not spread across Python.
- Views for marts, materialization only for the heavy one.
- Night shifts and anomalies handled explicitly (duration caps, midnight rollover).
- Working calendar accounts for Russian holidays and reschedules.

## Security

No real data, keys or internal addresses. `scripts/check_secrets.py` runs in CI and fails
on tokens, private keys, private IPs, phone numbers and corporate identifiers. `.env`
is git-ignored.

## License

[MIT](LICENSE).
