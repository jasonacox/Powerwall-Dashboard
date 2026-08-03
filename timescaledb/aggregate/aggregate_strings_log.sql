-- Powerwall+ string monitoring -> pw_strings_log. Best-effort port (no PW+
-- hardware to validate against -- see timescaledb/README.md). Same
-- whole-row-unpivot-then-filter pattern as aggregate_vitals_log.sql: matches
-- field names A-F (optionally suffixed 1-5 for additional inverters) x
-- Current/Power/Voltage, so it works for any number of installed strings.
-- Also computes the derived per-inverter total power (InverterN = sum of
-- that inverter's 6 string letters' _Power), matching stock InfluxDB's
-- cq_inverters/cq_inverters1 -- note the quirky but established numbering:
-- unsuffixed fields are Inverter1, suffix "1" is Inverter2, ... suffix "5" is
-- Inverter6.
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
    AND kv.key ~ '^[A-F][1-5]?_(Current|Power|Voltage)$'
),
agg AS (
  SELECT bucket, metric_name, avg(value) AS value
  FROM unpivoted
  GROUP BY bucket, metric_name
),
inverter_map(suffix, inverter) AS (
  VALUES ('', 'Inverter1'), ('1', 'Inverter2'), ('2', 'Inverter3'),
         ('3', 'Inverter4'), ('4', 'Inverter5'), ('5', 'Inverter6')
),
inverters AS (
  SELECT a_pow.bucket, m.inverter,
         a_pow.value + b_pow.value + c_pow.value + d_pow.value + e_pow.value + f_pow.value AS value
  FROM inverter_map m
  JOIN agg a_pow ON a_pow.metric_name = 'A' || m.suffix || '_Power'
  JOIN agg b_pow ON b_pow.metric_name = 'B' || m.suffix || '_Power' AND b_pow.bucket = a_pow.bucket
  JOIN agg c_pow ON c_pow.metric_name = 'C' || m.suffix || '_Power' AND c_pow.bucket = a_pow.bucket
  JOIN agg d_pow ON d_pow.metric_name = 'D' || m.suffix || '_Power' AND d_pow.bucket = a_pow.bucket
  JOIN agg e_pow ON e_pow.metric_name = 'E' || m.suffix || '_Power' AND e_pow.bucket = a_pow.bucket
  JOIN agg f_pow ON f_pow.metric_name = 'F' || m.suffix || '_Power' AND f_pow.bucket = a_pow.bucket
)
INSERT INTO pw_strings_log (time, metric_name, value)
SELECT bucket, metric_name, value FROM agg
UNION ALL
SELECT bucket, inverter, value FROM inverters
ON CONFLICT (time, metric_name) DO UPDATE SET value = EXCLUDED.value;
