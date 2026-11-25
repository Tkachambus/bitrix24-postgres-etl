-- 061: Функция обновления dm.mv_employee_day + лог
-- Вызов: SELECT master.refresh_mv_employee_day();
-- Для крона: /usr/bin/podman exec analytics_dw psql -U postgres -d analytics_dw -c "SELECT master.refresh_mv_employee_day()"

BEGIN;

CREATE OR REPLACE FUNCTION master.refresh_mv_employee_day()
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY dm.mv_employee_day;
  INSERT INTO master.refresh_log (rows_in_mv)
  SELECT count(*) FROM dm.mv_employee_day;
END;
$function$;

COMMENT ON FUNCTION master.refresh_mv_employee_day() IS 'Обновляет dm.mv_employee_day (REFRESH MATERIALIZED VIEW CONCURRENTLY) + пишет лог';

COMMIT;
