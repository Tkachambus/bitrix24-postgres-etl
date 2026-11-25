-- 060: dm.mv_employee_day — материализованная копия dm.v_employee_day
-- Для быстрых отчётов в Astro (10-50 мс). Индексы под частые фильтры.
-- Обновление: SELECT master.refresh_mv_employee_day();
-- В кроне (каждые 5 мин): psql -d analytics_dw -c "SELECT master.refresh_mv_employee_day()"
-- Логин/пароль: пропиши в crontab -e, например:
-- */5 * * * * /usr/bin/podman exec analytics_dw psql -U postgres -d analytics_dw -c "SELECT master.refresh_mv_employee_day()"
--
-- Идемпотентность: DROP + CREATE в одной транзакции, чтобы не было «окна без MV».
-- Крон с REFRESH CONCURRENTLY в этот момент либо подождёт DDL и выполнится,
-- либо попадёт на новую MV и отработает — без ошибок.

BEGIN;

DROP MATERIALIZED VIEW IF EXISTS dm.mv_employee_day;

CREATE MATERIALIZED VIEW dm.mv_employee_day AS
SELECT * FROM dm.v_employee_day
WITH DATA;

-- UNIQUE INDEX обязателен для REFRESH MATERIALIZED VIEW CONCURRENTLY
CREATE UNIQUE INDEX idx_mv_emp_day_pk
  ON dm.mv_employee_day (user_id, date_key);

CREATE INDEX idx_mv_emp_day_date
  ON dm.mv_employee_day (date_key);

CREATE INDEX idx_mv_emp_day_user
  ON dm.mv_employee_day (user_id);

CREATE INDEX idx_mv_emp_day_source
  ON dm.mv_employee_day (effective_source);

COMMENT ON MATERIALIZED VIEW dm.mv_employee_day IS 'Материализованная копия dm.v_employee_day. Обновляется через master.refresh_mv_employee_day()';

COMMIT;
