-- 040: dm.v_session_detail — детализация сессий СКУД
-- Одна строка = одна сессия (вход + выход).
-- Для дашборда СКУД и проверки парных событий.

BEGIN;

CREATE OR REPLACE VIEW dm.v_session_detail AS
SELECT
    s.id AS session_id,
    s.person_id AS user_id,
    COALESCE(NULLIF(TRIM(u.name), ''), 'Неизвестный (' || s.person_id::text || ')') AS user_name,
    u.department,
    s.entry_time,
    s.exit_time,
    s.duration_sec,
    s.status AS session_status,
    s.last_session,
    e_in.turnstile_id AS entry_turnstile_id,
    e_in.source AS entry_source,
    e_out.turnstile_id AS exit_turnstile_id,
    e_out.source AS exit_source,
    s.merged_at
FROM master.scud_session s
LEFT JOIN master.scud_user u ON u.id = s.person_id
LEFT JOIN master.scud_event e_in ON e_in.id = s.entry_event_id
LEFT JOIN master.scud_event e_out ON e_out.id = s.exit_event_id;

COMMENT ON VIEW dm.v_session_detail IS 'Одна строка = одна сессия СКУД. Джойн к пользователю и событиям входа/выхода';

COMMIT;
