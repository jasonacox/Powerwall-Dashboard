-- Dynamic jsonb_each()-based unpivot -- a genuinely new Tesla alert type
-- requires zero code changes here (only Telegraf auto-creating the new raw
-- column, an already-existing, unrelated mechanism).
--
-- No-op until the "alerts" table exists (Telegraf creates it the first time
-- the Powerwall reports an alert, which some systems never do).
DO $$
BEGIN
  IF to_regclass('public.alerts') IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO pw_alerts_log (time, alert_name, value)
  SELECT
    time_bucket('1 minute', a.time) AT TIME ZONE 'UTC' AS bucket,
    kv.key AS alert_name,
    max((kv.value)::text::double precision) AS value
  FROM alerts a
  CROSS JOIN LATERAL jsonb_each(
    to_jsonb(a) - 'time' - 'host' - 'month' - 'year' - 'url'
  ) AS kv(key, value)
  WHERE a.time >= date_trunc('minute', (now() - interval '15 minutes') AT TIME ZONE 'UTC')
    AND jsonb_typeof(kv.value) <> 'null'
  GROUP BY bucket, kv.key
  ON CONFLICT (time, alert_name) DO UPDATE SET value = EXCLUDED.value;
END $$;
