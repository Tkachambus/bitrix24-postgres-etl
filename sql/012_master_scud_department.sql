-- 012: master.scud_department — справочник подразделений из Bitrix24
-- Содержит id, name, parent_id, active, sort, code.
-- Заполняется через staging.incoming_b24 (entity=scud_department), sync-b24 раз в день.

BEGIN;

CREATE TABLE IF NOT EXISTS master.scud_department (
  id        integer NOT NULL PRIMARY KEY,
  name      text,
  parent_id integer,
  active    boolean,
  sort      integer,
  code      text,
  merged_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE master.scud_department IS 'Подразделения Bitrix24 (entity=scud_department)';

COMMIT;
