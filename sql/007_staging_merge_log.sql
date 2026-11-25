-- 007: Лог обработанных batch-ей (для merge_unmerged)

BEGIN;

CREATE TABLE IF NOT EXISTS staging.merge_log (
  batch_id    uuid NOT NULL PRIMARY KEY,
  merged_at   timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE staging.merge_log IS 'Отметки об обработке batch_id функцией master.merge_unmerged()';

COMMIT;
