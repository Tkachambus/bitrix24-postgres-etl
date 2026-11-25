-- 020: Функция переноса из staging → master (UPSERT по batch)
-- Вызов: SELECT master.merge_unmerged();

BEGIN;

CREATE OR REPLACE FUNCTION master.merge_unmerged()
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
  v_batch_id  uuid;
  v_entity    text;
  v_count     int := 0;
BEGIN
  FOR v_batch_id, v_entity IN
    SELECT DISTINCT i.batch_id, i.entity
    FROM staging.incoming_b24 i
    LEFT JOIN staging.merge_log l ON l.batch_id = i.batch_id
    WHERE l.batch_id IS NULL
  LOOP
    CASE v_entity
      WHEN 'scud_event' THEN
        INSERT INTO master.scud_event (id, person_id, direction, timestamp, turnstile_id, source)
        SELECT
          (payload->>'id')::bigint,
          (payload->>'person_id')::int,
          payload->>'direction',
          (payload->>'timestamp')::timestamptz,
          (payload->>'turnstile_id')::int,
          payload->>'source'
        FROM staging.incoming_b24
        WHERE batch_id = v_batch_id AND entity = v_entity
        ON CONFLICT (id) DO UPDATE SET
          person_id = EXCLUDED.person_id, direction = EXCLUDED.direction,
          timestamp = EXCLUDED.timestamp, turnstile_id = EXCLUDED.turnstile_id,
          source = EXCLUDED.source, merged_at = now();

      WHEN 'scud_session' THEN
        INSERT INTO master.scud_session (id, person_id, entry_time, exit_time, entry_event_id, exit_event_id, duration_sec, last_session, status)
        SELECT
          (payload->>'id')::bigint,
          (payload->>'person_id')::int,
          (payload->>'entry_time')::timestamptz,
          (payload->>'exit_time')::timestamptz,
          (payload->>'entry_event_id')::bigint,
          (payload->>'exit_event_id')::bigint,
          (payload->>'duration_sec')::int,
          payload->>'last_session',
          payload->>'status'
        FROM staging.incoming_b24
        WHERE batch_id = v_batch_id AND entity = v_entity
        ON CONFLICT (id) DO UPDATE SET
          person_id = EXCLUDED.person_id, entry_time = EXCLUDED.entry_time,
          exit_time = EXCLUDED.exit_time, entry_event_id = EXCLUDED.entry_event_id,
          exit_event_id = EXCLUDED.exit_event_id, duration_sec = EXCLUDED.duration_sec,
          last_session = EXCLUDED.last_session, status = EXCLUDED.status,
          merged_at = now();

      WHEN 'scud_regime' THEN
        INSERT INTO master.scud_regime (id, user_id, tracking_date, checked_at, type, planned_event_at, actual_event_at, status, task_sent, task_id)
        SELECT
          (payload->>'id')::bigint,
          (payload->>'user_id')::int,
          (payload->>'tracking_date')::date,
          (payload->>'checked_at')::timestamptz,
          payload->>'type',
          (payload->>'planned_event_at')::timestamptz,
          (payload->>'actual_event_at')::timestamptz,
          payload->>'status',
          (payload->>'task_sent')::boolean,
          (payload->>'task_id')::int
        FROM staging.incoming_b24
        WHERE batch_id = v_batch_id AND entity = v_entity
        ON CONFLICT (id) DO UPDATE SET
          user_id = EXCLUDED.user_id, tracking_date = EXCLUDED.tracking_date,
          checked_at = EXCLUDED.checked_at, type = EXCLUDED.type,
          planned_event_at = EXCLUDED.planned_event_at,
          actual_event_at = EXCLUDED.actual_event_at, status = EXCLUDED.status,
          task_sent = EXCLUDED.task_sent, task_id = EXCLUDED.task_id,
          merged_at = now();

      WHEN 'absence' THEN
        INSERT INTO master.absence (id, user_id, name, date_active_from, date_active_to, active, absence_type)
        SELECT
          (payload->>'id')::bigint,
          (payload->>'user_id')::int,
          payload->>'name',
          (payload->>'date_active_from')::timestamptz,
          (payload->>'date_active_to')::timestamptz,
          (payload->>'active')::boolean,
          payload->>'absence_type'
        FROM staging.incoming_b24
        WHERE batch_id = v_batch_id AND entity = v_entity
        ON CONFLICT (id) DO UPDATE SET
          user_id = EXCLUDED.user_id, name = EXCLUDED.name,
          date_active_from = EXCLUDED.date_active_from,
          date_active_to = EXCLUDED.date_active_to, active = EXCLUDED.active,
          absence_type = EXCLUDED.absence_type, merged_at = now();

      WHEN 'scud_department' THEN
        INSERT INTO master.scud_department (id, name, parent_id, active, sort, code)
        SELECT
          (payload->>'id')::int,
          payload->>'name',
          (payload->>'parent_id')::int,
          (payload->>'active')::boolean,
          (payload->>'sort')::int,
          payload->>'code'
        FROM staging.incoming_b24
        WHERE batch_id = v_batch_id AND entity = v_entity
        ON CONFLICT (id) DO UPDATE SET
          name = EXCLUDED.name, parent_id = EXCLUDED.parent_id,
          active = EXCLUDED.active, sort = EXCLUDED.sort,
          code = EXCLUDED.code, merged_at = now();

      WHEN 'scud_user' THEN
        INSERT INTO master.scud_user (id, name, scud_key, time_scheduler, time_arrival, time_departure, timeman_type, department, active, departments, department_names)
        SELECT
          (payload->>'id')::bigint,
          payload->>'name',
          payload->>'scud_key',
          (payload->>'time_scheduler')::boolean,
          payload->>'time_arrival',
          payload->>'time_departure',
          payload->>'timeman_type',
          payload->'department',
          (payload->>'active')::boolean,
          payload->'departments',
          payload->'department_names'
        FROM staging.incoming_b24
        WHERE batch_id = v_batch_id AND entity = v_entity
        ON CONFLICT (id) DO UPDATE SET
          name = EXCLUDED.name, scud_key = EXCLUDED.scud_key,
          time_scheduler = EXCLUDED.time_scheduler,
          time_arrival = EXCLUDED.time_arrival,
          time_departure = EXCLUDED.time_departure,
          timeman_type = EXCLUDED.timeman_type,
          department = EXCLUDED.department,
          active = EXCLUDED.active,
          departments = EXCLUDED.departments,
          department_names = EXCLUDED.department_names,
          merged_at = now();

      WHEN 'timeman_entry' THEN
        INSERT INTO master.timeman_entry (id, user_id, current_status, date_start, date_finish, time_start, time_finish, duration, recorded_duration, time_leaks, active, paused, approved, approved_by, schedule_id, timestamp_x)
        SELECT
          (payload->>'id')::bigint,
          (payload->>'user_id')::int,
          payload->>'current_status',
          (payload->>'date_start')::timestamptz,
          (payload->>'date_finish')::timestamptz,
          (payload->>'time_start')::int,
          (payload->>'time_finish')::int,
          (payload->>'duration')::int,
          (payload->>'recorded_duration')::int,
          (payload->>'time_leaks')::int,
          (payload->>'active')::boolean,
          (payload->>'paused')::boolean,
          (payload->>'approved')::boolean,
          (payload->>'approved_by')::int,
          (payload->>'schedule_id')::int,
          (payload->>'timestamp_x')::timestamptz
        FROM staging.incoming_b24
        WHERE batch_id = v_batch_id AND entity = v_entity
        ON CONFLICT (id) DO UPDATE SET
          user_id = EXCLUDED.user_id, current_status = EXCLUDED.current_status,
          date_start = EXCLUDED.date_start, date_finish = EXCLUDED.date_finish,
          time_start = EXCLUDED.time_start, time_finish = EXCLUDED.time_finish,
          duration = EXCLUDED.duration, recorded_duration = EXCLUDED.recorded_duration,
          time_leaks = EXCLUDED.time_leaks, active = EXCLUDED.active,
          paused = EXCLUDED.paused, approved = EXCLUDED.approved,
          approved_by = EXCLUDED.approved_by, schedule_id = EXCLUDED.schedule_id,
          timestamp_x = EXCLUDED.timestamp_x, merged_at = now();

      ELSE
        -- неизвестная entity — пропускаем
    END CASE;

    INSERT INTO staging.merge_log (batch_id) VALUES (v_batch_id)
    ON CONFLICT DO NOTHING;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$function$;

COMMENT ON FUNCTION master.merge_unmerged() IS 'Переносит необработанные batch из staging в master. Возвращает кол-во обработанных batch-ей';

COMMIT;
