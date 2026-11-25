-- 013: Новые колонки в master.scud_user для департаментов
-- API теперь отдаёт department, departments (массив ID), department_names (массив названий).

BEGIN;

ALTER TABLE master.scud_user
  ADD COLUMN IF NOT EXISTS departments      jsonb,
  ADD COLUMN IF NOT EXISTS department_names jsonb;

COMMIT;
