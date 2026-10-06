-- Time-weighted (not plain avg()) averaging: each sample weighted by seconds
-- until the next sample, clamped to bucket boundaries. Corrects a distortion
-- from two independently-clocked Telegraf pollers unevenly multi-sampling
-- transients -- see timescaledb/README.md.
WITH agg_rows AS (
  SELECT
    time, load_instant_power, solar_instant_power, battery_instant_power, site_instant_power,
    load_instant_total_current, solar_instant_total_current, battery_instant_total_current, site_instant_total_current,
    load_instant_average_voltage, solar_instant_average_voltage, battery_instant_average_voltage, site_instant_average_voltage,
    LEAD(time) OVER (ORDER BY time) AS next_time,
    time_bucket('1 minute', time) AS bucket_naive
  FROM http
  WHERE load_instant_power IS NOT NULL
    AND time >= date_trunc('minute', (now() - interval '15 minutes') AT TIME ZONE 'UTC')
),
weighted AS (
  SELECT
    (bucket_naive AT TIME ZONE 'UTC') AS bucket,
    EXTRACT(EPOCH FROM (
      LEAST(COALESCE(next_time, time + interval '5 seconds'), bucket_naive + interval '1 minute') - time
    )) AS w,
    load_instant_power, solar_instant_power,
    CASE WHEN battery_instant_power > 0 THEN battery_instant_power ELSE 0 END AS from_pw_v,
    CASE WHEN battery_instant_power < 0 THEN -battery_instant_power ELSE 0 END AS to_pw_v,
    CASE WHEN site_instant_power > 0 THEN site_instant_power ELSE 0 END AS from_grid_v,
    CASE WHEN site_instant_power < 0 THEN -site_instant_power ELSE 0 END AS to_grid_v,
    load_instant_total_current, solar_instant_total_current, battery_instant_total_current, site_instant_total_current,
    load_instant_average_voltage, solar_instant_average_voltage, battery_instant_average_voltage, site_instant_average_voltage
  FROM agg_rows
),
pct AS (
  SELECT time_bucket('1 minute', time) AT TIME ZONE 'UTC' AS bucket,
         last(percentage, time) AS percentage
  FROM http
  WHERE percentage IS NOT NULL
    AND time >= date_trunc('minute', (now() - interval '15 minutes') AT TIME ZONE 'UTC')
  GROUP BY 1
)
INSERT INTO pw_autogen_1m (
  time, home, solar, from_pw, to_pw, from_grid, to_grid, percentage,
  home_current, solar_current, pw_current, grid_current,
  home_voltage, solar_voltage, pw_voltage, grid_voltage
)
SELECT
  w.bucket,
  sum(w.load_instant_power * w.w) / NULLIF(sum(w.w),0),
  sum(w.solar_instant_power * w.w) / NULLIF(sum(w.w),0),
  sum(w.from_pw_v * w.w) / NULLIF(sum(w.w),0),
  sum(w.to_pw_v * w.w) / NULLIF(sum(w.w),0),
  sum(w.from_grid_v * w.w) / NULLIF(sum(w.w),0),
  sum(w.to_grid_v * w.w) / NULLIF(sum(w.w),0),
  max(pct.percentage),
  sum(w.load_instant_total_current * w.w) / NULLIF(sum(w.w),0),
  sum(w.solar_instant_total_current * w.w) / NULLIF(sum(w.w),0),
  sum(w.battery_instant_total_current * w.w) / NULLIF(sum(w.w),0),
  sum(w.site_instant_total_current * w.w) / NULLIF(sum(w.w),0),
  sum(w.load_instant_average_voltage * w.w) / NULLIF(sum(w.w),0),
  sum(w.solar_instant_average_voltage * w.w) / NULLIF(sum(w.w),0),
  sum(w.battery_instant_average_voltage * w.w) / NULLIF(sum(w.w),0),
  sum(w.site_instant_average_voltage * w.w) / NULLIF(sum(w.w),0)
FROM weighted w
LEFT JOIN pct ON pct.bucket = w.bucket
GROUP BY w.bucket
ON CONFLICT (time) DO UPDATE SET
  home = EXCLUDED.home, solar = EXCLUDED.solar,
  from_pw = EXCLUDED.from_pw, to_pw = EXCLUDED.to_pw,
  from_grid = EXCLUDED.from_grid, to_grid = EXCLUDED.to_grid,
  percentage = EXCLUDED.percentage,
  home_current = EXCLUDED.home_current, solar_current = EXCLUDED.solar_current,
  pw_current = EXCLUDED.pw_current, grid_current = EXCLUDED.grid_current,
  home_voltage = EXCLUDED.home_voltage, solar_voltage = EXCLUDED.solar_voltage,
  pw_voltage = EXCLUDED.pw_voltage, grid_voltage = EXCLUDED.grid_voltage;
