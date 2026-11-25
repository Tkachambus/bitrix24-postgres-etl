-- 006: Универсальная staging-таблица для приёма данных из Bitrix24
-- Аналог staging.incoming_1c, но для данных СКУД и тайм-менеджмента

BEGIN;

CREATE TABLE IF NOT EXISTS staging.incoming_b24 (
  batch_id          uuid NOT NULL,
  entity            text NOT NULL,
  external_id       text NOT NULL,
  source_updated_at timestamptz,
  is_deleted        boolean NOT NULL DEFAULT false,
  payload           jsonb NOT NULL,
  received_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (batch_id, entity, external_id)
);

CREATE INDEX IF NOT EXISTS idx_incoming_b24_batch ON staging.incoming_b24 (batch_id);
CREATE INDEX IF NOT EXISTS idx_incoming_b24_entity ON staging.incoming_b24 (entity);

COMMENT ON TABLE staging.incoming_b24 IS 'Буфер данных из Bitrix24 (СКУД, тайм-менеджмент, отсутствия, пользователи). entity = scud_event, scud_session, scud_regime, timeman_entry, absence, scud_user';

COMMIT;
