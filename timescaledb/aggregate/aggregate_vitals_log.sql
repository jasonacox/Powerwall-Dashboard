-- Per-pack vitals -> pw_vitals_log. Unpivots the WHOLE raw row and keeps only
-- keys matching known vitals field patterns, rather than a fixed PW1/PW2/PW3
-- column list -- this makes the query correct for any Powerwall count (or
-- split-phase vs three-phase installs) with zero changes, since Telegraf only
-- ever creates the columns actual hardware reports (see GOTCHAS.md).
WITH src AS (
  SELECT time, to_jsonb(t) - 'time' - 'host' - 'month' - 'year' - 'url' AS row_json
  FROM http t
  WHERE time >= date_trunc('minute', (now() - interval '15 minutes') AT TIME ZONE 'UTC')
),
unpivoted AS (
  SELECT time_bucket('1 minute', src.time) AT TIME ZONE 'UTC' AS bucket,
         kv.key AS metric_name, (kv.value)::text::double precision AS value
  FROM src
  CROSS JOIN LATERAL jsonb_each(src.row_json) AS kv(key, value)
  WHERE jsonb_typeof(kv.value) <> 'null'
    AND (kv.key ~ '^(ISLAND_|METER_[XYZ]_)'
         OR kv.key ~ '_(PINV_Fout|PINV_VSplit[12]|v_out|f_out|i_out|p_out|q_out)$')
),
agg AS (
  SELECT bucket, metric_name, avg(value) AS value
  FROM unpivoted
  GROUP BY bucket, metric_name
),
totals AS (
  SELECT bucket,
         replace(metric_name, '_PINV_VSplit1', '_pinv_total') AS metric_name,
         value AS v1
  FROM agg WHERE metric_name LIKE '%\_PINV\_VSplit1' ESCAPE '\'
)
INSERT INTO pw_vitals_log (time, metric_name, value)
SELECT bucket, metric_name, value FROM agg
UNION ALL
SELECT t.bucket, t.metric_name, t.v1 + a2.value
FROM totals t
JOIN agg a2 ON a2.bucket = t.bucket AND a2.metric_name = replace(t.metric_name, '_pinv_total', '_PINV_VSplit2')
ON CONFLICT (time, metric_name) DO UPDATE SET value = EXCLUDED.value;
