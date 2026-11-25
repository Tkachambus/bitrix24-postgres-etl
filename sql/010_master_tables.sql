-- 010: Нормализованные таблицы master-слоя
-- Источник: staging.incoming_b24 → master.merge_unmerged()

BEGIN;

CREATE TABLE IF NOT EXISTS master.scud_event (
  id          bigint NOT NULL PRIMARY KEY,
  person_id   integer,
  direction   text,
  timestamp   timestamptz,
  turnstile_id integer,
  source      text,
  merged_at   timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE master.scud_event IS 'События СКУД (проходы через турникет)';

CREATE TABLE IF NOT EXISTS master.scud_session (
  id              bigint NOT NULL PRIMARY KEY,
  person_id       integer,
  entry_time      timestamptz,
  exit_time       timestamptz,
  entry_event_id  bigint,
  exit_event_id   bigint,
  duration_sec    integer,
  last_session    text,
  status          text,
  merged_at       timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE master.scud_session IS 'Сессии СКУД (вход/выход)';

CREATE TABLE IF NOT EXISTS master.scud_regime (
  id                bigint NOT NULL PRIMARY KEY,
  user_id           integer,
  tracking_date     date,
  checked_at        timestamptz,
  type              text,
  planned_event_at  timestamptz,
  actual_event_at   timestamptz,
  status            text,
  task_sent         boolean,
  task_id           integer,
  merged_at         timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE master.scud_regime IS 'Мониторинг режима (опоздания) — в разработке';

CREATE TABLE IF NOT EXISTS master.timeman_entry (
  id                bigint NOT NULL PRIMARY KEY,
  user_id           integer,
  current_status    text,
  date_start        timestamptz,
  date_finish       timestamptz,
  time_start        integer,
  time_finish       integer,
  duration          integer,
  recorded_duration integer,
  time_leaks        integer,
  active            boolean,
  paused            boolean,
  approved          boolean,
  approved_by       integer,
  schedule_id       integer,
  timestamp_x       timestamptz,
  merged_at         timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE master.timeman_entry IS 'Рабочие дни (Bitrix24 timeman)';

CREATE TABLE IF NOT EXISTS master.absence (
  id              bigint NOT NULL PRIMARY KEY,
  user_id         integer,
  name            text,
  date_active_from timestamptz,
  date_active_to  timestamptz,
  active          boolean,
  absence_type    text,
  merged_at       timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE master.absence IS 'Отсутствия (отпуск, больничный, ...)';

CREATE TABLE IF NOT EXISTS master.scud_user (
  id              bigint NOT NULL PRIMARY KEY,
  name            text,
  scud_key        text,
  time_scheduler  boolean,
  time_arrival    text,
  time_departure  text,
  timeman_type    text,
  department      jsonb,
  active          boolean,
  departments      jsonb,
  department_names jsonb,
  merged_at       timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE master.scud_user IS 'Пользователи с доп. полями СКУД';

COMMIT;
