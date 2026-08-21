-- Boundary-interpolated integration: splits a trapezoid spanning an hour
-- boundary proportionally between the two hours it touches, correcting a
-- documented undercounting bug in InfluxDB's integral() (see
-- timescaledb/README.md). Any interval over 5 minutes is treated as a real
-- outage (contributes 0) rather than bridged as one large trapezoid.
--
-- Requires a psql variable "tz" (the installation's Olson timezone, e.g.
-- America/Los_Angeles) so hour boundaries align to local wall-clock time --
-- passed by the aggregate-cron entrypoint as: psql -v tz="$TZ" -f ...
WITH lagged AS (
  SELECT
    time,
    home, solar, from_pw, to_pw, from_grid, to_grid,
    LAG(time)       OVER (ORDER BY time) AS prev_time,
    LAG(home)       OVER (ORDER BY time) AS prev_home,
    LAG(solar)      OVER (ORDER BY time) AS prev_solar,
    LAG(from_pw)    OVER (ORDER BY time) AS prev_from_pw,
    LAG(to_pw)      OVER (ORDER BY time) AS prev_to_pw,
    LAG(from_grid)  OVER (ORDER BY time) AS prev_from_grid,
    LAG(to_grid)    OVER (ORDER BY time) AS prev_to_grid
  FROM pw_autogen_1m
  WHERE time >= now() - interval '4 hours'
),
intervals AS (
  SELECT
    time, prev_time,
    date_trunc('hour', time AT TIME ZONE :'tz') AT TIME ZONE :'tz' AS hour_start,
    CASE WHEN prev_time IS NULL OR (time - prev_time) > interval '5 minutes' THEN 0
         ELSE (COALESCE(home,0)+COALESCE(prev_home,0))/2.0 * (EXTRACT(EPOCH FROM (time-prev_time))/3600.0)/1000.0 END AS home_wh,
    CASE WHEN prev_time IS NULL OR (time - prev_time) > interval '5 minutes' THEN 0
         ELSE (COALESCE(solar,0)+COALESCE(prev_solar,0))/2.0 * (EXTRACT(EPOCH FROM (time-prev_time))/3600.0)/1000.0 END AS solar_wh,
    CASE WHEN prev_time IS NULL OR (time - prev_time) > interval '5 minutes' THEN 0
         ELSE (COALESCE(from_pw,0)+COALESCE(prev_from_pw,0))/2.0 * (EXTRACT(EPOCH FROM (time-prev_time))/3600.0)/1000.0 END AS from_pw_wh,
    CASE WHEN prev_time IS NULL OR (time - prev_time) > interval '5 minutes' THEN 0
         ELSE (COALESCE(to_pw,0)+COALESCE(prev_to_pw,0))/2.0 * (EXTRACT(EPOCH FROM (time-prev_time))/3600.0)/1000.0 END AS to_pw_wh,
    CASE WHEN prev_time IS NULL OR (time - prev_time) > interval '5 minutes' THEN 0
         ELSE (COALESCE(from_grid,0)+COALESCE(prev_from_grid,0))/2.0 * (EXTRACT(EPOCH FROM (time-prev_time))/3600.0)/1000.0 END AS from_grid_wh,
    CASE WHEN prev_time IS NULL OR (time - prev_time) > interval '5 minutes' THEN 0
         ELSE (COALESCE(to_grid,0)+COALESCE(prev_to_grid,0))/2.0 * (EXTRACT(EPOCH FROM (time-prev_time))/3600.0)/1000.0 END AS to_grid_wh
  FROM lagged
),
split AS (
  SELECT
    hour_start, prev_time, home_wh, solar_wh, from_pw_wh, to_pw_wh, from_grid_wh, to_grid_wh,
    CASE WHEN prev_time IS NULL OR prev_time >= hour_start THEN 1.0
         ELSE EXTRACT(EPOCH FROM (time - hour_start)) / NULLIF(EXTRACT(EPOCH FROM (time - prev_time)), 0)
    END AS frac_current
  FROM intervals
),
allocated AS (
  SELECT hour_start AS bucket,
         frac_current * home_wh AS home_wh, frac_current * solar_wh AS solar_wh,
         frac_current * from_pw_wh AS from_pw_wh, frac_current * to_pw_wh AS to_pw_wh,
         frac_current * from_grid_wh AS from_grid_wh, frac_current * to_grid_wh AS to_grid_wh
  FROM split
  UNION ALL
  SELECT hour_start - interval '1 hour' AS bucket,
         (1 - frac_current) * home_wh, (1 - frac_current) * solar_wh,
         (1 - frac_current) * from_pw_wh, (1 - frac_current) * to_pw_wh,
         (1 - frac_current) * from_grid_wh, (1 - frac_current) * to_grid_wh
  FROM split
  WHERE frac_current < 1.0
)
INSERT INTO pw_kwh_1h (time, home, solar, from_pw, to_pw, from_grid, to_grid)
SELECT bucket, sum(home_wh), sum(solar_wh), sum(from_pw_wh), sum(to_pw_wh), sum(from_grid_wh), sum(to_grid_wh)
FROM allocated
WHERE bucket >= date_trunc('hour', now() AT TIME ZONE :'tz') AT TIME ZONE :'tz' - interval '3 hours'
GROUP BY bucket
ON CONFLICT (time) DO UPDATE SET
  home = EXCLUDED.home, solar = EXCLUDED.solar,
  from_pw = EXCLUDED.from_pw, to_pw = EXCLUDED.to_pw,
  from_grid = EXCLUDED.from_grid, to_grid = EXCLUDED.to_grid;
