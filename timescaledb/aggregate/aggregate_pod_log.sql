-- Per-pack POD fields -> pw_pod_log. Same whole-row-unpivot-then-filter
-- pattern as aggregate_vitals_log.sql, so it works for any Powerwall count.
WITH src AS (
  SELECT time,
    to_jsonb(t) - 'time' - 'host' - 'month' - 'year' - 'url' AS row_json
  FROM http t
  WHERE time >= date_trunc('minute', (now() - interval '15 minutes') AT TIME ZONE 'UTC')
),
unpivoted AS (
  SELECT time_bucket('1 minute', src.time) AT TIME ZONE 'UTC' AS bucket,
         kv.key AS metric_name, (kv.value)::text::double precision AS value
  FROM src
  CROSS JOIN LATERAL jsonb_each(src.row_json) AS kv(key, value)
  WHERE jsonb_typeof(kv.value) <> 'null'
    AND (kv.key IN ('backup_reserve_percent', 'nominal_full_pack_energy', 'nominal_energy_remaining')
         OR kv.key ~ '_POD_nom_(energy_remaining|full_pack_energy)$')
)
INSERT INTO pw_pod_log (time, metric_name, value)
SELECT bucket, metric_name, avg(value)
FROM unpivoted
GROUP BY bucket, metric_name
ON CONFLICT (time, metric_name) DO UPDATE SET value = EXCLUDED.value;
