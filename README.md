RU | [EN](README.en.md)

# Bitrix24 → PostgreSQL ETL (demo)

[![CI](https://github.com/Tkachambus/bitrix24-postgres-etl/actions/workflows/ci.yml/badge.svg)](https://github.com/Tkachambus/bitrix24-postgres-etl/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Python 3.12](https://img.shields.io/badge/python-3.12-blue.svg)](https://www.python.org/)
[![PostgreSQL 16](https://img.shields.io/badge/postgresql-16-336791.svg)](https://www.postgresql.org/)

Демонстрационный ETL-сервис: забирает данные из корпоративного API (по мотивам Bitrix24)
и складывает их в PostgreSQL по слоям **staging → master → data mart**. Проект собран
по мотивам production-кейса; все данные, имена и адреса здесь **синтетические**.

## Что показывает проект

- pull-сервис на Python с фоновыми воркерами и инкрементальной загрузкой (`last_id`);
- append-only staging с идемпотентными батчами (`batch_id`);
- нормализацию в master через одну SQL-функцию `master.merge_unmerged()` (UPSERT);
- аналитические витрины и materialized view с `REFRESH CONCURRENTLY`;
- производственный календарь и расчёт опозданий/ранних уходов;
- health-check, который сверяет источник и staging по дням;
- тесты, линтер, CI и проверку на утечку секретов.

## Архитектура

```mermaid
flowchart LR
    A[Source API] -->|pull, last_id| B[(staging.incoming_b24)]
    B -->|master.merge_unmerged()| C[(master tables)]
    C --> D[dm.v_employee_day]
    C --> E[dm.v_session_detail]
    C --> F[dm.v_employee_month]
    D --> G[(dm.mv_employee_day)]
```

## Данные

| Слой | Назначение |
|---|---|
| `staging.incoming_b24` | сырые JSON-батчи, append-only, дедуп по `(batch_id, entity, external_id)` |
| `master.*` | нормализованные таблицы: события, сессии, табель, отсутствия, пользователи, подразделения |
| `dm.*` | витрины «сотрудник × день», детализация сессий, месячные сводки |
| `dm.mv_employee_day` | материализованная копия витрины для быстрых отчётов |

## Стек

Python 3.12, psycopg 3, httpx, pydantic-settings, PostgreSQL 16, Docker Compose, pytest, ruff, GitHub Actions.

## Быстрый старт

```bash
cp .env.example .env
docker compose up -d db
make sql        # применяет sql/*.sql по порядку
make seed       # генерирует синтетических сотрудников и события
docker compose up -d sync
```

Проверка:

```bash
psql postgres://postgres:postgres@localhost:5433/analytics_dw -c \
  "SELECT count(*) FROM dm.mv_employee_day;"
```

Если Docker нет — подойдёт любой локальный PostgreSQL 16: создайте базу `analytics_dw`,
примените `sql/*.sql` по порядку и запустите `python scripts/seed_mock_data.py`.

## Скриншоты

| Дашборд посещаемости | Детализация по сотруднику |
|---|---|
| ![attendance](docs/preview/attendance.png) | ![employee](docs/preview/employee.png) |

![pipeline](docs/preview/pipeline.png)

## Структура

```text
sql/                  DDL: staging → master → dm (порядок применения — по имени файла)
sync-b24/             pull-сервис: воркеры, клиент источника, запись в staging
scripts/seed_mock_data.py   генератор синтетических данных и прогон пайплайна
scripts/health_check.py     сверка источника и staging по дням
scripts/check_secrets.py    проверка репозитория на секреты и корпоративные имена
scripts/fill_calendar.py    заполнение производственного календаря
tests/                unit-тесты воркеров и генератора данных
docs/preview/         макеты дашбордов (PNG + HTML-исходники)
```

## Решения, которые стоит отметить

- **Инкрементальная загрузка** через `last_id`, а для сущностей без него — по периоду.
- **Идемпотентность**: повторный батч не дублирует строки, merge фиксируется в `staging.merge_log`.
- **Один вход в master**: вся логика нормализации в SQL-функции, а не размазана по Python.
- **Витрины как VIEW**, материализуется только тяжёлая — так проще менять модель.
- **Ночные смены и аномалии**: длительность ограничивается капом, переход через полночь обрабатывается отдельно.
- **Календарь РФ** учитывает праздники и переносы.

## Безопасность

В репозитории нет реальных данных, ключей и внутренних адресов. `scripts/check_secrets.py`
проверяет это в CI: ищет токены, приватные ключи, приватные IP, телефоны и корпоративные
идентификаторы. `.env` в `.gitignore`.

## Лицензия

[MIT](LICENSE).
