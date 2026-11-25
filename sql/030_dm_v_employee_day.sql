-- 030: dm.v_employee_day — сотрудник × день
-- Одна строка = user_id + date_key. Каждая сущность аггрегируется независимо,
-- поэтому ни одна не размножает строки другой.
--
-- first_entry / last_exit — из scud_event (append-only, всегда финальные).
-- scud_duration_sec / scud_sessions_count — из scud_session (99.7% CLOSED).
-- planned_arrival / planned_departure — из scud_user (timeman_type / time_arrival).
-- is_late / is_early_leave — сравнение first_entry/last_exit с планом (+15 мин запас).
-- is_weekend, is_holiday, day_type — из dm.calendar (производственный календарь РФ).

BEGIN;

CREATE SCHEMA IF NOT EXISTS dm;

DROP VIEW IF EXISTS dm.v_employee_day CASCADE;
CREATE VIEW dm.v_employee_day AS
WITH dates AS (
    SELECT u.id::integer AS user_id, d::date AS date_key
    FROM master.scud_user u
    CROSS JOIN generate_series(
        (SELECT MIN(timestamp::date) FROM master.scud_event),
        CURRENT_DATE,
        '1 day'
    ) AS d
    WHERE EXISTS (SELECT 1 FROM master.scud_event e WHERE e.person_id = u.id)
       OR EXISTS (SELECT 1 FROM master.timeman_entry t WHERE t.user_id = u.id)
       OR EXISTS (SELECT 1 FROM master.absence a WHERE a.user_id = u.id)
),
scud_event_agg AS (
    SELECT
        person_id AS user_id,
        timestamp::date AS date_key,
        MIN(timestamp) FILTER (WHERE direction = 'IN') AS first_entry,
        MAX(timestamp) FILTER (WHERE direction = 'OUT') AS last_exit
    FROM master.scud_event
    GROUP BY person_id, timestamp::date
),
scud_session_agg AS (
    SELECT
        person_id AS user_id,
        entry_time::date AS date_key,
        SUM(duration_sec) AS scud_duration_sec,
        COUNT(*) AS scud_sessions_count,
        -- session_last_exit: если exit_time < entry_time (ночная смена или неисправленный timestamp),
        -- добавляем 1 день для корректного сравнения с first_entry.
        -- OLD: exit_time::time < entry_time::time — ломал зомби-сессии (entry 31марта, exit 8апреля).
        MAX(CASE
            WHEN exit_time < entry_time
            THEN exit_time + interval '1 day'
            ELSE exit_time
        END) AS session_last_exit
    FROM master.scud_session
    GROUP BY person_id, entry_time::date
),
timeman AS (
    SELECT DISTINCT ON (user_id, date_start::date)
        user_id,
        date_start::date AS date_key,
        current_status AS timeman_status,
        date_start::time AS timeman_entry_time,
        COALESCE(date_finish, date_start)::time AS timeman_exit_time,
        date_start AS timeman_entry_ts,
        COALESCE(date_finish, date_start) AS timeman_exit_ts,
        duration AS timeman_duration,
        paused AS timeman_paused,
        approved AS timeman_approved,
        schedule_id
    FROM master.timeman_entry
    ORDER BY user_id, date_start::date, timestamp_x DESC
),
absence_agg AS (
    SELECT
        user_id,
        d::date AS date_key,
        string_agg(DISTINCT absence_type, ', ' ORDER BY absence_type) AS absence_types,
        string_agg(DISTINCT name, '; ' ORDER BY name) AS absence_names
    FROM master.absence a
    CROSS JOIN LATERAL generate_series(a.date_active_from::date, a.date_active_to::date, '1 day'::interval) AS d
    WHERE a.active = true
    GROUP BY user_id, d::date
),
schedule AS (
    SELECT
        id AS user_id,
        COALESCE(
            NULLIF(time_arrival, '')::time,
            CASE timeman_type
                WHEN 'type1' THEN '09:00'::time WHEN 'type2' THEN '10:00'::time
                WHEN 'type3' THEN '08:00'::time WHEN 'type4' THEN '07:00'::time
                WHEN 'type5' THEN '09:00'::time WHEN 'type6' THEN '11:00'::time
                WHEN 'type7' THEN '21:00'::time WHEN 'type8' THEN '09:30'::time
                WHEN 'type9' THEN '08:30'::time
            END
        ) AS planned_arrival,
        COALESCE(
            NULLIF(time_departure, '')::time,
            CASE timeman_type
                WHEN 'type1' THEN '18:00'::time WHEN 'type2' THEN '19:00'::time
                WHEN 'type3' THEN '17:00'::time WHEN 'type4' THEN '19:00'::time
                WHEN 'type5' THEN '21:00'::time WHEN 'type6' THEN '20:00'::time
                WHEN 'type7' THEN '09:00'::time WHEN 'type8' THEN '18:30'::time
                WHEN 'type9' THEN '17:30'::time
            END
        ) AS planned_departure
    FROM master.scud_user
)
SELECT
    d.user_id,
    COALESCE(NULLIF(TRIM(u.name), ''), 'Неизвестный (' || d.user_id::text || ')') AS user_name,
    u.active,
    COALESCE(
        array_to_string(ARRAY(SELECT jsonb_array_elements_text(u.department_names)), ', '),
        u.department->>'NAME'
    ) AS department,
    d.date_key,
    c.is_weekend,
    e.first_entry,
    -- last_exit: GREATEST выбирает более позднюю дату из события OUT и session_last_exit.
    -- Чинит ночные смены (e.last_exit ← дата входа, session_last_exit ← +1д) и зомби (e.last_exit раньше выхода).
    -- OLD: COALESCE(e.last_exit, s.session_last_exit) — брал первый не-NULL, не чинил ночные смены.
    GREATEST(e.last_exit, s.session_last_exit) AS last_exit,
    -- scud_duration_sec: капаем сверху до last_exit - first_entry.
    -- Чинит артефакт INTERRUPTED-сессий с duration_sec > реального времени (авто-закрытие кроном).
    -- CASE + last_exit > first_entry отсекает: переход через полночь (last_exit < first_entry),
    -- инвертированные события (OUT раньше IN) и NULL. В этих случаях — исходная сумма.
    CASE
        WHEN e.first_entry IS NOT NULL
             AND COALESCE(e.last_exit, s.session_last_exit) > e.first_entry
        THEN LEAST(
            s.scud_duration_sec,
            EXTRACT(EPOCH FROM (COALESCE(e.last_exit, s.session_last_exit) - e.first_entry))::int
        )
        ELSE s.scud_duration_sec
    END AS scud_duration_sec,
    s.scud_sessions_count,
    t.timeman_status,
    t.timeman_entry_time,
    t.timeman_exit_time,
    t.timeman_entry_ts,
    t.timeman_exit_ts,
    t.timeman_duration,
    t.timeman_paused,
    t.timeman_approved,
    a.absence_types,
    a.absence_names,
    sch.planned_arrival,
    sch.planned_departure,
    -- effective_entry_time / effective_exit_time: единые метки входа/выхода (SCUD → Timeman fallback).
    -- Full timestamp (с датой), позволяет считать разницу и детектить аномалии (забыл выключить).
    CASE
        WHEN e.first_entry IS NOT NULL
             AND GREATEST(e.last_exit, s.session_last_exit) > e.first_entry
        THEN e.first_entry
        WHEN t.timeman_entry_ts IS NOT NULL
        THEN t.timeman_entry_ts
    END AS effective_entry_time,
    CASE
        WHEN e.first_entry IS NOT NULL
             AND GREATEST(e.last_exit, s.session_last_exit) > e.first_entry
        THEN GREATEST(e.last_exit, s.session_last_exit)
        WHEN t.timeman_exit_ts IS NOT NULL
        THEN t.timeman_exit_ts
    END AS effective_exit_time,
    EXTRACT(EPOCH FROM (
        CASE
            WHEN e.first_entry IS NOT NULL
                 AND GREATEST(e.last_exit, s.session_last_exit) > e.first_entry
            THEN GREATEST(e.last_exit, s.session_last_exit) - e.first_entry
            WHEN t.timeman_entry_ts IS NOT NULL AND t.timeman_exit_ts IS NOT NULL
            THEN t.timeman_exit_ts - t.timeman_entry_ts
        END
    ))::int AS effective_duration_raw_sec,
    CASE
        WHEN e.first_entry IS NOT NULL
             AND GREATEST(e.last_exit, s.session_last_exit) > e.first_entry
             AND sch.planned_arrival IS NOT NULL
        THEN date_trunc('minute', e.first_entry::time) > sch.planned_arrival + interval '15 minutes'
        WHEN t.timeman_entry_ts IS NOT NULL AND sch.planned_arrival IS NOT NULL
        THEN date_trunc('minute', t.timeman_entry_ts::time) > sch.planned_arrival + interval '15 minutes'
    END AS is_late,
    CASE
        WHEN e.first_entry IS NOT NULL
             AND GREATEST(e.last_exit, s.session_last_exit) > e.first_entry
             AND sch.planned_departure IS NOT NULL
        THEN date_trunc('minute', GREATEST(e.last_exit, s.session_last_exit)::time) < sch.planned_departure - interval '15 minutes'
        WHEN t.timeman_exit_ts IS NOT NULL AND sch.planned_departure IS NOT NULL
        THEN date_trunc('minute', t.timeman_exit_ts::time) < sch.planned_departure - interval '15 minutes'
    END AS is_early_leave,
    -- is_scud_day: TRUE если есть IN/OUT события (СКУД зафиксировал проход).
    -- OLD: было AND s.scud_duration_sec > 0 — отсекал офисников с duration=0 (инверсия).
    CASE
        WHEN e.first_entry IS NOT NULL
             AND GREATEST(e.last_exit, s.session_last_exit) > e.first_entry
        THEN TRUE ELSE FALSE
    END AS is_scud_day,
    -- effective_duration_sec: единая длительность. Приоритет: Timeman → СКУД (кап 16ч) → NULL
    -- Timeman надёжнее СКУД (54% дней Timeman > СКУД).
    -- СКУД — fallback для дней без Timeman (19k+ дней).
    -- Кап 57600 (16ч) от зомби-сессий (3k+ аномалий с миллионами секунд).
    CASE
        WHEN t.timeman_duration > 0 THEN t.timeman_duration
        WHEN e.first_entry IS NOT NULL
             AND GREATEST(e.last_exit, s.session_last_exit) > e.first_entry
        THEN LEAST(
            s.scud_duration_sec,
            EXTRACT(EPOCH FROM (GREATEST(e.last_exit, s.session_last_exit) - e.first_entry))::int,
            57600
        )
    END AS effective_duration_sec,
    -- effective_source: откуда взята effective_duration ('timeman' / 'scud' / 'none')
    -- Для отката: вернуть старый приоритет (СКУД → Timeman → NULL).
    CASE
        WHEN t.timeman_duration > 0 THEN 'timeman'
        WHEN e.first_entry IS NOT NULL
             AND GREATEST(e.last_exit, s.session_last_exit) > e.first_entry
        THEN 'scud'
        ELSE 'none'
    END AS effective_source,
    c.is_holiday,
    c.holiday_name,
    c.day_type
FROM dates d
LEFT JOIN master.scud_user u ON u.id = d.user_id
LEFT JOIN scud_event_agg e ON e.user_id = d.user_id AND e.date_key = d.date_key
LEFT JOIN scud_session_agg s ON s.user_id = d.user_id AND s.date_key = d.date_key
LEFT JOIN timeman t ON t.user_id = d.user_id AND t.date_key = d.date_key
LEFT JOIN absence_agg a ON a.user_id = d.user_id AND a.date_key = d.date_key
LEFT JOIN schedule sch ON sch.user_id = d.user_id
LEFT JOIN dm.calendar c ON c.date_key = d.date_key;

COMMENT ON VIEW dm.v_employee_day IS 'Одна запись = сотрудник × день. SCUD + Timeman + absence + режим + производственный календарь в одной строке';

COMMIT;
