-- 050: dm.v_employee_month — сводка по сотруднику за месяц
-- Строится поверх dm.v_employee_day.

BEGIN;

CREATE OR REPLACE VIEW dm.v_employee_month AS
SELECT
    user_id,
    user_name,
    department,
    date_trunc('month', date_key)::date AS month_key,
    COUNT(DISTINCT date_key) AS total_days,
    COUNT(DISTINCT date_key) FILTER (
        WHERE COALESCE(scud_sessions_count, 0) > 0
           OR timeman_status IS NOT NULL
    ) AS work_days,
    COUNT(DISTINCT date_key) FILTER (WHERE COALESCE(scud_sessions_count, 0) > 0) AS scud_days,
    COUNT(DISTINCT date_key) FILTER (WHERE timeman_status IS NOT NULL) AS timeman_days,
    COUNT(DISTINCT date_key) FILTER (WHERE absence_types IS NOT NULL) AS absence_days,
    ROUND(COALESCE(SUM(scud_duration_sec), 0) / 3600.0, 2) AS scud_hours,
    ROUND(COALESCE(SUM(timeman_duration), 0) / 3600.0, 2) AS timeman_hours,
    ROUND(AVG(COALESCE(scud_duration_sec, 0)) / 3600.0, 2) AS avg_daily_hours,
    -- effective_hours / effective_avg_daily: единая метрика (SCUD→Timeman fallback).
    -- OLD: не было. Добавлено 05.06.2026.
    ROUND(COALESCE(SUM(effective_duration_sec), 0) / 3600.0, 2) AS effective_hours,
    ROUND(AVG(COALESCE(effective_duration_sec, 0)) / 3600.0, 2) AS effective_avg_daily,
    -- Для отката: удалить 2 строки effective_hours / effective_avg_daily.
    -- среднее время первого входа (сек от полуночи)
    ROUND(AVG(EXTRACT(EPOCH FROM first_entry::time)))::int AS avg_first_entry_epoch,
    ROUND(AVG(EXTRACT(EPOCH FROM last_exit::time)))::int AS avg_last_exit_epoch,
    -- среднее время первого входа как HH:MM
    TO_CHAR(
        AVG(EXTRACT(EPOCH FROM first_entry::time)) * interval '1 second',
        'HH24:MI'
    ) AS avg_first_entry_time,
    TO_CHAR(
        AVG(EXTRACT(EPOCH FROM last_exit::time)) * interval '1 second',
        'HH24:MI'
    ) AS avg_last_exit_time,
    -- среднее время входа/выхода по единой метрике (SCUD → Timeman fallback)
    -- OLD: не было. Добавлено 05.06.2026 вместе с effective_entry_time / effective_exit_time в v_employee_day.
    ROUND(AVG(EXTRACT(EPOCH FROM effective_entry_time::time)))::int AS avg_effective_entry_epoch,
    ROUND(AVG(EXTRACT(EPOCH FROM effective_exit_time::time)))::int AS avg_effective_exit_epoch,
    TO_CHAR(
        AVG(EXTRACT(EPOCH FROM effective_entry_time::time)) * interval '1 second',
        'HH24:MI'
    ) AS avg_effective_entry_time,
    TO_CHAR(
        AVG(EXTRACT(EPOCH FROM effective_exit_time::time)) * interval '1 second',
        'HH24:MI'
    ) AS avg_effective_exit_time
FROM dm.v_employee_day
GROUP BY user_id, user_name, department, date_trunc('month', date_key)
ORDER BY month_key DESC, user_name;

COMMENT ON VIEW dm.v_employee_month IS 'Одна запись = сотрудник × месяц. Агрегат по дням: часы, присутствие, среднее время входа/выхода';

COMMIT;
