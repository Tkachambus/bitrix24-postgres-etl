-- 062: Таблица лога обновлений dm.mv_employee_day
-- Заполняется внутри master.refresh_mv_employee_day() после каждого REFRESH
-- Проверка: SELECT * FROM master.refresh_log ORDER BY id DESC LIMIT 10;

BEGIN;

CREATE TABLE IF NOT EXISTS master.refresh_log (
  id SERIAL PRIMARY KEY,
  refreshed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  rows_in_mv INT
);

COMMENT ON TABLE master.refresh_log IS 'Лог обновлений dm.mv_employee_day. Заполняется автоматически функцией master.refresh_mv_employee_day()';

COMMIT;
