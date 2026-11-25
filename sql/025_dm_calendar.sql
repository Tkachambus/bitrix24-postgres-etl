-- 035: dm.calendar — производственный календарь РФ
-- Источник: isdayoff.ru (учитывает переносы правительства)
-- Заполнение: python scripts/fill_calendar.py (с Windows, раз в год)
-- Либо ручной вызов: SELECT staging.merge_calendar('[{"date_key":...}]'::jsonb)
--
-- SECURITY DEFINER: функция в staging (куда у integration_writer есть доступ),
-- а INSERT в dm выполняется от имени владельца функции (postgres/SuperBublik),
-- поэтому integration_writer НЕ получает прав на master или dm.

BEGIN;

DROP TABLE IF EXISTS dm.calendar CASCADE;

CREATE TABLE dm.calendar (
  date_key      DATE PRIMARY KEY,
  year          INT NOT NULL,
  month         INT NOT NULL,
  day           INT NOT NULL,
  day_of_week   INT NOT NULL,   -- 0=Вс 1=Пн … 6=Сб
  is_workday    BOOLEAN NOT NULL,
  is_weekend    BOOLEAN NOT NULL,
  is_holiday    BOOLEAN NOT NULL DEFAULT false,
  is_short_day  BOOLEAN NOT NULL DEFAULT false,
  day_type      TEXT NOT NULL CHECK (day_type IN ('workday','weekend','holiday','short_day')),
  holiday_name  TEXT
);

COMMENT ON TABLE dm.calendar IS 'Производственный календарь РФ (isdayoff.ru). Заполняется через staging.merge_calendar()';

CREATE OR REPLACE FUNCTION staging.merge_calendar(p_data JSONB)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
  INSERT INTO dm.calendar (date_key, year, month, day, day_of_week,
    is_workday, is_weekend, is_holiday, is_short_day, day_type, holiday_name)
  SELECT *
  FROM jsonb_to_recordset(p_data) AS x(
    date_key DATE, year INT, month INT, day INT, day_of_week INT,
    is_workday BOOLEAN, is_weekend BOOLEAN, is_holiday BOOLEAN,
    is_short_day BOOLEAN, day_type TEXT, holiday_name TEXT
  )
  ON CONFLICT (date_key) DO UPDATE SET
    year = EXCLUDED.year, month = EXCLUDED.month, day = EXCLUDED.day,
    day_of_week = EXCLUDED.day_of_week, is_workday = EXCLUDED.is_workday,
    is_weekend = EXCLUDED.is_weekend, is_holiday = EXCLUDED.is_holiday,
    is_short_day = EXCLUDED.is_short_day, day_type = EXCLUDED.day_type,
    holiday_name = EXCLUDED.holiday_name;
END;
$function$;

COMMENT ON FUNCTION staging.merge_calendar(JSONB) IS 'UPSERT справочника дней из isdayoff.ru (SECURITY DEFINER)';

GRANT EXECUTE ON FUNCTION staging.merge_calendar(JSONB) TO integration_writer;

COMMIT;
